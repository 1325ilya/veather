//  BTBSideloadFix.m — /sideload: fixes for things that break after re-signing
//  with a different team:
//   * keychain: drop kSecAttrAccessGroup (old team prefix → errSecMissingEntitlement)
//   * app groups: give the app a private folder when the group container is unavailable

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

void BTBFeatureSideloadFix(void) {
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
