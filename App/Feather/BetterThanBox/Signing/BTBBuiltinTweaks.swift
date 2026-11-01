//
//  BTBBuiltinTweaks.swift
//  BetterThanBox
//
//  Built-in tweaks (replacing the Telegram bot commands). All live in one
//  dylib (App/Tweaks, built by CI) and are switched on via Info.plist
//  `BTBEnabledTweaks`, so several can be combined in one app.
//

import Foundation
import Zsign
import OSLog

enum BTBBuiltinTweak: String, CaseIterable, Codable, Identifiable {
	case noads
	case sideload
	case nowifi
	case backup
	case norev
	case ipadui
	case noupd

	var id: String { rawValue }

	var title: String {
		switch self {
		case .noads: .localized("No Ads")
		case .sideload: .localized("Sideload Fixes")
		case .nowifi: .localized("Network Blocker")
		case .backup: .localized("Data Manager")
		case .norev: .localized("No Rate Prompts")
		case .ipadui: .localized("iPad Interface")
		case .noupd: .localized("Bypass Update Checks")
		}
	}

	var subtitle: String {
		switch self {
		case .noads: .localized("Blocks ad networks and popular ad SDKs (AdMob, AppLovin, Unity, Meta, ironSource).")
		case .sideload: .localized("Fixes keychain and app group errors after re-signing with another team.")
		case .nowifi: .localized("The app gets no internet access at all.")
		case .backup: .localized("Three-finger long press inside the app: back up or restore its data to Files.")
		case .norev: .localized("Suppresses \"Rate this app\" dialogs.")
		case .ipadui: .localized("Forces the iPad layout on iPhone.")
		case .noupd: .localized("Answers App Store version checks with \"no update\" so the app stops nagging.")
		}
	}

	var systemImage: String {
		switch self {
		case .noads: "nosign"
		case .sideload: "wrench.and.screwdriver"
		case .nowifi: "wifi.slash"
		case .backup: "externaldrive.badge.timemachine"
		case .norev: "star.slash"
		case .ipadui: "ipad"
		case .noupd: "arrow.down.app"
		}
	}

	static var dylibURL: URL? {
		Bundle.main.url(forResource: "BTBTweaks", withExtension: "btbtweak")
	}

	static var isAvailable: Bool { dylibURL != nil }

	static let dylibName = "BTBTweaks.dylib"

	/// Copies the dylib into the app, adds the load command and writes the feature list.
	static func inject(_ tweaks: [String], into app: URL) throws {
		let enabled = tweaks.compactMap(BTBBuiltinTweak.init(rawValue:))
		guard !enabled.isEmpty else { return }
		guard let source = dylibURL else {
			Logger.signing.error("BTBTweaks dylib missing from the app bundle")
			return
		}
		guard let executable = Bundle(url: app)?.executableURL else {
			throw SigningFileHandlerError.appNotFound
		}

		let fm = FileManager.default
		let frameworks = app.appendingPathComponent("Frameworks")
		try fm.createDirectoryIfNeeded(at: frameworks)
		let destination = frameworks.appendingPathComponent(dylibName)
		try fm.removeFileIfNeeded(at: destination)
		try fm.copyItem(at: source, to: destination)

		let loadPath = "@executable_path/Frameworks/\(dylibName)"
		if !Zsign.listDylibs(appExecutable: executable.path).contains(loadPath) {
			_ = Zsign.injectDyLib(appExecutable: executable.path, with: loadPath, weak: true)
		}

		let infoURL = app.appendingPathComponent("Info.plist")
		if let info = NSMutableDictionary(contentsOf: infoURL) {
			info["BTBEnabledTweaks"] = enabled.map(\.rawValue)
			if enabled.contains(.ipadui) {
				info["UIDeviceFamily"] = [1, 2]
			}
			info.write(to: infoURL, atomically: true)
		}
		Logger.signing.info("Injected built-in tweaks: \(enabled.map(\.rawValue).joined(separator: ","), privacy: .public)")
	}
}
