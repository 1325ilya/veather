//
//  BTBVerifySignature.swift
//  Veather
//
//  Signature / integrity check of a library app (idea: VexSign SignatureVerifier):
//  reports whether the main binary carries a code signature.
//

import Foundation
import UIKit
import Zsign

enum BTBVerifySignature {
	static func run(for app: AppInfoPresentable) {
		guard
			let dir = Storage.shared.getAppDirectory(for: app),
			let exec = Bundle(url: dir)?.executableURL
		else {
			UIAlertController.showAlertWithOk(title: .localized("Verify Signature"), message: .localized("Executable not found"))
			return
		}
		let signed = Zsign.checkSigned(appExecutable: exec.path)
		let cert = Storage.shared.getCertificate(from: app)
		var lines = [signed ? String.localized("The binary is code-signed.") : String.localized("The binary has no code signature.")]
		if let cert {
			lines.append(cert.revoked
				? String.localized("Certificate revoked: %@", arguments: cert.nickname ?? "?")
				: String.localized("Signed with: %@", arguments: cert.nickname ?? "?"))
		}
		UIAlertController.showAlertWithOk(title: .localized("Verify Signature"), message: lines.joined(separator: "\n"))
	}
}

// Veather build 1793541783
