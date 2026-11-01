//  BTBCommon.h — shared helpers for BetterThanBox built-in tweaks.
//  Tweaks use only the ObjC runtime and dyld interposing (no Substrate/ElleKit).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/log.h>

#define BTB_LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[BetterThanBox] " fmt, ##__VA_ARGS__)

// dyld interposing: replaces calls to `_replacee` with `_replacement` in every image
#define BTB_INTERPOSE(_replacement, _replacee) \
	__attribute__((used)) static struct { const void *replacement; const void *replacee; } \
	_btb_interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = { \
		(const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee \
	};

/// Replaces an instance (or class, when isClass) method implementation with a block.
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

// Feature flags, filled from Info.plist key `BTBEnabledTweaks` (set by BetterThanBox when signing).
extern BOOL BTBFlagNoAds;
extern BOOL BTBFlagNoNetwork;
extern BOOL BTBFlagNoUpdates;
extern BOOL BTBFlagNoRate;
extern BOOL BTBFlagIPadUI;
extern BOOL BTBFlagSideloadFix;
extern BOOL BTBFlagDataManager;

void BTBFeatureNoAds(void);
void BTBFeatureNoNetwork(void);
void BTBFeatureNoUpdates(void);
void BTBFeatureNoRate(void);
void BTBFeatureIPadUI(void);
void BTBFeatureSideloadFix(void);
void BTBFeatureDataManager(void);
BOOL BTBIsAdHost(const char *host);
