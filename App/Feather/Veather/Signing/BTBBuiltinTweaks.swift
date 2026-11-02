//
//  BTBBuiltinTweaks.swift
//  Veather
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
	case gameguard

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
		case .gameguard: .localized("GameGuardian")
		}
	}

	var subtitle: String {
		switch self {
		case .noads: .localized("Blocks ads in apps and web views (AdMob, AppLovin, Unity, ironSource, Meta, Yandex, VK…). Ads fail to load, so the app never waits for one.")
		case .sideload: .localized("Fixes keychain and app group errors after re-signing, and shows the app its original bundle ID.")
		case .nowifi: .localized("The app gets no internet access at all, including web views and game engines.")
		case .backup: .localized("Hold three fingers on the screen inside the app: back up or restore its data and settings to Files.")
		case .norev: .localized("Suppresses \"Rate this app\" dialogs.")
		case .ipadui: .localized("Forces the iPad layout on iPhone; menus no longer crash the app.")
		case .noupd: .localized("Answers App Store version checks with \"no update\" so the app stops nagging.")
		case .gameguard: .localized("Memory editor for offline games: hold four fingers on the screen, search a value (coins, lives), change or freeze it. Offline games only.")
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
		case .gameguard: "gamecontroller.fill"
		}
	}

	/// Tweaks that need the user to read and confirm a warning before they are switched on.
	var warning: String? {
		switch self {
		case .gameguard:
			.localized("Use GameGuardian only in offline, single-player games. In online games it can get your account banned, and it breaks the game for other players. You are responsible for how you use it.")
		default:
			nil
		}
	}

	static var dylibURL: URL? {
		Bundle.main.url(forResource: "BTBTweaks", withExtension: "btbtweak")
	}

	static var isAvailable: Bool { dylibURL != nil }

	static let dylibName = "BTBTweaks.dylib"

	/// Copies the dylib into the app, adds the load command and writes the feature list.
	/// For Sideload Fixes: remember the bundle ID the app had before signing, so the
	/// tweak can show it to the app's own code. An ID recorded by an earlier signing wins.
	static func recordOriginalBundleID(_ original: String?, in app: URL, tweaks: [String]) {
		guard tweaks.contains(BTBBuiltinTweak.sideload.rawValue), let original, !original.isEmpty else { return }
		let infoURL = app.appendingPathComponent("Info.plist")
		guard let info = NSMutableDictionary(contentsOf: infoURL) else { return }
		if let existing = info["BTBOriginalBundleID"] as? String, !existing.isEmpty { return }
		// recorded even when unchanged here: zsign may still switch the ID to match the
		// provisioning profile; the tweak only acts when the IDs really differ
		info["BTBOriginalBundleID"] = original
		info.write(to: infoURL, atomically: true)
		BTBLiveLog.log("Sideload Fixes: app code will see bundle ID \(original)", .step)
	}
	
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
		BTBLiveLog.log("Built-in tweaks: \(enabled.map(\.title).joined(separator: ", "))", .step)
	}
}
