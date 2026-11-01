//
//  LibraryInfoView.swift
//  Feather
//
//  Created by samara on 14.04.2025.
//

import SwiftUI
import NimbleViews
import Zsign

// MARK: - View
struct LibraryInfoView: View {
	var app: AppInfoPresentable
	var onSign: (() -> Void)? = nil
	var onInstall: (() -> Void)? = nil
	
	@Environment(\.dismiss) private var dismiss
	
	// MARK: Body
	var body: some View {
		NBNavigationView(app.name ?? "", displayMode: .inline) {
			List {
				Section {
					_header()
				}
				.listRowBackground(Color.clear)
				
				_infoSection(for: app)
				_certSection(for: app)
				_bundleSection(for: app)
				_executableSection(for: app)
				
				Section {
					if let appDir = Storage.shared.getAppDirectory(for: app) {
						NavigationLink {
							BTBFileBrowserView(root: appDir, title: app.name)
						} label: {
							Label(.localized("Browse & Edit App Files"), systemImage: "doc.text.magnifyingglass")
						}
					}
					Button(.localized("Open in Files"), systemImage: "folder") {
						UIApplication.open(Storage.shared.getUuidDirectory(for: app)!.toSharedDocumentsURL()!)
					}
				}
			}
			.toolbar {
				NBToolbarButton(role: .close)
			}
		}
	}
}

// MARK: - Extension: View
extension LibraryInfoView {
	@ViewBuilder
	private func _header() -> some View {
		VStack(spacing: 10) {
			FRAppIconView(app: app, size: 84)
				.shadow(color: .black.opacity(0.25), radius: 10, y: 4)
			Text(app.name ?? .localized("Unknown"))
				.font(.title2.weight(.bold))
				.multilineTextAlignment(.center)
			if let version = app.version {
				Text(verbatim: String.localized("Version %@", arguments: version))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			HStack(spacing: 10) {
				if app.isSigned {
					if let onInstall {
						_actionButton(.localized("Install"), systemImage: "square.and.arrow.down", prominent: true) {
							_run(onInstall)
						}
					}
					if let id = app.identifier {
						_actionButton(.localized("Open"), systemImage: "arrow.up.forward.app", prominent: false) {
							UIApplication.openApp(with: id)
						}
					}
					if let onSign {
						_actionButton(.localized("Re-sign"), systemImage: "signature", prominent: false) {
							_run(onSign)
						}
					}
				} else if let onSign {
					_actionButton(.localized("Sign"), systemImage: "signature", prominent: true) {
						_run(onSign)
					}
				}
			}
			.padding(.top, 4)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 6)
	}
	
	@ViewBuilder
	private func _actionButton(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
		if prominent {
			Button(action: action) {
				Label(title, systemImage: systemImage)
					.font(.subheadline.weight(.semibold))
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
		} else {
			Button(action: action) {
				Label(title, systemImage: systemImage)
					.font(.subheadline.weight(.semibold))
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.bordered)
			.controlSize(.large)
		}
	}
	
	private func _run(_ action: @escaping () -> Void) {
		dismiss()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: action)
	}
	
	@ViewBuilder
	private func _infoSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Info")) {
			if let name = app.name {
				_infoCell(.localized("Name"), desc: name)
			}
			
			if let ver = app.version {
				_infoCell(.localized("Version"), desc: ver)
			}
			
			if let id = app.identifier {
				_infoCell(.localized("Identifier"), desc: id)
			}
			
			if let date = app.date {
				_infoCell(.localized("Date Added"), desc: date.formatted())
			}
			
			if 
				let name = app.name, 
				let appDirectory = Storage.shared.getAppDirectory(for: app),
				let appMinimumOS = Bundle(url: appDirectory)?.minimumOSVersion
			{
				_infoCell(.localized("Minimum OS"), desc: appMinimumOS)
			}
		}
	}
	
	@ViewBuilder
	private func _certSection(for app: AppInfoPresentable) -> some View {
		if let cert = Storage.shared.getCertificate(from: app) {
			NBSection(.localized("Certificate")) {
				CertificatesCellView(
					cert: cert
				)
			}
		}
	}
	
	@ViewBuilder
	private func _bundleSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Bundle")) {
			NavigationLink(.localized("Alternative Icons")) {
				SigningAlternativeIconView(app: app, appIcon: .constant(nil), isModifing: .constant(false))
			}
			NavigationLink(.localized("Frameworks & PlugIns")) {
				SigningFrameworksView(app: app, options: .constant(nil))
			}
		}
	}
	
	@ViewBuilder
	private func _executableSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Executable")) {
			NavigationLink(.localized("Dylibs")) {
				SigningDylibView(app: app, options: .constant(nil))
			}
			Button(.localized("Verify Signature"), systemImage: "checkmark.shield") {
				BTBVerifySignature.run(for: app)
			}
			NavigationLink(.localized("Entitlements")) {
				if 
					let path = Bundle(url: Storage.shared.getAppDirectory(for: app)!)?.executableURL?.path,
					let data = LCGetMachOEntitlements(path),
					let rawDict = (try? PropertyListSerialization.propertyList(
						from: data,
						options: [],
						format: nil
					)) as? [String: Any] 
				{
					let binaryEntitlementsDict = rawDict.mapValues { AnyCodable($0) }
					CertificatesInfoEntitlementView(entitlements: binaryEntitlementsDict)
				} else {
					Text(.localized("No Entitlements listed."))
						.font(.footnote)
						.foregroundColor(.disabled())
				}
			}
		}
	}
	
	@ViewBuilder
	private func _infoCell(_ title: String, desc: String) -> some View {
		LabeledContent(title) {
			Text(desc)
		}
		.copyableText(desc)
	}
}

