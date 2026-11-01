//
//  BTBKeychainIsolation.swift
//  BetterThanBox
//
//  Keychain isolation (idea: EnSign): with a wildcard profile every signed app
//  gets `TEAMID.*` and can read the keychain items of the others. This writes
//  an entitlements file whose keychain group is only `TEAMID.<bundle id>`.
//

import Foundation

enum BTBKeychainIsolation {
	/// Returns a temporary entitlements file, or nil when no profile is available.
	static func entitlementsFile(
		certificate: CertificatePair?,
		bundleID: String,
		existing: URL?,
		workDir: URL
	) throws -> URL? {
		var base: [String: Any]
		if
			let existing,
			let data = try? Data(contentsOf: existing),
			let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
		{
			base = dict
		} else if
			let cert = certificate,
			let decoded = Storage.shared.getProvisionFileDecoded(for: cert)
		{
			base = (decoded.Entitlements ?? [:]).mapValues { $0.value }
		} else {
			return nil
		}
		
		guard let team = (base["com.apple.developer.team-identifier"] as? String)
			?? (base["application-identifier"] as? String)?.components(separatedBy: ".").first
		else { return nil }
		
		base["application-identifier"] = "\(team).\(bundleID)"
		base["keychain-access-groups"] = ["\(team).\(bundleID)"]
		
		let url = workDir.appendingPathComponent("BTBKeychain_\(UUID().uuidString).plist")
		try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
		let data = try PropertyListSerialization.data(fromPropertyList: base, format: .xml, options: 0)
		try data.write(to: url, options: .atomic)
		return url
	}
}
