//
//  BTBCyan.swift
//  Veather
//
//  .cyan tweak packages (bot commands /custom, /cgen, /patch).
//  A .cyan here is a zip holding one or more .dylib/.deb plus a cyan.json
//  manifest. /custom imports one (its tweaks become injection files),
//  /cgen builds one from selected files, /patch applies common plugin fixes.
//

import Foundation
import SwiftUI
import UIKit
import Zip
import UniformTypeIdentifiers
import NimbleViews

enum BTBCyan {
	struct Manifest: Codable {
		var generator = "Veather"
		var files: [String]
		var replaceSubstrateWithEllekit: Bool = true
		var injectIntoExtensions: Bool = false
	}

	/// /custom — import a .cyan; returns the tweak files (copied to a work dir).
	static func importPackage(_ url: URL) throws -> (files: [URL], manifest: Manifest?) {
		let fm = FileManager.default
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }

		let work = fm.temporaryDirectory.appendingPathComponent("BTBCyan_\(UUID().uuidString)", isDirectory: true)
		try fm.createDirectory(at: work, withIntermediateDirectories: true)
		let zipCopy = work.appendingPathComponent("package.zip")
		try fm.copyItem(at: url, to: zipCopy)
		Zip.addCustomFileExtension("cyan")
		try Zip.unzipFile(zipCopy, destination: work, overwrite: true, password: nil, progress: nil)

		var tweaks: [URL] = []
		var manifest: Manifest?
		if let e = fm.enumerator(at: work, includingPropertiesForKeys: nil) {
			for case let f as URL in e {
				switch f.pathExtension.lowercased() {
				case "dylib", "deb": tweaks.append(f)
				case "json":
					if f.lastPathComponent == "cyan.json" {
						manifest = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: f))
					}
				default: break
				}
			}
		}
		return (tweaks, manifest)
	}

	/// /cgen — build a .cyan from .deb/.dylib files.
	static func generate(from files: [URL], options: Options) throws -> URL {
		let fm = FileManager.default
		let work = fm.temporaryDirectory.appendingPathComponent("BTBCyanGen_\(UUID().uuidString)", isDirectory: true)
		try fm.createDirectory(at: work, withIntermediateDirectories: true)
		var staged: [URL] = []
		for f in files {
			let dest = work.appendingPathComponent(f.lastPathComponent)
			try? fm.copyItem(at: f, to: dest)
			staged.append(dest)
		}
		let manifest = Manifest(
			files: staged.map { $0.lastPathComponent },
			replaceSubstrateWithEllekit: options.experiment_replaceSubstrateWithEllekit,
			injectIntoExtensions: options.injectIntoExtensions
		)
		let manifestURL = work.appendingPathComponent("cyan.json")
		try JSONEncoder().encode(manifest).write(to: manifestURL)
		staged.append(manifestURL)

		let out = fm.temporaryDirectory.appendingPathComponent("tweaks_\(Int(Date().timeIntervalSince1970)).cyan")
		try? fm.removeItem(at: out)
		Zip.addCustomFileExtension("cyan")
		try Zip.zipFiles(paths: staged, zipFilePath: out, password: nil, compression: .BestCompression, progress: nil)
		return out
	}
}

/// Toolbar menu added to the signing Tweaks screen.
struct BTBCyanMenu: View {
	@Binding var options: Options
	@State private var _importing = false

	var body: some View {
		Menu {
			Button(.localized("Import .cyan"), systemImage: "square.and.arrow.down") { _importing = true }
			Button(.localized("Export .cyan"), systemImage: "square.and.arrow.up") { _export() }
				.disabled(options.injectionFiles.isEmpty)
			Button(.localized("Apply Plugin Fixes"), systemImage: "bandage") {
				options.experiment_replaceSubstrateWithEllekit = true
				options.injectIntoExtensions = true
			}
		} label: {
			Label(".cyan", systemImage: "shippingbox")
		}
		.fileImporter(isPresented: $_importing, allowedContentTypes: [.data, .zip], allowsMultipleSelection: false) { result in
			if case .success(let urls) = result, let url = urls.first { _import(url) }
		}
	}

	private func _import(_ url: URL) {
		do {
			let (files, manifest) = try BTBCyan.importPackage(url)
			for f in files {
				FileManager.default.moveAndStore(f, with: "FeatherTweak") { stored in
					if !options.injectionFiles.contains(stored) { options.injectionFiles.append(stored) }
				}
			}
			if let m = manifest {
				options.experiment_replaceSubstrateWithEllekit = m.replaceSubstrateWithEllekit
				options.injectIntoExtensions = m.injectIntoExtensions
			}
		} catch {
			UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
		}
	}

	private func _export() {
		do {
			let out = try BTBCyan.generate(from: options.injectionFiles, options: options)
			let picker = UIDocumentPickerViewController(forExporting: [out], asCopy: true)
			UIApplication.topViewController()?.present(picker, animated: true)
		} catch {
			UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
		}
	}
}
