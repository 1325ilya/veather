//
//  BTBSourceResolver.swift
//  BetterThanBox
//
//  Finds the same app across all user-added sources and picks the
//  candidate with the highest version (then newest date, then source order).
//  Only sources the user added themselves are searched.
//

import Foundation
import AltSourceKit

struct BTBCandidate: Identifiable, Hashable {
	let source: AltSource
	let repository: ASRepository
	/// App with `versions` re-sorted so the newest one is first.
	let app: ASRepository.App
	
	var id: String { "\(source.identifier ?? "?")|\(app.currentUniqueId)" }
	var sourceIdentifier: String { source.identifier ?? source.sourceURL?.absoluteString ?? "" }
	var sourceName: String { repository.name ?? source.name ?? .localized("Unknown") }
	var version: String? { app.currentVersion }
	var date: Date? { app.currentDate?.date }
	
	static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
	func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct BTBResolvedApp: Identifiable {
	let key: String
	let candidates: [BTBCandidate]
	let best: BTBCandidate
	let isPinned: Bool
	
	var id: String { key }
	var name: String { best.app.currentName }
	
	var reason: String {
		if isPinned { return .localized("Chosen manually") }
		if candidates.count == 1 { return .localized("Only source") }
		return String.localized("Newest version among %lld sources", arguments: candidates.count)
	}
}

enum BTBSourceResolver {
	private static let _pinPrefix = "BTB.pinnedSource."
	
	static func pinnedSource(for key: String) -> String? {
		UserDefaults.standard.string(forKey: _pinPrefix + key)
	}
	
	static func setPinnedSource(_ identifier: String?, for key: String) {
		if let identifier {
			UserDefaults.standard.set(identifier, forKey: _pinPrefix + key)
		} else {
			UserDefaults.standard.removeObject(forKey: _pinPrefix + key)
		}
	}
	
	/// Grouping key: bundle id when present, otherwise the lowercased name.
	static func key(for app: ASRepository.App) -> String {
		if let id = app.id?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
			return id.lowercased()
		}
		return "name:" + app.currentName.lowercased()
	}
	
	static func normalized(_ app: ASRepository.App) -> ASRepository.App {
		guard let versions = app.versions, versions.count > 1 else { return app }
		var copy = app
		copy.versions = versions.sorted {
			let result = BTBVersionCompare.compare($0.version, $1.version)
			if result != .orderedSame { return result == .orderedDescending }
			return ($0.date?.date ?? .distantPast) > ($1.date?.date ?? .distantPast)
		}
		return copy
	}
	
	/// Orders candidates: newest version first, then newest date, then source name.
	static func sort(_ candidates: [BTBCandidate]) -> [BTBCandidate] {
		candidates.sorted { a, b in
			let result = BTBVersionCompare.compare(a.version, b.version)
			if result != .orderedSame { return result == .orderedDescending }
			let da = a.date ?? .distantPast, db = b.date ?? .distantPast
			if da != db { return da > db }
			return a.sourceName.localizedCaseInsensitiveCompare(b.sourceName) == .orderedAscending
		}
	}
	
	static func resolve(
		sources: [AltSource: ASRepository],
		query: String
	) -> [BTBResolvedApp] {
		let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
		var groups: [String: [BTBCandidate]] = [:]
		
		for (source, repo) in sources {
			for app in repo.apps where app.currentDownloadUrl != nil || !(app.versions?.isEmpty ?? true) {
				if !q.isEmpty {
					let matches =
						app.currentName.localizedCaseInsensitiveContains(q) ||
						(app.id?.localizedCaseInsensitiveContains(q) ?? false) ||
						(app.developer?.localizedCaseInsensitiveContains(q) ?? false)
					if !matches { continue }
				}
				let candidate = BTBCandidate(source: source, repository: repo, app: normalized(app))
				groups[key(for: app), default: []].append(candidate)
			}
		}
		
		return groups.compactMap { key, list -> BTBResolvedApp? in
			let sorted = sort(list)
			guard var best = sorted.first else { return nil }
			var pinned = false
			if
				let pin = pinnedSource(for: key),
				let pinnedCandidate = sorted.first(where: { $0.sourceIdentifier == pin })
			{
				best = pinnedCandidate
				pinned = true
			}
			return BTBResolvedApp(key: key, candidates: sorted, best: best, isPinned: pinned)
		}
		.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}
}
