//  BTBNoAds.m — /noads: blocks known ad networks (DNS + URL loading)
//  and turns load/show calls of popular ad SDKs into no-ops.

#import "BTBURLBlock.h"
#import <UIKit/UIKit.h>

static NSArray<NSString *> *BTBAdHosts(void) {
	static NSArray *hosts;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		hosts = @[
			@"doubleclick.net", @"googlesyndication.com", @"googleadservices.com", @"admob.com",
			@"googletagservices.com", @"adservice.google.com",
			@"applovin.com", @"applvn.com", @"unityads.unity3d.com", @"ads.mopub.com",
			@"supersonicads.com", @"ironsrc.com", @"ironsrc.mobi", @"vungle.com", @"chartboost.com",
			@"inmobi.com", @"adcolony.com", @"startappservice.com", @"tapjoy.com", @"tapjoyads.com",
			@"pangle.io", @"pangleglobal.com", @"mintegral.com", @"rayjump.com",
			@"fyber.com", @"inner-active.mobi", @"smaato.net", @"criteo.com", @"amazon-adsystem.com",
			@"adnxs.com", @"an.facebook.com", @"yandexadexchange.net", @"ads.yandex.ru",
			@"mobileads.yandex.ru", @"bidmachine.io", @"appodeal.com", @"liftoff.io", @"moloco.com"
		];
	});
	return hosts;
}

BOOL BTBIsAdHost(const char *cHost) {
	if (!cHost) return NO;
	NSString *host = [[NSString stringWithUTF8String:cHost] lowercaseString];
	for (NSString *suffix in BTBAdHosts()) {
		if ([host isEqualToString:suffix] || [host hasSuffix:[@"." stringByAppendingString:suffix]]) return YES;
	}
	return NO;
}

static void BTBNoop(NSString *cls, NSString *sel, BOOL isClass) {
	Class c = NSClassFromString(cls);
	if (!c) return;
	SEL s = NSSelectorFromString(sel);
	Method m = class_getInstanceMethod(isClass ? object_getClass(c) : c, s);
	if (!m) return;
	char *ret = method_copyReturnType(m);
	BOOL returnsVoid = ret && ret[0] == 'v';
	free(ret);
	if (!returnsVoid) return; // only silence void methods, never break return values
	id block;
	switch (method_getNumberOfArguments(m)) {
		case 2: block = ^(id self) {}; break;
		case 3: block = ^(id self, id a) {}; break;
		case 4: block = ^(id self, id a, id b) {}; break;
		case 5: block = ^(id self, id a, id b, id c) {}; break;
		default: return;
	}
	BTBSwizzle(c, s, isClass, block);
}

static void BTBHideAdViews(void) {
	NSArray *bannerClasses = @[@"GADBannerView", @"GAMBannerView", @"MAAdView", @"ALAdView", @"FBAdView", @"ISBannerView", @"UADSBannerView", @"MPAdView", @"YMAAdView"];
	for (NSString *name in bannerClasses) {
		Class c = NSClassFromString(name);
		if (!c) continue;
		SEL sel = @selector(didMoveToWindow);
		__block IMP orig = NULL;
		orig = BTBSwizzle(c, sel, NO, ^(UIView *self) {
			if (orig) ((void (*)(id, SEL))orig)(self, sel);
			self.hidden = YES;
			self.alpha = 0;
		});
	}
}

void BTBFeatureNoAds(void) {
	BTBInstallURLFilter(^BTBURLDecision(NSURLRequest *request) {
		return BTBIsAdHost(request.URL.host.UTF8String) ? BTBURLDecisionFail : BTBURLDecisionAllow;
	});
	
	// Google Mobile Ads
	BTBNoop(@"GADBannerView", @"loadRequest:", NO);
	BTBNoop(@"GAMBannerView", @"loadRequest:", NO);
	BTBNoop(@"GADInterstitialAd", @"loadWithAdUnitID:request:completionHandler:", YES);
	BTBNoop(@"GADRewardedAd", @"loadWithAdUnitID:request:completionHandler:", YES);
	BTBNoop(@"GADRewardedInterstitialAd", @"loadWithAdUnitID:request:completionHandler:", YES);
	BTBNoop(@"GADAppOpenAd", @"loadWithAdUnitID:request:completionHandler:", YES);
	BTBNoop(@"GADInterstitialAd", @"presentFromRootViewController:", NO);
	BTBNoop(@"GADAppOpenAd", @"presentFromRootViewController:", NO);
	// AppLovin MAX
	BTBNoop(@"MAAdView", @"loadAd", NO);
	BTBNoop(@"MAInterstitialAd", @"loadAd", NO);
	BTBNoop(@"MAInterstitialAd", @"showAd", NO);
	BTBNoop(@"MAAppOpenAd", @"loadAd", NO);
	BTBNoop(@"MAAppOpenAd", @"showAd", NO);
	// Meta Audience Network
	BTBNoop(@"FBAdView", @"loadAd", NO);
	BTBNoop(@"FBInterstitialAd", @"loadAd", NO);
	// Unity Ads
	BTBNoop(@"UnityAds", @"load:loadDelegate:", YES);
	BTBNoop(@"UnityAds", @"show:placementId:showDelegate:", YES);
	// ironSource
	BTBNoop(@"IronSource", @"loadInterstitial", YES);
	BTBNoop(@"IronSource", @"showInterstitialWithViewController:", YES);
	
	BTBHideAdViews();
}
