//
//  BTBStorageManager.swift
//  BetterThanBox
//
//  Storage accounting and cleanup without reinstalling the app.
//  Certificates, the database, settings and sources are a protected set:
//  `remove(_:)` refuses to delete anything inside them.
//

import Foundation
import CoreData
import Nuke
import OSLog

enum BTBStorageCategory: String, CaseIterable, Identifiable {
	case imported
	case signed
	case archives
	case temporary
	case networkCache
	case other
	
	var id: String { rawValue }
	
	var title: String {
		switch self {
		case .imported: .localized("Imported Apps")
		case .signed: .localized("Signed Apps")
		case .archives: .localized("Exported IPAs")
		case .temporary: .localized("Temporary Files")
		case .networkCache: .localized("Icon & Network Cache")
		case .other: .localized("Other Files")
		}
	}
	
	var systemImage: String {
		switch self {
		case .imported: "square.and.arrow.down"
		case .signed: "signature"
		case .archives: "archivebox"
		case .temporary: "clock.arrow.circlepath"
		case .networkCache: "photo.stack"
		case .other: "doc.questionmark"
		}
	}
	
	var footer: String {
		switch self {
		case .imported: .localized("Unsigned apps you downloaded or imported. Library entries are removed too.")
		case .signed: .localized("Signed copies of apps. Library entries are removed too.")
		case .archives: .localized("IPA files exported from the library.")
		case .temporary: .localized("Leftovers from signing, unpacking and downloads.")
		case .networkCache: .localized("Cached icons, screenshots and source responses. Rebuilt automatically.")
		case .other: .localized("Files in Documents that do not belong to any category (for example Inbox).")
		}
	}
}

struct BTBStorageItem: Identifiable, Hashable {
	let url: URL
	let name: String
	let size: Int64
	let modified: Date?
	var id: URL { url }
}

final class BTBStorageManager {
	static let shared = BTBStorageManager()
	private let _fm = FileManager.default
	
	// MARK: Protected set
	
	/// Folders and files the cleaner must never touch.
	var protectedRoots: [URL] {
		var roots: [URL] = [
			_fm.certificates,
			URL.applicationSupportDirectory, // Core Data store (sources, certificates, library)
			URL.libraryDirectory.appendingPathComponent("Preferences") // settings
		]
		if let bundle = Bundle.main.resourceURL { roots.append(bundle) }
		return roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
	}
	
	func isProtected(_ url: URL) -> Bool {
		let path = url.standardizedFileURL.resolvingSymlinksInPath().path
		for root in protectedRoots {
			let rootPath = root.path
			if path == rootPath || path.hasPrefix(rootPath + "/") { return true }
			// never delete a parent of a protected folder either
			if rootPath.hasPrefix(path + "/") { return true }
		}
		return false
	}
	
	enum CleanError: LocalizedError {
		case protectedItem(String)
		var errorDescription: String? {
			switch self {
			case .protectedItem(let name): .localized("\"%@\" is protected and was not deleted.", arguments: name)
			}
		}
	}
	
	/// The only deletion entry point for the storage screen.
	func remove(_ url: URL) throws {
		guard !isProtected(url) else {
			Logger.misc.warning("Refusing to delete protected item: \(url.path)")
			throw CleanError.protectedItem(url.lastPathComponent)
		}
		if _fm.fileExists(atPath: url.path) {
			try _fm.removeItem(at: url)
		}
	}
	
	// MARK: Locations
	
	func directory(for category: BTBStorageCategory) -> URL? {
		switch category {
		case .imported: _fm.unsigned
		case .signed: _fm.signed
		case .archives: _fm.archives
		case .temporary: _fm.temporaryDirectory
		case .networkCache, .other: nil
		}
	}
	
	// MARK: Sizes
	
	func size(of url: URL) -> Int64 {
		var isDir: ObjCBool = false
		guard _fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
		if !isDir.boolValue {
			return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
		}
		var total: Int64 = 0
		let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
		if let e = _fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: nil) {
			for case let file as URL in e {
				let values = try? file.resourceValues(forKeys: Set(keys))
				if values?.isRegularFile == true {
					total += Int64(values?.totalFileAllocatedSize ?? 0)
				}
			}
		}
		return total
	}
	
	func size(of category: BTBStorageCategory) -> Int64 {
		switch category {
		case .networkCache:
			var total = Int64(URLCache.shared.currentDiskUsage)
			if let cache = ImagePipeline.shared.configuration.dataCache as? DataCache {
				total += Int64(cache.totalSize)
			}
			return total
		case .other:
			return items(in: .other).reduce(0) { $0 + $1.size }
		default:
			guard let dir = directory(for: category) else { return 0 }
			return size(of: dir)
		}
	}
	
	func items(in category: BTBStorageCategory) -> [BTBStorageItem] {
		let urls: [URL]
		switch category {
		case .networkCache:
			return []
		case .other:
			let known: Set<String> = [
				_fm.unsigned, _fm.signed, _fm.archives, _fm.certificates, BTBTweakVault.directory
			].map { $0.standardizedFileURL.path }.reduce(into: []) { $0.insert($1) }
			let docs = (try? _fm.contentsOfDirectory(at: URL.documentsDirectory, includingPropertiesForKeys: nil)) ?? []
			urls = docs.filter { !known.contains($0.standardizedFileURL.path) && !isProtected($0) }
		default:
			guard let dir = directory(for: category) else { return [] }
			urls = (try? _fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
		}
		
		return urls.map { url in
			BTBStorageItem(
				url: url,
				name: _displayName(for: url, in: category),
				size: size(of: url),
				modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
			)
		}
		.sorted { $0.size > $1.size }
	}
	
	/// For app folders (named by UUID) show the app name stored in the library.
	private func _displayName(for url: URL, in category: BTBStorageCategory) -> String {
		guard category == .imported || category == .signed else { return url.lastPathComponent }
		if
			let app = _fm.getPath(in: url, for: "app"),
			let bundle = Bundle(url: app)
		{
			return "\(bundle.name) (\(bundle.version))"
		}
		return url.lastPathComponent
	}
	
	// MARK: Cleaning
	
	/// Removes a single item. Library apps are removed through the database
	/// so that no orphan entries stay in the Library tab.
	func clean(_ item: BTBStorageItem, in category: BTBStorageCategory) throws {
		if category == .imported || category == .signed {
			let uuid = item.url.lastPathComponent
			if let app = _libraryApp(uuid: uuid, signed: category == .signed) {
				Storage.shared.deleteApp(for: app)
				return
			}
		}
		try remove(item.url)
	}
	
	func clean(_ category: BTBStorageCategory) {
		switch category {
		case .imported: ResetView.deleteImportedApps()
		case .signed: ResetView.deleteSignedApps()
		case .networkCache: ResetView.clearNetworkCache()
		case .temporary, .archives, .other:
			for item in items(in: category) {
				try? remove(item.url)
			}
		}
	}
	
	private func _libraryApp(uuid: String, signed: Bool) -> AppInfoPresentable? {
		let context = Storage.shared.context
		if signed {
			let request: NSFetchRequest<Signed> = Signed.fetchRequest()
			request.predicate = NSPredicate(format: "uuid == %@", uuid)
			return (try? context.fetch(request))?.first
		} else {
			let request: NSFetchRequest<Imported> = Imported.fetchRequest()
			request.predicate = NSPredicate(format: "uuid == %@", uuid)
			return (try? context.fetch(request))?.first
		}
	}
	
	// MARK: Auto clean rules
	
	static let autoCleanArchivesDaysKey = "BTB.autoClean.archivesDays"
	static let sizeLimitKey = "BTB.autoClean.sizeLimitMB"
	
	/// Runs the user's auto-clean rules. Called on launch.
	func runAutoCleanRules() {
		let defaults = UserDefaults.standard
		
		let days = defaults.integer(forKey: Self.autoCleanArchivesDaysKey)
		if days > 0 {
			let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
			for item in items(in: .archives) where (item.modified ?? .distantPast) < cutoff {
				try? remove(item.url)
			}
		}
		
		let limitMB = defaults.integer(forKey: Self.sizeLimitKey)
		if limitMB > 0 {
			let limit = Int64(limitMB) * 1024 * 1024
			// oldest exported IPAs and temporary files go first; library apps are never auto-deleted
			var candidates = items(in: .temporary) + items(in: .archives)
			candidates.sort { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
			var total = BTBStorageCategory.allCases.reduce(Int64(0)) { $0 + size(of: $1) }
			for item in candidates where total > limit {
				if (try? remove(item.url)) != nil { total -= item.size }
			}
		}
	}
}
