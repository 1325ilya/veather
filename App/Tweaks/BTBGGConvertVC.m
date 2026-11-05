//  BTBGGConvertVC.m — the "Converter" tab: type a number in any notation and see it in all the others
//  (decimal, hex, binary, octal, bytes in memory order, float, text).

#import "BTBGGUI.h"
#include <errno.h>

typedef NS_ENUM(NSInteger, ConvFormat) {
	ConvDec, ConvHex, ConvBin, ConvOct, ConvBytesLE, ConvBytesBE, ConvFloat32, ConvFloat64, ConvText, ConvFormatCount
};

static NSString *FormatTitle(ConvFormat f) {
	switch (f) {
		case ConvDec: return BL(@"Decimal", @"Десятичное");
		case ConvHex: return BL(@"Hex", @"Шестнадцатеричное (hex)");
		case ConvBin: return BL(@"Binary", @"Двоичное");
		case ConvOct: return BL(@"Octal", @"Восьмеричное");
		case ConvBytesLE: return BL(@"Bytes as in memory (little-endian)", @"Байты как в памяти (little-endian)");
		case ConvBytesBE: return BL(@"Bytes, big-endian", @"Байты, big-endian");
		case ConvFloat32: return BL(@"Float (32 bit)", @"Float (32 бита)");
		case ConvFloat64: return BL(@"Double (64 bit)", @"Double (64 бита)");
		default: return BL(@"Text", @"Текст");
	}
}

static NSString *FormatExample(ConvFormat f) {
	switch (f) {
		case ConvDec: return @"3840  /  -25";
		case ConvHex: return @"F00  /  0x0F00";
		case ConvBin: return @"1111 0000 0000";
		case ConvOct: return @"7400";
		case ConvBytesLE: return @"00 0F 00 00";
		case ConvBytesBE: return @"00 00 0F 00";
		case ConvFloat32: return @"1.5";
		case ConvFloat64: return @"0.1";
		default: return @"Hi";
	}
}

static NSInteger RoundWidth(NSUInteger bytes) { return bytes <= 1 ? 1 : bytes == 2 ? 2 : bytes <= 4 ? 4 : 8; }

static uint64_t Mask(NSInteger w) { return w >= 8 ? UINT64_MAX : ((1ull << (w * 8)) - 1); }

/// Digits of the text in the given base (spaces, underscores and a 0x / 0b / 0o prefix are allowed), or nil.
static NSString *Digits(NSString *text, int base) {
	NSString *t = [[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
	NSString *prefix = base == 16 ? @"0x" : base == 2 ? @"0b" : base == 8 ? @"0o" : @"";
	if (prefix.length && [t hasPrefix:prefix]) t = [t substringFromIndex:2];
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < t.length; i++) {
		unichar c = [t characterAtIndex:i];
		if (c == ' ' || c == '_' || c == ',' || c == '\'') continue;
		int v = c >= '0' && c <= '9' ? c - '0' : (c >= 'a' && c <= 'f' ? c - 'a' + 10 : 99);
		if (v >= base) return nil;
		[out appendFormat:@"%C", c];
	}
	return out.length ? out : nil;
}

static NSData *LEBytes(uint64_t u, NSInteger w) {
	uint8_t b[8];
	for (int i = 0; i < 8; i++) b[i] = (uint8_t)(u >> (8 * i));
	return [NSData dataWithBytes:b length:(NSUInteger)w];
}

/// Little-endian bytes of the typed value, or nil with an error text (nil error: nothing typed).
static NSData *ParseInput(ConvFormat f, NSString *text, NSInteger width, NSString **error) {
	NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (t.length == 0) return nil;
	NSString *bad = BL(@"This is not a valid number in this format.", @"Это не число в выбранном формате.");
	NSString *tooBig = BL(@"The number does not fit the chosen size.", @"Число не помещается в выбранный размер.");
	switch (f) {
		case ConvDec: {
			BOOL neg = [t hasPrefix:@"-"];
			NSString *d = Digits(neg ? [t substringFromIndex:1] : t, 10);
			if (!d) { *error = bad; return nil; }
			errno = 0;
			unsigned long long m = strtoull(d.UTF8String, NULL, 10);
			if (errno == ERANGE || (neg && m > (1ull << 63))) { *error = BL(@"The number is bigger than 64 bits.", @"Число больше 64 бит."); return nil; }
			uint64_t u = neg ? (~(uint64_t)m + 1) : (uint64_t)m;
			NSInteger w = width;
			if (w == 0) w = neg ? (m <= (1ull << 31) ? 4 : 8) : (m <= 0xFFFFFFFFull ? 4 : 8);
			BOOL fits = neg ? (w >= 8 || m <= (1ull << (w * 8 - 1))) : (u <= Mask(w));
			if (!fits) { *error = tooBig; return nil; }
			return LEBytes(u & Mask(w), w);
		}
		case ConvHex: case ConvBin: case ConvOct: {
			int base = f == ConvHex ? 16 : f == ConvBin ? 2 : 8;
			NSString *d = Digits(t, base);
			if (!d) { *error = bad; return nil; }
			errno = 0;
			unsigned long long u = strtoull(d.UTF8String, NULL, base);
			if (errno == ERANGE) { *error = BL(@"The number is bigger than 64 bits.", @"Число больше 64 бит."); return nil; }
			NSInteger w = width;
			if (w == 0) {
				if (f == ConvHex) w = RoundWidth((d.length + 1) / 2);
				else if (f == ConvBin) w = RoundWidth((d.length + 7) / 8);
				else w = u <= 0xFFFFFFFFull ? 4 : 8;
			}
			if (u > Mask(w)) { *error = tooBig; return nil; }
			return LEBytes(u, w);
		}
		case ConvBytesLE: case ConvBytesBE: {
			NSString *s = [t.lowercaseString stringByReplacingOccurrencesOfString:@"0x" withString:@""];
			NSMutableString *hex = [NSMutableString string];
			for (NSUInteger i = 0; i < s.length; i++) {
				unichar c = [s characterAtIndex:i];
				if (c == ' ' || c == ',' || c == '_' || c == ':' || c == '-') continue;
				if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) { *error = bad; return nil; }
				[hex appendFormat:@"%C", c];
			}
			if (hex.length == 0 || hex.length % 2) { *error = BL(@"Bytes are written as pairs of hex digits, e.g. 00 0F 00.", @"Байты записываются парами hex-цифр, например 00 0F 00."); return nil; }
			NSMutableData *d = [NSMutableData data];
			for (NSUInteger i = 0; i < hex.length; i += 2) {
				uint8_t b = (uint8_t)strtoul([hex substringWithRange:NSMakeRange(i, 2)].UTF8String, NULL, 16);
				[d appendBytes:&b length:1];
			}
			if (d.length > 8) { *error = BL(@"Up to 8 bytes.", @"Не больше 8 байт."); return nil; }
			NSMutableData *le = [NSMutableData data];
			const uint8_t *p = d.bytes;
			for (NSUInteger i = 0; i < d.length; i++) { uint8_t b = f == ConvBytesLE ? p[i] : p[d.length - 1 - i]; [le appendBytes:&b length:1]; }
			if (width > 0) {
				if ((NSInteger)le.length > width) { *error = tooBig; return nil; }
				le.length = (NSUInteger)width; // pad with zeros at the high end
			}
			return le;
		}
		case ConvFloat32: case ConvFloat64: {
			NSString *s = [t stringByReplacingOccurrencesOfString:@"," withString:@"."];
			char *end = NULL;
			double dv = strtod(s.UTF8String, &end);
			if (end == s.UTF8String || *end != 0) { *error = bad; return nil; }
			if (f == ConvFloat32) { float fl = (float)dv; return [NSData dataWithBytes:&fl length:4]; }
			return [NSData dataWithBytes:&dv length:8];
		}
		default: {
			NSData *d = [text dataUsingEncoding:NSUTF8StringEncoding];
			if (d.length == 0 || d.length > 8) { *error = BL(@"Up to 8 characters (bytes).", @"Не больше 8 символов (байт)."); return nil; }
			return d;
		}
	}
}

/// Every notation of the same bytes, as {title, value} rows.
static NSArray<NSArray<NSString *> *> *Describe(NSData *le) {
	NSUInteger n = le.length;
	const uint8_t *p = le.bytes;
	uint64_t u = 0;
	for (NSUInteger i = 0; i < n && i < 8; i++) u |= (uint64_t)p[i] << (8 * i);
	int64_t s = (int64_t)u;
	if (n < 8) { uint64_t sign = 1ull << (n * 8 - 1); s = (int64_t)((u ^ sign) - sign); }

	NSMutableString *bin = [NSMutableString string];
	for (NSInteger i = (NSInteger)n - 1; i >= 0; i--) {
		for (int b = 7; b >= 0; b--) [bin appendString:((p[i] >> b) & 1) ? @"1" : @"0"];
		if (i > 0) [bin appendString:@" "];
	}
	NSMutableArray *leParts = [NSMutableArray array], *beParts = [NSMutableArray array];
	for (NSUInteger i = 0; i < n; i++) {
		[leParts addObject:[NSString stringWithFormat:@"%02X", p[i]]];
		[beParts insertObject:[NSString stringWithFormat:@"%02X", p[i]] atIndex:0];
	}
	NSMutableString *ascii = [NSMutableString string];
	for (NSUInteger i = 0; i < n; i++) [ascii appendString:(p[i] >= 32 && p[i] < 127) ? [NSString stringWithFormat:@"%c", p[i]] : @"."];

	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:@[BL(@"Size", @"Размер"), [NSString stringWithFormat:BL(@"%lu byte(s), %lu bits", @"байт: %lu, бит: %lu"), (unsigned long)n, (unsigned long)n * 8]]];
	[rows addObject:@[BL(@"Decimal (unsigned)", @"Десятичное (без знака)"), [NSString stringWithFormat:@"%llu", u]]];
	[rows addObject:@[BL(@"Decimal (signed)", @"Десятичное (со знаком)"), [NSString stringWithFormat:@"%lld", s]]];
	[rows addObject:@[BL(@"Hex", @"Hex"), [NSString stringWithFormat:@"0x%0*llX", (int)n * 2, u]]];
	[rows addObject:@[BL(@"Binary", @"Двоичное"), bin]];
	[rows addObject:@[BL(@"Octal", @"Восьмеричное"), [NSString stringWithFormat:@"0%llo", u]]];
	[rows addObject:@[BL(@"Bytes in memory (little-endian)", @"Байты в памяти (little-endian)"), [leParts componentsJoinedByString:@" "]]];
	[rows addObject:@[BL(@"Bytes, big-endian", @"Байты, big-endian"), [beParts componentsJoinedByString:@" "]]];
	if (n == 4) { float fl; memcpy(&fl, p, 4); [rows addObject:@[BL(@"Float (32 bit)", @"Float (32 бита)"), [NSString stringWithFormat:@"%.9g", (double)fl]]]; }
	if (n == 8) { double db; memcpy(&db, p, 8); [rows addObject:@[BL(@"Double (64 bit)", @"Double (64 бита)"), [NSString stringWithFormat:@"%.17g", db]]]; }
	[rows addObject:@[BL(@"Text (ASCII)", @"Текст (ASCII)"), ascii]];
	return rows;
}

@interface BTBGGConvertVC : UITableViewController <UITextFieldDelegate>
@end

@implementation BTBGGConvertVC {
	ConvFormat _format;
	NSInteger _width;       // 0 = automatic
	UITextField *_field;
	UIButton *_formatButton, *_widthButton;
	UILabel *_status;
	UIView *_header;
	NSArray<NSArray<NSString *> *> *_rows;
	CGFloat _headerWidth;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.backgroundColor = BTBGGBackground();
	self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	_format = ConvDec;

	UILabel *hint = BTBGGLabel([UIFont systemFontOfSize:13], UIColor.secondaryLabelColor);
	hint.text = BL(@"Pick the notation of what you have, type it, and see it in every other notation. Tap a line to copy it.", @"Выбери формат того, что у тебя есть, введи значение — и увидишь его во всех остальных форматах. Нажми на строку, чтобы скопировать.");

	_formatButton = BTBGGBigButton(@"", NO, nil, nil);
	_widthButton = BTBGGBigButton(@"", NO, nil, nil);
	_field = [UITextField new];
	_field.borderStyle = UITextBorderStyleRoundedRect;
	_field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	_field.autocorrectionType = UITextAutocorrectionTypeNo;
	_field.smartDashesType = UITextSmartDashesTypeNo;
	_field.smartQuotesType = UITextSmartQuotesTypeNo;
	_field.keyboardType = UIKeyboardTypeASCIICapable;
	_field.clearButtonMode = UITextFieldViewModeWhileEditing;
	_field.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightRegular];
	_field.delegate = self;
	[_field addTarget:self action:@selector(convert) forControlEvents:UIControlEventEditingChanged];
	[_field.heightAnchor constraintEqualToConstant:46].active = YES;
	_status = BTBGGLabel([UIFont systemFontOfSize:13], UIColor.systemRedColor);

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[hint, _formatButton, _widthButton, _field, _status]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 10;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	_header = [UIView new];
	[_header addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:_header.topAnchor constant:10],
		[stack.leadingAnchor constraintEqualToAnchor:_header.leadingAnchor constant:20],
		[stack.trailingAnchor constraintEqualToAnchor:_header.trailingAnchor constant:-20],
		[stack.bottomAnchor constraintEqualToAnchor:_header.bottomAnchor constant:-8],
	]];
	self.tableView.tableHeaderView = _header;
	[self buildMenus];
	[self convert];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (fabs(self.tableView.bounds.size.width - _headerWidth) > 0.5) [self updateHeaderHeight];
}

- (void)updateHeaderHeight {
	CGFloat w = self.tableView.bounds.size.width;
	if (w <= 0) return;
	_headerWidth = w;
	CGSize fit = [_header systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
	_header.frame = CGRectMake(0, 0, w, fit.height);
	self.tableView.tableHeaderView = _header;
}

- (void)buildMenus {
	__weak typeof(self) weak = self;
	NSMutableArray *formats = [NSMutableArray array];
	for (NSInteger i = 0; i < ConvFormatCount; i++) {
		ConvFormat f = (ConvFormat)i;
		UIAction *a = [UIAction actionWithTitle:FormatTitle(f) image:nil identifier:nil handler:^(UIAction *x) {
			__strong typeof(self) me = weak;
			if (!me) return;
			me->_format = f;
			[me buildMenus];
			[me convert];
		}];
		a.state = f == _format ? UIMenuElementStateOn : UIMenuElementStateOff;
		[formats addObject:a];
	}
	_formatButton.menu = [UIMenu menuWithChildren:formats];
	_formatButton.showsMenuAsPrimaryAction = YES;
	[_formatButton setTitle:[NSString stringWithFormat:BL(@"I have: %@ ▾", @"У меня: %@ ▾"), FormatTitle(_format)] forState:UIControlStateNormal];

	NSArray *sizes = @[@0, @1, @2, @4, @8];
	NSMutableArray *widths = [NSMutableArray array];
	for (NSNumber *n in sizes) {
		NSInteger w = n.integerValue;
		NSString *title = w == 0 ? BL(@"Automatic", @"Автоматически") : [NSString stringWithFormat:BL(@"%ld byte(s) (%ld bit)", @"%ld байт (%ld бит)"), (long)w, (long)w * 8];
		UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *x) {
			__strong typeof(self) me = weak;
			if (!me) return;
			me->_width = w;
			[me buildMenus];
			[me convert];
		}];
		a.state = w == _width ? UIMenuElementStateOn : UIMenuElementStateOff;
		[widths addObject:a];
	}
	_widthButton.menu = [UIMenu menuWithChildren:widths];
	_widthButton.showsMenuAsPrimaryAction = YES;
	[_widthButton setTitle:[NSString stringWithFormat:BL(@"Size: %@ ▾", @"Размер: %@ ▾"), _width == 0 ? BL(@"automatic", @"автоматически") : [NSString stringWithFormat:BL(@"%ld byte(s)", @"%ld байт"), (long)_width]] forState:UIControlStateNormal];
	_field.placeholder = [NSString stringWithFormat:BL(@"e.g. %@", @"например, %@"), FormatExample(_format)];
	_field.keyboardType = (_format == ConvDec || _format == ConvBin || _format == ConvOct || _format == ConvFloat32 || _format == ConvFloat64) ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeASCIICapable;
	[_field reloadInputViews];
}

- (void)convert {
	NSString *err = nil;
	NSData *d = ParseInput(_format, _field.text ?: @"", _width, &err);
	_rows = d ? Describe(d) : @[];
	_status.textColor = UIColor.systemRedColor;
	_status.text = err ?: @"";
	[self updateHeaderHeight];
	[self.tableView reloadData];
}

- (BOOL)textFieldShouldReturn:(UITextField *)f { [f resignFirstResponder]; return YES; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)_rows.count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _rows.count ? BL(@"Result", @"Результат") : nil; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = _rows[ip.row][0];
	cell.textLabel.font = [UIFont systemFontOfSize:13];
	cell.textLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.text = _rows[ip.row][1];
	cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightMedium];
	cell.detailTextLabel.textColor = UIColor.labelColor;
	cell.detailTextLabel.numberOfLines = 0;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	UIPasteboard.generalPasteboard.string = _rows[ip.row][1];
	_status.textColor = UIColor.systemGreenColor;
	_status.text = [NSString stringWithFormat:BL(@"Copied: %@", @"Скопировано: %@"), _rows[ip.row][1]];
	[self updateHeaderHeight];
	__weak typeof(self) weak = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		__strong typeof(self) me = weak;
		if (!me) return;
		if ([me->_status.text hasPrefix:BL(@"Copied", @"Скопировано")]) { me->_status.text = @""; [me updateHeaderHeight]; }
		me->_status.textColor = UIColor.systemRedColor;
	});
}

@end

UIViewController *BTBGGMakeConverterVC(void) { return [BTBGGConvertVC new]; }
