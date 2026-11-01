//
//  BTBIntents.swift
//  BetterThanBox
//
//  Shortcuts / Siri actions (idea: BatSign SignIntents).
//

import AppIntents
import Foundation

struct BTBCheckCertificatesIntent: AppIntent {
	static var title: LocalizedStringResource = "Check Certificates"
	static var description = IntentDescription("Re-checks every certificate for revocation and reports how many are healthy.")
	
	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
		let certs = Storage.shared.getAllCertificates()
		var valid = 0, revoked = 0, expired = 0, unknown = 0
		for cert in certs {
			if let exp = cert.expiration, exp < Date() { expired += 1; continue }
			let status: BTBCertStatus = await withCheckedContinuation { continuation in
				BTBCertHealth.check(cert) { continuation.resume(returning: $0) }
			}
			switch status {
			case .valid: valid += 1
			case .revoked: revoked += 1
			default: unknown += 1
			}
		}
		let summary = String.localized(
			"Certificates: %lld valid, %lld revoked, %lld expired, %lld not checked.",
			arguments: valid, revoked, expired, unknown
		)
		return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
	}
}

struct BTBCleanStorageIntent: AppIntent {
	static var title: LocalizedStringResource = "Clean Temporary Files"
	static var description = IntentDescription("Deletes temporary files and the icon cache. Certificates, sources and apps are kept.")
	
	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let manager = BTBStorageManager.shared
		let before = manager.size(of: .temporary) + manager.size(of: .networkCache)
		manager.clean(.temporary)
		manager.clean(.networkCache)
		let summary = String.localized("Freed %@.", arguments: btbFormatBytes(before))
		return .result(dialog: IntentDialog(stringLiteral: summary))
	}
}

struct BTBOpenAppIntent: AppIntent {
	static var title: LocalizedStringResource = "Open BetterThanBox"
	static var openAppWhenRun: Bool = true
	
	func perform() async throws -> some IntentResult { .result() }
}

struct BTBShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: BTBCheckCertificatesIntent(),
			phrases: ["Check certificates in \(.applicationName)"]
		)
		AppShortcut(
			intent: BTBCleanStorageIntent(),
			phrases: ["Clean \(.applicationName)"]
		)
	}
}
