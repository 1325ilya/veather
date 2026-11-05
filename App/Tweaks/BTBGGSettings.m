//  BTBGGSettings.m — look of the GameGuardian panel (new light-blue style or the legacy purple one),
//  panel transparency, hiding the floating button, and the settings screen that holds them.

#import "BTBGGUI.h"
#import <QuartzCore/QuartzCore.h>

static NSString *const kStyleKey = @"btb.gg.style2";    // 0 new, 1 legacy
static NSString *const kLegacyKey = @"btb.gg.legacy";    // 0 blue, 1 purple
static NSString *const kOldStyleKey = @"btb.gg.style";   // first version: 1 meant the purple one
static NSString *const kAlphaKey = @"btb.gg.alpha";
static NSString *const kFingerKey = @"btb.gg.fourfinger.off";

BOOL BTBGGFourFingerEnabled(void) { return ![[NSUserDefaults standardUserDefaults] boolForKey:kFingerKey]; }

void BTBGGSetFourFingerEnabled(BOOL enabled) { [[NSUserDefaults standardUserDefaults] setBool:!enabled forKey:kFingerKey]; }

BTBGGStyleKind BTBGGCurrentStyle(void) {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSNumber *n = [d objectForKey:kStyleKey];
	if (!n) {
		NSNumber *old = [d objectForKey:kOldStyleKey];
		return (old && old.integerValue == 1) ? BTBGGStyleLegacyPurple : BTBGGStyleNew;
	}
	if (n.integerValue == 0) return BTBGGStyleNew;
	return [d integerForKey:kLegacyKey] == 1 ? BTBGGStyleLegacyPurple : BTBGGStyleLegacyBlue;
}

void BTBGGSetStyle(BTBGGStyleKind style) {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setInteger:style == BTBGGStyleNew ? 0 : 1 forKey:kStyleKey];
	if (style != BTBGGStyleNew) [d setInteger:style == BTBGGStyleLegacyPurple ? 1 : 0 forKey:kLegacyKey];
}

CGFloat BTBGGPanelAlpha(void) {
	NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:kAlphaKey];
	CGFloat a = n ? (CGFloat)n.doubleValue : 1.0;
	return MIN(1.0, MAX(0.35, a));
}

void BTBGGSetPanelAlpha(CGFloat alpha) {
	[[NSUserDefaults standardUserDefaults] setDouble:MIN(1.0, MAX(0.35, alpha)) forKey:kAlphaKey];
}

UIColor *BTBGGAccent(void) {
	switch (BTBGGCurrentStyle()) {
		case BTBGGStyleNew: return [UIColor colorWithRed:0.49 green:0.36 blue:1 alpha:1];          // Veather's brand colour
		case BTBGGStyleLegacyPurple: return [UIColor colorWithRed:0.49 green:0.36 blue:1 alpha:1];
		default: return [UIColor colorWithRed:0.20 green:0.55 blue:0.98 alpha:1];
	}
}

UIColor *BTBGGAccent2(void) {
	switch (BTBGGCurrentStyle()) {
		case BTBGGStyleNew: return [UIColor colorWithRed:0.36 green:0.55 blue:1.0 alpha:1];
		case BTBGGStyleLegacyPurple: return BTBGGAccent();
		default: return [UIColor colorWithRed:0.35 green:0.80 blue:1.0 alpha:1];
	}
}

UIColor *BTBGGBackground(void) {
	if (BTBGGCurrentStyle() == BTBGGStyleLegacyPurple) return UIColor.systemBackgroundColor;
	if (BTBGGCurrentStyle() == BTBGGStyleNew) return UIColor.systemGroupedBackgroundColor;
	return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
		return t.userInterfaceStyle == UIUserInterfaceStyleDark
			? [UIColor colorWithRed:0.06 green:0.09 blue:0.14 alpha:1]
			: [UIColor colorWithRed:0.92 green:0.96 blue:1.0 alpha:1];
	}];
}

// MARK: - Icons

UIImage *BTBGGTileImage(NSString *symbol, UIColor *color) {
	CGFloat size = 30;
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
	return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		CGRect rect = CGRectMake(0, 0, size, size);
		UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:size * 0.28];
		[path addClip];
		CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
		CGFloat r1, g1, b1, a1;
		[color getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
		CGFloat comps[8] = {MIN(1, r1 + 0.12), MIN(1, g1 + 0.12), MIN(1, b1 + 0.12), 1, r1, g1, b1, 1};
		CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
		CGContextDrawLinearGradient(ctx.CGContext, g, CGPointMake(0, 0), CGPointMake(0, size), 0);
		CGGradientRelease(g);
		CGColorSpaceRelease(cs);
		UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size * 0.52 weight:UIImageSymbolWeightSemibold];
		UIImage *sym = [[UIImage systemImageNamed:symbol withConfiguration:cfg] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
		CGSize ss = sym.size;
		[sym drawInRect:CGRectMake((size - ss.width) / 2, (size - ss.height) / 2, ss.width, ss.height)];
	}];
}

/// A shield (own drawing) with the letters GG.
UIImage *BTBGGShieldImage(CGFloat size, UIColor *tint) {
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
	return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		CGFloat w = size * 0.62, h = size * 0.72;
		CGFloat x = (size - w) / 2, y = (size - h) / 2;
		UIBezierPath *p = [UIBezierPath bezierPath];
		[p moveToPoint:CGPointMake(x + w / 2, y)];
		[p addLineToPoint:CGPointMake(x + w, y + h * 0.16)];
		[p addLineToPoint:CGPointMake(x + w, y + h * 0.52)];
		[p addQuadCurveToPoint:CGPointMake(x + w / 2, y + h) controlPoint:CGPointMake(x + w, y + h * 0.82)];
		[p addQuadCurveToPoint:CGPointMake(x, y + h * 0.52) controlPoint:CGPointMake(x, y + h * 0.82)];
		[p addLineToPoint:CGPointMake(x, y + h * 0.16)];
		[p closePath];
		[UIColor.whiteColor setFill];
		[p fill];
		// a seam down the middle, like a visor
		UIBezierPath *seam = [UIBezierPath bezierPath];
		[seam moveToPoint:CGPointMake(x + w / 2, y + h * 0.06)];
		[seam addLineToPoint:CGPointMake(x + w / 2, y + h * 0.9)];
		[[tint colorWithAlphaComponent:0.25] setStroke];
		seam.lineWidth = 1.2;
		[seam stroke];
		NSString *gg = @"GG";
		UIFont *font = [UIFont systemFontOfSize:size * 0.25 weight:UIFontWeightHeavy];
		NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: tint, NSKernAttributeName: @(size * 0.01)};
		CGSize ts = [gg sizeWithAttributes:attrs];
		[gg drawAtPoint:CGPointMake(x + (w - ts.width) / 2, y + h * 0.26) withAttributes:attrs];
	}];
}

// MARK: - Button

@implementation BTBGGGradientButton

+ (Class)layerClass { return [CAGradientLayer class]; }

- (void)applyStyle {
	CAGradientLayer *g = (CAGradientLayer *)self.layer;
	UIColor *a = BTBGGAccent(), *b = BTBGGAccent2();
	g.startPoint = CGPointMake(0, 0);
	g.endPoint = CGPointMake(1, 1);
	if (self.filled) {
		g.colors = @[(id)a.CGColor, (id)b.CGColor];
		[self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
		self.tintColor = UIColor.whiteColor;
	} else {
		UIColor *soft = [a colorWithAlphaComponent:0.16];
		g.colors = @[(id)soft.CGColor, (id)soft.CGColor];
		[self setTitleColor:a forState:UIControlStateNormal];
		self.tintColor = a;
	}
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGSize s = self.bounds.size;
	BOOL round = s.width > 0 && fabs(s.width - s.height) < 1 && s.width >= 40;
	self.layer.cornerRadius = round ? s.width / 2 : 12;
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	self.alpha = highlighted ? 0.7 : 1;
}

@end

// MARK: - Settings screen

static NSUInteger CountFiles(NSString *dir) {
	NSUInteger n = 0;
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *f in [fm enumeratorAtPath:dir]) {
		NSString *ext = f.pathExtension.lowercaseString;
		if ([ext isEqualToString:@"lua"] || [ext isEqualToString:@"txt"]) n++;
	}
	return n;
}

@interface BTBGGSettingsVC : UITableViewController
@end

@implementation BTBGGSettingsVC {
	UILabel *_percent;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = BL(@"Settings", @"Настройки");
	self.tableView.backgroundColor = BTBGGBackground();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	if (s == 0) return BTBGGCurrentStyle() == BTBGGStyleNew ? 2 : 3;
	return s == 2 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	switch (s) {
		case 0: return BL(@"Style", @"Стиль");
		case 1: return BL(@"Panel transparency", @"Прозрачность панели");
		case 2: return BL(@"Floating button", @"Плавающая кнопка");
		default: return BL(@"Shared scripts", @"Общие скрипты");
	}
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	switch (s) {
		case 0: return BL(@"“New” follows the look of the Veather app. “Legacy” keeps the two older looks: light blue and the first purple one.", @"«Новый» — вид приложения Veather. «Legacy» — два прежних вида: голубой и самый первый фиолетовый.");
		case 1: return BL(@"Lower it to see the game behind the panel.", @"Уменьши, чтобы видеть игру за панелью.");
		case 2: return BL(@"Four-finger long press: hold four fingers on the screen for about a second. Turn it off if it opens by accident in the game. The hidden button comes back when the game restarts. At least one way to open the panel always stays on.", @"Долгое нажатие четырьмя пальцами: удерживай четыре пальца на экране около секунды. Выключи, если панель случайно открывается в игре. Скрытая кнопка вернётся при перезапуске игры. Хотя бы один способ открыть панель всегда остаётся включённым.");
		default: return BL(@"Shared scripts are added in Veather → Settings → GameGuardian (or in the Files app, folder Veather/GameGuardian/Scripts). Scripts are copied into the game when Veather signs it, so sign the game again after changing them.", @"Общие скрипты добавляются в Veather → Настройки → GameGuardian (или в приложении «Файлы», папка Veather/GameGuardian/Scripts). Скрипты копируются в игру при подписи, поэтому после изменений подпиши игру заново.");
	}
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	if (ip.section == 0) {
		BOOL isNew = BTBGGCurrentStyle() == BTBGGStyleNew;
		cell.tintColor = BTBGGAccent();
		if (ip.row == 0) {
			cell.textLabel.text = BL(@"New (like Veather)", @"Новый (как в Veather)");
			cell.accessoryType = isNew ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		} else if (ip.row == 1) {
			cell.textLabel.text = BL(@"Legacy (older looks)", @"Legacy (старые виды)");
			cell.accessoryType = isNew ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;
		} else {
			UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[BL(@"Light blue", @"Голубой"), BL(@"Purple", @"Фиолетовый")]];
			seg.selectedSegmentIndex = BTBGGCurrentStyle() == BTBGGStyleLegacyPurple ? 1 : 0;
			seg.selectedSegmentTintColor = BTBGGAccent();
			[seg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
			[seg addTarget:self action:@selector(legacyChanged:) forControlEvents:UIControlEventValueChanged];
			seg.translatesAutoresizingMaskIntoConstraints = NO;
			[cell.contentView addSubview:seg];
			[NSLayoutConstraint activateConstraints:@[
				[seg.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
				[seg.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
				[seg.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
				[seg.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
			]];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
	} else if (ip.section == 1) {
		UISlider *slider = [UISlider new];
		slider.minimumValue = 0.35;
		slider.maximumValue = 1;
		slider.value = (float)BTBGGPanelAlpha();
		slider.minimumTrackTintColor = BTBGGAccent();
		[slider addTarget:self action:@selector(alphaChanged:) forControlEvents:UIControlEventValueChanged];
		_percent = BTBGGLabel([UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium], UIColor.secondaryLabelColor);
		_percent.numberOfLines = 1;
		_percent.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(slider.value * 100)];
		[_percent.widthAnchor constraintEqualToConstant:44].active = YES;
		UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[slider, _percent]];
		row.spacing = 12;
		row.alignment = UIStackViewAlignmentCenter;
		row.translatesAutoresizingMaskIntoConstraints = NO;
		[cell.contentView addSubview:row];
		[NSLayoutConstraint activateConstraints:@[
			[row.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
			[row.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
			[row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
			[row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
		]];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	} else if (ip.section == 2 && ip.row == 0) {
		cell.textLabel.text = BL(@"Open with four fingers", @"Открывать четырьмя пальцами");
		UISwitch *sw = [UISwitch new];
		sw.on = BTBGGFourFingerEnabled();
		sw.onTintColor = BTBGGAccent();
		[sw addTarget:self action:@selector(fingerChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	} else if (ip.section == 2) {
		cell.textLabel.text = BL(@"Hide the button until restart", @"Скрыть кнопку до перезапуска");
		cell.textLabel.textColor = BTBGGAccent();
	} else {
		cell.textLabel.text = BL(@"Scripts available in this game", @"Общих скриптов в этой игре");
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)(CountFiles(BTBGGScriptsRoot(YES, YES)) + CountFiles(BTBGGScriptsRoot(YES, NO)))];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	return cell;
}

- (void)legacyChanged:(UISegmentedControl *)seg {
	BTBGGSetStyle(seg.selectedSegmentIndex == 1 ? BTBGGStyleLegacyPurple : BTBGGStyleLegacyBlue);
	dispatch_async(dispatch_get_main_queue(), ^{ BTBGGRebuildPanel(YES); });
}

- (void)fingerChanged:(UISwitch *)sw {
	if (!sw.on && BTBGGFloatingButtonHidden()) {
		sw.on = YES;
		UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"Cannot turn it off", @"Нельзя выключить") message:BL(@"The floating button is hidden, so this is the only way to open the panel. Restart the game to get the button back.", @"Плавающая кнопка скрыта, и это единственный способ открыть панель. Перезапусти игру, чтобы вернуть кнопку.") preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:a animated:YES completion:nil];
		return;
	}
	BTBGGSetFourFingerEnabled(sw.on);
}

- (void)alphaChanged:(UISlider *)slider {
	BTBGGSetPanelAlpha(slider.value);
	_percent.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(slider.value * 100)];
	BTBGGApplyPanelAlpha();
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == 0) {
		if (ip.row == 2) return;
		BOOL isNew = BTBGGCurrentStyle() == BTBGGStyleNew;
		if ((ip.row == 0) == isNew) return;
		BTBGGSetStyle(ip.row == 0 ? BTBGGStyleNew : BTBGGStyleLegacyBlue);
		dispatch_async(dispatch_get_main_queue(), ^{ BTBGGRebuildPanel(YES); });
	} else if (ip.section == 2 && ip.row == 1) {
		if (!BTBGGFourFingerEnabled()) {
			UIAlertController *w = [UIAlertController alertControllerWithTitle:BL(@"Cannot hide the button", @"Нельзя скрыть кнопку") message:BL(@"Four-finger opening is off, so the button is the only way to open the panel. Turn the four-finger switch on first.", @"Открытие четырьмя пальцами выключено, и кнопка — единственный способ открыть панель. Сначала включи переключатель четырёх пальцев.") preferredStyle:UIAlertControllerStyleAlert];
			[w addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
			[self presentViewController:w animated:YES completion:nil];
			return;
		}
		UIAlertController *a = [UIAlertController alertControllerWithTitle:BL(@"Hide the button?", @"Скрыть кнопку?") message:BL(@"It stays hidden until the game restarts. The panel still opens with a four-finger long press.", @"Она будет скрыта до перезапуска игры. Панель по-прежнему открывается долгим нажатием четырьмя пальцами.") preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Hide", @"Скрыть") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { BTBGGHideFloatingButton(); }]];
		[a addAction:[UIAlertAction actionWithTitle:BL(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:a animated:YES completion:nil];
	}
}

@end

UIViewController *BTBGGMakeSettingsVC(void) { return [BTBGGSettingsVC new]; }
