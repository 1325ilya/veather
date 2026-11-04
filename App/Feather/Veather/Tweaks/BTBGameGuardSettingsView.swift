//
//  BTBGameGuardSettingsView.swift
//  Veather
//
//  Settings → GameGuardian: the scripts shared by all games.
//

import SwiftUI
import UniformTypeIdentifiers
import NimbleViews

struct BTBGameGuardSettingsView: View {
	@State private var _importGG = true
	@State private var _showPicker = false
	@State private var _count: Int = 0
	@State private var _message: String?

	private var _types: [UTType] {
		var types: [UTType] = [.plainText, .data]
		if let lua = UTType(filenameExtension: "lua") { types.insert(lua, at: 0) }
		return types
	}

	var body: some View {
		List {
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
