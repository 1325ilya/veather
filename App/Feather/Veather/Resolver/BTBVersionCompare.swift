//
//  BTBVersionCompare.swift
//  Veather
//
//  Compares app version strings by numeric segments ("1.10.2" > "1.9.9").
//  Non-numeric suffixes ("1.2b3") are compared after the numeric part.
//

import Foundation

enum BTBVersionCompare {
	/// Returns `.orderedAscending` when `lhs` < `rhs`.
	static func compare(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
		switch (lhs, rhs) {
		case (nil, nil): return .orderedSame
		case (nil, _): return .orderedAscending
		case (_, nil): return .orderedDescending
		case let (l?, r?): return compare(l, r)
		}
	}
	
	static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
		let l = _segments(lhs)
		let r = _segments(rhs)
		let count = max(l.count, r.count)
		
		for i in 0..<count {
			let a = i < l.count ? l[i] : .number(0)
			let b = i < r.count ? r[i] : .number(0)
			let result = a.compare(b)
			if result != .orderedSame { return result }
		}
		return .orderedSame
	}
	
	static func isNewer(_ lhs: String?, than rhs: String?) -> Bool {
		compare(lhs, rhs) == .orderedDescending
	}
	
	private enum Segment {
		case number(Int)
		case text(String)
		
		func compare(_ other: Segment) -> ComparisonResult {
			switch (self, other) {
			case let (.number(a), .number(b)):
				return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
			// "1.0" (release) is newer than "1.0-beta"
			case (.number, .text): return .orderedDescending
			case (.text, .number): return .orderedAscending
			case let (.text(a), .text(b)):
				return a.compare(b, options: [.caseInsensitive, .numeric])
			}
		}
	}
	
	private static func _segments(_ version: String) -> [Segment] {
		var result: [Segment] = []
		let trimmed = version
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
		
		for part in trimmed.split(whereSeparator: { ".-_ +()".contains($0) }) {
			let digits = part.prefix(while: { $0.isNumber })
			let rest = part.dropFirst(digits.count)
			if let number = Int(digits) {
				result.append(.number(number))
			}
			if !rest.isEmpty {
				result.append(.text(String(rest)))
			}
		}
		// drop trailing zeroes so "1.0" == "1"
		while case .number(0)? = result.last, result.count > 1 {
			result.removeLast()
		}
		return result
	}
}
