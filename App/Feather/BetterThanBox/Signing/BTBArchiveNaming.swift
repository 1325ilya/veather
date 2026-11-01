//
//  BTBArchiveNaming.swift
//  BetterThanBox
//
//  Export file name template and .ipa/.tipa choice (ideas: EnSign output name
//  template + timestamp, TIPA output for TrollStore).
//

import Foundation

enum BTBArchiveNaming {
	static func fileName(name: String, version: String, bundleID: String, date: Date = Date()) -> String {
		let template = UserDefaults.standard.string(forKey: "BTB.archive.nameTemplate") ?? "{name}_{version}_{date}"
		let ext = UserDefaults.standard.string(forKey: "BTB.archive.extension") ?? "ipa"
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd_HH-mm"
		var result = template.isEmpty ? "{name}_{version}_{date}" : template
		let values: [String: String] = [
			"{name}": name,
			"{version}": version,
			"{bundle}": bundleID,
			"{date}": formatter.string(from: date),
			"{timestamp}": "\(Int(date.timeIntervalSince1970))"
		]
		for (key, value) in values {
			result = result.replacingOccurrences(of: key, with: value)
		}
		// keep the name valid for Files
		let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
		result = result.components(separatedBy: invalid).joined(separator: "-")
		if result.trimmingCharacters(in: .whitespaces).isEmpty { result = name }
		return "\(result).\(ext == "tipa" ? "tipa" : "ipa")"
	}
}
