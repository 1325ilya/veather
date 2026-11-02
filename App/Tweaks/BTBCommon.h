//  BTBCommon.h — shared helpers for BetterThanBox built-in tweaks.
//  Tweaks use only the ObjC runtime and dyld interposing (no Substrate/ElleKit).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <strings.h>
#import <os/log.h>
#import <dlfcn.h>

#define BTB_LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[Veather] " fmt, ##__VA_ARGS__)

// dyld interposing: replaces calls to `_replacee` with `_replacement` in the app's own images
#define BTB_INTERPOSE(_replacement, _replacee) \
	__attribute__((used)) static struct { const void *replacement; const void *replacee; } \
	_btb_interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = { \
		(const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee \
	};

/// Replaces an instance (or class, when isClass) method implementation with a block.
/// Returns the previous implementation (the inherited one when the method lived in a superclass).
static inline IMP BTBSwizzle(Class cls, SEL sel, BOOL isClass, id block) {
	if (!cls) return NULL;
	Class target = isClass ? object_getClass(cls) : cls;
	Method m = class_getInstanceMethod(target, sel);
	if (!m) return NULL;
	IMP newImp = imp_implementationWithBlock(block);
	if (class_addMethod(target, sel, newImp, method_getTypeEncoding(m))) {
		return method_getImplementation(m);
	}
	return method_setImplementation(m, newImp);
}

/// Return type code of a method ('v' void, 'B'/'c' BOOL, '@' object…), or 0 if missing.
static inline char BTBReturnType(Class cls, SEL sel, BOOL isClass) {
	if (!cls) return 0;
	Method m = class_getInstanceMethod(isClass ? object_getClass(cls) : cls, sel);
	if (!m) return 0;
	char buffer[8] = {0};
	method_getReturnType(m, buffer, sizeof(buffer));
	return buffer[0];
}

/// Number of explicit arguments (without self and _cmd), or -1 if missing.
static inline int BTBArgumentCount(Class cls, SEL sel, BOOL isClass) {
	if (!cls) return -1;
	Method m = class_getInstanceMethod(isClass ? object_getClass(cls) : cls, sel);
	if (!m) return -1;
	return (int)method_getNumberOfArguments(m) - 2;
}

/// True when the code at `address` belongs to the OS (shared cache, /usr/lib), not to the app.
static inline BOOL BTBAddressIsSystem(const void *address) {
	Dl_info info;
	if (!address || !dladdr(address, &info) || !info.dli_fname) return YES;
	const char *p = info.dli_fname;
	return strncmp(p, "/System/", 8) == 0
		|| strncmp(p, "/usr/lib/", 9) == 0
		|| strncmp(p, "/Developer/", 11) == 0;
}

static inline void BTBOnMain(dispatch_block_t block) {
	if ([NSThread isMainThread]) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}

// Feature flags, filled from Info.plist key `BTBEnabledTweaks` (set by BetterThanBox when signing).
extern BOOL BTBFlagNoAds;
extern BOOL BTBFlagNoNetwork;
extern BOOL BTBFlagNoUpdates;
extern BOOL BTBFlagNoRate;
extern BOOL BTBFlagIPadUI;
extern BOOL BTBFlagSideloadFix;
extern BOOL BTBFlagDataManager;
extern BOOL BTBFlagGameGuard;

void BTBFeatureNoAds(void);
void BTBFeatureNoNetwork(void);
void BTBFeatureNoUpdates(void);
void BTBFeatureNoRate(void);
void BTBFeatureIPadUI(void);
void BTBFeatureSideloadFix(void);
void BTBFeatureDataManager(void);
void BTBFeatureGameGuard(void);
BOOL BTBIsAdHost(const char *host);
NSArray<NSString *> *BTBAdHosts(void);
