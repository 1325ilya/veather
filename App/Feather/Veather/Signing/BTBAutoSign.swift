//
//  BTBAutoSign.swift
//  Veather
//
//  "Sign right after import": a freshly imported .ipa is signed with the
//  default options and the selected certificate, then the install prompt
//  opens — import, sign and install in one go.
//

import CoreData
import SwiftUI
import UIKit

@MainActor
enum BTBAutoSign {
	nonisolated static let enabledKey = "BTB.autoSignAfterImport"

	nonisolated static var isEnabled: Bool {
		UserDefaults.standard.bool(forKey: enabledKey)
	}

	private static var _signedUUIDs: Set<String> = []

	/// Call after an import finished successfully.
	static func handleImportFinished() {
		guard isEnabled, let app = _latestImported() else { return }
		// several imports can finish close together: sign each app only once
		if let uuid = app.uuid {
			guard !_signedUUIDs.contains(uuid) else { return }
			_signedUUIDs.insert(uuid)
		}
		BTBLiveLog.log(String.localized("Auto-signing %@…", arguments: app.name ?? ""), .step)
		BTBBulkSigner.sign([app], progress: { _, _ in }) { ok, errors in
			if ok > 0 {
				UINotificationFeedbackGenerator().notificationOccurred(.success)
				NotificationCenter.default.post(name: Notification.Name("Feather.installApp"), object: nil)
			} else {
				UINotificationFeedbackGenerator().notificationOccurred(.error)
				UIAlertController.showAlertWithOk(
					title: .localized("Auto-Sign Failed"),
					message: errors.joined(separator: "\n")
				)
			}
		}
	}

	private static func _latestImported() -> Imported? {
		let request = NSFetchRequest<Imported>(entityName: "Imported")
		request.sortDescriptors = [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
		request.fetchLimit = 1
		return try? Storage.shared.context.fetch(request).first
	}
}

/// Settings row for auto-sign.
struct BTBAutoSignToggle: View {
	@AppStorage(BTBAutoSign.enabledKey) private var _enabled = false

	var body: some View {
		Toggle(isOn: $_enabled) {
			BTBRowLabel(
				.localized("Sign Right After Import"),
				systemImage: "bolt.fill",
				color: .yellow,
				subtitle: .localized("Import → sign → install prompt, in one step")
			)
		}
	}
}
