//
//  BTBGGSharedScripts.swift
//  Veather
//
//  The folder of GameGuardian scripts that every game gets ("Shared" in the panel's Scripts tab).
//  It has two sub-folders: GG (scripts that use the gg.* API) and Lua (plain Lua).
//  By default it is Documents/GameGuardian/Scripts, which is visible in the Files app
//  (Veather exposes its Documents). The user can pick another folder in Settings.
//  The scripts are copied into the game when Veather signs it, so a game sees them read-only.
//

import Foundation

enum BTBGGSharedScripts {
	static let bookmarkKey = "BTB.GG.SharedFolderBookmark"
	static let subfolders = ["GG", "Lua"]

	static var defaultFolder: URL {
		FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("GameGuardian", isDirectory: true)
			.appendingPathComponent("Scripts", isDirectory: true)
	}

	/// The folder picked in Settings (nil: the default one is used).
	static var chosenFolder: URL? {
		guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
		var stale = false
		guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
		if stale, url.startAccessingSecurityScopedResource() {
			defer { url.stopAccessingSecurityScopedResource() }
			if let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
		}
		return url
	}

	static var folder: URL { chosenFolder ?? defaultFolder }

	static func choose(_ url: URL) throws {
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }
		let data = try url.bookmarkData()
		UserDefaults.standard.set(data, forKey: bookmarkKey)
		prepare(url)
	}

	static func useDefault() {
		UserDefaults.standard.removeObject(forKey: bookmarkKey)
		prepare(defaultFolder)
	}

	/// Creates the GG and Lua folders (and an example in a brand new default folder).
	static func prepare(_ root: URL? = nil) {
		let fm = FileManager.default
		let base = root ?? folder
		let scoped = base.startAccessingSecurityScopedResource()
		defer { if scoped { base.stopAccessingSecurityScopedResource() } }
		for name in subfolders {
			try? fm.createDirectory(at: base.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
		}
		let gg = base.appendingPathComponent("GG", isDirectory: true)
		if base.standardizedFileURL.path == defaultFolder.standardizedFileURL.path,
		   (try? fm.contentsOfDirectory(atPath: gg.path))?.isEmpty ?? true {
			let example = """
			-- \(String.localized("Example of a shared script: it is available in every game."))
			-- \(String.localized("It asks for a number, searches for it and shows how many places hold it. It changes nothing."))
			local r = gg.prompt({"Number to look for"}, {""}, {"number"})
			if not r then return end
			gg.setRanges(gg.REGION_ANONYMOUS | gg.REGION_C_ALLOC | gg.REGION_C_DATA)
			gg.searchNumber(r[1], gg.TYPE_DWORD)
			gg.alert("Found: " .. gg.getResultCount())
			gg.clearResults()

			"""
			try? example.write(to: gg.appendingPathComponent("example.lua"), atomically: true, encoding: .utf8)
		}
	}

	private static func isScript(_ url: URL) -> Bool {
		["lua", "txt"].contains(url.pathExtension.lowercased())
	}

	/// Number of scripts in the folder (both kinds, nested ones too).
	static func scriptCount() -> Int {
		let fm = FileManager.default
		let base = folder
		let scoped = base.startAccessingSecurityScopedResource()
		defer { if scoped { base.stopAccessingSecurityScopedResource() } }
		var count = 0
		for name in subfolders {
			let dir = base.appendingPathComponent(name, isDirectory: true)
			guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
			for case let url as URL in en where isScript(url) { count += 1 }
		}
		return count
	}

	/// Copies the shared scripts into the app bundle (app/BTBGGShared/{GG,Lua}).
	static func copy(into app: URL) {
		let fm = FileManager.default
		let base = folder
		let scoped = base.startAccessingSecurityScopedResource()
		defer { if scoped { base.stopAccessingSecurityScopedResource() } }
		let target = app.appendingPathComponent("BTBGGShared", isDirectory: true)
		try? fm.removeItem(at: target)
		var copied = 0
		for name in subfolders {
			let source = base.appendingPathComponent(name, isDirectory: true)
			let dest = target.appendingPathComponent(name, isDirectory: true)
			try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
			guard let en = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
			let prefix = source.standardizedFileURL.path
			for case let url as URL in en {
				let full = url.standardizedFileURL.path
				guard full.hasPrefix(prefix) else { continue }
				let relative = String(full.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
				guard !relative.isEmpty else { continue }
				let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
				let out = dest.appendingPathComponent(relative)
				if isDir {
					try? fm.createDirectory(at: out, withIntermediateDirectories: true)
				} else if isScript(url) {
					try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
					if (try? fm.copyItem(at: url, to: out)) != nil { copied += 1 }
				}
			}
		}
		BTBLiveLog.log("GameGuardian: \(copied) shared script(s) added", .step)
	}
}
