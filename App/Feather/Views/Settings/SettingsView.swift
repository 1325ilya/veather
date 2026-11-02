//
//  SettingsView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import NimbleViews
import UIKit
import Darwin
import IDeviceSwift

// MARK: - View
struct SettingsView: View {
	@AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0
	@State private var _currentIcon: String? = UIApplication.shared.alternateIconName
	
	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>
	
	private var selectedCertificate: CertificatePair? {
		guard
			_storedSelectedCert >= 0,
			_storedSelectedCert < _certificates.count
		else {
			return nil
		}
		return _certificates[_storedSelectedCert]
	}

    
	private let _githubUrl = "https://github.com/1325ilya/BetterThanBox"
    
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Settings")) {
			Form {
				_header()

				Section {
					NavigationLink(destination: BTBSelfUpdateView()) {
						BTBRowLabel(.localized("Check for Updates"), systemImage: "arrow.down.circle.fill", color: .blue)
					}
					NavigationLink(destination: AppearanceView()) {
						BTBRowLabel(.localized("Appearance"), systemImage: "paintbrush.fill", color: .indigo)
					}
					NavigationLink(destination: AppIconView(currentIcon: $_currentIcon)) {
						BTBRowLabel(.localized("App Icon"), systemImage: "app.badge.fill", color: .orange)
					}
					BTBAppLockToggle()
					BTBHidePersonalInfoToggle()
				}
				
				NBSection(.localized("Certificates")) {
					// one row with a stable identity whether or not a certificate exists
					NavigationLink(destination: CertificatesView()) {
						if let cert = selectedCertificate {
							CertificatesCellView(cert: cert)
						} else {
							BTBRowLabel(
								.localized("Add a Certificate"),
								systemImage: "exclamationmark.shield.fill",
								color: .orange,
								subtitle: .localized("Signing needs your certificate (.p12 + .mobileprovision). Tap to add one.")
							)
						}
					}
					NavigationLink(destination: CertificatesView()) {
						BTBRowLabel(.localized("Certificates"), systemImage: "checkmark.seal.fill", color: .green)
					}
					NavigationLink(destination: BTBCertHealthView()) {
						BTBRowLabel(.localized("Certificate Health"), systemImage: "heart.text.square.fill", color: .pink)
					}
				} footer: {
					Text(.localized("Add and manage certificates used for signing applications."))
				}
				
				NBSection(.localized("Signing & Installing")) {
					NavigationLink(destination: ConfigurationView()) {
						BTBRowLabel(.localized("Signing Options"), systemImage: "signature", color: .purple)
					}
					BTBAutoSignToggle()
					NavigationLink(destination: InstallationView()) {
						BTBRowLabel(.localized("Installation"), systemImage: "arrow.down.app.fill", color: .blue)
					}
					NavigationLink(destination: ArchiveView()) {
						BTBRowLabel(.localized("Archive & Compression"), systemImage: "archivebox.fill", color: .brown)
					}
					NavigationLink(destination: BTBBackgroundSettingsView()) {
						BTBRowLabel(.localized("Background Checks"), systemImage: "bell.badge.fill", color: .red)
					}
				}
				
				NBSection(.localized("Data")) {
					NavigationLink(destination: BTBBackupView()) {
						BTBRowLabel(.localized("Backup & Restore"), systemImage: "externaldrive.fill.badge.timemachine", color: .green)
					}
					NavigationLink(destination: BTBStorageView()) {
						BTBRowLabel(.localized("Storage"), systemImage: "internaldrive.fill", color: .gray)
					}
				} footer: {
					Text(.localized("More tools — file manager, logs, IPSW, tweak vault — are on the Tools tab."))
				}
				
				_directories()
				
				_feedback()
				
				Section {
					NavigationLink(destination: ResetView()) {
						BTBRowLabel(.localized("Reset"), systemImage: "trash.fill", color: .red)
					}
				} footer: {
					Text(.localized("Reset the applications sources, certificates, apps, and general contents."))
				}
			}
		}
	}
}

// MARK: - View extension
extension SettingsView {
	private var _build: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
	}
	
	@ViewBuilder
	private func _header() -> some View {
		Section {
			NavigationLink(destination: AboutView()) {
				HStack(spacing: 14) {
					FRAppIconView(size: 58)
					VStack(alignment: .leading, spacing: 4) {
						Text(verbatim: Bundle.main.name)
							.font(.title3.weight(.bold))
						Text(verbatim: String.localized("Version %@ (%@)", arguments: Bundle.main.version, _build))
							.font(.footnote)
							.foregroundStyle(.secondary)
						_certificateStatus()
					}
				}
				.padding(.vertical, 6)
			}
		}
	}
	
	@ViewBuilder
	private func _certificateStatus() -> some View {
		if let cert = selectedCertificate {
			if cert.revoked {
				_statusPill(.localized("Certificate revoked"), icon: "xmark.octagon.fill", color: .red)
			} else if let info = cert.expiration?.expirationInfo() {
				_statusPill(info.formatted, icon: info.icon, color: info.color)
			}
		} else {
			_statusPill(.localized("No certificate"), icon: "exclamationmark.triangle.fill", color: .orange)
		}
	}
	
	private func _statusPill(_ text: String, icon: String, color: Color) -> some View {
		HStack(spacing: 4) {
			Image(systemName: icon)
				.foregroundStyle(color)
			Text(verbatim: text)
				.foregroundStyle(.primary)
		}
		.font(.caption.weight(.semibold))
		.padding(.horizontal, 8)
		.padding(.vertical, 3)
		.background(Capsule().fill(color.opacity(0.18)))
	}
	
	@ViewBuilder
	private func _feedback() -> some View {
		NBSection(.localized("Support")) {
			Button {
				UIApplication.open(URL(string: "\(_githubUrl)/issues/new/choose")!)
			} label: {
				BTBRowLabel(.localized("Submit Feedback"), systemImage: "exclamationmark.bubble.fill", color: .orange)
			}
			Button {
				UIApplication.open(_githubUrl)
			} label: {
				BTBRowLabel(.localized("GitHub Repository"), systemImage: "chevron.left.forwardslash.chevron.right", color: Color(white: 0.22))
			}
		} footer: {
			Text(.localized("If any issues occur within the app please report it via the GitHub repository. When submitting an issue, make sure to submit detailed information."))
		}
	}
	
	@ViewBuilder
	private func _directories() -> some View {
		NBSection(.localized("Folders")) {
			NavigationLink(destination: BTBFileBrowserView(root: URL.documentsDirectory, title: .localized("Files"))) {
				BTBRowLabel(.localized("File Manager"), systemImage: "folder.fill.badge.gearshape", color: .cyan)
			}
			Button {
				UIApplication.open(URL.documentsDirectory.toSharedDocumentsURL()!)
			} label: {
				BTBRowLabel(.localized("Open Documents"), systemImage: "folder.fill", color: .blue)
			}
			Button {
				UIApplication.open(FileManager.default.archives.toSharedDocumentsURL()!)
			} label: {
				BTBRowLabel(.localized("Open Archives"), systemImage: "archivebox.fill", color: .brown)
			}
			Button {
				UIApplication.open(FileManager.default.certificates.toSharedDocumentsURL()!)
			} label: {
				BTBRowLabel(.localized("Open Certificates"), systemImage: "person.text.rectangle.fill", color: .green)
			}
		} footer: {
			Text(.localized("All of the apps files are contained in the documents directory, here are some quick links to these."))
		}
	}
}

/// Blurs certificate names (and other personal info) for screenshots and screen recordings.
struct BTBHidePersonalInfoToggle: View {
	@AppStorage("BTB.hidePersonalInfo") private var _hidePersonal = false
	
	var body: some View {
		Toggle(isOn: $_hidePersonal) {
			BTBRowLabel(
				.localized("Hide Personal Info"),
				systemImage: "eye.slash.fill",
				color: .gray,
				subtitle: .localized("Blur certificate names for screenshots and screen recordings")
			)
		}
	}
}
