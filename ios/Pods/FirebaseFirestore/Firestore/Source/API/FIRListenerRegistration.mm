/*
 * Copyright 2017 Google
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

#include <memory>

#import "Firestore/Source/API/FIRListenerRegistration+Internal.h"

#include "Firestore/core/src/firebase/firestore/util/delayed_constructor.h"

NS_ASSUME_NONNULL_BEGIN

using firebase::firestore::util::DelayedConstructor;

@implementation FSTListenerRegistration {
  DelayedConstructor<ListenerRegistration> _registration;
}

- (instancetype)initWithRegistration:(ListenerRegistration &&)registration {
  if (self = [super init]) {
    _registration.Init(std::move(registration));
  }
  return self;
}

- (void)remove {
  _registration->Remove();
}

@end

NS_ASSUME_NONNULL_END
