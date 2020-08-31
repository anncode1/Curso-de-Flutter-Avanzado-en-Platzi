/*
 * Copyright 2019 Google
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

#ifndef FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_API_DOCUMENT_REFERENCE_H_
#define FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_API_DOCUMENT_REFERENCE_H_

#if !defined(__OBJC__)
#error "This header only supports Objective-C++"
#endif  // !defined(__OBJC__)

#import <Foundation/Foundation.h>

#include <string>
#include <utility>
#include <vector>

#import "FIRDocumentReference.h"
#import "FIRFirestoreSource.h"

#include "Firestore/core/src/firebase/firestore/api/document_snapshot.h"
#include "Firestore/core/src/firebase/firestore/api/listener_registration.h"
#include "Firestore/core/src/firebase/firestore/core/listen_options.h"
#include "Firestore/core/src/firebase/firestore/model/document_key.h"
#include "Firestore/core/src/firebase/firestore/model/resource_path.h"
#include "Firestore/core/src/firebase/firestore/util/statusor_callback.h"

NS_ASSUME_NONNULL_BEGIN

@class FIRFirestore;
@class FSTMutation;

namespace firebase {
namespace firestore {
namespace api {

class Firestore;

class DocumentReference {
 public:
  using Completion = void (^)(NSError* _Nullable error) _Nullable;

  DocumentReference() = default;
  DocumentReference(model::ResourcePath path, Firestore* firestore);
  DocumentReference(model::DocumentKey document_key, Firestore* firestore)
      : firestore_{firestore}, key_{std::move(document_key)} {
  }

  size_t Hash() const;

  Firestore* firestore() const {
    return firestore_;
  }
  const model::DocumentKey& key() const {
    return key_;
  }

  const std::string& document_id() const;

  // TODO(varconst) uncomment when core API CollectionReference is implemented.
  // CollectionReference Parent() const;

  std::string Path() const;

  // TODO(varconst) uncomment when core API CollectionReference is implemented.
  // CollectionReference GetCollectionReference(
  //     const std::string& collection_path) const;

  void SetData(std::vector<FSTMutation*>&& mutations, Completion completion);

  void UpdateData(std::vector<FSTMutation*>&& mutations, Completion completion);

  void DeleteDocument(Completion completion);

  void GetDocument(FIRFirestoreSource source,
                   DocumentSnapshot::Listener&& completion);

  ListenerRegistration AddSnapshotListener(
      core::ListenOptions options, DocumentSnapshot::Listener&& listener);

 private:
  Firestore* firestore_ = nullptr;
  model::DocumentKey key_;
};

bool operator==(const DocumentReference& lhs, const DocumentReference& rhs);

}  // namespace api
}  // namespace firestore
}  // namespace firebase

NS_ASSUME_NONNULL_END

#endif  // FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_API_DOCUMENT_REFERENCE_H_
