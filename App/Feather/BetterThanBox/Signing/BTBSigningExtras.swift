//
//  BTBSigningExtras.swift
//  BetterThanBox
//
//  Extra bundle modifications applied before signing
//  (ideas from zsign -E/-W, Sideloadly, EnSign, VexSign).
//

import Foundation
import OSLog

enum BTBSigningExtras {
	static func apply(to app: URL, options: Options) throws {
		let fm = FileManager.default
		
		if options.btb_removeExtensions {
			for name in ["PlugIns", "Extensions"] {
				let url = app.appendingPathComponent(name)
				if fm.fileExists(atPath: url.path) {
					try fm.removeItem(at: url)
					Logger.signing.info("Removed \(name, privacy: .public)")
				}
			}
		}
		
		if options.btb_removeWatchApp {
			for name in ["Watch", "com.apple.WatchPlaceholder"] {
				let url = app.appendingPathComponent(name)
				if fm.fileExists(atPath: url.path) {
					try fm.removeItem(at: url)
					Logger.signing.info("Removed \(name, privacy: .public)")
				}
			}
		}
		
		let infoURL = app.appendingPathComponent("Info.plist")
		if
			options.btb_removeDeviceRestrictions || options.btb_fixIcons,
			let info = NSMutableDictionary(contentsOf: infoURL)
		{
			if options.btb_removeDeviceRestrictions {
				info.removeObject(forKey: "UIRequiredDeviceCapabilities")
				info.removeObject(forKey: "UISupportedDevices")
				// allow the app on both iPhone and iPad
				info["UIDeviceFamily"] = [1, 2]
			}
			if options.btb_fixIcons {
				for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
					guard
						let icons = (info[key] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary,
						let primary = (icons["CFBundlePrimaryIcon"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary
					else { continue }
					primary["UIPrerenderedIcon"] = true
					icons["CFBundlePrimaryIcon"] = primary
					info[key] = icons
				}
				info["UIPrerenderedIcon"] = true
			}
			info.write(to: infoURL, atomically: true)
		}
		
		if !options.btb_builtinTweaks.isEmpty {
			try BTBBuiltinTweak.inject(options.btb_builtinTweaks, into: app)
		}

		if options.btb_thinToArm64 {
			var thinned = 0
			for url in machOFiles(in: app) {
				if (try? BTBMachOThinner.thinToArm64(url)) == true { thinned += 1 }
			}
			Logger.signing.info("Thinned \(thinned) Mach-O files to arm64")
		}
	}
	
	/// Executables of the app, its extensions and frameworks, plus loose dylibs.
	static func machOFiles(in app: URL) -> [URL] {
		var result: [URL] = []
		let fm = FileManager.default
		guard let e = fm.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
		for case let url as URL in e {
			let ext = url.pathExtension
			if ext == "dylib" {
				result.append(url)
			} else if ["app", "appex", "framework"].contains(ext), let exec = Bundle(url: url)?.executableURL {
				result.append(exec)
			}
		}
		if let exec = Bundle(url: app)?.executableURL { result.append(exec) }
		return Array(Set(result.map { $0.standardizedFileURL }))
	}
}

/// Minimal fat-binary thinner: keeps the arm64 slice of a universal Mach-O.
enum BTBMachOThinner {
	private static let FAT_MAGIC: UInt32 = 0xcafebabe
	private static let FAT_MAGIC_64: UInt32 = 0xcafebabf
	private static let CPU_TYPE_ARM64: UInt32 = 0x0100000c
	private static let CPU_SUBTYPE_MASK: UInt32 = 0x00ffffff
	
	/// Returns true when the file was rewritten.
	static func thinToArm64(_ url: URL) throws -> Bool {
		let data = try Data(contentsOf: url, options: .mappedIfSafe)
		guard data.count >= 8 else { return false }
		
		func be32(_ offset: Int) -> UInt32 {
			data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
		}
		func be64(_ offset: Int) -> UInt64 {
			data.subdata(in: offset..<offset + 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.bigEndian
		}
		
		let magic = be32(0)
		guard magic == FAT_MAGIC || magic == FAT_MAGIC_64 else { return false }
		let is64 = magic == FAT_MAGIC_64
		let count = Int(be32(4))
		guard count > 1, count < 32 else { return false }
		
		let archSize = is64 ? 32 : 20
		var chosen: (offset: Int, size: Int)?
		for i in 0..<count {
			let base = 8 + i * archSize
			guard base + archSize <= data.count else { return false }
			let cpuType = be32(base)
			let cpuSubtype = be32(base + 4) & CPU_SUBTYPE_MASK
			let offset = is64 ? Int(be64(base + 8)) : Int(be32(base + 8))
			let size = is64 ? Int(be64(base + 16)) : Int(be32(base + 12))
			// plain arm64 (subtype 0 = ALL) runs on every 64-bit device
			if cpuType == CPU_TYPE_ARM64 && cpuSubtype == 0 {
				chosen = (offset, size)
			}
		}
		
		guard let slice = chosen, slice.offset + slice.size <= data.count else { return false }
		let thin = data.subdata(in: slice.offset..<slice.offset + slice.size)
		let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
		try thin.write(to: url, options: .atomic)
		if let permissions = attributes?[.posixPermissions] {
			try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
		}
		return true
	}
}
