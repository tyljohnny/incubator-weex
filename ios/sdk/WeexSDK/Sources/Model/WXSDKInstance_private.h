/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 * 
 *   http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

#import <Foundation/Foundation.h>
#import "WXSDKInstance.h"
#import "WXComponentManager.h"
#import "WXModuleMethod.h"
#import "WXThreadSafeMutableDictionary.h"
#import <JavaScriptCore/JavaScriptCore.h>

@interface WXSDKInstance ()

@property (nonatomic, assign) CGFloat viewportWidth;

@property (nonatomic, strong) WXThreadSafeMutableDictionary *moduleInstances;
@property (nonatomic, strong) NSMutableDictionary *naviBarStyles;
@property (nonatomic, strong) NSMutableDictionary *styleConfigs;
@property (nonatomic, strong) NSMutableDictionary *attrConfigs;
@property (nonatomic, strong) NSString *mainBundleString;

// add monitor information
@property (nonatomic, strong) NSString *callCreateInstanceContext;
@property (nonatomic, strong) NSString *createInstanceContextResult;
@property (nonatomic, strong) NSString *executeRaxApiResult;

- (void)addModuleEventObservers:(NSString*)event callback:(NSString*)callbackId option:(NSDictionary*)option moduleClassName:(NSString*)moduleClassName;
- (void)_addModuleEventObserversWithModuleMethod:(WXModuleMethod*)method;
- (void)removeModuleEventObserver:(NSString*)event moduleClassName:(NSString*)moduleClassName;
- (void)_removeModuleEventObserverWithModuleMethod:(WXModuleMethod*)method;

@end
