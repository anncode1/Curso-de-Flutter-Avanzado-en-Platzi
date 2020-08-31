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

#import "Firestore/Source/Model/FSTDocument.h"

#include <utility>

#import "Firestore/Source/Model/FSTFieldValue.h"
#import "Firestore/Source/Util/FSTClasses.h"

#include "Firestore/core/src/firebase/firestore/model/document_key.h"
#include "Firestore/core/src/firebase/firestore/model/field_path.h"
#include "Firestore/core/src/firebase/firestore/util/hard_assert.h"
#include "Firestore/core/src/firebase/firestore/util/hashing.h"
#include "Firestore/core/src/firebase/firestore/util/string_apple.h"

namespace util = firebase::firestore::util;
using firebase::firestore::model::DocumentKey;
using firebase::firestore::model::FieldPath;
using firebase::firestore::model::SnapshotVersion;

NS_ASSUME_NONNULL_BEGIN

@interface FSTMaybeDocument ()

- (instancetype)initWithKey:(DocumentKey)key
                    version:(SnapshotVersion)version NS_DESIGNATED_INITIALIZER;

@end

@implementation FSTMaybeDocument {
  DocumentKey _key;
  SnapshotVersion _version;
}

- (instancetype)initWithKey:(DocumentKey)key version:(SnapshotVersion)version {
  self = [super init];
  if (self) {
    _key = std::move(key);
    _version = std::move(version);
  }
  return self;
}

- (bool)hasPendingWrites {
  @throw FSTAbstractMethodException();  // NOLINT
}

- (id)copyWithZone:(NSZone *_Nullable)zone {
  // All document types are immutable
  return self;
}

- (const DocumentKey &)key {
  return _key;
}

- (const SnapshotVersion &)version {
  return _version;
}

@end

@implementation FSTDocument {
  FSTDocumentState _documentState;
}

+ (instancetype)documentWithData:(FSTObjectValue *)data
                             key:(DocumentKey)key
                         version:(SnapshotVersion)version
                           state:(FSTDocumentState)state {
  return [[FSTDocument alloc] initWithData:data
                                       key:std::move(key)
                                   version:std::move(version)
                                     state:state];
}

+ (instancetype)documentWithData:(FSTObjectValue *)data
                             key:(DocumentKey)key
                         version:(SnapshotVersion)version
                           state:(FSTDocumentState)state
                           proto:(GCFSDocument *)proto {
  return [[FSTDocument alloc] initWithData:data
                                       key:std::move(key)
                                   version:std::move(version)
                                     state:state
                                     proto:proto];
}

- (instancetype)initWithData:(FSTObjectValue *)data
                         key:(DocumentKey)key
                     version:(SnapshotVersion)version
                       state:(FSTDocumentState)state {
  self = [super initWithKey:std::move(key) version:std::move(version)];
  if (self) {
    _data = data;
    _documentState = state;
    _proto = nil;
  }
  return self;
}

- (instancetype)initWithData:(FSTObjectValue *)data
                         key:(DocumentKey)key
                     version:(SnapshotVersion)version
                       state:(FSTDocumentState)state
                       proto:(GCFSDocument *)proto {
  self = [super initWithKey:std::move(key) version:std::move(version)];
  if (self) {
    _data = data;
    _documentState = state;
    _proto = proto;
  }
  return self;
}

- (bool)hasLocalMutations {
  return _documentState == FSTDocumentStateLocalMutations;
}

- (bool)hasCommittedMutations {
  return _documentState == FSTDocumentStateCommittedMutations;
}

- (bool)hasPendingWrites {
  return self.hasLocalMutations || self.hasCommittedMutations;
}

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[FSTDocument class]]) {
    return NO;
  }

  FSTDocument *otherDoc = other;
  return self.key == otherDoc.key && self.version == otherDoc.version &&
         _documentState == otherDoc->_documentState && [self.data isEqual:otherDoc.data];
}

- (NSUInteger)hash {
  NSUInteger result = self.key.Hash();
  result = result * 31 + self.version.Hash();
  result = result * 31 + [self.data hash];
  result = result * 31 + _documentState;
  return result;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<FSTDocument: key:%s version:%s documentState:%ld data:%@>",
                                    self.key.ToString().c_str(),
                                    self.version.timestamp().ToString().c_str(),
                                    (long)_documentState, self.data];
}

- (nullable FSTFieldValue *)fieldForPath:(const FieldPath &)path {
  return [_data valueForPath:path];
}

@end

@implementation FSTDeletedDocument {
  bool _hasCommittedMutations;
}

+ (instancetype)documentWithKey:(DocumentKey)key
                        version:(SnapshotVersion)version
          hasCommittedMutations:(bool)committedMutations {
  FSTDeletedDocument *deletedDocument = [[FSTDeletedDocument alloc] initWithKey:std::move(key)
                                                                        version:std::move(version)];

  if (deletedDocument) {
    deletedDocument->_hasCommittedMutations = committedMutations;
  }

  return deletedDocument;
}

- (bool)hasCommittedMutations {
  return _hasCommittedMutations;
}

- (bool)hasPendingWrites {
  return self.hasCommittedMutations;
}

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[FSTDeletedDocument class]]) {
    return NO;
  }

  FSTDeletedDocument *otherDoc = other;
  return self.key == otherDoc.key && self.version == otherDoc.version &&
         _hasCommittedMutations == otherDoc->_hasCommittedMutations;
}

- (NSUInteger)hash {
  NSUInteger result = self.key.Hash();
  result = result * 31 + self.version.Hash();
  result = result * 31 + (_hasCommittedMutations ? 1 : 0);
  return result;
}

- (NSString *)description {
  return [NSString
      stringWithFormat:@"<FSTDeletedDocument: key:%s version:%s committedMutations:%d>",
                       self.key.ToString().c_str(), self.version.timestamp().ToString().c_str(),
                       _hasCommittedMutations];
}

@end

@implementation FSTUnknownDocument

+ (instancetype)documentWithKey:(DocumentKey)key version:(SnapshotVersion)version {
  return [[FSTUnknownDocument alloc] initWithKey:std::move(key) version:std::move(version)];
}

- (bool)hasPendingWrites {
  return true;
}

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[FSTUnknownDocument class]]) {
    return NO;
  }

  FSTDocument *otherDoc = other;
  return self.key == otherDoc.key && self.version == otherDoc.version;
}

- (NSUInteger)hash {
  NSUInteger result = self.key.Hash();
  result = result * 31 + self.version.Hash();
  return result;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<FSTUnknownDocument: key:%s version:%s>",
                                    self.key.ToString().c_str(),
                                    self.version.timestamp().ToString().c_str()];
}

@end

const NSComparator FSTDocumentComparatorByKey =
    ^NSComparisonResult(FSTMaybeDocument *doc1, FSTMaybeDocument *doc2) {
      return CompareKeys(doc1.key, doc2.key);
    };

NS_ASSUME_NONNULL_END
