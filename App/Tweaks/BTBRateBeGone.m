//  BTBRateBeGone.m — /norev: suppress "Rate this app" prompts.
//   * StoreKit review requests (UIKit and SwiftUI/StoreKit 2 end up here)
//   * the review sheet itself, if something presents it directly
//   * popular third-party rating libraries

#import "BTBPresentation.h"

static BOOL BTBIsReviewClass(Class cls) {
	NSString *name = NSStringFromClass(cls);
	return [name rangeOfString:@"StoreReview"].location != NSNotFound;
}

void BTBFeatureNoRate(void) {
	Class store = NSClassFromString(@"SKStoreReviewController");
	BTBSwizzle(store, NSSelectorFromString(@"requestReview"), YES, ^(id self) {
		BTB_LOG("blocked requestReview");
	});
	BTBSwizzle(store, NSSelectorFromString(@"requestReviewInScene:"), YES, ^(id self, id scene) {
		BTB_LOG("blocked requestReviewInScene");
	});

	// review sheet presented in-process
	BTBAddPresentationFilter(^BTBPresentDecision(UIViewController *presenter, UIViewController *controller) {
		return BTBIsReviewClass([controller class]) ? BTBPresentBlock : BTBPresentAllow;
	});

	// review sheet hosted in its own window
	SEL setHidden = @selector(setHidden:);
	__block IMP origHidden = NULL;
	origHidden = BTBSwizzle([UIWindow class], setHidden, NO, ^(UIWindow *self, BOOL hidden) {
		if (!hidden && (BTBIsReviewClass([self class]) || BTBIsReviewClass([self.rootViewController class]))) {
			hidden = YES;
		}
		((void (*)(id, SEL, BOOL))origHidden)(self, setHidden, hidden);
	});

	// third-party libraries
	BTBSwizzle(NSClassFromString(@"Appirater"), NSSelectorFromString(@"showPrompt"), NO, ^(id self) {});
	BTBSwizzle(NSClassFromString(@"Appirater"), NSSelectorFromString(@"showRatingAlert"), NO, ^(id self) {});
	BTBSwizzle(NSClassFromString(@"iRate"), NSSelectorFromString(@"promptForRating"), NO, ^(id self) {});
	BTBSwizzle(NSClassFromString(@"iRate"), NSSelectorFromString(@"promptIfNetworkAvailable"), NO, ^(id self) {});
}
