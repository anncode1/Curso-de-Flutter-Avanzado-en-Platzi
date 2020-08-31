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

#include "Firestore/core/src/firebase/firestore/local/leveldb_mutation_queue.h"

#include <memory>
#include <utility>

#import "Firestore/Protos/objc/firestore/local/Mutation.pbobjc.h"
#import "Firestore/Source/Core/FSTQuery.h"
#import "Firestore/Source/Local/FSTLevelDB.h"
#import "Firestore/Source/Local/FSTLocalSerializer.h"
#import "Firestore/Source/Model/FSTMutation.h"
#import "Firestore/Source/Model/FSTMutationBatch.h"

#include "Firestore/core/src/firebase/firestore/local/leveldb_util.h"
#include "Firestore/core/src/firebase/firestore/model/mutation_batch.h"
#include "Firestore/core/src/firebase/firestore/model/resource_path.h"
#include "Firestore/core/src/firebase/firestore/util/string_util.h"
#include "Firestore/core/src/firebase/firestore/util/to_string.h"
#include "absl/strings/match.h"

NS_ASSUME_NONNULL_BEGIN

namespace firebase {
namespace firestore {
namespace local {

using auth::User;
using leveldb::DB;
using leveldb::Iterator;
using leveldb::Status;
using model::BatchId;
using model::DocumentKey;
using model::DocumentKeySet;
using model::kBatchIdUnknown;
using model::ResourcePath;

BatchId LoadNextBatchIdFromDb(DB* db) {
  // TODO(gsoltis): implement Prev() and SeekToLast() on
  // LevelDbTransaction::Iterator, then port this to a transaction.
  std::unique_ptr<Iterator> it(
      db->NewIterator(LevelDbTransaction::DefaultReadOptions()));

  std::string table_key = LevelDbMutationKey::KeyPrefix();

  LevelDbMutationKey row_key;
  BatchId max_batch_id = kBatchIdUnknown;

  bool more_user_ids = false;
  std::string next_user_id;

  it->Seek(table_key);
  if (it->Valid() && row_key.Decode(MakeStringView(it->key()))) {
    more_user_ids = true;
    next_user_id = row_key.user_id();
  }

  // This loop assumes that nextUserId contains the next username at the start
  // of the iteration.
  while (more_user_ids) {
    // Compute the first key after the last mutation for next_user_id.
    std::string user_end = LevelDbMutationKey::KeyPrefix(next_user_id);
    user_end = util::PrefixSuccessor(user_end);

    // Seek to that key with the intent of finding the boundary between
    // next_user_id's mutations and the one after that (if any).
    it->Seek(user_end);

    // At this point there are three possible cases to handle differently. Each
    // case must prepare the next iteration (by assigning to next_user_id or
    // setting more_user_ids = NO) and seek the iterator to the last row in the
    // current user's mutation sequence.
    if (!it->Valid()) {
      // The iterator is past the last row altogether (there are no additional
      // userIDs and now rows in any table after mutations). The last row will
      // have the highest batchID.
      more_user_ids = false;
      it->SeekToLast();

    } else if (row_key.Decode(MakeStringView(it->key()))) {
      // The iterator is valid and the key decoded successfully so the next user
      // was just decoded.
      next_user_id = row_key.user_id();
      it->Prev();

    } else {
      // The iterator is past the end of the mutations table but there are other
      // rows.
      more_user_ids = false;
      it->Prev();
    }

    // In all the cases above there was at least one row for the current user
    // and each case has set things up such that iterator points to it.
    if (!row_key.Decode(MakeStringView(it->key()))) {
      HARD_FAIL("There should have been a key previous to %s", user_end);
    }

    if (row_key.batch_id() > max_batch_id) {
      max_batch_id = row_key.batch_id();
    }
  }

  return max_batch_id + 1;
}

LevelDbMutationQueue::LevelDbMutationQueue(const User& user,
                                           FSTLevelDB* db,
                                           FSTLocalSerializer* serializer)
    : db_(db),
      serializer_(serializer),
      user_id_(user.is_authenticated() ? user.uid() : "") {
}

void LevelDbMutationQueue::Start() {
  next_batch_id_ = LoadNextBatchIdFromDb(db_.ptr);

  std::string key = mutation_queue_key();
  FSTPBMutationQueue* metadata = MetadataForKey(key);
  if (!metadata) {
    metadata = [FSTPBMutationQueue message];
  }
  metadata_ = metadata;
}

bool LevelDbMutationQueue::IsEmpty() {
  std::string user_key = LevelDbMutationKey::KeyPrefix(user_id_);

  auto it = db_.currentTransaction->NewIterator();
  it->Seek(user_key);

  bool empty = true;
  if (it->Valid() && absl::StartsWith(it->key(), user_key)) {
    empty = false;
  }
  return empty;
}

void LevelDbMutationQueue::AcknowledgeBatch(FSTMutationBatch* batch,
                                            NSData* _Nullable stream_token) {
  SetLastStreamToken(stream_token);
}

FSTMutationBatch* LevelDbMutationQueue::AddMutationBatch(
    FIRTimestamp* local_write_time,
    std::vector<FSTMutation*>&& base_mutations,
    std::vector<FSTMutation*>&& mutations) {
  BatchId batch_id = next_batch_id_;
  next_batch_id_++;

  FSTMutationBatch* batch =
      [[FSTMutationBatch alloc] initWithBatchID:batch_id
                                 localWriteTime:local_write_time
                                  baseMutations:std::move(base_mutations)
                                      mutations:std::move(mutations)];
  std::string key = mutation_batch_key(batch_id);
  db_.currentTransaction->Put(key, [serializer_ encodedMutationBatch:batch]);

  // Store an empty value in the index which is equivalent to serializing a
  // GPBEmpty message. In the future if we wanted to store some other kind of
  // value here, we can parse these empty values as with some other protocol
  // buffer (and the parser will see all default values).
  std::string empty_buffer;

  for (FSTMutation* mutation : [batch mutations]) {
    key = LevelDbDocumentMutationKey::Key(user_id_, mutation.key, batch_id);
    db_.currentTransaction->Put(key, empty_buffer);

    db_.indexManager->AddToCollectionParentIndex(mutation.key.path().PopLast());
  }

  return batch;
}

void LevelDbMutationQueue::RemoveMutationBatch(FSTMutationBatch* batch) {
  auto check_iterator = db_.currentTransaction->NewIterator();

  BatchId batch_id = batch.batchID;
  std::string key = mutation_batch_key(batch_id);

  // As a sanity check, verify that the mutation batch exists before deleting
  // it.
  check_iterator->Seek(key);
  HARD_ASSERT(check_iterator->Valid(), "Mutation batch %s did not exist",
              DescribeKey(key));

  HARD_ASSERT(key == check_iterator->key(),
              "Mutation batch %s not found; found %s", DescribeKey(key),
              DescribeKey(check_iterator->key()));

  db_.currentTransaction->Delete(key);

  for (FSTMutation* mutation : [batch mutations]) {
    key = LevelDbDocumentMutationKey::Key(user_id_, mutation.key, batch_id);
    db_.currentTransaction->Delete(key);
    [db_.referenceDelegate removeMutationReference:mutation.key];
  }
}

std::vector<FSTMutationBatch*> LevelDbMutationQueue::AllMutationBatches() {
  std::string user_key = LevelDbMutationKey::KeyPrefix(user_id_);

  auto it = db_.currentTransaction->NewIterator();
  it->Seek(user_key);
  std::vector<FSTMutationBatch*> result;
  for (; it->Valid() && absl::StartsWith(it->key(), user_key); it->Next()) {
    result.push_back(ParseMutationBatch(it->value()));
  }
  return result;
}

std::vector<FSTMutationBatch*>
LevelDbMutationQueue::AllMutationBatchesAffectingDocumentKeys(
    const DocumentKeySet& document_keys) {
  // Take a pass through the document keys and collect the set of unique
  // mutation batch_ids that affect them all. Some batches can affect more than
  // one key.
  std::set<BatchId> batch_ids;

  auto index_iterator = db_.currentTransaction->NewIterator();
  LevelDbDocumentMutationKey row_key;
  for (const DocumentKey& document_key : document_keys) {
    std::string index_prefix =
        LevelDbDocumentMutationKey::KeyPrefix(user_id_, document_key.path());
    for (index_iterator->Seek(index_prefix); index_iterator->Valid();
         index_iterator->Next()) {
      // Only consider rows matching exactly the specific key of interest. Index
      // rows have this form (with markers in brackets):
      //
      // <User>user <Path>collection <Path>doc <BatchId>2 <Terminator>
      // <User>user <Path>collection <Path>doc <BatchId>3 <Terminator>
      // <User>user <Path>collection <Path>doc <Path>sub <Path>doc <BatchId>3
      // <Terminator>
      //
      // Note that Path markers sort after BatchId markers so this means that
      // when searching for collection/doc, all the entries for it will be
      // contiguous in the table, allowing a break after any mismatch.
      if (!absl::StartsWith(index_iterator->key(), index_prefix) ||
          !row_key.Decode(index_iterator->key()) ||
          row_key.document_key() != document_key) {
        break;
      }

      batch_ids.insert(row_key.batch_id());
    }
  }

  return AllMutationBatchesWithIds(batch_ids);
}

std::vector<FSTMutationBatch*>
LevelDbMutationQueue::AllMutationBatchesAffectingDocumentKey(
    const DocumentKey& key) {
  return AllMutationBatchesAffectingDocumentKeys(DocumentKeySet{key});
}

std::vector<FSTMutationBatch*>
LevelDbMutationQueue::AllMutationBatchesAffectingQuery(FSTQuery* query) {
  HARD_ASSERT(![query isDocumentQuery],
              "Document queries shouldn't go down this path");
  HARD_ASSERT(
      ![query isCollectionGroupQuery],
      "CollectionGroup queries should be handled in LocalDocumentsView");

  const ResourcePath& query_path = query.path;
  size_t immediate_children_path_length = query_path.size() + 1;

  // TODO(mcg): Actually implement a single-collection query
  //
  // This is actually executing an ancestor query, traversing the whole subtree
  // below the collection which can be horrifically inefficient for some
  // structures. The right way to solve this is to implement the full value
  // index, but that's not in the cards in the near future so this is the best
  // we can do for the moment.
  //
  // Since we don't yet index the actual properties in the mutations, our
  // current approach is to just return all mutation batches that affect
  // documents in the collection being queried.
  //
  // Unlike allMutationBatchesAffectingDocumentKey, this iteration will scan the
  // document-mutation index for more than a single document so the associated
  // batchIDs will be neither necessarily unique nor in order. This means an
  // efficient simultaneous scan isn't possible.
  std::string index_prefix =
      LevelDbDocumentMutationKey::KeyPrefix(user_id_, query_path);
  auto index_iterator = db_.currentTransaction->NewIterator();
  index_iterator->Seek(index_prefix);

  LevelDbDocumentMutationKey row_key;

  // Collect up unique batchIDs encountered during a scan of the index. Use a
  // set<BatchId> to accumulate batch IDs so they can be traversed in order in a
  // scan of the main table.
  //
  // This method is faster than performing lookups of the keys with _db->Get and
  // keeping a hash of batchIDs that have already been looked up. The
  // performance difference is minor for small numbers of keys but > 30% faster
  // for larger numbers of keys.
  std::set<BatchId> unique_batch_ids;
  for (; index_iterator->Valid(); index_iterator->Next()) {
    if (!absl::StartsWith(index_iterator->key(), index_prefix) ||
        !row_key.Decode(index_iterator->key())) {
      break;
    }

    // Rows with document keys more than one segment longer than the query path
    // can't be matches. For example, a query on 'rooms' can't match the
    // document /rooms/abc/messages/xyx.
    // TODO(mcg): we'll need a different scanner when we implement ancestor
    // queries.
    if (row_key.document_key().path().size() !=
        immediate_children_path_length) {
      continue;
    }

    unique_batch_ids.insert(row_key.batch_id());
  }

  return AllMutationBatchesWithIds(unique_batch_ids);
}

FSTMutationBatch* _Nullable LevelDbMutationQueue::LookupMutationBatch(
    model::BatchId batch_id) {
  std::string key = mutation_batch_key(batch_id);

  std::string value;
  Status status = db_.currentTransaction->Get(key, &value);
  if (!status.ok()) {
    if (status.IsNotFound()) {
      return nil;
    }
    HARD_FAIL("Lookup mutation batch (%s, %s) failed with status: %s", user_id_,
              batch_id, status.ToString());
  }

  return ParseMutationBatch(value);
}

FSTMutationBatch* _Nullable LevelDbMutationQueue::NextMutationBatchAfterBatchId(
    model::BatchId batch_id) {
  BatchId next_batch_id = batch_id + 1;

  std::string key = mutation_batch_key(next_batch_id);
  auto it = db_.currentTransaction->NewIterator();
  it->Seek(key);

  LevelDbMutationKey row_key;
  if (!it->Valid() || !row_key.Decode(it->key())) {
    // Past the last row in the DB or out of the mutations table
    return nil;
  }

  if (row_key.user_id() != user_id_) {
    // Jumped past the last mutation for this user
    return nil;
  }

  HARD_ASSERT(row_key.batch_id() >= next_batch_id,
              "Should have found mutation after %s", next_batch_id);
  return ParseMutationBatch(it->value());
}

void LevelDbMutationQueue::PerformConsistencyCheck() {
  if (!IsEmpty()) {
    return;
  }

  // Verify that there are no entries in the document-mutation index if the
  // queue is empty.
  std::string index_prefix = LevelDbDocumentMutationKey::KeyPrefix(user_id_);
  auto index_iterator = db_.currentTransaction->NewIterator();
  index_iterator->Seek(index_prefix);

  std::vector<std::string> dangling_mutation_references;

  for (; index_iterator->Valid(); index_iterator->Next()) {
    // Only consider rows matching this index prefix for the current user.
    if (!absl::StartsWith(index_iterator->key(), index_prefix)) {
      break;
    }

    dangling_mutation_references.push_back(DescribeKey(index_iterator));
  }

  HARD_ASSERT(
      dangling_mutation_references.empty(),
      "Document leak -- detected dangling mutation references when queue "
      "is empty. Dangling keys: %s",
      util::ToString(dangling_mutation_references));
}

NSData* _Nullable LevelDbMutationQueue::GetLastStreamToken() {
  return metadata_.lastStreamToken;
}

void LevelDbMutationQueue::SetLastStreamToken(NSData* _Nullable stream_token) {
  metadata_.lastStreamToken = stream_token;

  db_.currentTransaction->Put(mutation_queue_key(), metadata_);
}

std::vector<FSTMutationBatch*> LevelDbMutationQueue::AllMutationBatchesWithIds(
    const std::set<BatchId>& batch_ids) {
  std::vector<FSTMutationBatch*> result;

  // Given an ordered set of unique batchIDs perform a skipping scan over the
  // main table to find the mutation batches.
  auto mutation_iterator = db_.currentTransaction->NewIterator();
  for (BatchId batch_id : batch_ids) {
    std::string mutation_key = mutation_batch_key(batch_id);
    mutation_iterator->Seek(mutation_key);
    if (!mutation_iterator->Valid() ||
        mutation_iterator->key() != mutation_key) {
      HARD_FAIL("Dangling document-mutation reference found: "
                "Missing batch %s; seeking there found %s",
                DescribeKey(mutation_key), DescribeKey(mutation_iterator));
    }

    result.push_back(ParseMutationBatch(mutation_iterator->value()));
  }
  return result;
}

FSTPBMutationQueue* _Nullable LevelDbMutationQueue::MetadataForKey(
    const std::string& key) {
  std::string value;
  Status status = db_.currentTransaction->Get(key, &value);
  if (status.ok()) {
    NSData* data = [[NSData alloc] initWithBytesNoCopy:(void*)value.data()
                                                length:value.size()
                                          freeWhenDone:NO];

    NSError* error;
    FSTPBMutationQueue* proto = [FSTPBMutationQueue parseFromData:data
                                                            error:&error];
    if (!proto) {
      HARD_FAIL("FSTPBMutationQueue failed to parse: %s", error);
    }
    return proto;
  } else if (status.IsNotFound()) {
    return nil;
  } else {
    HARD_FAIL("MetadataForKey: failed loading key %s with status: %s", key,
              status.ToString());
  }
}

FSTMutationBatch* LevelDbMutationQueue::ParseMutationBatch(
    absl::string_view encoded) {
  NSData* data = [[NSData alloc] initWithBytesNoCopy:(void*)encoded.data()
                                              length:encoded.size()
                                        freeWhenDone:NO];

  NSError* error;
  FSTPBWriteBatch* proto = [FSTPBWriteBatch parseFromData:data error:&error];
  if (!proto) {
    HARD_FAIL("FSTPBMutationBatch failed to parse: %s", error);
  }

  return [serializer_ decodedMutationBatch:proto];
}

}  // namespace local
}  // namespace firestore
}  // namespace firebase

NS_ASSUME_NONNULL_END
