//
//  BTBGameGuardSettingsView.swift
//  Veather
//
//  Settings → GameGuardian: where the scripts shared by all games come from.
//

import SwiftUI
import UniformTypeIdentifiers
import NimbleViews

struct BTBGameGuardSettingsView: View {
	@State private var _showPicker = false
	@State private var _folder: URL = BTBGGSharedScripts.folder
	@State private var _isDefault: Bool = BTBGGSharedScripts.chosenFolder == nil
	@State private var _count: Int = 0
	@State private var _error: String?

	var body: some View {
		List {
			NBSection(.localized("Shared scripts folder")) {
				VStack(alignment: .leading, spacing: 4) {
					Text(_isDefault ? .localized("Default folder") : .localized("Chosen folder"))
						.font(.subheadline).foregroundStyle(.secondary)
					Text(_displayPath)
						.font(.footnote.monospaced())
						.textSelection(.enabled)
				}
				HStack {
					Text(.localized("Scripts in it"))
					Spacer()
					Text("\(_count)").foregroundStyle(.secondary)
				}
				Button {
					_showPicker = true
				} label: {
					Label(.localized("Choose a folder…"), systemImage: "folder.badge.plus")
				}
				if !_isDefault {
					Button {
						BTBGGSharedScripts.useDefault()
						_reload()
					} label: {
						Label(.localized("Use the default folder"), systemImage: "arrow.uturn.backward")
					}
				}
				if let _error {
					Text(_error).font(.footnote).foregroundStyle(.red)
				}
			} footer: {
				Text(.localized("Scripts in the GG folder use the gg.* API; scripts in the Lua folder are plain Lua. Every game with GameGuardian gets them in its Scripts tab (Shared). They are copied into the game when Veather signs it, so sign the game again after changing them. The default folder is also visible in the Files app, under Veather."))
			}
		}
		.navigationTitle(.localized("GameGuardian"))
		.onAppear {
			BTBGGSharedScripts.prepare()
			_reload()
		}
		.fileImporter(isPresented: $_showPicker, allowedContentTypes: [.folder]) { result in
			switch result {
			case .success(let url):
				do {
					try BTBGGSharedScripts.choose(url)
					_error = nil
				} catch {
					_error = error.localizedDescription
				}
				_reload()
			case .failure(let error):
				_error = error.localizedDescription
			}
		}
	}

	private var _displayPath: String {
		let path = _folder.path
		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
		if path.hasPrefix(docs) { return "Veather" + path.dropFirst(docs.count) }
		return path
	}

	private func _reload() {
		_folder = BTBGGSharedScripts.folder
		_isDefault = BTBGGSharedScripts.chosenFolder == nil
		_count = BTBGGSharedScripts.scriptCount()
	}
}
