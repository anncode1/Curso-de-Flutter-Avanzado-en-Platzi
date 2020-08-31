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

#ifndef FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_MODEL_DOCUMENT_KEY_H_
#define FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_MODEL_DOCUMENT_KEY_H_

#include <functional>
#include <initializer_list>
#include <memory>
#include <string>

#if defined(__OBJC__)
#import "Firestore/Source/Model/FSTDocumentKey.h"
#endif  // defined(__OBJC__)

#include "Firestore/core/src/firebase/firestore/model/resource_path.h"
#include "Firestore/core/src/firebase/firestore/util/comparison.h"
#include "Firestore/core/src/firebase/firestore/util/hashing.h"
#include "absl/strings/string_view.h"

namespace firebase {
namespace firestore {
namespace model {

/**
 * DocumentKey represents the location of a document in the Firestore database.
 */
class DocumentKey {
 public:
  /** Creates a "blank" document key not associated with any document. */
  DocumentKey() : path_{std::make_shared<ResourcePath>()} {
  }

  /** Creates a new document key containing a copy of the given path. */
  explicit DocumentKey(const ResourcePath& path);

  /** Creates a new document key, taking ownership of the given path. */
  explicit DocumentKey(ResourcePath&& path);

#if defined(__OBJC__)
  NSUInteger Hash() const {
    return util::Hash(ToString());
  }
#endif  // defined(__OBJC__)

  std::string ToString() const {
    return path().CanonicalString();
  }

  /**
   * Creates and returns a new document key using '/' to split the string into
   * segments.
   */
  static DocumentKey FromPathString(absl::string_view path) {
    return DocumentKey{ResourcePath::FromString(path)};
  }

  /** Creates and returns a new document key with the given segments. */
  static DocumentKey FromSegments(std::initializer_list<std::string> list) {
    return DocumentKey{ResourcePath{list}};
  }

  /** Returns a shared instance of an empty document key. */
  static const DocumentKey& Empty();

  /** Returns true iff the given path is a path to a document. */
  static bool IsDocumentKey(const ResourcePath& path) {
    return path.size() % 2 == 0;
  }

  /** The path to the document. */
  const ResourcePath& path() const {
    return path_ ? *path_ : Empty().path();
  }

  /** Returns true if the document is in the specified collectionId. */
  bool HasCollectionId(absl::string_view collection_id) const {
    size_t size = path().size();
    return size >= 2 && path()[size - 2] == collection_id;
  }

 private:
  // This is an optimization to make passing DocumentKey around cheaper (it's
  // copied often).
  std::shared_ptr<const ResourcePath> path_;
};

inline bool operator==(const DocumentKey& lhs, const DocumentKey& rhs) {
  return lhs.path() == rhs.path();
}
inline bool operator!=(const DocumentKey& lhs, const DocumentKey& rhs) {
  return lhs.path() != rhs.path();
}
inline bool operator<(const DocumentKey& lhs, const DocumentKey& rhs) {
  return lhs.path() < rhs.path();
}
inline bool operator<=(const DocumentKey& lhs, const DocumentKey& rhs) {
  return lhs.path() <= rhs.path();
}
inline bool operator>(const DocumentKey& lhs, const DocumentKey& rhs) {
  return lhs.path() > rhs.path();
}
inline bool operator>=(const DocumentKey& lhs, const DocumentKey& rhs) {
  return lhs.path() >= rhs.path();
}

struct DocumentKeyHash {
  size_t operator()(const DocumentKey& key) const {
    return util::Hash(key.path());
  }
};

#if defined(__OBJC__)
inline NSComparisonResult CompareKeys(const DocumentKey& lhs,
                                      const DocumentKey& rhs) {
  if (lhs < rhs) {
    return NSOrderedAscending;
  }
  if (lhs > rhs) {
    return NSOrderedDescending;
  }
  return NSOrderedSame;
}

#endif  // defined(__OBJC__)

}  // namespace model

namespace util {

template <>
struct Comparator<model::DocumentKey> : public std::less<model::DocumentKey> {};

}  // namespace util
}  // namespace firestore
}  // namespace firebase

#endif  // FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_MODEL_DOCUMENT_KEY_H_
