//
//  BTBGameGuardSettingsView.swift
//  Veather
//
//  Settings → GameGuardian: the scripts shared by all games.
//

import SwiftUI
import UniformTypeIdentifiers
import NimbleViews
import PhotosUI

struct BTBGameGuardSettingsView: View {
	@State private var _importGG = true
	@State private var _showPicker = false
	@State private var _count: Int = 0
	@State private var _message: String?
	@State private var _iconItem: PhotosPickerItem?
	@State private var _showIconFiles = false
	@State private var _icon: UIImage? = BTBGGFloatingIcon.image
	@State private var _iconMessage: String?

	private func _applyIcon(_ data: Data) {
		if BTBGGFloatingIcon.set(data) {
			_icon = BTBGGFloatingIcon.image
			_iconMessage = .localized("Saved. Sign the game again to see it.")
		} else {
			_iconMessage = .localized("Could not read the picture.")
		}
	}

	private var _types: [UTType] {
		var types: [UTType] = [.plainText, .data]
		if let lua = UTType(filenameExtension: "lua") { types.insert(lua, at: 0) }
		return types
	}

	var body: some View {
		List {
			NBSection(.localized("Floating button icon")) {
				HStack(spacing: 14) {
					if let _icon {
						Image(uiImage: _icon)
							.resizable().scaledToFit()
							.frame(width: 56, height: 56)
					} else {
						Image(systemName: "shield.lefthalf.filled")
							.font(.system(size: 30))
							.foregroundStyle(.secondary)
							.frame(width: 56, height: 56)
					}
					Text(_icon == nil ? .localized("Standard icon") : .localized("Your picture"))
						.foregroundStyle(.secondary)
				}
				PhotosPicker(selection: $_iconItem, matching: .images) {
					Label(.localized("Choose from Photos…"), systemImage: "photo")
				}
				Button {
					_showIconFiles = true
				} label: {
					Label(.localized("Choose from Files…"), systemImage: "folder")
				}
				if _icon != nil {
					Button(role: .destructive) {
						BTBGGFloatingIcon.reset()
						_icon = nil
						_iconMessage = nil
					} label: {
						Label(.localized("Back to the standard icon"), systemImage: "arrow.uturn.backward")
					}
				}
				if let _iconMessage {
					Text(_iconMessage).font(.footnote).foregroundStyle(.secondary)
				}
			} footer: {
				Text(.localized("The picture is remembered and put on the floating GameGuardian button. It is copied into the game when Veather signs it, so sign the game again after changing it. A PNG with a transparent background looks best."))
			}
			NBSection(.localized("Shared scripts")) {
				VStack(alignment: .leading, spacing: 4) {
					Text(.localized("Folder"))
						.font(.subheadline).foregroundStyle(.secondary)
					Text("Veather/GameGuardian/Scripts")
						.font(.footnote.monospaced())
						.textSelection(.enabled)
				}
				HStack {
					Text(.localized("Scripts in it"))
					Spacer()
					Text("\(_count)").foregroundStyle(.secondary)
				}
				Button {
					_importGG = true
					_showPicker = true
				} label: {
					Label(.localized("Add GG scripts…"), systemImage: "plus.circle")
				}
				Button {
					_importGG = false
					_showPicker = true
				} label: {
					Label(.localized("Add plain Lua scripts…"), systemImage: "plus.circle")
				}
				if let _message {
					Text(_message).font(.footnote).foregroundStyle(.secondary)
				}
			} footer: {
				Text(.localized("Scripts in the GG folder use the gg.* API; scripts in the Lua folder are plain Lua. Every game with GameGuardian gets them in its Scripts tab (Shared). You can also put files into this folder in the Files app (On My iPhone → Veather). They are copied into the game when Veather signs it, so sign the game again after changing them."))
			}
		}
		.navigationTitle(.localized("GameGuardian"))
		.onChange(of: _iconItem) { item in
			guard let item else { return }
			Task {
				if let data = try? await item.loadTransferable(type: Data.self) { _applyIcon(data) }
				else { _iconMessage = .localized("Could not read the picture.") }
				_iconItem = nil
			}
		}
		.fileImporter(isPresented: $_showIconFiles, allowedContentTypes: [.image]) { result in
			if case .success(let url) = result {
				let scoped = url.startAccessingSecurityScopedResource()
				defer { if scoped { url.stopAccessingSecurityScopedResource() } }
				if let data = try? Data(contentsOf: url) { _applyIcon(data) }
				else { _iconMessage = .localized("Could not read the picture.") }
			}
		}
		.onAppear {
			BTBGGSharedScripts.prepare()
			_count = BTBGGSharedScripts.scriptCount()
		}
		.fileImporter(isPresented: $_showPicker, allowedContentTypes: _types, allowsMultipleSelection: true) { result in
			switch result {
			case .success(let urls):
				let added = BTBGGSharedScripts.add(urls, toGG: _importGG)
				_message = added > 0 ? .localized("Added: ") + "\(added)" : .localized("Nothing added. Pick .lua or text files.")
			case .failure(let error):
				_message = error.localizedDescription
			}
			_count = BTBGGSharedScripts.scriptCount()
		}
	}
}
