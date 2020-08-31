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

#import <Foundation/Foundation.h>

#include <memory>
#include <vector>

#import "Firestore/Source/Core/FSTTypes.h"

#include "Firestore/core/src/firebase/firestore/api/document_reference.h"
#include "Firestore/core/src/firebase/firestore/api/document_snapshot.h"
#include "Firestore/core/src/firebase/firestore/auth/credentials_provider.h"
#include "Firestore/core/src/firebase/firestore/core/database_info.h"
#include "Firestore/core/src/firebase/firestore/core/listen_options.h"
#include "Firestore/core/src/firebase/firestore/core/query_listener.h"
#include "Firestore/core/src/firebase/firestore/core/view_snapshot.h"
#include "Firestore/core/src/firebase/firestore/model/database_id.h"
#include "Firestore/core/src/firebase/firestore/util/async_queue.h"
#include "Firestore/core/src/firebase/firestore/util/executor.h"
#include "Firestore/core/src/firebase/firestore/util/statusor_callback.h"

@class FIRDocumentReference;
@class FIRDocumentSnapshot;
@class FIRFirestoreSettings;
@class FIRQuery;
@class FIRQuerySnapshot;
@class FSTDatabaseID;
@class FSTDatabaseInfo;
@class FSTDocument;
@class FSTMutation;
@class FSTQuery;
@class FSTTransaction;

NS_ASSUME_NONNULL_BEGIN

using firebase::firestore::api::DocumentSnapshot;
using firebase::firestore::core::ListenOptions;
using firebase::firestore::core::QueryListener;
using firebase::firestore::core::ViewSnapshot;

/**
 * FirestoreClient is a top-level class that constructs and owns all of the pieces of the client
 * SDK architecture. It is responsible for creating the worker queue that is shared by all of the
 * other components in the system.
 */
@interface FSTFirestoreClient : NSObject

/**
 * Creates and returns a FSTFirestoreClient with the given parameters.
 *
 * All callbacks and events will be triggered on the provided userExecutor.
 */
+ (instancetype)
    clientWithDatabaseInfo:(const firebase::firestore::core::DatabaseInfo &)databaseInfo
                  settings:(FIRFirestoreSettings *)settings
       credentialsProvider:(firebase::firestore::auth::CredentialsProvider *)
                               credentialsProvider  // no passing ownership
              userExecutor:(std::unique_ptr<firebase::firestore::util::Executor>)userExecutor
               workerQueue:(std::unique_ptr<firebase::firestore::util::AsyncQueue>)workerQueue;

- (instancetype)init __attribute__((unavailable("Use static constructor method.")));

/** Shuts down this client, cancels all writes / listeners, and releases all resources. */
- (void)shutdownWithCompletion:(nullable FSTVoidErrorBlock)completion;

/** Disables the network connection. Pending operations will not complete. */
- (void)disableNetworkWithCompletion:(nullable FSTVoidErrorBlock)completion;

/** Enables the network connection and requeues all pending operations. */
- (void)enableNetworkWithCompletion:(nullable FSTVoidErrorBlock)completion;

/** Starts listening to a query. */
- (std::shared_ptr<QueryListener>)listenToQuery:(FSTQuery *)query
                                        options:(ListenOptions)options
                                       listener:(ViewSnapshot::SharedListener &&)listener;

/** Stops listening to a query previously listened to. */
- (void)removeListener:(const std::shared_ptr<QueryListener> &)listener;

/**
 * Retrieves a document from the cache via the indicated completion. If the doc
 * doesn't exist, an error will be sent to the completion.
 */
- (void)getDocumentFromLocalCache:(const firebase::firestore::api::DocumentReference &)doc
                       completion:(DocumentSnapshot::Listener &&)completion;

/**
 * Retrieves a (possibly empty) set of documents from the cache via the
 * indicated completion.
 */
- (void)getDocumentsFromLocalCache:(FIRQuery *)query
                        completion:(void (^)(FIRQuerySnapshot *_Nullable query,
                                             NSError *_Nullable error))completion;

/** Write mutations. completion will be notified when it's written to the backend. */
- (void)writeMutations:(std::vector<FSTMutation *> &&)mutations
            completion:(nullable FSTVoidErrorBlock)completion;

/** Tries to execute the transaction in updateBlock up to retries times. */
- (void)transactionWithRetries:(int)retries
                   updateBlock:(FSTTransactionBlock)updateBlock
                    completion:(FSTVoidIDErrorBlock)completion;

/** The database ID of the databaseInfo this client was initialized with. */
// Ownes a DatabaseInfo instance, which contains the id here.
@property(nonatomic, assign, readonly) const firebase::firestore::model::DatabaseId *databaseID;

/**
 * Dispatch queue for user callbacks / events. This will often be the "Main Dispatch Queue" of the
 * app but the developer can configure it to a different queue if they so choose.
 */
- (firebase::firestore::util::Executor *)userExecutor;

/** For testing only. */
- (firebase::firestore::util::AsyncQueue *)workerQueue;

@end

NS_ASSUME_NONNULL_END
