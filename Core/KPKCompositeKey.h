//
//  KPKPassword.h
//  KeePassKit
//
//  Created by Michael Starke on 12.07.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//


#import <Foundation/Foundation.h>
#import "KPKVersion.h"
/**
 *  The Composite Key to be used for encryption and decryption of databases
 *  It does not store key  nor password strings rather creates a composite key
 *  every time the password or keyfile is set.
 */
@interface KPKCompositeKey : NSObject

/**
 *  YES if the composite key has a password or keyfile set - that is, it's considered usable
 */
@property (nonatomic, readonly, assign) BOOL hasPasswordOrKeyFile;
/**
 *  YES if the composite key has a password set.
 */
@property (nonatomic, readonly, assign) BOOL hasPassword;
@property (nonatomic, readonly, assign) NSTimeInterval modifactionTimeStamp;

+ (void)benchmarkTransformationRounds:(NSUInteger)seconds completionHandler:(void(^)(NSUInteger rounds))completionHandler;

/*
 The password class to be able to decrypt and encrypt databses
 Neither the password nor the keyfile are stored and just read
 and hashed into the composite key.
 
 The Final key is then created before a write or read gets performend
 */
- (id)initWithPassword:(NSString *)password key:(NSURL *)url;
/*
 @return the final Data to use to en/decrypt the database
 */
- (NSData *)finalDataForVersion:(KPKVersion )version masterSeed:(NSData *)masterSeed transformSeed:(NSData *)transformSeed rounds:(NSUInteger )rounds;

/**
 *  Updates the password and keyfile for the composite key
 *  @param password the new password, can be nil
 *  @param key      the new key file URL, can be nil
 */
- (void)setPassword:(NSString *)password andKeyfile:(NSURL *)key;

/*
 @return YES if the password and/or key are correct for this composite key
 */
- (BOOL)testPassword:(NSString *)password key:(NSURL *)key forVersion:(KPKVersion)version;


@end
