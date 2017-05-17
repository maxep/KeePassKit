//
//  KPKTree+KPKSynchronization.m
//  KeePassKit
//
//  Created by Michael Starke on 17/11/2016.
//  Copyright © 2016 HicknHack Software GmbH. All rights reserved.
//

#import "KPKTree.h"
#import "KPKTree_Private.h"

#import "KPKNode.h"
#import "KPKNode_Private.h"

#import "KPKGroup.h"
#import "KPKGroup_Private.h"

#import "KPKEntry.h"
#import "KPKEntry_Private.h"

#import "KPKMetaData.h"
#import "KPKMetaData_Private.h"

#import "KPKDeletedNode.h"

#import "KPKTimeInfo.h"

#import "KPKScopedSet.h"

@implementation KPKTree (Synchronization)

- (void)syncronizeWithTree:(KPKTree *)tree options:(KPKSynchronizationOptions)options {
  
  if(options == KPKSynchronizationCreateNewUuidsOption) {
    /* create new uuid in the sourc tree */
    [tree.root _regenerateUUIDs];
  }
  
  [self _mergeNodes:tree.allGroups options:options];
  [self _mergeNodes:tree.allEntries options:options];
  [self _mergeLocationFromNodes:tree.allEntries];
  [self _mergeLocationFromNodes:tree.allGroups];
  [self _mergeDeletedObjects:tree.mutableDeletedObjects];
  [self _reapplyDeletions];
  [self.metaData _mergeWithMetaDataFromTree:tree options:options];
  ;
  /* clear undo stack just to be save */
  [self.undoManager removeAllActions];
  
}

- (void)_mergeNodes:(NSArray<KPKNode *> *)nodes options:(KPKSynchronizationOptions)options {
  for(KPKNode *externNode in nodes) {
    KPKDeletedNode *deletedNode = self.deletedObjects[externNode.uuid];
    if(nil != deletedNode) {
      NSComparisonResult result = [deletedNode.deletionDate compare:externNode.timeInfo.modificationDate];
      if(result == NSOrderedDescending ) {
        continue; // Node was deleted in destination after being modified in source
      }
    }
    KPKNode *localNode = externNode.asGroup ? [self.root groupForUUID:externNode.uuid] : [self.root entryForUUID:externNode.uuid];
    
    /* Node is unkown, create a copy and integrate it */
    if(!localNode) {
      localNode = [[externNode.class alloc] initWithUUID:externNode.uuid];
      [localNode _updateFromNode:externNode options:KPKUpdateOptionIgnoreModificationTime | KPKUpdateOptionUpateMovedTime];
      
      KPKGroup *localParent = [self.root groupForUUID:externNode.parent.uuid];
      if(!localParent) {
        localParent = self.root;
      }
      KPK_SCOPED_NO_BEGIN(localNode.updateTiming)
      [localNode addToGroup:localParent atIndex:externNode.index];
      KPK_SCOPED_NO_END(localNode.updateTiming)
    }
    else {
      NSAssert(options != KPKSynchronizationCreateNewUuidsOption, @"UUID collision while merging trees!");
      /*
       ignore entries and subgroups to just compare the group attributes,
       KPKNodeEqualityIgnoreHistory not needed since we do not compare entries at all
       */
      KPKNodeEqualityOptions equalityOptions = (KPKNodeEqualityIgnoreGroupsOption |
                                                KPKNodeEqualityIgnoreEntriesOption |
                                                KPKNodeEqualityIgnoreGroupsOption |
                                                KPKNodeEqualityIgnoreEntriesOption);
      
      if([localNode _isEqualToNode:externNode options:equalityOptions]) {
        continue; // node did not change
      }
      KPKUpdateOptions updateOptions = (equalityOptions == KPKSynchronizationOverwriteExistingOption) ? KPKUpdateOptionIgnoreModificationTime : 0;
      if(options == KPKSynchronizationOverwriteExistingOption ||
         options == KPKSynchronizationOverwriteIfNewerOption ||
         options == KPKSynchronizationSynchronizeOption) {
        [localNode _updateFromNode:externNode options:updateOptions];
      }
    }
  }
}

- (void)_mergeLocationFromNodes:(NSArray <KPKNode *>*)nodes {
  for(KPKNode *externNode in nodes) {
    KPKNode *localNode = externNode.asGroup ? [self.root groupForUUID:externNode.uuid] : [self.root entryForUUID:externNode.uuid];
    if(!localNode) {
      /* no local group for extern group found */
      continue;
    }
    KPKGroup *localExternParent = [self.root groupForUUID:externNode.parent.uuid];
    KPKGroup *localParent = localNode.parent;
    
    if(!localExternParent || !localParent) {
      continue;
    }
    
    if([localParent.uuid isEqual:localExternParent.uuid]) {
      /* parents are the same */
      continue;
    }
    
    switch([localNode.timeInfo.locationChanged compare:externNode.timeInfo.locationChanged]) {
      case NSOrderedAscending:
        KPK_SCOPED_NO_BEGIN(localNode.updateTiming)
        [localNode addToGroup:localExternParent];
        KPK_SCOPED_NO_END(localNode.updateTiming)
      case NSOrderedSame:
      case NSOrderedDescending:
        continue;
    }
  }
}

- (void)_mergeHistory:(KPKEntry *)entry ofEntry:(KPKEntry *)otherEntry {
  
}

- (void)_mergeDeletedObjects:(NSDictionary<NSUUID *,KPKDeletedNode *> *)deletedObjects {
  for(NSUUID *uuid in deletedObjects) {
    KPKDeletedNode *otherDeletedNode = deletedObjects[uuid];
    KPKDeletedNode *localDeletedNode = self.mutableDeletedObjects[uuid];
    if(!localDeletedNode) {
      self.mutableDeletedObjects[uuid] = otherDeletedNode;
      continue; // done;
    }
    
    /* if the other node was deleted later, we use this other node instaed and remove ours */
    NSComparisonResult result = [localDeletedNode.deletionDate compare:otherDeletedNode.deletionDate];
    if(result == NSOrderedAscending) {
      self.mutableDeletedObjects[uuid] = otherDeletedNode;
    }
  }
}

- (void)_reapplyDeletions {
  NSArray *pending = self.mutableDeletedObjects.allKeys;
  NSMutableArray *skipped = [[NSMutableArray alloc] initWithCapacity:pending.count];
  while(pending.count > 0) {
    for(NSUUID *uuid in pending) {
      KPKEntry *deletedEntry = [self.root entryForUUID:uuid];
      /* delete the entry using low level API not remove */
      [deletedEntry.parent _removeChild:deletedEntry];
      
      KPKGroup *deletedGroup = [self.root groupForUUID:uuid];
      if(deletedGroup.countOfGroups == 0 && deletedGroup.countOfEntries == 0) {
        [deletedGroup.parent _removeChild:deletedGroup];
      }
      else {
        [skipped addObject:uuid];
      }
    }
    /* If we have skipped everything, there's something wrong! */
    if([pending isEqualToArray:skipped]) {
      [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"Reapplying deletions after mergin not possible" userInfo:nil] raise];
      break;
    }
    /* re-queue the skipped uuids */
    pending = [skipped copy];
  }
}

@end
