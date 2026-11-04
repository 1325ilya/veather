//  BTBTweaks.m — entry point of BTBTweaks.dylib.
//  One dylib, features switched on by Info.plist `BTBEnabledTweaks` (array of ids).

#import "BTBCommon.h"
#import <netdb.h>

BOOL BTBFlagNoAds, BTBFlagNoNetwork, BTBFlagNoUpdates, BTBFlagNoRate, BTBFlagIPadUI, BTBFlagSideloadFix, BTBFlagDataManager, BTBFlagGameGuard, BTBFlagSpoofAds;

// single getaddrinfo interposer shared by the network features
static int btb_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
	if (node) {
		BOOL local = strcmp(node, "localhost") == 0 || strcmp(node, "127.0.0.1") == 0 || strcmp(node, "::1") == 0;
		if (BTBFlagNoNetwork && !local) return EAI_NONAME;
		if (BTBFlagNoAds && BTBIsAdHost(node)) return EAI_NONAME;
	}
	return getaddrinfo(node, service, hints, res);
}
BTB_INTERPOSE(btb_getaddrinfo, getaddrinfo)

__attribute__((constructor)) static void BTBTweaksInit(void) {
	@autoreleasepool {
		NSArray *enabled = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"BTBEnabledTweaks"];
		if (![enabled isKindOfClass:[NSArray class]]) return;
		NSSet *set = [NSSet setWithArray:enabled];
		BTBFlagNoAds = [set containsObject:@"noads"];
		BTBFlagNoNetwork = [set containsObject:@"nowifi"];
		BTBFlagNoUpdates = [set containsObject:@"noupd"];
		BTBFlagNoRate = [set containsObject:@"norev"];
		BTBFlagIPadUI = [set containsObject:@"ipadui"];
		BTBFlagSideloadFix = [set containsObject:@"sideload"];
		BTBFlagDataManager = [set containsObject:@"backup"];
		BTBFlagGameGuard = [set containsObject:@"gameguard"];
		BTBFlagSpoofAds = [set containsObject:@"spoofads"];
		if (BTBFlagSpoofAds) BTBFlagNoAds = YES; // banners, interstitials and ad domains stay blocked
		
		if (BTBFlagSideloadFix) BTBFeatureSideloadFix();
		if (BTBFlagNoNetwork) BTBFeatureNoNetwork();
		if (BTBFlagNoAds) BTBFeatureNoAds();
		if (BTBFlagSpoofAds) BTBFeatureSpoofAds();
		if (BTBFlagNoUpdates) BTBFeatureNoUpdates();
		if (BTBFlagNoRate) BTBFeatureNoRate();
		if (BTBFlagIPadUI) BTBFeatureIPadUI();
		if (BTBFlagDataManager) BTBFeatureDataManager();
		if (BTBFlagGameGuard) BTBFeatureGameGuard();
		BTB_LOG("enabled tweaks: %{public}@", [enabled componentsJoinedByString:@","]);
	}
}
