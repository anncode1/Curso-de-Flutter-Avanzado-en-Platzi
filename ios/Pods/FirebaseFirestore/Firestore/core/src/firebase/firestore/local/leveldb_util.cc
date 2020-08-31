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

#include "Firestore/core/src/firebase/firestore/local/leveldb_util.h"

#include "Firestore/core/include/firebase/firestore/firestore_errors.h"
#include "absl/strings/str_cat.h"

namespace firebase {
namespace firestore {
namespace local {

namespace {

FirestoreErrorCode ConvertStatusCode(const leveldb::Status& status) {
  if (status.ok()) return FirestoreErrorCode::Ok;
  if (status.IsNotFound()) return FirestoreErrorCode::NotFound;
  if (status.IsCorruption()) return FirestoreErrorCode::DataLoss;
  if (status.IsIOError()) return FirestoreErrorCode::Unavailable;
  if (status.IsNotSupportedError()) return FirestoreErrorCode::Unimplemented;
  if (status.IsInvalidArgument()) return FirestoreErrorCode::InvalidArgument;
  return FirestoreErrorCode::Unknown;
}

}  // namespace

util::Status ConvertStatus(const leveldb::Status& status) {
  if (status.ok()) return util::Status::OK();

  FirestoreErrorCode code = ConvertStatusCode(status);
  return util::Status{code, absl::StrCat("LevelDB error: ", status.ToString())};
}

}  // namespace local
}  // namespace firestore
}  // namespace firebase
