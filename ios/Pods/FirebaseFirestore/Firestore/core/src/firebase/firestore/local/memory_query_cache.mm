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

#include "Firestore/core/src/firebase/firestore/local/memory_query_cache.h"

#import <Protobuf/GPBMessage.h>

#include <vector>

#import "Firestore/Protos/objc/firestore/local/Target.pbobjc.h"
#import "Firestore/Source/Core/FSTQuery.h"
#import "Firestore/Source/Local/FSTMemoryPersistence.h"
#import "Firestore/Source/Local/FSTQueryData.h"

#include "Firestore/core/src/firebase/firestore/model/document_key.h"

using firebase::firestore::model::DocumentKey;
using firebase::firestore::model::DocumentKeySet;
using firebase::firestore::model::ListenSequenceNumber;
using firebase::firestore::model::SnapshotVersion;
using firebase::firestore::model::TargetId;

namespace firebase {
namespace firestore {
namespace local {

NS_ASSUME_NONNULL_BEGIN

MemoryQueryCache::MemoryQueryCache(FSTMemoryPersistence* persistence)
    : persistence_(persistence),
      highest_listen_sequence_number_(ListenSequenceNumber(0)),
      highest_target_id_(TargetId(0)),
      last_remote_snapshot_version_(SnapshotVersion::None()),
      queries_() {
}

void MemoryQueryCache::AddTarget(FSTQueryData* query_data) {
  queries_[query_data.query] = query_data;
  if (query_data.targetID > highest_target_id_) {
    highest_target_id_ = query_data.targetID;
  }
  if (query_data.sequenceNumber > highest_listen_sequence_number_) {
    highest_listen_sequence_number_ = query_data.sequenceNumber;
  }
}

void MemoryQueryCache::UpdateTarget(FSTQueryData* query_data) {
  // For the memory query cache, adds and updates are treated the same.
  AddTarget(query_data);
}

void MemoryQueryCache::RemoveTarget(FSTQueryData* query_data) {
  queries_.erase(query_data.query);
  references_.RemoveReferences(query_data.targetID);
}

FSTQueryData* _Nullable MemoryQueryCache::GetTarget(FSTQuery* query) {
  auto iter = queries_.find(query);
  return iter == queries_.end() ? nil : iter->second;
}

void MemoryQueryCache::EnumerateTargets(const TargetCallback& callback) {
  for (const auto& kv : queries_) {
    callback(kv.second);
  }
}

int MemoryQueryCache::RemoveTargets(
    model::ListenSequenceNumber upper_bound,
    const std::unordered_map<TargetId, FSTQueryData*>& live_targets) {
  std::vector<FSTQuery*> to_remove;
  for (const auto& kv : queries_) {
    FSTQuery* query = kv.first;
    FSTQueryData* query_data = kv.second;

    if (query_data.sequenceNumber <= upper_bound) {
      if (live_targets.find(query_data.targetID) == live_targets.end()) {
        to_remove.push_back(query);
        references_.RemoveReferences(query_data.targetID);
      }
    }
  }

  for (FSTQuery* element : to_remove) {
    queries_.erase(element);
  }
  return static_cast<int>(to_remove.size());
}

void MemoryQueryCache::AddMatchingKeys(const DocumentKeySet& keys,
                                       TargetId target_id) {
  references_.AddReferences(keys, target_id);
  for (const DocumentKey& key : keys) {
    [persistence_.referenceDelegate addReference:key];
  }
}

void MemoryQueryCache::RemoveMatchingKeys(const DocumentKeySet& keys,
                                          TargetId target_id) {
  references_.RemoveReferences(keys, target_id);
  for (const DocumentKey& key : keys) {
    [persistence_.referenceDelegate removeReference:key];
  }
}

DocumentKeySet MemoryQueryCache::GetMatchingKeys(TargetId target_id) {
  return references_.ReferencedKeys(target_id);
}

bool MemoryQueryCache::Contains(const DocumentKey& key) {
  return references_.ContainsKey(key);
}

size_t MemoryQueryCache::CalculateByteSize(FSTLocalSerializer* serializer) {
  size_t count = 0;
  for (const auto& kv : queries_) {
    FSTQueryData* query_data = kv.second;
    count += [[serializer encodedQueryData:query_data] serializedSize];
  }
  return count;
}

const SnapshotVersion& MemoryQueryCache::GetLastRemoteSnapshotVersion() const {
  return last_remote_snapshot_version_;
}

void MemoryQueryCache::SetLastRemoteSnapshotVersion(SnapshotVersion version) {
  last_remote_snapshot_version_ = std::move(version);
}

NS_ASSUME_NONNULL_END

}  // namespace local
}  // namespace firestore
}  // namespace firebase
