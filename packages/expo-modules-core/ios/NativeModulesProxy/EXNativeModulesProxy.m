// Copyright 2018-present 650 Industries. All rights reserved.

#import <objc/runtime.h>

#import <React/RCTLog.h>
#import <React/RCTUIManager.h>
#import <React/RCTComponentData.h>
#import <React/RCTModuleData.h>

#import <ExpoModulesCore/EXNativeModulesProxy.h>
#import <ExpoModulesCore/EXEventEmitter.h>
#import <ExpoModulesCore/EXViewManager.h>
#import <ExpoModulesCore/EXViewManagerAdapter.h>
#import <ExpoModulesCore/EXViewManagerAdapterClassesRegistry.h>
#import "ExpoModulesCore-Swift.h"

static const NSString *exportedMethodsNamesKeyPath = @"exportedMethods";
static const NSString *viewManagersNamesKeyPath = @"viewManagersNames";
static const NSString *exportedConstantsKeyPath = @"modulesConstants";

static const NSString *methodInfoKeyKey = @"key";
static const NSString *methodInfoNameKey = @"name";
static const NSString *methodInfoArgumentsCountKey = @"argumentsCount";

@interface RCTBridge (RegisterAdditionalModuleClasses)

- (void)registerAdditionalModuleClasses:(NSArray<Class> *)modules;

@end

@interface EXNativeModulesProxy ()

@property (nonatomic, strong) NSRegularExpression *regexp;
@property (nonatomic, strong) EXModuleRegistry *exModuleRegistry;
@property (nonatomic, strong) NSMutableDictionary<const NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *exportedMethodsKeys;
@property (nonatomic, strong) NSMutableDictionary<const NSString *, NSMutableDictionary<NSNumber *, NSString *> *> *exportedMethodsReverseKeys;
@property (nonatomic, strong) SwiftInteropBridge *swiftInteropBridge;
@property (nonatomic) BOOL ownsModuleRegistry;

@end

@implementation EXNativeModulesProxy

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE(NativeUnimoduleProxy)

/**
 The default designated initializer, called by React Native.
 */
- (instancetype)init
{
  if (self = [super init]) {
    _exModuleRegistry = [[[EXModuleRegistryProvider alloc] init] moduleRegistry];
    _exportedMethodsKeys = [NSMutableDictionary dictionary];
    _exportedMethodsReverseKeys = [NSMutableDictionary dictionary];
    _ownsModuleRegistry = YES;

//    for (EXViewManager *viewManager in [_exModuleRegistry getAllViewManagers]) {
//      Class viewManagerWrapperClass = [EXViewManagerAdapterClassesRegistry createViewManagerAdapterClassForViewManager:viewManager];
//      RCTRegisterModule(viewManagerWrapperClass);
  //    [additionalModuleClasses addObject:viewManagerWrapperClass];
//    }
  }
  return self;
}

- (void)setBridge:(RCTBridge *)bridge
{
  _bridge = bridge;

  if (!_ownsModuleRegistry) {
    return;
  }

  EXReactNativeEventEmitter *eventEmitter = [bridge moduleForClass:[EXReactNativeEventEmitter class]];
  [_exModuleRegistry registerInternalModule:eventEmitter];

  NSMutableArray<Class> *additionalModuleClasses = [NSMutableArray new];
  NSMutableDictionary *componentDataByName = [bridge.uiManager valueForKey:@"_componentDataByName"];

//  for (Class klass in [EXModuleRegistryProvider getModulesClasses]) {
//    if ([klass conformsToProtocol:@protocol(RCTBridgeModule)]) {
//      [additionalModuleClasses addObject:klass];
//    }
//  }

  for (EXViewManager *viewManager in [_exModuleRegistry getAllViewManagers]) {
    Class viewManagerWrapperClass = [EXViewManagerAdapterClassesRegistry createViewManagerAdapterClassForViewManager:viewManager];
    [additionalModuleClasses addObject:viewManagerWrapperClass];

    RCTComponentData *componentData = [[RCTComponentData alloc] initWithManagerClass:viewManagerWrapperClass bridge:bridge];
    componentDataByName[NSStringFromClass(viewManagerWrapperClass)] = componentData;
  }

  [additionalModuleClasses addObject:[EXViewManagerAdapter class]];

//  [_bridge registerModulesForClasses:additionalModuleClasses];
  [_bridge registerAdditionalModuleClasses:additionalModuleClasses];

  EXReactNativeAdapter *reactNativeAdapter = [_exModuleRegistry getModuleImplementingProtocol:@protocol(EXUIManager)];
  [reactNativeAdapter setBridge:bridge];

  [_exModuleRegistry initialize];
}

/**
 Notice that we call `super` here, so it's just another designated initializer. This is used in the old setup
 where the native modules proxy is registered in `extraModulesForBridge:` by the bridge delegate.
 */
- (instancetype)initWithModuleRegistry:(EXModuleRegistry *)moduleRegistry
{
  if (self = [super init]) {
    _exModuleRegistry = moduleRegistry;
    _exportedMethodsKeys = [NSMutableDictionary dictionary];
    _exportedMethodsReverseKeys = [NSMutableDictionary dictionary];
    _ownsModuleRegistry = NO;
  }
  return self;
}

- (instancetype)initWithModuleRegistry:(EXModuleRegistry *)moduleRegistry swiftInteropBridge:(SwiftInteropBridge *)swiftInteropBridge
{
  if (self = [self initWithModuleRegistry:moduleRegistry]) {
    _swiftInteropBridge = swiftInteropBridge;
  }
  return self;
}

# pragma mark - React API

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (NSDictionary *)constantsToExport
{
  NSMutableDictionary <NSString *, id> *exportedModulesConstants = [NSMutableDictionary dictionary];
  // Grab all the constants exported by modules
  for (EXExportedModule *exportedModule in [_exModuleRegistry getAllExportedModules]) {
    @try {
      exportedModulesConstants[[[exportedModule class] exportedModuleName]] = [exportedModule constantsToExport] ?: [NSNull null];
    } @catch (NSException *exception) {
      continue;
    }
  }
  [exportedModulesConstants addEntriesFromDictionary:[_swiftInteropBridge exportedModulesConstants]];

  // Also add `exportedMethodsNames`
  NSMutableDictionary<const NSString *, NSMutableArray<NSMutableDictionary<const NSString *, id> *> *> *exportedMethodsNamesAccumulator = [NSMutableDictionary dictionary];
  for (EXExportedModule *exportedModule in [_exModuleRegistry getAllExportedModules]) {
    const NSString *exportedModuleName = [[exportedModule class] exportedModuleName];
    exportedMethodsNamesAccumulator[exportedModuleName] = [NSMutableArray array];
    [[exportedModule getExportedMethods] enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull exportedName, NSString * _Nonnull selectorName, BOOL * _Nonnull stop) {
      NSMutableDictionary<const NSString *, id> *methodInfo = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                                              methodInfoNameKey: exportedName,
                                                                                                              // - 3 is for resolver and rejecter of the promise and the last, empty component
                                                                                                              methodInfoArgumentsCountKey: @([[selectorName componentsSeparatedByString:@":"] count] - 3)
                                                                                                              }];
      [exportedMethodsNamesAccumulator[exportedModuleName] addObject:methodInfo];
    }];
    [self assignExportedMethodsKeys:exportedMethodsNamesAccumulator[exportedModuleName] forModuleName:exportedModuleName];
  }

  // Add entries from Swift modules
  [exportedMethodsNamesAccumulator addEntriesFromDictionary:[_swiftInteropBridge exportedMethodNames]];

  // Also, add `viewManagersNames` for sanity check and testing purposes -- with names we know what managers to mock on UIManager
  NSArray<EXViewManager *> *viewManagers = [_exModuleRegistry getAllViewManagers];
  NSMutableArray<NSString *> *viewManagersNames = [NSMutableArray arrayWithCapacity:[viewManagers count]];
  for (EXViewManager *viewManager in viewManagers) {
    [viewManagersNames addObject:[viewManager viewName]];
  }

  [viewManagersNames addObjectsFromArray:[_swiftInteropBridge exportedViewManagersNames]];

  NSMutableDictionary <NSString *, id> *constantsAccumulator = [NSMutableDictionary dictionary];
  constantsAccumulator[viewManagersNamesKeyPath] = viewManagersNames;
  constantsAccumulator[exportedConstantsKeyPath] = exportedModulesConstants;
  constantsAccumulator[exportedMethodsNamesKeyPath] = exportedMethodsNamesAccumulator;

  return constantsAccumulator;
}

RCT_EXPORT_METHOD(callMethod:(NSString *)moduleName methodNameOrKey:(id)methodNameOrKey arguments:(NSArray *)arguments resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
  if ([_swiftInteropBridge hasModule:moduleName]) {
    [_swiftInteropBridge callMethod:methodNameOrKey onModule:moduleName withArgs:arguments resolve:resolve reject:reject];
    return;
  }
  EXExportedModule *module = [_exModuleRegistry getExportedModuleForName:moduleName];
  if (module == nil) {
    NSString *reason = [NSString stringWithFormat:@"No exported module was found for name '%@'. Are you sure all the packages are linked correctly?", moduleName];
    reject(@"E_NO_MODULE", reason, nil);
    return;
  }

  if (!methodNameOrKey) {
    reject(@"E_NO_METHOD", @"No method key or name provided", nil);
    return;
  }

  NSString *methodName;
  if ([methodNameOrKey isKindOfClass:[NSString class]]) {
    methodName = (NSString *)methodNameOrKey;
  } else if ([methodNameOrKey isKindOfClass:[NSNumber class]]) {
    methodName = _exportedMethodsReverseKeys[moduleName][(NSNumber *)methodNameOrKey];
  } else {
    reject(@"E_INV_MKEY", @"Method key is neither a String nor an Integer -- don't know how to map it to method name.", nil);
    return;
  }

  dispatch_async([module methodQueue], ^{
    @try {
      [module callExportedMethod:methodName withArguments:arguments resolver:resolve rejecter:reject];
    } @catch (NSException *e) {
      NSString *message = [NSString stringWithFormat:@"An exception was thrown while calling `%@.%@` with arguments `%@`: %@", moduleName, methodName, arguments, e];
      reject(@"E_EXC", message, nil);
    }
  });
}

- (void)assignExportedMethodsKeys:(NSMutableArray<NSMutableDictionary<const NSString *, id> *> *)exportedMethods forModuleName:(const NSString *)moduleName
{
  if (!_exportedMethodsKeys[moduleName]) {
    _exportedMethodsKeys[moduleName] = [NSMutableDictionary dictionary];
  }

  if (!_exportedMethodsReverseKeys[moduleName]) {
    _exportedMethodsReverseKeys[moduleName] = [NSMutableDictionary dictionary];
  }

  for (int i = 0; i < [exportedMethods count]; i++) {
    NSMutableDictionary<const NSString *, id> *methodInfo = exportedMethods[i];

    if (!methodInfo[(NSString *)methodInfoNameKey] || ![methodInfo[methodInfoNameKey] isKindOfClass:[NSString class]]) {
      NSString *reason = [NSString stringWithFormat:@"Method info of a method of module %@ has no method name.", moduleName];
      @throw [NSException exceptionWithName:@"Empty method name in method info" reason:reason userInfo:nil];
    }

    NSString *methodName = methodInfo[(NSString *)methodInfoNameKey];
    NSNumber *previousMethodKey = _exportedMethodsKeys[moduleName][methodName];
    if (previousMethodKey) {
      methodInfo[methodInfoKeyKey] = previousMethodKey;
    } else {
      NSNumber *newKey = @([[_exportedMethodsKeys[moduleName] allValues] count]);
      methodInfo[methodInfoKeyKey] = newKey;
      _exportedMethodsKeys[moduleName][methodName] = newKey;
      _exportedMethodsReverseKeys[moduleName][newKey] = methodName;
    }
  }
}

@end
