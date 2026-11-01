//
//  BTBTweakVault.swift
//  BetterThanBox
//
//  Tweak Vault (idea: BatSign Tweak Vault): keep your .deb / .dylib files
//  in one place and inject them into any app with one tap.
//

import SwiftUI
import UniformTypeIdentifiers
import NimbleViews

enum BTBTweakVault {
	static var directory: URL {
		URL.documentsDirectory.appendingPathComponent("TweakVault", isDirectory: true)
	}
	
	static func files() -> [URL] {
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
		return urls
			.filter { ["deb", "dylib"].contains($0.pathExtension.lowercased()) }
			.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
	}
	
	@discardableResult
	static func add(_ url: URL) -> URL? {
		let fm = FileManager.default
		try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }
		var dest = directory.appendingPathComponent(url.lastPathComponent)
		var i = 2
		while fm.fileExists(atPath: dest.path) {
			dest = directory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(i).\(url.pathExtension)")
			i += 1
		}
		do {
			try fm.copyItem(at: url, to: dest)
			return dest
		} catch {
			return nil
		}
	}
	
	static func remove(_ url: URL) {
		try? FileManager.default.removeItem(at: url)
	}
}

/// Section shown in the signing "Tweaks" screen: toggle vault tweaks for this app.
struct BTBTweakVaultSection: View {
	@Binding var options: Options
	@State private var _files: [URL] = BTBTweakVault.files()
	
	var body: some View {
		NBSection(.localized("Tweak Vault")) {
			if _files.isEmpty {
				Text(.localized("The vault is empty. Add tweaks in Settings → Tweak Vault, or save imported ones there."))
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			ForEach(_files, id: \.self) { file in
				Toggle(isOn: Binding(
					get: { options.injectionFiles.contains(file) },
					set: { on in
						options.injectionFiles.removeAll { $0 == file }
						if on { options.injectionFiles.append(file) }
					}
				)) {
					Label(file.lastPathComponent, systemImage: file.pathExtension.lowercased() == "deb" ? "shippingbox" : "puzzlepiece.extension")
						.lineLimit(2)
				}
			}
		}
		.onAppear { _files = BTBTweakVault.files() }
	}
}

/// Manager screen (Settings → Tweak Vault).
struct BTBTweakVaultView: View {
	@State private var _files: [URL] = []
	@State private var _isImporting = false
	
	var body: some View {
		List {
			Section {
				Button {
					_isImporting = true
				} label: {
					Label(.localized("Add .deb / .dylib"), systemImage: "plus.circle")
				}
			} footer: {
				Text(.localized("Saved tweaks can be switched on for any app in the signing screen (Tweaks)."))
			}
			NBSection(.localized("Tweaks"), secondary: _files.count.description) {
				ForEach(_files, id: \.self) { file in
					NavigationLink {
						if file.pathExtension.lowercased() == "deb" {
							BTBTweakAnalyzerView(url: file)
						} else {
							BTBHexView(url: file)
						}
					} label: {
						VStack(alignment: .leading, spacing: 2) {
							Text(file.lastPathComponent).lineLimit(2)
							Text(btbFormatBytes(BTBStorageManager.shared.size(of: file)))
								.font(.caption).foregroundStyle(.secondary)
						}
					}
				}
				.onDelete { offsets in
					for i in offsets { BTBTweakVault.remove(_files[i]) }
					_files = BTBTweakVault.files()
				}
			}
		}
		.navigationTitle(.localized("Tweak Vault"))
		.fileImporter(isPresented: $_isImporting, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
			if case .success(let urls) = result {
				for url in urls where ["deb", "dylib"].contains(url.pathExtension.lowercased()) {
					BTBTweakVault.add(url)
				}
				_files = BTBTweakVault.files()
			}
		}
		.onAppear { _files = BTBTweakVault.files() }
	}
}
