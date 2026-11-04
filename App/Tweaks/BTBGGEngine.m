//  BTBGGEngine.m — memory scanner/editor engine (see BTBGGEngine.h).
//  Works only on the process it is injected into, so it is meant for offline single-player games.

#import "BTBGGEngine.h"
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <os/proc.h>
#import <sys/mman.h>
#import <errno.h>
#import <math.h>
#import <UIKit/UIKit.h>

static const size_t kChunk = 1 << 20;
static const size_t kMaxOverlap = 4096;
static const size_t kMemoryFloor = 400u << 20; // stop when less than ~400 MB is left for the game
static const NSUInteger kMaxFrozen = 20000;

NSString *BTBGGL(NSString *en, NSString *ru) {
	NSString *lang = NSLocale.preferredLanguages.firstObject;
	return [lang hasPrefix:@"ru"] ? ru : en;
}

// MARK: - Types and numbers

static size_t TS(BTBGGType t) { // size of one value
	switch (t) {
		case BTBGGTypeByte: return 1;
		case BTBGGTypeWord: return 2;
		case BTBGGTypeQword: case BTBGGTypeDouble: return 8;
		default: return 4;
	}
}
static size_t RS(BTBGGType t) { return t == BTBGGTypeXor ? 8 : TS(t); } // bytes that must be read
static BOOL IsFloat(BTBGGType t) { return t == BTBGGTypeFloat || t == BTBGGTypeDouble; }

static int64_t SV(uint64_t raw, BTBGGType t) {
	switch (t) {
		case BTBGGTypeByte: return (int8_t)raw;
		case BTBGGTypeWord: return (int16_t)raw;
		case BTBGGTypeQword: return (int64_t)raw;
		default: return (int32_t)raw;
	}
}
static double DV(uint64_t raw, BTBGGType t) {
	if (t == BTBGGTypeFloat) { float f; memcpy(&f, &raw, 4); return f; }
	if (t == BTBGGTypeDouble) { double d; memcpy(&d, &raw, 8); return d; }
	return (double)SV(raw, t);
}

/// -1 less, 0 equal, 1 greater, 2 not comparable (NaN)
static int Cmp(uint64_t a, uint64_t b, BTBGGType t) {
	if (IsFloat(t)) {
		double x = DV(a, t), y = DV(b, t);
		if (isnan(x) || isnan(y)) return 2;
		return x < y ? -1 : (x > y);
	}
	int64_t x = SV(a, t), y = SV(b, t);
	return x < y ? -1 : (x > y);
}

static BOOL ParseRaw(NSString *text, BTBGGType t, uint64_t *raw) {
	NSString *s = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (s.length == 0) return NO;
	s = [s stringByReplacingOccurrencesOfString:@"," withString:@"."];
	const char *c = s.UTF8String;
	char *end = NULL;
	*raw = 0;
	if (IsFloat(t)) {
		double d = strtod(c, &end);
		if (end == c || *end) return NO;
		if (t == BTBGGTypeFloat) { float f = (float)d; memcpy(raw, &f, 4); } else memcpy(raw, &d, 8);
		return YES;
	}
	const char *p = c;
	int base = 10;
	if (*p == 'h' || *p == 'H') { base = 16; p++; }
	else if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) { base = 16; p += 2; }
	unsigned long long u = 0;
	if (base == 16) {
		u = strtoull(p, &end, 16);
	} else {
		errno = 0;
		long long v = strtoll(p, &end, 10);
		if (errno == ERANGE && *p != '-') { errno = 0; u = strtoull(p, &end, 10); } else u = (unsigned long long)v;
	}
	if (end == p || *end) return NO;
	size_t n = TS(t);
	if (n < 8) u &= ((1ull << (n * 8)) - 1);
	*raw = u;
	return YES;
}

static NSString *Fmt(uint64_t raw, BTBGGType t) {
	switch (t) {
		case BTBGGTypeFloat: { float f; memcpy(&f, &raw, 4); return [NSString stringWithFormat:@"%g", f]; }
		case BTBGGTypeDouble: { double d; memcpy(&d, &raw, 8); return [NSString stringWithFormat:@"%.10g", d]; }
		case BTBGGTypeQword: return [NSString stringWithFormat:@"%lld", (long long)SV(raw, t)];
		default: return [NSString stringWithFormat:@"%lld", (long long)SV(raw, t)];
	}
}

// MARK: - Search specification

typedef NS_ENUM(int, SpecKind) { SpecSingle, SpecRange, SpecGroup, SpecUnknown };

typedef struct {
	SpecKind kind;
	BTBGGType type;
	BTBGGType candType[4];
	uint64_t candRaw[4];
	int candCount;
	uint64_t lo, hi;
	uint64_t group[8];
	int groupCount;
	size_t dist;
} Spec;

static NSString *WrongNumber(BTBGGType t) {
	return IsFloat(t) ? BTBGGL(@"That is not a number.", @"Это не число.")
		: BTBGGL(@"This type needs a whole number (use Decimal for numbers with a dot).", @"Для этого типа нужно целое число (для чисел с точкой выбери «Дробное»).");
}

static BOOL ParseSpec(NSString *text, BTBGGType t, Spec *s, NSString **err) {
	memset(s, 0, sizeof(*s));
	s->type = t;
	NSString *str = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (str.length == 0) { if (err) *err = BTBGGL(@"Type the number first.", @"Сначала введи число."); return NO; }

	if ([str containsString:@";"]) {
		if (t == BTBGGTypeAuto || t == BTBGGTypeXor) { if (err) *err = BTBGGL(@"Group search needs a concrete type (Dword, Float…).", @"Для поиска группы выбери конкретный тип (Dword, Float…)."); return NO; }
		NSArray *halves = [str componentsSeparatedByString:@"::"];
		NSArray *tokens = [halves[0] componentsSeparatedByString:@";"];
		s->dist = 128;
		if (halves.count > 1) { NSInteger d = [halves[1] integerValue]; if (d > 0) s->dist = (size_t)MIN(d, (NSInteger)kMaxOverlap); }
		for (NSString *tok in tokens) {
			if ([tok stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length == 0) continue;
			if (s->groupCount >= 8) { if (err) *err = BTBGGL(@"At most 8 numbers in a group.", @"В группе не больше 8 чисел."); return NO; }
			if (!ParseRaw(tok, t, &s->group[s->groupCount])) { if (err) *err = WrongNumber(t); return NO; }
			s->groupCount++;
		}
		if (s->groupCount == 0) { if (err) *err = BTBGGL(@"Type the numbers first.", @"Сначала введи числа."); return NO; }
		s->kind = SpecGroup;
		return YES;
	}

	NSRange tilde = [str rangeOfString:@"~"];
	if (tilde.location != NSNotFound && tilde.location > 0) {
		if (t == BTBGGTypeAuto || t == BTBGGTypeXor) { if (err) *err = BTBGGL(@"A range needs a concrete type (Dword, Float…).", @"Для диапазона выбери конкретный тип (Dword, Float…)."); return NO; }
		uint64_t a, b;
		if (!ParseRaw([str substringToIndex:tilde.location], t, &a) || !ParseRaw([str substringFromIndex:NSMaxRange(tilde)], t, &b)) { if (err) *err = WrongNumber(t); return NO; }
		int c = Cmp(a, b, t);
		s->lo = c == 1 ? b : a;
		s->hi = c == 1 ? a : b;
		s->kind = SpecRange;
		return YES;
	}

	s->kind = SpecSingle;
	if (t == BTBGGTypeAuto) {
		NSString *norm = [str stringByReplacingOccurrencesOfString:@"," withString:@"."];
		BOOL looksFloat = [norm rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@".eE"]].location != NSNotFound
			&& ![norm.lowercaseString hasPrefix:@"0x"] && ![norm.lowercaseString hasPrefix:@"h"];
		uint64_t raw;
		if (!looksFloat) {
			if (ParseRaw(norm, BTBGGTypeDword, &raw)) { s->candType[s->candCount] = BTBGGTypeDword; s->candRaw[s->candCount++] = raw; }
			if (ParseRaw(norm, BTBGGTypeQword, &raw)) { s->candType[s->candCount] = BTBGGTypeQword; s->candRaw[s->candCount++] = raw; }
		}
		if (ParseRaw(norm, BTBGGTypeFloat, &raw)) { s->candType[s->candCount] = BTBGGTypeFloat; s->candRaw[s->candCount++] = raw; }
		if (ParseRaw(norm, BTBGGTypeDouble, &raw)) { s->candType[s->candCount] = BTBGGTypeDouble; s->candRaw[s->candCount++] = raw; }
		if (s->candCount == 0) { if (err) *err = BTBGGL(@"That is not a number.", @"Это не число."); return NO; }
		return YES;
	}
	uint64_t raw;
	if (!ParseRaw(str, t, &raw)) { if (err) *err = WrongNumber(t); return NO; }
	if (t == BTBGGTypeXor && (uint32_t)raw == 0) { if (err) *err = BTBGGL(@"XOR search needs a number other than 0.", @"Для XOR-поиска нужно число, не равное 0."); return NO; }
	s->candType[0] = t;
	s->candRaw[0] = raw;
	s->candCount = 1;
	return YES;
}

// MARK: - Saved list item

@implementation BTBGGItem
@end

// MARK: - Freeze item

@interface BTBGGFreezeItem : NSObject
@property (nonatomic) BTBGGType type;
@property (nonatomic) uint64_t raw;
@property (nonatomic) BTBGGFreezeMode mode;
@end
@implementation BTBGGFreezeItem
@end

// MARK: - Image table (to tell the app's own code from system libraries)

typedef struct { uint64_t start, end; uint32_t image; } ImageSeg;

static int SegCompare(const void *a, const void *b) {
	uint64_t x = ((const ImageSeg *)a)->start, y = ((const ImageSeg *)b)->start;
	return x < y ? -1 : (x > y);
}

static int HitCompare(const void *a, const void *b) {
	uint64_t x = ((const BTBGGHit *)a)->addrType, y = ((const BTBGGHit *)b)->addrType;
	return x < y ? -1 : (x > y);
}

// MARK: - Engine

@implementation BTBGGEngine {
	NSLock *_opLock;
	BTBGGHit *_store;           // vm_allocate'd, so scans can skip it (it would find itself)
	size_t _maxHits;
	size_t _count;
	uint8_t *_readBuffer;       // same
	size_t _readBufferLength;
	BOOL _stoppedEarly;

	ImageSeg *_segs;
	size_t _segCount;
	uint32_t _imageCount;
	NSMutableArray<NSString *> *_imageNames;
	NSMutableArray<NSNumber *> *_imageBases;
	NSMutableArray<NSNumber *> *_imageIsApp;

	NSMutableDictionary<NSNumber *, BTBGGFreezeItem *> *_frozen;
	NSLock *_freezeLock;
	dispatch_source_t _freezeTimer;
	dispatch_queue_t _freezeQueue;

	NSMutableArray<BTBGGItem *> *_list;
}

+ (instancetype)shared {
	static BTBGGEngine *e;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ e = [BTBGGEngine new]; });
	return e;
}

- (instancetype)init {
	if ((self = [super init])) {
		_opLock = [NSLock new];
		_freezeLock = [NSLock new];
		_freezeQueue = dispatch_queue_create("com.veather.gg.freeze", DISPATCH_QUEUE_SERIAL);
		_frozen = [NSMutableDictionary dictionary];
		_regions = BTBGGRegionDefault;
		_addressFrom = 0;
		_addressTo = UINT64_MAX;
		_list = [NSMutableArray array];
		_imageNames = [NSMutableArray array];
		_imageBases = [NSMutableArray array];
		_imageIsApp = [NSMutableArray array];
		_readBufferLength = kChunk + kMaxOverlap + 16;
		vm_address_t a = 0;
		if (vm_allocate(mach_task_self(), &a, _readBufferLength, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) _readBuffer = (uint8_t *)a;
		[self loadPersistedList];
	}
	return self;
}

- (void)lock { [_opLock lock]; }
- (BOOL)tryLock { return [_opLock tryLock]; }
- (void)unlock { [_opLock unlock]; }
- (size_t)count { return _count; }
- (BOOL)stoppedEarly { return _stoppedEarly; }
- (NSMutableArray<BTBGGItem *> *)list { return _list; }

// MARK: Values

+ (size_t)sizeOfType:(BTBGGType)type { return TS(type); }
+ (BOOL)isFloatType:(BTBGGType)type { return IsFloat(type); }
+ (BOOL)parse:(NSString *)text type:(BTBGGType)type raw:(uint64_t *)raw {
	if (type == BTBGGTypeAuto) type = BTBGGTypeDword;
	return ParseRaw(text, type, raw);
}
+ (NSString *)format:(uint64_t)raw type:(BTBGGType)type { return Fmt(raw, type); }
+ (double)doubleValue:(uint64_t)raw type:(BTBGGType)type { return DV(raw, type); }
+ (int64_t)integerValue:(uint64_t)raw type:(BTBGGType)type { return IsFloat(type) ? (int64_t)DV(raw, type) : SV(raw, type); }
+ (uint64_t)rawFromDouble:(double)value type:(BTBGGType)type {
	uint64_t raw = 0;
	if (type == BTBGGTypeFloat) { float f = (float)value; memcpy(&raw, &f, 4); }
	else if (type == BTBGGTypeDouble) memcpy(&raw, &value, 8);
	else return [self rawFromInteger:(int64_t)value type:type];
	return raw;
}
+ (uint64_t)rawFromInteger:(int64_t)value type:(BTBGGType)type {
	if (IsFloat(type)) return [self rawFromDouble:(double)value type:type];
	uint64_t u = (uint64_t)value;
	size_t n = TS(type);
	if (n < 8) u &= ((1ull << (n * 8)) - 1);
	return u;
}

+ (NSString *)nameOfType:(BTBGGType)type {
	switch (type) {
		case BTBGGTypeByte: return @"Byte";
		case BTBGGTypeWord: return @"Word";
		case BTBGGTypeDword: return @"Dword";
		case BTBGGTypeQword: return @"Qword";
		case BTBGGTypeFloat: return @"Float";
		case BTBGGTypeDouble: return @"Double";
		case BTBGGTypeXor: return @"XOR";
		case BTBGGTypeAuto: return @"Auto";
	}
	return @"?";
}

- (BOOL)readBytes:(uint64_t)address into:(void *)buffer length:(size_t)length {
	vm_size_t out = 0;
	return vm_read_overwrite(mach_task_self(), (vm_address_t)address, length, (vm_address_t)buffer, &out) == KERN_SUCCESS && out == length;
}

- (BOOL)writeBytes:(uint64_t)address from:(const void *)buffer length:(size_t)length {
	return vm_write(mach_task_self(), (vm_address_t)address, (vm_offset_t)buffer, (mach_msg_type_number_t)length) == KERN_SUCCESS;
}

- (BOOL)readValue:(uint64_t)address type:(BTBGGType)type raw:(uint64_t *)raw {
	if (type == BTBGGTypeXor) {
		uint32_t pair[2];
		if (![self readBytes:address into:pair length:8]) return NO;
		*raw = (uint32_t)(pair[0] ^ pair[1]);
		return YES;
	}
	uint64_t v = 0;
	if (![self readBytes:address into:&v length:TS(type)]) return NO;
	*raw = v;
	return YES;
}

- (BOOL)writeValue:(uint64_t)address type:(BTBGGType)type raw:(uint64_t)raw {
	if (type == BTBGGTypeXor) { // keep the first word, change the second so that a ^ b == value
		uint32_t a;
		if (![self readBytes:address into:&a length:4]) return NO;
		uint32_t b = (uint32_t)raw ^ a;
		return [self writeBytes:address + 4 from:&b length:4];
	}
	return [self writeBytes:address from:&raw length:TS(type)];
}

// MARK: Images and regions

- (void)refreshImages {
	uint32_t n = _dyld_image_count();
	if (_segs && n == _imageCount) return;
	free(_segs);
	_segs = NULL;
	_segCount = 0;
	[_imageNames removeAllObjects];
	[_imageBases removeAllObjects];
	[_imageIsApp removeAllObjects];
	_imageCount = n;
	NSString *bundle = NSBundle.mainBundle.bundlePath ?: @"";
	size_t cap = 4096;
	ImageSeg *segs = malloc(cap * sizeof(ImageSeg));
	size_t count = 0;
	for (uint32_t i = 0; i < n; i++) {
		const struct mach_header *h = _dyld_get_image_header(i);
		const char *name = _dyld_get_image_name(i);
		BOOL ok = h && h->magic == MH_MAGIC_64;
		[_imageNames addObject:name ? [NSString stringWithUTF8String:name] : @""];
		[_imageBases addObject:@((uint64_t)(uintptr_t)h)];
		[_imageIsApp addObject:@(bundle.length > 0 && name && strncmp(name, bundle.UTF8String, bundle.length) == 0)];
		if (!ok) continue;
		intptr_t slide = _dyld_get_image_vmaddr_slide(i);
		const struct mach_header_64 *h64 = (const struct mach_header_64 *)h;
		const struct load_command *lc = (const struct load_command *)((const uint8_t *)h64 + sizeof(*h64));
		for (uint32_t c = 0; c < h64->ncmds; c++) {
			if (lc->cmd == LC_SEGMENT_64) {
				const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
				if (strcmp(seg->segname, "__PAGEZERO") != 0 && seg->vmsize > 0) {
					if (count == cap) { cap *= 2; segs = realloc(segs, cap * sizeof(ImageSeg)); }
					segs[count].start = seg->vmaddr + slide;
					segs[count].end = seg->vmaddr + slide + seg->vmsize;
					segs[count].image = i;
					count++;
				}
			}
			lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
		}
	}
	qsort(segs, count, sizeof(ImageSeg), SegCompare);
	_segs = segs;
	_segCount = count;
}

/// Index of the image that contains the address, or -1.
- (long)imageForAddress:(uint64_t)a {
	size_t lo = 0, hi = _segCount;
	while (lo < hi) {
		size_t mid = (lo + hi) / 2;
		if (_segs[mid].start <= a) lo = mid + 1; else hi = mid;
	}
	if (lo == 0) return -1;
	ImageSeg s = _segs[lo - 1];
	return (a >= s.start && a < s.end) ? (long)s.image : -1;
}

- (BOOL)moduleForAddress:(uint64_t)address name:(NSString **)name offset:(uint64_t *)offset {
	[self refreshImages];
	long idx = [self imageForAddress:address];
	if (idx < 0 || idx >= (long)_imageNames.count) return NO;
	if (name) *name = _imageNames[idx].lastPathComponent;
	if (offset) *offset = address - _imageBases[idx].unsignedLongLongValue;
	return YES;
}

- (NSString *)describeAddress:(uint64_t)address {
	NSString *m = nil;
	uint64_t off = 0;
	if ([self moduleForAddress:address name:&m offset:&off]) return [NSString stringWithFormat:@"%@+0x%llx", m, off];
	return [NSString stringWithFormat:@"0x%llx", address];
}

typedef BOOL (^RegionBlock)(uint64_t start, uint64_t size, BTBGGRegion cls, uint32_t tag, uint32_t prot, uint32_t resident, uint32_t swapped, long image);

- (void)enumerateRegionsFrom:(uint64_t)from to:(uint64_t)to block:(RegionBlock)block {
	vm_address_t addr = (vm_address_t)from;
	natural_t depth = 0;
	while ((uint64_t)addr < to) {
		vm_size_t size = 0;
		vm_region_submap_info_data_64_t info;
		mach_msg_type_number_t cnt = VM_REGION_SUBMAP_INFO_COUNT_64;
		if (vm_region_recurse_64(mach_task_self(), &addr, &size, &depth, (vm_region_recurse_info_t)&info, &cnt) != KERN_SUCCESS || size == 0) break;
		if (info.is_submap) { depth++; continue; }
		uint64_t start = addr, end = (uint64_t)addr + size;
		addr = (vm_address_t)end;
		if (end <= from) continue;
		if (start < from) start = from;
		if (end > to) end = to;
		if (end <= start) continue;
		long image = [self imageForAddress:start];
		BTBGGRegion cls;
		uint32_t tag = info.user_tag;
		if (image >= 0) cls = _imageIsApp[image].boolValue ? BTBGGRegionAppData : BTBGGRegionSystemData;
		else if (tag >= 1 && tag <= 13) cls = BTBGGRegionHeap;
		else if (tag == 30) cls = BTBGGRegionStack;
		else if (tag == 0 || tag >= 240) cls = BTBGGRegionAnonymous;
		else cls = BTBGGRegionOther;
		if (!block(start, end - start, cls, tag, info.protection, info.pages_resident, info.pages_swapped_out, image)) return;
	}
}

- (NSArray<NSDictionary *> *)regionList {
	[self refreshImages];
	NSMutableArray *out = [NSMutableArray array];
	[self enumerateRegionsFrom:0 to:UINT64_MAX block:^BOOL(uint64_t start, uint64_t size, BTBGGRegion cls, uint32_t tag, uint32_t prot, uint32_t res, uint32_t sw, long image) {
		[out addObject:@{
			@"start": @(start), @"end": @(start + size), @"mask": @(cls), @"tag": @(tag),
			@"writable": @((prot & VM_PROT_WRITE) != 0), @"readable": @((prot & VM_PROT_READ) != 0),
			@"executable": @((prot & VM_PROT_EXECUTE) != 0),
			@"name": image >= 0 ? self->_imageNames[image].lastPathComponent : @"",
		}];
		return YES;
	}];
	return out;
}

- (BOOL)overlapsOwn:(uint64_t)start length:(uint64_t)length {
	uint64_t end = start + length;
	uint64_t s1 = (uint64_t)(uintptr_t)_store, e1 = s1 + (uint64_t)_maxHits * sizeof(BTBGGHit);
	uint64_t s2 = (uint64_t)(uintptr_t)_readBuffer, e2 = s2 + _readBufferLength;
	return (_store && start < e1 && end > s1) || (_readBuffer && start < e2 && end > s2);
}

typedef BOOL (^ChunkBlock)(uint64_t base, const uint8_t *buf, size_t n, size_t avail);

/// Reads the writable regions chosen in `regions`, one chunk at a time. `n` bytes start in the chunk;
/// `avail` bytes are readable (n plus up to `overlap` bytes of the next chunk). Return NO to stop.
- (void)scanChunksWithOverlap:(size_t)overlap block:(ChunkBlock)block {
	if (!_readBuffer) return;
	overlap = MIN(overlap, kMaxOverlap);
	NSUInteger mask = _regions;
	__block BOOL stop = NO;
	[self enumerateRegionsFrom:_addressFrom to:_addressTo block:^BOOL(uint64_t start, uint64_t size, BTBGGRegion cls, uint32_t tag, uint32_t prot, uint32_t res, uint32_t sw, long image) {
		if (!((prot & VM_PROT_READ) && (prot & VM_PROT_WRITE))) return YES;
		if (!(mask & cls)) return YES;
		if (size >= (1ull << 36)) return YES;
		if (res == 0 && sw == 0) return YES; // never touched: reading it would only commit empty pages
		for (uint64_t off = 0; off < size && !stop; off += kChunk) {
			if (self.cancel) { stop = YES; self->_stoppedEarly = YES; break; }
			size_t n = (size_t)MIN((uint64_t)kChunk, size - off);
			size_t avail = (size_t)MIN((uint64_t)n + overlap, size - off);
			if ([self overlapsOwn:start + off length:avail]) continue;
			if (![self readBytes:start + off into:self->_readBuffer length:avail]) continue;
			if (!block(start + off, self->_readBuffer, n, avail)) stop = YES;
		}
		return !stop;
	}];
}

// MARK: Store

- (BOOL)prepareStore {
	if (_store) return YES;
	for (size_t entries = (size_t)1 << 27; entries >= ((size_t)1 << 22) && !_store; entries >>= 1) {
		vm_address_t a = 0;
		if (vm_allocate(mach_task_self(), &a, entries * sizeof(BTBGGHit), VM_FLAGS_ANYWHERE) == KERN_SUCCESS) { _store = (BTBGGHit *)a; _maxHits = entries; }
	}
	return _store != NULL;
}

- (void)freeStore {
	if (!_store) return;
	vm_deallocate(mach_task_self(), (vm_address_t)_store, _maxHits * sizeof(BTBGGHit));
	_store = NULL;
	_maxHits = 0;
}

- (void)clearResults {
	_count = 0;
	_stoppedEarly = NO;
	[self freeStore];
}

- (BTBGGHit)hitAtIndex:(size_t)index {
	BTBGGHit empty = {0, 0};
	return (_store && index < _count) ? _store[index] : empty;
}

- (void)loadHits:(const BTBGGHit *)hits count:(size_t)count {
	_count = 0;
	if (count == 0) { [self freeStore]; return; }
	if (![self prepareStore]) return;
	count = MIN(count, _maxHits);
	memcpy(_store, hits, count * sizeof(BTBGGHit));
	_count = count;
}

- (void)removeHitsWithAddresses:(NSSet<NSNumber *> *)addresses {
	size_t kept = 0;
	for (size_t i = 0; i < _count; i++) {
		if ([addresses containsObject:@(BTBGGHitAddress(_store[i]))]) continue;
		_store[kept++] = _store[i];
	}
	_count = kept;
	if (kept == 0) [self freeStore];
}

// MARK: Search

- (BOOL)search:(NSString *)text type:(BTBGGType)type unknown:(BOOL)unknown error:(NSString **)error {
	Spec spec;
	if (unknown) {
		if (type == BTBGGTypeXor) { if (error) *error = BTBGGL(@"XOR cannot be searched without a number.", @"XOR нельзя искать без числа."); return NO; }
		if (type == BTBGGTypeAuto) type = BTBGGTypeDword;
		memset(&spec, 0, sizeof(spec));
		spec.kind = SpecUnknown;
		spec.type = type;
	} else if (!ParseSpec(text, type, &spec, error)) {
		return NO;
	}
	[self clearResults];
	if (![self prepareStore] || !_readBuffer) { if (error) *error = BTBGGL(@"Out of memory.", @"Не хватает памяти."); return NO; }
	[self refreshImages];
	self.cancel = NO;

	BTBGGHit *store = _store;
	size_t maxHits = _maxHits;
	__block size_t found = 0;
	__block BOOL full = NO;

	// results are written through `f`; the macro stops the scan when the store or the phone's memory is full
#define EMIT(a, ty, rw) do { \
		store[f].addrType = ((uint64_t)(a)) | ((uint64_t)(ty) << 56); store[f].raw = (rw); f++; \
		if (f >= maxHits || ((f & 0xFFFF) == 0 && os_proc_available_memory() < kMemoryFloor)) { full = YES; found = f; return NO; } \
	} while (0)

	size_t overlap = spec.kind == SpecGroup ? spec.dist + 16 : 8;
	[self scanChunksWithOverlap:overlap block:^BOOL(uint64_t base, const uint8_t *buf, size_t n, size_t avail) {
		size_t f = found;
		switch (spec.kind) {
			case SpecSingle: {
				size_t step = 8;
				for (int k = 0; k < spec.candCount; k++) step = MIN(step, TS(spec.candType[k]));
				for (size_t i = 0; i < n; i += step) {
					for (int k = 0; k < spec.candCount; k++) {
						BTBGGType ct = spec.candType[k];
						size_t sz = TS(ct);
						if (i & (sz - 1)) continue;
						if (i + RS(ct) > avail) continue;
						const uint8_t *p = buf + i;
						if (ct == BTBGGTypeXor) {
							uint32_t a, b;
							memcpy(&a, p, 4);
							memcpy(&b, p + 4, 4);
							if ((a ^ b) == (uint32_t)spec.candRaw[k]) EMIT(base + i, ct, spec.candRaw[k]);
						} else if (memcmp(p, &spec.candRaw[k], sz) == 0) {
							EMIT(base + i, ct, spec.candRaw[k]);
						}
					}
				}
				break;
			}
			case SpecRange: {
				size_t sz = TS(spec.type);
				for (size_t i = 0; i + sz <= avail && i < n; i += sz) {
					uint64_t v = 0;
					memcpy(&v, buf + i, sz);
					if (Cmp(v, spec.lo, spec.type) >= 0 && Cmp(v, spec.lo, spec.type) != 2 && Cmp(v, spec.hi, spec.type) <= 0) EMIT(base + i, spec.type, v);
				}
				break;
			}
			case SpecGroup: {
				size_t sz = TS(spec.type);
				if (avail < sz) break;
				for (size_t i = 0; i < n && i + sz <= avail; i += sz) {
					if (memcmp(buf + i, &spec.group[0], sz) != 0) continue;
					size_t pos[8];
					pos[0] = i;
					BOOL ok = YES;
					for (int k = 1; k < spec.groupCount && ok; k++) {
						size_t lo = i > spec.dist ? i - spec.dist : 0;
						lo = (lo + sz - 1) & ~(sz - 1);
						size_t hi = MIN(i + spec.dist, avail - sz);
						BOOL hit = NO;
						for (size_t j = lo; j <= hi; j += sz) {
							if (memcmp(buf + j, &spec.group[k], sz) == 0) { pos[k] = j; hit = YES; break; }
						}
						ok = hit;
					}
					if (!ok) continue;
					for (int k = 0; k < spec.groupCount; k++) EMIT(base + pos[k], spec.type, spec.group[k]);
				}
				break;
			}
			case SpecUnknown: {
				// hidden/encrypted value: remember every non-zero aligned word, narrow it down later
				size_t sz = TS(spec.type);
				for (size_t i = 0; i < n && i + sz <= avail; i += sz) {
					uint64_t w = 0;
					memcpy(&w, buf + i, sz);
					if (w != 0) EMIT(base + i, spec.type, w);
				}
				break;
			}
		}
		found = f;
		return YES;
	}];
#undef EMIT

	if (spec.kind == SpecGroup && found > 1) { // several groups can share a member: keep each address once
		qsort(store, found, sizeof(BTBGGHit), HitCompare);
		size_t u = 0;
		for (size_t i = 0; i < found; i++) if (u == 0 || store[i].addrType != store[u - 1].addrType) store[u++] = store[i];
		found = u;
	}
	_count = found;
	_stoppedEarly = full || self.cancel;
	if (found == 0) [self freeStore];
	return YES;
}

- (BOOL)refine:(NSString *)text mode:(BTBGGMode)mode error:(NSString **)error {
	if (_count == 0 || !_store) return YES;

	// the typed numbers, parsed once per type
	uint64_t arg[8] = {0}, arg2[8] = {0};
	BOOL ok[8] = {NO};
	BOOL needsText = mode == BTBGGModeExact || mode == BTBGGModeRange || mode == BTBGGModeIncreasedBy || mode == BTBGGModeDecreasedBy
		|| mode == BTBGGModeNotEqual || mode == BTBGGModeAtMost || mode == BTBGGModeAtLeast;
	if (needsText) {
		NSString *str = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (str.length == 0) { if (error) *error = BTBGGL(@"Type the number first.", @"Сначала введи число."); return NO; }
		NSString *first = str, *second = nil;
		if (mode == BTBGGModeRange) {
			NSRange t = [str rangeOfString:@"~"];
			if (t.location == NSNotFound || t.location == 0) { if (error) *error = BTBGGL(@"Type a range like 10~20.", @"Введи диапазон вида 10~20."); return NO; }
			first = [str substringToIndex:t.location];
			second = [str substringFromIndex:NSMaxRange(t)];
		}
		BOOL any = NO;
		for (int t = 0; t < 7; t++) {
			ok[t] = ParseRaw(first, (BTBGGType)t, &arg[t]) && (!second || ParseRaw(second, (BTBGGType)t, &arg2[t]));
			if (ok[t] && second && Cmp(arg[t], arg2[t], (BTBGGType)t) == 1) { uint64_t x = arg[t]; arg[t] = arg2[t]; arg2[t] = x; }
			any = any || ok[t];
		}
		if (!any) { if (error) *error = BTBGGL(@"That is not a number.", @"Это не число."); return NO; }
	}

	self.cancel = NO;
	size_t total = _count, kept = 0;
	BTBGGHit *src = _store; // filtered in place: the write index never passes the read index
	for (size_t i = 0; i < total; i++) {
		if ((i & 0x3FFF) == 0 && self.cancel) { // keep what was not checked yet
			memmove(src + kept, src + i, (total - i) * sizeof(BTBGGHit));
			kept += total - i;
			_stoppedEarly = YES;
			break;
		}
		BTBGGHit h = src[i];
		BTBGGType t = BTBGGHitType(h);
		uint64_t now = 0;
		if (![self readValue:BTBGGHitAddress(h) type:t raw:&now]) continue;
		BOOL keep = NO;
		uint64_t old = h.raw;
		switch (mode) {
			case BTBGGModeExact: keep = ok[t] && (t == BTBGGTypeXor ? (uint32_t)now == (uint32_t)arg[t] : memcmp(&now, &arg[t], TS(t)) == 0); break;
			case BTBGGModeRange: keep = ok[t] && Cmp(now, arg[t], t) >= 0 && Cmp(now, arg[t], t) != 2 && Cmp(now, arg2[t], t) <= 0; break;
			case BTBGGModeNotEqual: keep = ok[t] && Cmp(now, arg[t], t) != 0; break;
			case BTBGGModeAtMost: keep = ok[t] && Cmp(now, arg[t], t) <= 0; break;
			case BTBGGModeAtLeast: keep = ok[t] && Cmp(now, arg[t], t) >= 0 && Cmp(now, arg[t], t) != 2; break;
			case BTBGGModeChanged: keep = Cmp(now, old, t) != 0; break;
			case BTBGGModeUnchanged: keep = Cmp(now, old, t) == 0; break;
			case BTBGGModeGreater: keep = Cmp(now, old, t) == 1; break;
			case BTBGGModeSmaller: keep = Cmp(now, old, t) == -1; break;
			case BTBGGModeIncreasedBy:
			case BTBGGModeDecreasedBy: {
				if (!ok[t]) break;
				double sign = mode == BTBGGModeIncreasedBy ? 1 : -1;
				if (IsFloat(t)) {
					double expected = sign * DV(arg[t], t), got = DV(now, t) - DV(old, t);
					keep = fabs(got - expected) <= MAX(1e-4, fabs(expected) * 1e-4);
				} else {
					keep = SV(now, t) - SV(old, t) == (int64_t)sign * SV(arg[t], t);
				}
				break;
			}
		}
		if (keep) { src[kept].addrType = h.addrType; src[kept].raw = now; kept++; }
	}
	_count = kept;
	if (kept > 0 && _store) {
		// give the memory of the dropped results back to the game
		uintptr_t keepEnd = ((uintptr_t)_store + kept * sizeof(BTBGGHit) + vm_page_size - 1) & ~((uintptr_t)vm_page_size - 1);
		uintptr_t storeEnd = (uintptr_t)_store + _maxHits * sizeof(BTBGGHit);
		if (keepEnd < storeEnd) madvise((void *)keepEnd, storeEnd - keepEnd, MADV_FREE_REUSABLE);
	}
	if (kept == 0) [self clearResults];
	return YES;
}

- (NSUInteger)editAll:(NSString *)text freeze:(BOOL)freeze mode:(BTBGGFreezeMode)mode typeFilter:(int)typeFilter {
	NSUInteger written = 0, frozen = 0;
	uint64_t parsed[8] = {0};
	BOOL parsedOK[8] = {NO}, tried[8] = {NO};
	for (size_t i = 0; i < _count; i++) {
		BTBGGHit h = _store[i];
		BTBGGType t = BTBGGHitType(h);
		if (typeFilter >= 0 && typeFilter != (int)t) continue;
		if (!tried[t]) { parsedOK[t] = ParseRaw(text, t, &parsed[t]); tried[t] = YES; }
		if (!parsedOK[t]) continue;
		if ([self writeValue:BTBGGHitAddress(h) type:t raw:parsed[t]]) {
			written++;
			if (freeze && frozen < kMaxFrozen) { [self freezeAddress:BTBGGHitAddress(h) type:t raw:parsed[t] mode:mode]; frozen++; }
		}
	}
	return written;
}

// MARK: Freezing

- (void)freezeAddress:(uint64_t)address type:(BTBGGType)type raw:(uint64_t)raw mode:(BTBGGFreezeMode)mode {
	BTBGGFreezeItem *item = [BTBGGFreezeItem new];
	item.type = type;
	item.raw = raw;
	item.mode = mode;
	[_freezeLock lock];
	_frozen[@(address)] = item;
	if (!_freezeTimer) {
		dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _freezeQueue);
		dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 20 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
		__weak BTBGGEngine *weakSelf = self;
		dispatch_source_set_event_handler(timer, ^{ [weakSelf freezeTick]; });
		_freezeTimer = timer;
		dispatch_resume(timer);
	}
	[_freezeLock unlock];
}

- (void)freezeTick {
	[_freezeLock lock];
	NSDictionary *snapshot = [_frozen copy];
	[_freezeLock unlock];
	[snapshot enumerateKeysAndObjectsUsingBlock:^(NSNumber *addr, BTBGGFreezeItem *item, BOOL *stop) {
		uint64_t a = addr.unsignedLongLongValue, now = 0;
		if (![self readValue:a type:item.type raw:&now]) return;
		int c = Cmp(now, item.raw, item.type);
		BOOL write = NO;
		switch (item.mode) {
			case BTBGGFreezeExact: write = item.type == BTBGGTypeXor ? (uint32_t)now != (uint32_t)item.raw : c != 0; break;
			case BTBGGFreezeAtLeast: write = c == -1; break;
			case BTBGGFreezeAtMost: write = c == 1; break;
		}
		if (write) [self writeValue:a type:item.type raw:item.raw];
	}];
}

- (void)stopTimerIfEmpty { // call with _freezeLock held
	if (_frozen.count == 0 && _freezeTimer) { dispatch_source_cancel(_freezeTimer); _freezeTimer = nil; }
}

- (void)unfreezeAddress:(uint64_t)address {
	[_freezeLock lock];
	[_frozen removeObjectForKey:@(address)];
	[self stopTimerIfEmpty];
	[_freezeLock unlock];
}

- (void)unfreezeAll {
	[_freezeLock lock];
	[_frozen removeAllObjects];
	[self stopTimerIfEmpty];
	[_freezeLock unlock];
}

- (BOOL)isFrozen:(uint64_t)address {
	[_freezeLock lock];
	BOOL r = _frozen[@(address)] != nil;
	[_freezeLock unlock];
	return r;
}

- (NSUInteger)frozenCount {
	[_freezeLock lock];
	NSUInteger n = _frozen.count;
	[_freezeLock unlock];
	return n;
}

// MARK: Saved list

static NSString *ListPath(void) {
	NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Veather/GameGuard"];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return [dir stringByAppendingPathComponent:@"list.json"];
}

- (BTBGGItem *)addToListAddress:(uint64_t)address type:(BTBGGType)type label:(NSString *)label {
	if (type == BTBGGTypeAuto) type = BTBGGTypeDword;
	for (BTBGGItem *it in _list) if (it.address == address && it.type == type) { if (label.length) it.label = label; return it; }
	BTBGGItem *item = [BTBGGItem new];
	item.address = address;
	item.type = type;
	item.label = label ?: @"";
	NSString *m = nil;
	uint64_t off = 0;
	if ([self moduleForAddress:address name:&m offset:&off]) { item.module = m; item.offset = off; }
	[_list addObject:item];
	return item;
}

- (void)removeListItems:(NSArray<BTBGGItem *> *)items {
	for (BTBGGItem *it in items) [self unfreezeAddress:it.address];
	[_list removeObjectsInArray:items];
}

- (void)clearList {
	for (BTBGGItem *it in _list) [self unfreezeAddress:it.address];
	[_list removeAllObjects];
}

- (NSArray *)persistableEntries {
	NSMutableArray *out = [NSMutableArray array];
	for (BTBGGItem *it in _list) {
		if (!it.module) continue; // heap addresses change on every launch: not worth saving
		[out addObject:@{@"label": it.label ?: @"", @"type": @(it.type), @"module": it.module, @"offset": @(it.offset)}];
	}
	return out;
}

- (void)persistList {
	NSData *data = [NSJSONSerialization dataWithJSONObject:[self persistableEntries] options:0 error:nil];
	if (data) [data writeToFile:ListPath() atomically:YES];
}

- (void)loadPersistedList {
	NSData *data = [NSData dataWithContentsOfFile:ListPath()];
	if (!data) return;
	NSArray *entries = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if ([entries isKindOfClass:[NSArray class]]) [self addEntries:entries];
}

- (NSInteger)addEntries:(NSArray *)entries {
	[self refreshImages];
	NSInteger added = 0;
	for (id e in entries) {
		if (![e isKindOfClass:[NSDictionary class]]) continue;
		NSString *module = e[@"module"];
		NSNumber *type = e[@"type"], *offset = e[@"offset"];
		if (![module isKindOfClass:[NSString class]] || !type || !offset || type.integerValue < 0 || type.integerValue > BTBGGTypeXor) continue;
		long found = -1;
		for (NSUInteger i = 0; i < _imageNames.count; i++) {
			if (![_imageNames[i].lastPathComponent isEqualToString:module]) continue;
			if (found < 0 || _imageIsApp[i].boolValue) found = (long)i;
		}
		if (found < 0) continue;
		uint64_t address = _imageBases[found].unsignedLongLongValue + offset.unsignedLongLongValue;
		NSUInteger before = _list.count;
		BTBGGItem *item = [self addToListAddress:address type:(BTBGGType)type.integerValue label:[e[@"label"] isKindOfClass:[NSString class]] ? e[@"label"] : @""];
		if (_list.count > before) { added++; (void)item; }
	}
	return added;
}

- (NSString *)listJSON {
	NSData *data = [NSJSONSerialization dataWithJSONObject:[self persistableEntries] options:NSJSONWritingPrettyPrinted error:nil];
	return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";
}

- (NSInteger)importListJSON:(NSString *)json {
	NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
	id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	if (![obj isKindOfClass:[NSArray class]]) return -1;
	NSInteger n = [self addEntries:obj];
	[self persistList];
	return n;
}

@end
