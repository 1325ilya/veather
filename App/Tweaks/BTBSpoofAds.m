//  BTBSpoofAds.m — /spoofads: rewarded ads without watching them.
//  The ad is never loaded or shown; the app is told "the ad finished" and gets its
//  reward right away. Everything else (banners, interstitials, ad web views) is
//  blocked by the No Ads feature, which this tweak switches on too.
//
//  Covers Google AdMob (rewarded, rewarded interstitial) and AppLovin MAX (rewarded).
//  Rewards that the game's own server verifies (server-side verification) can't be faked.

#import "BTBCommon.h"
#import <UIKit/UIKit.h>

static const void *kFakeKey = &kFakeKey;
static const void *kDelegateKey = &kDelegateKey;

static BOOL BTBIsFake(id obj) { return objc_getAssociatedObject(obj, kFakeKey) != nil; }

static void BTBCall(id target, SEL sel, id arg) {
	if (target && [target respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
}

static void BTBLater(NSTimeInterval seconds, dispatch_block_t block) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

// MARK: Google AdMob

static void BTBSpoofAdMobClass(NSString *className) {
	Class cls = NSClassFromString(className);
	if (!cls) return;

	// load: hand back a fake ad object instead of going to the network
	SEL load = NSSelectorFromString(@"loadWithAdUnitID:request:completionHandler:");
	BTBSwizzle(cls, load, YES, ^(id self_, NSString *unit, id request, void (^completion)(id, NSError *)) {
		id ad = class_createInstance(cls, 0);
		objc_setAssociatedObject(ad, kFakeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		BTBLater(0.05, ^{ if (completion) completion(ad, nil); });
	});

	// delegate lives in an associated object on fakes
	SEL setDelegate = NSSelectorFromString(@"setFullScreenContentDelegate:");
	__block IMP origSet = NULL;
	origSet = BTBSwizzle(cls, setDelegate, NO, ^(id self_, id delegate) {
		if (BTBIsFake(self_)) objc_setAssociatedObject(self_, kDelegateKey, delegate, OBJC_ASSOCIATION_ASSIGN);
		else if (origSet) ((void (*)(id, SEL, id))origSet)(self_, setDelegate, delegate);
	});
	SEL getDelegate = NSSelectorFromString(@"fullScreenContentDelegate");
	__block IMP origGet = NULL;
	origGet = BTBSwizzle(cls, getDelegate, NO, ^id(id self_) {
		if (BTBIsFake(self_)) return objc_getAssociatedObject(self_, kDelegateKey);
		return origGet ? ((id (*)(id, SEL))origGet)(self_, getDelegate) : nil;
	});

	SEL canPresent = NSSelectorFromString(@"canPresentFromViewController:error:");
	__block IMP origCan = NULL;
	origCan = BTBSwizzle(cls, canPresent, NO, ^BOOL(id self_, id vc, NSError **error) {
		if (BTBIsFake(self_)) return YES;
		return origCan ? ((BOOL (*)(id, SEL, id, NSError **))origCan)(self_, canPresent, vc, error) : YES;
	});

	// show: skip the ad, grant the reward, close "the ad"
	SEL present = NSSelectorFromString(@"presentFromViewController:userDidEarnRewardHandler:");
	__block IMP origPresent = NULL;
	origPresent = BTBSwizzle(cls, present, NO, ^(id self_, id vc, void (^reward)(void)) {
		if (!BTBIsFake(self_)) {
			if (origPresent) ((void (*)(id, SEL, id, id))origPresent)(self_, present, vc, reward);
			return;
		}
		id delegate = objc_getAssociatedObject(self_, kDelegateKey);
		BTBCall(delegate, NSSelectorFromString(@"adWillPresentFullScreenContent:"), self_);
		BTBCall(delegate, NSSelectorFromString(@"adDidRecordImpression:"), self_);
		BTBLater(0.25, ^{
			if (reward) reward();
			BTBCall(delegate, NSSelectorFromString(@"adWillDismissFullScreenContent:"), self_);
			BTBCall(delegate, NSSelectorFromString(@"adDidDismissFullScreenContent:"), self_);
		});
	});
}

// MARK: AppLovin MAX

static id BTBMaxReward(void) {
	Class cls = NSClassFromString(@"MAReward");
	SEL sel = NSSelectorFromString(@"rewardWithAmount:label:");
	if (cls && [cls respondsToSelector:sel]) {
		return ((id (*)(Class, SEL, NSInteger, NSString *))objc_msgSend)(cls, sel, 1, @"");
	}
	return nil;
}

static id BTBMaxDelegate(id ad) {
	SEL sel = NSSelectorFromString(@"delegate");
	return [ad respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(ad, sel) : nil;
}

static void BTBSpoofMaxRewarded(void) {
	Class cls = NSClassFromString(@"MARewardedAd");
	if (!cls) return;

	SEL load = NSSelectorFromString(@"loadAd");
	BTBSwizzle(cls, load, NO, ^(id self_) {
		BTBLater(0.05, ^{ BTBCall(BTBMaxDelegate(self_), NSSelectorFromString(@"didLoadAd:"), nil); });
	});
	BTBSwizzle(cls, NSSelectorFromString(@"isReady"), NO, ^BOOL(id self_) { return YES; });

	void (^show)(id) = ^(id self_) {
		id delegate = BTBMaxDelegate(self_);
		BTBCall(delegate, NSSelectorFromString(@"didDisplayAd:"), nil);
		BTBLater(0.25, ^{
			SEL rewardSel = NSSelectorFromString(@"didRewardUserForAd:withReward:");
			if (delegate && [delegate respondsToSelector:rewardSel]) {
				((void (*)(id, SEL, id, id))objc_msgSend)(delegate, rewardSel, nil, BTBMaxReward());
			}
			BTBCall(delegate, NSSelectorFromString(@"didHideAd:"), nil);
		});
	};
	// every "show" variant of the SDK
	for (NSString *name in @[@"showAd", @"showAdForPlacement:", @"showAdForPlacement:customData:", @"showAdForPlacement:customData:viewController:", @"showAdFromViewController:"]) {
		SEL sel = NSSelectorFromString(name);
		int args = BTBArgumentCount(cls, sel, NO);
		if (args == 0) BTBSwizzle(cls, sel, NO, ^(id self_) { show(self_); });
		else if (args == 1) BTBSwizzle(cls, sel, NO, ^(id self_, id a) { show(self_); });
		else if (args == 2) BTBSwizzle(cls, sel, NO, ^(id self_, id a, id b) { show(self_); });
		else if (args == 3) BTBSwizzle(cls, sel, NO, ^(id self_, id a, id b, id c) { show(self_); });
	}
}

void BTBFeatureSpoofAds(void) {
	// run after the ad blocker so these replace its "rewarded ads fail" behaviour
	BTBSpoofAdMobClass(@"GADRewardedAd");
	BTBSpoofAdMobClass(@"GADRewardedInterstitialAd");
	BTBSpoofMaxRewarded();
	BTB_LOG("rewarded ads are answered without showing an ad");
}
