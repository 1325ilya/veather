//
//  BTBUpdateRules.swift
//  BetterThanBox
//
//  Per-app update rules (idea: VexSign PerAppUpdateRules):
//  skip a specific version, search updates in all sources or only the origin.
//

import Foundation

enum BTBUpdateRules {
	static let allSourcesKey = "BTB.updates.allSources"
	private static let _ignorePrefix = "BTB.updates.ignored."
	
	static func isIgnored(bundleID: String, version: String) -> Bool {
		UserDefaults.standard.string(forKey: _ignorePrefix + bundleID.lowercased()) == version
	}
	
	static func ignore(bundleID: String, version: String?) {
		let key = _ignorePrefix + bundleID.lowercased()
		if let version {
			UserDefaults.standard.set(version, forKey: key)
		} else {
			UserDefaults.standard.removeObject(forKey: key)
		}
	}
}
