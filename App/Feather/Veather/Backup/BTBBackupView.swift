//
//  BTBBackupView.swift
//  Veather
//

import SwiftUI
import UniformTypeIdentifiers
import NimbleViews

struct BTBBackupView: View {
	@State private var _password = ""
	@State private var _restorePassword = ""
	@State private var _isWorking = false
	@State private var _isImporting = false
	@State private var _status: String?

	var body: some View {
		List {
			NBSection(.localized("Back Up")) {
				SecureField(.localized("Password (recommended)"), text: $_password)
					.textContentType(.newPassword)
				Button {
					_export()
				} label: {
					Label(.localized("Create Backup"), systemImage: "externaldrive.badge.plus")
				}
				.disabled(_isWorking)
			} footer: {
				Text(.localized("Saves certificates with their passwords, sources and settings into one .btbbackup file. Store it in Files or iCloud Drive to restore after reinstalling. Use a password: the file contains your certificates."))
			}

			NBSection(.localized("Restore")) {
				SecureField(.localized("Backup password"), text: $_restorePassword)
				Button {
					_isImporting = true
				} label: {
					Label(.localized("Restore from File"), systemImage: "arrow.counterclockwise.circle")
				}
				.disabled(_isWorking)
			} footer: {
				Text(.localized("Certificates and sources are added to the existing ones; nothing is deleted."))
			}

			if _isWorking {
				Section { ProgressView() }
			}
			if let _status {
				Section { Text(_status).font(.footnote) }
			}
		}
		.navigationTitle(.localized("Backup & Restore"))
		.fileImporter(isPresented: $_isImporting, allowedContentTypes: [.data, .zip]) { result in
			if case .success(let url) = result { _restore(url) }
		}
	}

	private func _export() {
		_isWorking = true
		let password = _password
		DispatchQueue.global(qos: .userInitiated).async {
			let result = Result { try BTBBackupManager.export(password: password) }
			DispatchQueue.main.async {
				_isWorking = false
				switch result {
				case .success(let url):
					_status = nil
					let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
					UIApplication.topViewController()?.present(picker, animated: true)
				case .failure(let error):
					_status = error.localizedDescription
				}
			}
		}
	}

	private func _restore(_ url: URL) {
		_isWorking = true
		let password = _restorePassword
		Task {
			do {
				let result = try await BTBBackupManager.restore(from: url, password: password)
				_status = String.localized(
					"Restored: %lld certificates, %lld sources%@.",
					arguments: result.certificates, result.sources,
					result.settings ? String.localized(", settings") : ""
				)
			} catch {
				_status = error.localizedDescription
			}
			_isWorking = false
		}
	}
}
