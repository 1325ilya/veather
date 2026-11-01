//  BTBSideloadFix.m — /sideload: fixes for things that break after re-signing
//  with a different team or bundle ID:
//   * keychain: drop kSecAttrAccessGroup (old team prefix → errSecMissingEntitlement)
//   * app groups: give the app a private folder when the group container is unavailable
//   * bundle ID: when BetterThanBox changed it, the app's own code sees the original ID
//     (Info.plist `BTBOriginalBundleID`); iOS frameworks keep seeing the real one, so
//     preferences, notifications and the keychain keep working

#import "BTBCommon.h"
#import <Security/Security.h>

static CFDictionaryRef BTBStripGroup(CFDictionaryRef query) CF_RETURNS_RETAINED {
	if (!query || !CFDictionaryContainsKey(query, kSecAttrAccessGroup)) {
		return query ? CFRetain(query) : NULL;
	}
	CFMutableDictionaryRef copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
	CFDictionaryRemoveValue(copy, kSecAttrAccessGroup);
	return copy;
}

static OSStatus btb_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
	if (!BTBFlagSideloadFix) return SecItemAdd(attributes, result);
	CFDictionaryRef q = BTBStripGroup(attributes);
	OSStatus s = SecItemAdd(q, result);
	if (q) CFRelease(q);
	return s;
}
static OSStatus btb_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
	if (!BTBFlagSideloadFix) return SecItemCopyMatching(query, result);
	CFDictionaryRef q = BTBStripGroup(query);
	OSStatus s = SecItemCopyMatching(q, result);
	if (q) CFRelease(q);
	return s;
}
static OSStatus btb_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributes) {
	if (!BTBFlagSideloadFix) return SecItemUpdate(query, attributes);
	CFDictionaryRef q = BTBStripGroup(query);
	CFDictionaryRef a = BTBStripGroup(attributes);
	OSStatus s = SecItemUpdate(q, a);
	if (q) CFRelease(q);
	if (a) CFRelease(a);
	return s;
}
static OSStatus btb_SecItemDelete(CFDictionaryRef query) {
	if (!BTBFlagSideloadFix) return SecItemDelete(query);
	CFDictionaryRef q = BTBStripGroup(query);
	OSStatus s = SecItemDelete(q);
	if (q) CFRelease(q);
	return s;
}
BTB_INTERPOSE(btb_SecItemAdd, SecItemAdd)
BTB_INTERPOSE(btb_SecItemCopyMatching, SecItemCopyMatching)
BTB_INTERPOSE(btb_SecItemUpdate, SecItemUpdate)
BTB_INTERPOSE(btb_SecItemDelete, SecItemDelete)

static void BTBFixAppGroups(void) {
	SEL sel = @selector(containerURLForSecurityApplicationGroupIdentifier:);
	__block IMP orig = NULL;
	orig = BTBSwizzle([NSFileManager class], sel, NO, ^NSURL *(NSFileManager *self, NSString *group) {
		NSURL *url = orig ? ((NSURL *(*)(id, SEL, NSString *))orig)(self, sel, group) : nil;
		if (url || group.length == 0) return url;
		NSURL *library = [[self URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] firstObject];
		NSURL *fallback = [[library URLByAppendingPathComponent:@"BTBAppGroups" isDirectory:YES] URLByAppendingPathComponent:group isDirectory:YES];
		[self createDirectoryAtURL:fallback withIntermediateDirectories:YES attributes:nil error:nil];
		return fallback;
	});
}

static void BTBSpoofBundleID(void) {
	NSBundle *main = [NSBundle mainBundle];
	NSString *original = [main objectForInfoDictionaryKey:@"BTBOriginalBundleID"];
	NSString *real = main.bundleIdentifier;
	if (![original isKindOfClass:[NSString class]] || original.length == 0 || [original isEqualToString:real]) return;

	NSMutableDictionary *spoofedInfo = [main.infoDictionary mutableCopy];
	spoofedInfo[@"CFBundleIdentifier"] = original;
	NSDictionary *spoofedInfoCopy = [spoofedInfo copy];

	SEL idSel = @selector(bundleIdentifier);
	__block IMP origID = NULL;
	origID = BTBSwizzle([NSBundle class], idSel, NO, ^NSString *(NSBundle *self) {
		if (self == main && !BTBAddressIsSystem(__builtin_return_address(0))) return original;
		return ((NSString *(*)(id, SEL))origID)(self, idSel);
	});

	SEL keySel = @selector(objectForInfoDictionaryKey:);
	__block IMP origKey = NULL;
	origKey = BTBSwizzle([NSBundle class], keySel, NO, ^id(NSBundle *self, NSString *key) {
		if (self == main && [key isEqualToString:@"CFBundleIdentifier"] && !BTBAddressIsSystem(__builtin_return_address(0))) {
			return original;
		}
		return ((id (*)(id, SEL, id))origKey)(self, keySel, key);
	});

	SEL infoSel = @selector(infoDictionary);
	__block IMP origInfo = NULL;
	origInfo = BTBSwizzle([NSBundle class], infoSel, NO, ^NSDictionary *(NSBundle *self) {
		if (self == main && !BTBAddressIsSystem(__builtin_return_address(0))) return spoofedInfoCopy;
		return ((NSDictionary *(*)(id, SEL))origInfo)(self, infoSel);
	});

	BTB_LOG("bundle ID for the app's code: %{public}@ (real: %{public}@)", original, real);
}

void BTBFeatureSideloadFix(void) {
	BTBFixAppGroups();
	BTBSpoofBundleID();
}
