//  BTBIPadUI.m — /ipadui: make the app use its iPad interface on iPhone.
//  BetterThanBox also adds iPad (2) to UIDeviceFamily when this tweak is chosen.
//
//  On the iPad idiom UIKit shows action sheets and share sheets as popovers and
//  throws an exception when the app gave no anchor (code written for iPhone never
//  does) — that crash was the main problem of this tweak. We now anchor such
//  popovers to the centre of the presenting view.

#import "BTBPresentation.h"

static void BTBAnchorPopover(UIViewController *presenter, UIViewController *controller) {
	if (controller.modalPresentationStyle != UIModalPresentationPopover) return;
	UIPopoverPresentationController *popover = controller.popoverPresentationController;
	if (!popover) return;

	BOOL hasAnchor = popover.sourceView != nil || popover.barButtonItem != nil;
	if (!hasAnchor && [popover respondsToSelector:@selector(sourceItem)]) {
		hasAnchor = [popover valueForKey:@"sourceItem"] != nil;
	}
	if (hasAnchor) return;

	UIView *view = presenter.viewIfLoaded ?: presenter.view;
	if (!view) return;
	popover.sourceView = view;
	popover.sourceRect = CGRectMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds), 1, 1);
	popover.permittedArrowDirections = 0;
}

void BTBFeatureIPadUI(void) {
	BTBSwizzle([UIDevice class], @selector(userInterfaceIdiom), NO, ^UIUserInterfaceIdiom(id self) {
		return UIUserInterfaceIdiomPad;
	});
	BTBSwizzle([UITraitCollection class], @selector(userInterfaceIdiom), NO, ^UIUserInterfaceIdiom(id self) {
		return UIUserInterfaceIdiomPad;
	});

	BTBAddPresentationFilter(^BTBPresentDecision(UIViewController *presenter, UIViewController *controller) {
		BTBAnchorPopover(presenter, controller);
		return BTBPresentAllow;
	});
}
