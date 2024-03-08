#import "RCTCloudKitStorage.h"

static NSString *const kRCTCloudKitRecordDidUpdate =
  @"RCTCloudKitRecordDidUpdate";
static NSString *const kRCTCloudKitRecordDidDelete =
  @"RCTCloudKitRecordDidDelete";
static NSString *const kRCTCloudKitStorageZoneName =
  @"RCTCloudKitStorage";
static NSString *const kRCTCloudKitRecordType =
  @"RCTCloudKitRecordType";
static NSString *const kRCTCloudKitSubscription =
  @"RCTCloudKitSubscription";
static NSString *const kRCTCloudKitUserDefaultsDidRegisterSubscription =
  @"RCTCloudKitUserDefaultsDidRegisterSubscription";
static NSString *const kRCTCloudKitUserDefaultsServerChangeToken =
  @"RCTCloudKitServerChangeToken";

@implementation RCTCloudKitStorage

+ (CKRecordZone *)zone
{
  return [[CKRecordZone alloc] initWithZoneName:kRCTCloudKitStorageZoneName];
}

+ (nullable CKServerChangeToken*)serverChangeToken
{
  return [NSUserDefaults.standardUserDefaults
          objectForKey:kRCTCloudKitUserDefaultsServerChangeToken];
}

+ (void)setServerChangeToken:(CKServerChangeToken *)serverChangeToken
{
  [NSUserDefaults.standardUserDefaults
   setObject:serverChangeToken
   forKey:kRCTCloudKitUserDefaultsServerChangeToken];
}

+ (BOOL)didReceiveRemoteNotification:(NSDictionary *)notification
              fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
  CKNotification *ckNotification =
    [CKNotification notificationFromRemoteNotificationDictionary:notification];

  if (ckNotification.notificationType != CKNotificationTypeRecordZone) {
    return NO;
  }

  CKRecordZoneNotification *zoneNotification =
    (CKRecordZoneNotification *)ckNotification;
  CKRecordZoneID *zoneID = self.zone.zoneID;

  if (![zoneNotification.recordZoneID.zoneName isEqual:zoneID.zoneName]) {
    return NO;
  }

  CKFetchRecordZoneChangesConfiguration *configuration =
    [CKFetchRecordZoneChangesConfiguration new];
  configuration.previousServerChangeToken = self.serverChangeToken;

  CKFetchRecordZoneChangesOperation *operation =
    [[CKFetchRecordZoneChangesOperation alloc]
     initWithRecordZoneIDs:@[zoneID]
     configurationsByRecordZoneID:@{zoneID:configuration}];

  operation.recordChangedBlock = ^(CKRecord *record) {
    id userInfo = @{@"record":record};
    [NSNotificationCenter.defaultCenter
     postNotificationName:kRCTCloudKitRecordDidUpdate
     object:self
     userInfo:userInfo];
  };

  operation.recordWithIDWasDeletedBlock = ^(CKRecordID *recordId,
                                            CKRecordType recordType) {
    id userInfo = @{@"recordID":recordId};
    [NSNotificationCenter.defaultCenter
     postNotificationName:kRCTCloudKitRecordDidDelete
     object:self
     userInfo:userInfo];
  };

  operation.recordZoneChangeTokensUpdatedBlock = ^(CKRecordZoneID *recordZoneID,
                                                   CKServerChangeToken *token,
                                                   NSData *data) {
    if ([zoneNotification.recordZoneID isEqual:zoneID]) {
      self.serverChangeToken = token;
    }
  };


  operation.recordZoneFetchCompletionBlock = ^(CKRecordZoneID *recordZoneID,
                                               CKServerChangeToken *token,
                                               NSData *data,
                                               BOOL more,
                                               NSError *error) {
    if (error == nil) {
      if ([zoneNotification.recordZoneID isEqual:zoneID]) {
        self.serverChangeToken = token;
      }

      completionHandler(UIBackgroundFetchResultNewData);
    } else {
      completionHandler(UIBackgroundFetchResultFailed);
    }
  };

  operation.qualityOfService = NSQualityOfServiceUtility;

  [CKContainer.defaultContainer.privateCloudDatabase addOperation:operation];

  return YES;
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (void)startObserving
{
  [[NSNotificationCenter defaultCenter]
   addObserver:self
   selector:@selector(handleRecordDidUpdate:)
   name:kRCTCloudKitRecordDidUpdate
   object:nil];
  [[NSNotificationCenter defaultCenter]
   addObserver:self
   selector:@selector(handleRecordDidDelete:)
   name:kRCTCloudKitRecordDidDelete
   object:nil];
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"change", @"delete"];
}

- (void)stopObserving
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (nullable NSString *)contentsOfRecord:(CKRecord *)record
{
  CKAsset *asset = [record valueForKey:@"contents"];
  if (![asset isKindOfClass:CKAsset.class]) {
    return nil;
  }

  NSError *error;
  NSString *contents = [NSString stringWithContentsOfURL:asset.fileURL
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];

  if (error != nil) {
    return nil;
  }

  return contents;
}

- (void)handleRecordDidUpdate:(NSNotification *)notification
{
  CKRecord *record = notification.userInfo[@"record"];
  NSString *contents = [self contentsOfRecord:record];
  if (contents != nil) {
    id data = @{
      @"key": record.recordID.recordName,
      @"value": contents,
    };
    [self sendEventWithName:@"change" body:data];
  } else {
    NSLog(@"Failed to emit record change event");
  }
}

- (void)handleRecordDidDelete:(NSNotification *)notification
{
  CKRecordID *recordID = notification.userInfo[@"recordID"];
  if (recordID != nil) {
    id data = @{
      @"key": recordID.recordName,
    };
    [self sendEventWithName:@"delete" body:data];
  } else {
    NSLog(@"Failed to emit record delete event");
  }
}

RCT_EXPORT_METHOD(registerForPushUpdates)
{
  if ([NSUserDefaults.standardUserDefaults
       boolForKey:kRCTCloudKitUserDefaultsDidRegisterSubscription]) {
    return;
  }

  CKRecordZoneSubscription *subscription =
    [[CKRecordZoneSubscription alloc]
     initWithZoneID:RCTCloudKitStorage.zone.zoneID
     subscriptionID:kRCTCloudKitSubscription];

  subscription.recordType = kRCTCloudKitRecordType;

  CKNotificationInfo *notificationInfo = [CKNotificationInfo new];
  notificationInfo.shouldSendContentAvailable = YES;
  subscription.notificationInfo = notificationInfo;

  CKModifySubscriptionsOperation *operation =
    [[CKModifySubscriptionsOperation alloc]
     initWithSubscriptionsToSave:@[subscription]
     subscriptionIDsToDelete:NULL];

  operation.modifySubscriptionsCompletionBlock = ^(NSArray *subscriptions,
                                                   NSArray *deleted,
                                                   NSError *error) {
    if (error) {
      NSLog(@"Failed to register for push updates (%@)", error.description);
    } else {
      [NSUserDefaults.standardUserDefaults
       setBool:YES
       forKey:kRCTCloudKitUserDefaultsDidRegisterSubscription];
    }
  };

  operation.qualityOfService = NSQualityOfServiceUtility;

  [CKContainer.defaultContainer.privateCloudDatabase addOperation:operation];
}

RCT_EXPORT_METHOD(getItem:(NSString *)recordName
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  CKRecordID *recordId = [[CKRecordID alloc]
                          initWithRecordName:recordName
                          zoneID:RCTCloudKitStorage.zone.zoneID];
  [CKContainer.defaultContainer.privateCloudDatabase
   fetchRecordWithID:recordId
   completionHandler:^(CKRecord *record, NSError *error) {
    NSString *contents = error == nil ? [self contentsOfRecord:record] : nil;
    if (contents != nil) {
      resolve(contents);
    } else {
      reject(@"could_not_load_contents", @"Could not load contents", error);
    }
  }];
}

RCT_EXPORT_METHOD(setItem:(NSString *)recordName
                  withContents:(NSString *)contents
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  CKRecordZoneID *zoneID = [[CKRecordZoneID alloc] initWithZoneName:kRCTCloudKitStorageZoneName ownerName:CKCurrentUserDefaultName];
  CKDatabase *database = [CKContainer defaultContainer].privateCloudDatabase;

  // Check if the zone already exists
  [database fetchRecordZoneWithID:zoneID completionHandler:^(CKRecordZone * _Nullable zone, NSError * _Nullable error) {
    if (zone) {
      // Zone exists, proceed to save the item
      [self saveItemWithRecordName:recordName contents:contents inZoneWithID:zoneID resolve:resolve reject:reject];
    } else if (error.code == CKErrorZoneNotFound) {
      // Zone not found, create it
      CKRecordZone *newZone = [[CKRecordZone alloc] initWithZoneID:zoneID];
      [database saveRecordZone:newZone completionHandler:^(CKRecordZone * _Nullable savedZone, NSError * _Nullable zoneError) {
        if (zoneError) {
          reject(@"could_not_create_zone", @"Could not create zone", zoneError);
        } else {
          // Zone created, proceed to save the item
          [self saveItemWithRecordName:recordName contents:contents inZoneWithID:zoneID resolve:resolve reject:reject];
        }
      }];
    } else {
      // Some other error occurred
      reject(@"could_not_fetch_zone", @"Could not fetch zone", error);
    }
  }];
}

- (void)saveItemWithRecordName:(NSString *)recordName
                      contents:(NSString *)contents
                    inZoneWithID:(CKRecordZoneID *)zoneID
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject
{
  CKDatabase *database = [CKContainer defaultContainer].privateCloudDatabase; // Define database here
  CKRecordID *recordId = [[CKRecordID alloc] initWithRecordName:recordName zoneID:zoneID];
  CKRecord *record = [[CKRecord alloc] initWithRecordType:kRCTCloudKitRecordType recordID:recordId];
  NSString *filename = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"dat"];
  NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:filename];

  NSError *error;
  [contents writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error];
  if (error) {
    reject(@"could_not_write_contents", @"Could not write contents", error);
    return;
  }

  CKAsset *asset = [[CKAsset alloc] initWithFileURL:url];
  [record setObject:asset forKey:@"contents"];

  CKModifyRecordsOperation *operation = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:@[record] recordIDsToDelete:nil];
  operation.savePolicy = CKRecordSaveAllKeys;
  operation.qualityOfService = NSQualityOfServiceUserInitiated;
  operation.modifyRecordsCompletionBlock = ^(NSArray *savedRecords, NSArray *deletedRecordIDs, NSError *operationError) {
    if (operationError == nil) {
      NSLog(@"Successfully saved record.");
      resolve(nil);
    } else {
      NSLog(@"Failed to save record: %@", operationError);
      reject(@"could_not_save_contents", @"Could not save contents", operationError);
    }
  };

  [database addOperation:operation];
}

@end
