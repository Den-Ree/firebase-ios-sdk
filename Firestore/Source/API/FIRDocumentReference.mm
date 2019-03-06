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

#import "FIRDocumentReference.h"

#include <memory>
#include <utility>

#import "FIRFirestoreErrors.h"
#import "FIRFirestoreSource.h"
#import "Firestore/Source/API/FIRCollectionReference+Internal.h"
#import "Firestore/Source/API/FIRDocumentReference+Internal.h"
#import "Firestore/Source/API/FIRDocumentSnapshot+Internal.h"
#import "Firestore/Source/API/FIRFirestore+Internal.h"
#import "Firestore/Source/API/FIRListenerRegistration+Internal.h"
#import "Firestore/Source/API/FSTUserDataConverter.h"
#import "Firestore/Source/Core/FSTEventManager.h"
#import "Firestore/Source/Core/FSTQuery.h"
#import "Firestore/Source/Model/FSTDocumentSet.h"
#import "Firestore/Source/Model/FSTFieldValue.h"
#import "Firestore/Source/Util/FSTUsageValidation.h"

#include "Firestore/core/src/firebase/firestore/api/document_reference.h"
#include "Firestore/core/src/firebase/firestore/api/document_snapshot.h"
#include "Firestore/core/src/firebase/firestore/api/handle_maybe.h"
#include "Firestore/core/src/firebase/firestore/model/document_key.h"
#include "Firestore/core/src/firebase/firestore/model/precondition.h"
#include "Firestore/core/src/firebase/firestore/model/resource_path.h"
#include "Firestore/core/src/firebase/firestore/util/error_apple.h"
#include "Firestore/core/src/firebase/firestore/util/status.h"
#include "Firestore/core/src/firebase/firestore/util/statusor.h"
#include "Firestore/core/src/firebase/firestore/util/string_apple.h"

namespace util = firebase::firestore::util;
using firebase::firestore::api::DocumentReference;
using firebase::firestore::api::DocumentSnapshot;
using firebase::firestore::api::HandleMaybe;
using firebase::firestore::core::ParsedSetData;
using firebase::firestore::core::ParsedUpdateData;
using firebase::firestore::model::DocumentKey;
using firebase::firestore::model::Precondition;
using firebase::firestore::model::ResourcePath;
using firebase::firestore::util::Status;
using firebase::firestore::util::StatusOr;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - FIRDocumentReference

@interface FIRDocumentReference ()
- (instancetype)initWithReference:(DocumentReference &&)reference
                        firestore:(FIRFirestore *)firestore NS_DESIGNATED_INITIALIZER;

@end

@implementation FIRDocumentReference {
  DocumentReference _documentReference;
}

- (instancetype)initWithReference:(DocumentReference &&)reference
                        firestore:(FIRFirestore *)firestore {
  if (self = [super init]) {
    _documentReference = std::move(reference);
    _firestore = firestore;
  }
  return self;
}

#pragma mark - NSObject Methods

- (BOOL)isEqual:(nullable id)other {
  if (other == self) return YES;
  if (![[other class] isEqual:[self class]]) return NO;

  return _documentReference == static_cast<FIRDocumentReference *>(other)->_documentReference;
}

- (NSUInteger)hash {
  return _documentReference.Hash();
}

#pragma mark - Public Methods

- (NSString *)documentID {
  return util::WrapNSString(_documentReference.document_id());
}

- (FIRCollectionReference *)parent {
  return [FIRCollectionReference referenceWithPath:_documentReference.key().path().PopLast()
                                         firestore:_firestore];
}

- (NSString *)path {
  return util::WrapNSString(_documentReference.Path());
}

- (FIRCollectionReference *)collectionWithPath:(NSString *)collectionPath {
  if (!collectionPath) {
    FSTThrowInvalidArgument(@"Collection path cannot be nil.");
  }

  ResourcePath sub_path = ResourcePath::FromString(util::MakeString(collectionPath));
  ResourcePath path = _documentReference.key().path().Append(sub_path);
  return [FIRCollectionReference referenceWithPath:path firestore:_firestore];
}

- (void)setData:(NSDictionary<NSString *, id> *)documentData {
  [self setData:documentData merge:NO completion:nil];
}

- (void)setData:(NSDictionary<NSString *, id> *)documentData merge:(BOOL)merge {
  [self setData:documentData merge:merge completion:nil];
}

- (void)setData:(NSDictionary<NSString *, id> *)documentData
    mergeFields:(NSArray<id> *)mergeFields {
  [self setData:documentData mergeFields:mergeFields completion:nil];
}

- (void)setData:(NSDictionary<NSString *, id> *)documentData
     completion:(nullable void (^)(NSError *_Nullable error))completion {
  [self setData:documentData merge:NO completion:completion];
}

- (void)setData:(NSDictionary<NSString *, id> *)documentData
          merge:(BOOL)merge
     completion:(nullable void (^)(NSError *_Nullable error))completion {
  ParsedSetData parsed = merge
                             ? [_firestore.dataConverter parsedMergeData:documentData fieldMask:nil]
                             : [_firestore.dataConverter parsedSetData:documentData];
  _documentReference.SetData(
      std::move(parsed).ToMutations(_documentReference.key(), Precondition::None()), completion);
}

- (void)setData:(NSDictionary<NSString *, id> *)documentData
    mergeFields:(NSArray<id> *)mergeFields
     completion:(nullable void (^)(NSError *_Nullable error))completion {
  ParsedSetData parsed = [_firestore.dataConverter parsedMergeData:documentData
                                                         fieldMask:mergeFields];
  _documentReference.SetData(
      std::move(parsed).ToMutations(_documentReference.key(), Precondition::None()), completion);
}

- (void)updateData:(NSDictionary<id, id> *)fields {
  [self updateData:fields completion:nil];
}

- (void)updateData:(NSDictionary<id, id> *)fields
        completion:(nullable void (^)(NSError *_Nullable error))completion {
  ParsedUpdateData parsed = [_firestore.dataConverter parsedUpdateData:fields];
  _documentReference.UpdateData(
      std::move(parsed).ToMutations(_documentReference.key(), Precondition::Exists(true)),
      completion);
}

- (void)deleteDocument {
  [self deleteDocumentWithCompletion:nil];
}

- (void)deleteDocumentWithCompletion:(nullable void (^)(NSError *_Nullable error))completion {
  _documentReference.DeleteDocument(completion);
}

- (void)getDocumentWithCompletion:(FIRDocumentSnapshotBlock)completion {
  _documentReference.GetDocument(FIRFirestoreSourceDefault,
                                 [self wrapDocumentSnapshotBlock:completion]);
}

- (void)getDocumentWithSource:(FIRFirestoreSource)source
                   completion:(FIRDocumentSnapshotBlock)completion {
  _documentReference.GetDocument(source, [self wrapDocumentSnapshotBlock:completion]);
}

- (id<FIRListenerRegistration>)addSnapshotListener:(FIRDocumentSnapshotBlock)listener {
  return [self addSnapshotListenerWithIncludeMetadataChanges:NO listener:listener];
}

- (id<FIRListenerRegistration>)
    addSnapshotListenerWithIncludeMetadataChanges:(BOOL)includeMetadataChanges
                                         listener:(FIRDocumentSnapshotBlock)listener {
  FSTListenOptions *options =
      [self internalOptionsForIncludeMetadataChanges:includeMetadataChanges];
  return [self addSnapshotListenerInternalWithOptions:options listener:listener];
}

- (id<FIRListenerRegistration>)
    addSnapshotListenerInternalWithOptions:(FSTListenOptions *)internalOptions
                                  listener:(FIRDocumentSnapshotBlock)listener {
  return _documentReference.AddSnapshotListener([self wrapDocumentSnapshotBlock:listener],
                                                internalOptions);
}

/** Converts the public API options object to the internal options object. */
- (FSTListenOptions *)internalOptionsForIncludeMetadataChanges:(BOOL)includeMetadataChanges {
  return [[FSTListenOptions alloc] initWithIncludeQueryMetadataChanges:includeMetadataChanges
                                        includeDocumentMetadataChanges:includeMetadataChanges
                                                 waitForSyncWhenOnline:NO];
}

- (HandleMaybe<DocumentSnapshot>)wrapDocumentSnapshotBlock:(FIRDocumentSnapshotBlock)block {
  FIRFirestore *firestore = _firestore;
  return [block, firestore](StatusOr<DocumentSnapshot> maybe_snapshot) {
    if (maybe_snapshot.ok()) {
      FIRDocumentSnapshot *result =
          [FIRDocumentSnapshot snapshotWithSnapshot:std::move(maybe_snapshot.ValueOrDie())
                                          firestore:firestore];
      block(result, nil);
    } else {
      block(nil, util::MakeNSError(maybe_snapshot.status()));
    }
  };
}

@end

#pragma mark - FIRDocumentReference (Internal)

@implementation FIRDocumentReference (Internal)

+ (instancetype)referenceWithPath:(const ResourcePath &)path firestore:(FIRFirestore *)firestore {
  if (path.size() % 2 != 0) {
    FSTThrowInvalidArgument(@"Invalid document reference. Document references must have an even "
                             "number of segments, but %s has %zu",
                            path.CanonicalString().c_str(), path.size());
  }
  return [FIRDocumentReference referenceWithKey:DocumentKey{path} firestore:firestore];
}

+ (instancetype)referenceWithKey:(DocumentKey)key firestore:(FIRFirestore *)firestore {
  DocumentReference underlyingReference{firestore.underlyingFirestore, std::move(key)};
  return [FIRDocumentReference referenceWithReference:std::move(underlyingReference)
                                            firestore:firestore];
}

+ (instancetype)referenceWithReference:(DocumentReference &&)reference
                             firestore:(FIRFirestore *)firestore {
  return [[FIRDocumentReference alloc] initWithReference:std::move(reference) firestore:firestore];
}

- (const DocumentKey &)key {
  return _documentReference.key();
}

@end

NS_ASSUME_NONNULL_END
