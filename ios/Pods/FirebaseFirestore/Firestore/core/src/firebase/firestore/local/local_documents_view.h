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

#ifndef FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_LOCAL_LOCAL_DOCUMENTS_VIEW_H_
#define FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_LOCAL_LOCAL_DOCUMENTS_VIEW_H_

#import <Foundation/Foundation.h>

#include <vector>

#include "Firestore/core/src/firebase/firestore/local/index_manager.h"
#include "Firestore/core/src/firebase/firestore/local/mutation_queue.h"
#include "Firestore/core/src/firebase/firestore/local/remote_document_cache.h"
#include "Firestore/core/src/firebase/firestore/model/document_key.h"
#include "Firestore/core/src/firebase/firestore/model/document_key_set.h"
#include "Firestore/core/src/firebase/firestore/model/document_map.h"

NS_ASSUME_NONNULL_BEGIN

@class FSTMaybeDocument;
@class FSTMutationBatch;
@class FSTQuery;

namespace firebase {
namespace firestore {
namespace local {

/**
 * A readonly view of the local state of all documents we're tracking (i.e. we
 * have a cached version in remoteDocumentCache or local mutations for the
 * document). The view is computed by applying the mutations in the
 * FSTMutationQueue to the FSTRemoteDocumentCache.
 */
class LocalDocumentsView {
 public:
  LocalDocumentsView(RemoteDocumentCache* remote_document_cache,
                     MutationQueue* mutation_queue,
                     IndexManager* index_manager)
      : remote_document_cache_{remote_document_cache},
        mutation_queue_{mutation_queue},
        index_manager_{index_manager} {
  }

  /**
   * Gets the local view of the document identified by `key`.
   *
   * @return Local view of the document or nil if we don't have any cached state
   * for it.
   */
  FSTMaybeDocument* _Nullable GetDocument(const model::DocumentKey& key);

  /**
   * Gets the local view of the documents identified by `keys`.
   *
   * If we don't have cached state for a document in `keys`, a
   * FSTDeletedDocument will be stored for that key in the resulting set.
   */
  model::MaybeDocumentMap GetDocuments(const model::DocumentKeySet& keys);

  /**
   * Similar to `documentsForKeys`, but creates the local view from the given
   * `baseDocs` without retrieving documents from the local store.
   */
  model::MaybeDocumentMap GetLocalViewOfDocuments(
      const model::MaybeDocumentMap& base_docs);

  /** Performs a query against the local view of all documents. */
  model::DocumentMap GetDocumentsMatchingQuery(FSTQuery* query);

 private:
  /** Internal version of GetDocument that allows re-using batches. */
  FSTMaybeDocument* _Nullable GetDocument(
      const model::DocumentKey& key,
      const std::vector<FSTMutationBatch*>& batches);

  /**
   * Returns the view of the given `docs` as they would appear after applying
   * all mutations in the given `batches`.
   */
  model::MaybeDocumentMap ApplyLocalMutationsToDocuments(
      const model::MaybeDocumentMap& docs,
      const std::vector<FSTMutationBatch*>& batches);

  /** Performs a simple document lookup for the given path. */
  model::DocumentMap GetDocumentsMatchingDocumentQuery(
      const model::ResourcePath& doc_path);

  model::DocumentMap GetDocumentsMatchingCollectionGroupQuery(FSTQuery* query);

  /** Queries the remote documents and overlays mutations. */
  model::DocumentMap GetDocumentsMatchingCollectionQuery(FSTQuery* query);

  RemoteDocumentCache* remote_document_cache_;
  MutationQueue* mutation_queue_;
  IndexManager* index_manager_;
};

}  // namespace local
}  // namespace firestore
}  // namespace firebase

NS_ASSUME_NONNULL_END

#endif  // FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_LOCAL_LOCAL_DOCUMENTS_VIEW_H_
