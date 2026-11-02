//
//  BTBSigningPresets.swift
//  Veather
//
//  Named signing presets (idea: VexSign NamedSigningProfileStore):
//  save the current signing options under a name and apply them in one tap.
//  Per-app values (name, bundle ID, version, icon) are not stored.
//

import SwiftUI

enum BTBSigningPresets {
	private static let _key = "BTB.signingPresets"
	
	static func all() -> [String: Options] {
		guard
			let data = UserDefaults.standard.data(forKey: _key),
			let decoded = try? JSONDecoder().decode([String: Options].self, from: data)
		else { return [:] }
		return decoded
	}
	
	static func names() -> [String] {
		all().keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
	}
	
	static func save(_ options: Options, as name: String) {
		var presets = all()
		var stored = options
		stored.appName = nil
		stored.appIdentifier = nil
		stored.appVersion = nil
		presets[name] = stored
		if let data = try? JSONEncoder().encode(presets) {
			UserDefaults.standard.set(data, forKey: _key)
		}
	}
	
	static func delete(_ name: String) {
		var presets = all()
		presets[name] = nil
		if let data = try? JSONEncoder().encode(presets) {
			UserDefaults.standard.set(data, forKey: _key)
		}
	}
	
	/// Applies a preset but keeps the per-app values already chosen.
	static func apply(_ name: String, to options: inout Options) {
		guard let preset = all()[name] else { return }
		let keepName = options.appName, keepID = options.appIdentifier, keepVersion = options.appVersion
		options = preset
		options.appName = keepName
		options.appIdentifier = keepID
		options.appVersion = keepVersion
	}
}

struct BTBSigningPresetsSection: View {
	@Binding var options: Options
	@State private var _names = BTBSigningPresets.names()
	@State private var _isNaming = false
	@State private var _newName = ""
	
	var body: some View {
		Section {
			Menu {
				ForEach(_names, id: \.self) { name in
					Button(name) { BTBSigningPresets.apply(name, to: &options) }
				}
				if !_names.isEmpty { Divider() }
				Button(.localized("Save Current as Preset…"), systemImage: "square.and.arrow.down") {
					_newName = ""
					_isNaming = true
				}
				if !_names.isEmpty {
					Menu(.localized("Delete Preset")) {
						ForEach(_names, id: \.self) { name in
							Button(name, role: .destructive) {
								BTBSigningPresets.delete(name)
								_names = BTBSigningPresets.names()
							}
						}
					}
				}
			} label: {
				Label(.localized("Presets"), systemImage: "slider.horizontal.below.square.filled.and.square")
			}
		}
		.alert(.localized("Preset Name"), isPresented: $_isNaming) {
			TextField(.localized("Name"), text: $_newName)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Save")) {
				let name = _newName.trimmingCharacters(in: .whitespaces)
				guard !name.isEmpty else { return }
				BTBSigningPresets.save(options, as: name)
				_names = BTBSigningPresets.names()
			}
		}
	}
}
