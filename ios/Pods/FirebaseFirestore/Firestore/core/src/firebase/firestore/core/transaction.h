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

#ifndef FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_CORE_TRANSACTION_H_
#define FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_CORE_TRANSACTION_H_

#if !defined(__OBJC__)
#error "This header only supports Objective-C++"
#endif  // !defined(__OBJC__)

#include <functional>
#include <unordered_map>
#include <vector>

#include "Firestore/core/src/firebase/firestore/core/user_data.h"
#include "Firestore/core/src/firebase/firestore/model/document_key.h"
#include "Firestore/core/src/firebase/firestore/model/precondition.h"
#include "Firestore/core/src/firebase/firestore/model/snapshot_version.h"
#include "Firestore/core/src/firebase/firestore/remote/datastore.h"
#include "Firestore/core/src/firebase/firestore/util/status.h"
#include "Firestore/core/src/firebase/firestore/util/statusor.h"
#include "absl/types/optional.h"

NS_ASSUME_NONNULL_BEGIN

@class FSTMaybeDocument;
@class FSTMutation;

namespace firebase {
namespace firestore {
namespace core {

class Transaction {
 public:
  // TODO(varconst): once `FSTMaybeDocument` is replaced with a C++ equivalent,
  // this function could take a single `StatusOr` parameter.
  using LookupCallback = std::function<void(
      const std::vector<FSTMaybeDocument*>&, const util::Status&)>;
  using CommitCallback = std::function<void(const util::Status&)>;

  Transaction() = default;
  explicit Transaction(remote::Datastore* transaction);

  /**
   * Takes a set of keys and asynchronously attempts to fetch all the documents
   * from the backend, ignoring any local changes.
   */
  void Lookup(const std::vector<model::DocumentKey>& keys,
              LookupCallback&& callback);

  /**
   * Stores mutation for the given key and set data, to be committed when
   * `Commit` is called.
   */
  void Set(const model::DocumentKey& key, ParsedSetData&& data);

  /**
   * Stores mutations for the given key and update data, to be committed when
   * `Commit` is called.
   */
  void Update(const model::DocumentKey& key, ParsedUpdateData&& data);

  /**
   * Stores a delete mutation for the given key, to be committed when `Commit`
   * is called.
   */
  void Delete(const model::DocumentKey& key);

  /**
   * Attempts to commit the mutations set on this transaction. Invokes the given
   * callback when finished. Once this is called, no other mutations or
   * commits are allowed on the transaction.
   */
  void Commit(CommitCallback&& callback);

 private:
  /**
   * Every time a document is read, this should be called to record its version.
   * If we read two different versions of the same document, this will return an
   * error. When the transaction is committed, the versions recorded will be set
   * as preconditions on the writes sent to the backend.
   */
  util::Status RecordVersion(FSTMaybeDocument* doc);

  /** Stores mutations to be written when `Commit` is called. */
  void WriteMutations(std::vector<FSTMutation*>&& mutations);

  /**
   * Returns version of this doc when it was read in this transaction as a
   * precondition, or no precondition if it was not read.
   */
  model::Precondition CreatePrecondition(const model::DocumentKey& key);

  /**
   * Returns the precondition for a document if the operation is an update. Will
   * return a failed status if an error occurred.
   */
  util::StatusOr<model::Precondition> CreateUpdatePrecondition(
      const model::DocumentKey& key);

  void EnsureCommitNotCalled();

  absl::optional<model::SnapshotVersion> GetVersion(
      const model::DocumentKey& key) const;

  remote::Datastore* datastore_ = nullptr;

  std::vector<FSTMutation*> mutations_;
  bool committed_ = false;

  /**
   * An error that may have occurred as a consequence of a write. If set, needs
   * to be raised in the completion handler instead of trying to commit.
   */
  util::Status last_write_error_;

  std::unordered_map<model::DocumentKey,
                     model::SnapshotVersion,
                     model::DocumentKeyHash>
      read_versions_;
};

}  // namespace core
}  // namespace firestore
}  // namespace firebase

NS_ASSUME_NONNULL_END

#endif  // FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_CORE_TRANSACTION_H_
