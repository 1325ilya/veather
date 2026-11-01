//
//  BTBBulkSigner.swift
//  BetterThanBox
//
//  Bulk signing (ideas: VexSign BatchSign/InstallQueue, Ksign BulkSigning,
//  BatSign serial sign queue): signs the selected library apps one after
//  another with the default options and the selected certificate.
//

import Foundation
import UIKit

@MainActor
enum BTBBulkSigner {
	static func sign(_ apps: [AppInfoPresentable], progress: @escaping (Int, Int) -> Void, completion: @escaping (_ ok: Int, _ errors: [String]) -> Void) {
		let options = OptionsManager.shared.options
		let certIndex = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		let certificate = Storage.shared.getCertificate(for: certIndex)
		
		guard certificate != nil || options.signingOption != .default else {
			completion(0, [String.localized("Please go to settings and import a valid certificate")])
			return
		}
		
		Task { @MainActor in
			var ok = 0
			var errors: [String] = []
			for (index, app) in apps.enumerated() {
				progress(index + 1, apps.count)
				var appOptions = options
				// keep PPQ protection behaviour of the single-app flow
				if options.ppqProtection, let id = app.identifier, certificate?.ppQCheck == true {
					appOptions.appIdentifier = "\(id).\(options.ppqString)"
				}
				let error: Error? = await withCheckedContinuation { continuation in
					FR.signPackageFile(app, using: appOptions, icon: nil, certificate: certificate) {
						continuation.resume(returning: $0)
					}
				}
				if let error {
					errors.append("\(app.name ?? "?"): \(error.localizedDescription)")
				} else {
					ok += 1
				}
			}
			completion(ok, errors)
		}
	}
}
