/*
 * Copyright 2018 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "Firestore/core/src/firebase/firestore/auth/firebase_credentials_provider_apple.h"

#import <FirebaseAuthInterop/FIRAuthInterop.h>
#import <FirebaseCore/FIRApp.h>
#import <FirebaseCore/FIRAppInternal.h>
#import <FirebaseCore/FIRComponentContainer.h>
#import <FirebaseCore/FIROptionsInternal.h>

#include "Firestore/core/src/firebase/firestore/util/hard_assert.h"
#include "Firestore/core/src/firebase/firestore/util/string_apple.h"

// NB: This is also defined in Firestore/Source/Public/FIRFirestoreErrors.h
// NOLINTNEXTLINE: public constant
NSString* const FIRFirestoreErrorDomain = @"FIRFirestoreErrorDomain";

namespace firebase {
namespace firestore {
namespace auth {

FirebaseCredentialsProvider::FirebaseCredentialsProvider(
    FIRApp* app, id<FIRAuthInterop> auth) {
  contents_ =
      std::make_shared<Contents>(app, auth, User::FromUid([auth getUserID]));
  std::weak_ptr<Contents> weak_contents = contents_;

  auth_listener_handle_ = [[NSNotificationCenter defaultCenter]
      addObserverForName:FIRAuthStateDidChangeInternalNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification* notification) {
                std::shared_ptr<Contents> contents = weak_contents.lock();
                if (!contents) {
                  return;
                }

                std::unique_lock<std::mutex> lock(contents->mutex);
                NSDictionary<NSString*, id>* user_info = notification.userInfo;

                // ensure we're only notifying for the current app.
                FIRApp* notified_app =
                    user_info[FIRAuthStateDidChangeInternalNotificationAppKey];
                if (![contents->app isEqual:notified_app]) {
                  return;
                }

                NSString* user_id =
                    user_info[FIRAuthStateDidChangeInternalNotificationUIDKey];
                contents->current_user = User::FromUid(user_id);
                contents->token_counter++;
                CredentialChangeListener listener = change_listener_;
                if (listener) {
                  listener(contents->current_user);
                }
              }];
}

FirebaseCredentialsProvider::~FirebaseCredentialsProvider() {
  if (auth_listener_handle_) {
    // Even though iOS 9 (and later) and macOS 10.11 (and later) keep a weak
    // reference to the observer so we could avoid this removeObserver call, we
    // still support iOS 8 which requires it.
    [[NSNotificationCenter defaultCenter] removeObserver:auth_listener_handle_];
  }
}

void FirebaseCredentialsProvider::GetToken(TokenListener completion) {
  HARD_ASSERT(auth_listener_handle_,
              "GetToken cannot be called after listener removed.");

  // Take note of the current value of the tokenCounter so that this method can
  // fail if there is a token change while the request is outstanding.
  int initial_token_counter = contents_->token_counter;

  std::weak_ptr<Contents> weak_contents = contents_;
  void (^get_token_callback)(NSString*, NSError*) = ^(
      NSString* _Nullable token, NSError* _Nullable error) {
    std::shared_ptr<Contents> contents = weak_contents.lock();
    if (!contents) {
      return;
    }

    std::unique_lock<std::mutex> lock(contents->mutex);
    if (initial_token_counter != contents->token_counter) {
      // Cancel the request since the user changed while the request was
      // outstanding so the response is likely for a previous user (which
      // user, we can't be sure).
      completion(util::Status(FirestoreErrorCode::Aborted,
                              "getToken aborted due to token change."));
    } else {
      if (error == nil) {
        if (token != nil) {
          completion(Token{util::MakeString(token), contents->current_user});
        } else {
          completion(Token::Unauthenticated());
        }
      } else {
        FirestoreErrorCode error_code = FirestoreErrorCode::Unknown;
        if (error.domain == FIRFirestoreErrorDomain) {
          error_code = static_cast<FirestoreErrorCode>(error.code);
        }
        completion(util::Status(error_code,
                                util::MakeString(error.localizedDescription)));
      }
    }
  };

  // TODO(wilhuff): Need a better abstraction over a missing auth provider.
  if (contents_->auth) {
    [contents_->auth getTokenForcingRefresh:contents_->force_refresh
                               withCallback:get_token_callback];
  } else {
    // If there's no Auth provider, call back immediately with a nil
    // (unauthenticated) token.
    get_token_callback(nil, nil);
  }
  contents_->force_refresh = false;
}

void FirebaseCredentialsProvider::InvalidateToken() {
  contents_->force_refresh = true;
}

void FirebaseCredentialsProvider::SetCredentialChangeListener(
    CredentialChangeListener changeListener) {
  std::unique_lock<std::mutex> lock(contents_->mutex);
  if (changeListener) {
    HARD_ASSERT(!change_listener_, "set change_listener twice!");
    // Fire initial event.
    changeListener(contents_->current_user);
  } else {
    HARD_ASSERT(auth_listener_handle_, "removed change_listener twice!");
    HARD_ASSERT(change_listener_, "change_listener removed without being set!");
    [[NSNotificationCenter defaultCenter] removeObserver:auth_listener_handle_];
    auth_listener_handle_ = nil;
  }
  change_listener_ = changeListener;
}

}  // namespace auth
}  // namespace firestore
}  // namespace firebase
