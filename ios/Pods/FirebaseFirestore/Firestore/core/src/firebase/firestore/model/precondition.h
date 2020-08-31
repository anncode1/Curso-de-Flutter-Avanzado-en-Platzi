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

#ifndef FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_MODEL_PRECONDITION_H_
#define FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_MODEL_PRECONDITION_H_

#include <utility>

#if defined(__OBJC__)
#import "Firestore/Source/Model/FSTDocument.h"
#include "Firestore/core/include/firebase/firestore/timestamp.h"
#endif  // defined(__OBJC__)

#include "Firestore/core/src/firebase/firestore/model/maybe_document.h"
#include "Firestore/core/src/firebase/firestore/model/snapshot_version.h"
#include "Firestore/core/src/firebase/firestore/util/hard_assert.h"

namespace firebase {
namespace firestore {
namespace model {

/**
 * Encodes a precondition for a mutation. This follows the model that the
 * backend accepts with the special case of an explicit "empty" precondition
 * (meaning no precondition).
 */
class Precondition {
 public:
  enum class Type {
    None,
    Exists,
    UpdateTime,
  };

  /** Creates a new Precondition with an exists flag. */
  static Precondition Exists(bool exists);

  /** Creates a new Precondition based on a time the document exists at. */
  static Precondition UpdateTime(SnapshotVersion update_time);

  /** Returns a precondition representing no precondition. */
  static Precondition None();

  /**
   * Returns true if the precondition is valid for the given document (and the
   * document is available).
   */
  bool IsValidFor(const MaybeDocument* maybe_doc) const;

  /** Returns whether this Precondition represents no precondition. */
  bool IsNone() const {
    return type_ == Type::None;
  }

  Type type() const {
    return type_;
  }

  const SnapshotVersion& update_time() const {
    return update_time_;
  }

  bool exists() const {
    return exists_;
  }

  bool operator==(const Precondition& other) const {
    return type_ == other.type_ && update_time_ == other.update_time_ &&
           exists_ == other.exists_;
  }

#if defined(__OBJC__)
  // Objective-C requires a default constructor.
  Precondition()
      : type_(Type::None),
        update_time_(SnapshotVersion::None()),
        exists_(false) {
  }

  // MaybeDocument is not fully ported yet. So we suppose this addition helper.
  bool IsValidFor(FSTMaybeDocument* maybe_doc) const {
    switch (type_) {
      case Type::UpdateTime:
        return [maybe_doc isKindOfClass:[FSTDocument class]] &&
               firebase::firestore::model::SnapshotVersion(maybe_doc.version) ==
                   update_time_;
      case Type::Exists:
        if (exists_) {
          return [maybe_doc isKindOfClass:[FSTDocument class]];
        } else {
          return maybe_doc == nil ||
                 [maybe_doc isKindOfClass:[FSTDeletedDocument class]];
        }
      case Type::None:
        return true;
    }
    UNREACHABLE();
  }

  // For Objective-C++ hash; to be removed after migration.
  // Do NOT use in C++ code.
  NSUInteger Hash() const {
    NSUInteger hash = std::hash<Timestamp>()(update_time_.timestamp());
    hash = hash * 31 + exists_;
    hash = hash * 31 + static_cast<NSUInteger>(type_);
    return hash;
  }

  NSString* description() const {
    switch (type_) {
      case Type::None:
        return @"<Precondition <none>>";
      case Type::Exists:
        if (exists_) {
          return @"<Precondition exists=yes>";
        } else {
          return @"<Precondition exists=no>";
        }
      case Type::UpdateTime:
        return [NSString
            stringWithFormat:@"<Precondition update_time=%s>",
                             update_time_.timestamp().ToString().c_str()];
    }
    UNREACHABLE();
  }
#endif  // defined(__OBJC__)

 private:
  Precondition(Type type, SnapshotVersion update_time, bool exists);

  // The actual time of this precondition.
  Type type_ = Type::None;

  // For UpdateTime type, preconditions a mutation based on the last updateTime.
  SnapshotVersion update_time_;

  // For Exists type, preconditions a mutation based on whether the document
  // exists.
  bool exists_;
};

}  // namespace model
}  // namespace firestore
}  // namespace firebase

#endif  // FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_MODEL_PRECONDITION_H_
