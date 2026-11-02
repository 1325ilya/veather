//
//  SigningEntitlementsView.swift
//  Feather
//
//  Created by samara on 20.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningEntitlementsView: View {
	@State private var _isAddingPresenting = false
	
	@Binding var bindingValue: URL?
	/// Veather: app whose embedded entitlements can be used as a starting point
	var app: AppInfoPresentable? = nil
	
	// MARK: Body
	var body: some View {
		NBList(.localized("Entitlements")) {
			if let ent = bindingValue {
				NavigationLink {
					BTBPlistEditorView(url: ent)
				} label: {
					Label(.localized("Edit Entitlements"), systemImage: "pencil")
				}
				Text(ent.lastPathComponent)
					.swipeActions() {
						Button(.localized("Delete")) {
							FileManager.default.deleteStored(ent) { _ in
								bindingValue = nil
							}
						}
					}
			} else {
				Button(.localized("Select entitlements file")) {
					_isAddingPresenting = true
				}
				if let app {
					Button(.localized("Create from App's Entitlements")) {
						_create(BTBEntitlements.embedded(in: app) ?? [:])
					}
				}
				Button(.localized("Create Empty")) {
					_create([:])
				}
			}
		}
		.sheet(isPresented: $_isAddingPresenting) {
			FileImporterRepresentableView(
				allowedContentTypes:  [.xmlPropertyList, .plist, .entitlements],
				onDocumentsPicked: { urls in
					guard let selectedFileURL = urls.first else { return }
					
					FileManager.default.moveAndStore(selectedFileURL, with: "FeatherEntitlement") { url in
						bindingValue = url
					}
				}
			)
			.ignoresSafeArea()
		}
	}
}

// MARK: - Veather: entitlements builder
extension SigningEntitlementsView {
	private func _create(_ dict: [String: Any]) {
		let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("BTBEntitlements_\(UUID().uuidString).plist")
		guard
			let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0),
			(try? data.write(to: tmp)) != nil
		else { return }
		FileManager.default.moveAndStore(tmp, with: "FeatherEntitlement") { url in
			bindingValue = url
		}
	}
}

enum BTBEntitlements {
	/// Entitlements embedded in the app's main executable.
	static func embedded(in app: AppInfoPresentable) -> [String: Any]? {
		guard
			let dir = Storage.shared.getAppDirectory(for: app),
			let exec = Bundle(url: dir)?.executableURL,
			let data = LCGetMachOEntitlements(exec.path),
			let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
		else { return nil }
		return dict
	}
}
