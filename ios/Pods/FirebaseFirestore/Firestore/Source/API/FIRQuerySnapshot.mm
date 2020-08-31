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

#include <utility>

#import "Firestore/Source/API/FIRQuerySnapshot+Internal.h"

#import "FIRSnapshotMetadata.h"
#import "Firestore/Source/API/FIRDocumentChange+Internal.h"
#import "Firestore/Source/API/FIRDocumentSnapshot+Internal.h"
#import "Firestore/Source/API/FIRFirestore+Internal.h"
#import "Firestore/Source/API/FIRQuery+Internal.h"
#import "Firestore/Source/API/FIRSnapshotMetadata+Internal.h"
#import "Firestore/Source/Core/FSTQuery.h"
#import "Firestore/Source/Model/FSTDocument.h"
#import "Firestore/Source/Util/FSTUsageValidation.h"

#include "Firestore/core/src/firebase/firestore/core/view_snapshot.h"
#include "Firestore/core/src/firebase/firestore/model/document_set.h"
#include "Firestore/core/src/firebase/firestore/util/delayed_constructor.h"

using firebase::firestore::api::Firestore;
using firebase::firestore::api::QuerySnapshot;
using firebase::firestore::core::ViewSnapshot;
using firebase::firestore::util::DelayedConstructor;

NS_ASSUME_NONNULL_BEGIN

@implementation FIRQuerySnapshot {
  DelayedConstructor<QuerySnapshot> _snapshot;

  FIRSnapshotMetadata *_cached_metadata;

  // Cached value of the documents property.
  NSArray<FIRQueryDocumentSnapshot *> *_documents;

  // Cached value of the documentChanges property.
  NSArray<FIRDocumentChange *> *_documentChanges;
  BOOL _documentChangesIncludeMetadataChanges;
}

- (instancetype)initWithSnapshot:(QuerySnapshot &&)snapshot {
  if (self = [super init]) {
    _snapshot.Init(std::move(snapshot));
  }
  return self;
}

- (instancetype)initWithFirestore:(Firestore *)firestore
                    originalQuery:(FSTQuery *)query
                         snapshot:(ViewSnapshot &&)snapshot
                         metadata:(SnapshotMetadata)metadata {
  QuerySnapshot wrapped(firestore, query, std::move(snapshot), std::move(metadata));
  return [self initWithSnapshot:std::move(wrapped)];
}

// NSObject Methods
- (BOOL)isEqual:(nullable id)other {
  if (![other isKindOfClass:[FIRQuerySnapshot class]]) return NO;

  FIRQuerySnapshot *otherSnapshot = other;
  return *_snapshot == *(otherSnapshot->_snapshot);
}

- (NSUInteger)hash {
  return _snapshot->Hash();
}

- (FIRQuery *)query {
  FIRFirestore *firestore = [FIRFirestore recoverFromFirestore:_snapshot->firestore()];
  return [FIRQuery referenceWithQuery:_snapshot->internal_query() firestore:firestore];
}

- (FIRSnapshotMetadata *)metadata {
  if (!_cached_metadata) {
    _cached_metadata = [[FIRSnapshotMetadata alloc] initWithMetadata:_snapshot->metadata()];
  }
  return _cached_metadata;
}

@dynamic empty;

- (BOOL)isEmpty {
  return _snapshot->empty();
}

// This property is exposed as an NSInteger instead of an NSUInteger since (as of Xcode 8.1)
// Swift bridges NSUInteger as UInt, and we want to avoid forcing Swift users to cast their ints
// where we can. See cr/146959032 for additional context.
- (NSInteger)count {
  return static_cast<NSInteger>(_snapshot->size());
}

- (NSArray<FIRQueryDocumentSnapshot *> *)documents {
  if (!_documents) {
    NSMutableArray<FIRQueryDocumentSnapshot *> *result = [NSMutableArray array];
    _snapshot->ForEachDocument([&result](DocumentSnapshot snapshot) {
      [result addObject:[[FIRQueryDocumentSnapshot alloc] initWithSnapshot:std::move(snapshot)]];
    });

    _documents = result;
  }
  return _documents;
}

- (NSArray<FIRDocumentChange *> *)documentChanges {
  return [self documentChangesWithIncludeMetadataChanges:NO];
}

- (NSArray<FIRDocumentChange *> *)documentChangesWithIncludeMetadataChanges:
    (BOOL)includeMetadataChanges {
  if (includeMetadataChanges && _snapshot->view_snapshot().excludes_metadata_changes()) {
    FSTThrowInvalidArgument(
        @"To include metadata changes with your document changes, you must call "
        @"addSnapshotListener(includeMetadataChanges: true).");
  }

  if (!_documentChanges || _documentChangesIncludeMetadataChanges != includeMetadataChanges) {
    _documentChanges = [FIRDocumentChange documentChangesForSnapshot:_snapshot->view_snapshot()
                                              includeMetadataChanges:includeMetadataChanges
                                                           firestore:_snapshot->firestore()];
    _documentChangesIncludeMetadataChanges = includeMetadataChanges;
  }
  return _documentChanges;
}

@end

NS_ASSUME_NONNULL_END
