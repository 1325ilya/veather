//
//  BTBFavorites.swift
//  BetterThanBox
//
//  Favorites for Discovery (idea: VexSign Discovery favorites). Stores the
//  grouping keys (bundle id / name) the user starred.
//

import Foundation

enum BTBFavorites {
	private static let _key = "BTB.favorites"

	static func all() -> Set<String> {
		Set(UserDefaults.standard.stringArray(forKey: _key) ?? [])
	}

	static func contains(_ key: String) -> Bool {
		all().contains(key)
	}

	static func toggle(_ key: String) {
		var set = all()
		if set.contains(key) { set.remove(key) } else { set.insert(key) }
		UserDefaults.standard.set(Array(set), forKey: _key)
	}
}
