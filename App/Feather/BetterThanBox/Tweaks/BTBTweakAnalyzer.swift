//
//  BTBTweakAnalyzer.swift
//  BetterThanBox
//
//  Tweak dependency analysis (idea: VexSign TweakAnalyzer). Reads a .deb's
//  control file (Package/Version/Architecture/Depends) and flags Cydia
//  Substrate dependencies (suggesting ElleKit) for sideloaded apps.
//

import Foundation
import SWCompression
import NimbleViews
import SwiftUI

struct BTBTweakInfo {
	var package = ""
	var version = ""
	var architecture = ""
	var author = ""
	var depends: [String] = []
	var dependsOnSubstrate: Bool {
		depends.contains { d in
			["mobilesubstrate", "cydia-substrate", "com.ex.substitute", "ellekit"].contains { d.lowercased().contains($0) }
		}
	}
}

enum BTBTweakAnalyzer {
	static func analyze(_ debURL: URL) async -> BTBTweakInfo? {
		do {
			let ar = AR(with: debURL)
			let files = try await ar.extract()
			guard let control = files.first(where: { $0.name.hasPrefix("control.tar") }) else { return nil }

			let tarData = try _decompress(name: control.name, data: control.content)
			let container = try TarContainer.open(container: tarData)
			guard let entry = container.first(where: {
				let n = ($0.info.name as NSString).lastPathComponent
				return n == "control"
			}), let data = entry.data, let text = String(data: data, encoding: .utf8) else { return nil }

			return parseControl(text)
		} catch {
			return nil
		}
	}

	static func parseControl(_ text: String) -> BTBTweakInfo {
		var info = BTBTweakInfo()
		for line in text.split(separator: "\n") {
			guard let colon = line.firstIndex(of: ":") else { continue }
			let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
			let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			switch key {
			case "package": info.package = value
			case "version": info.version = value
			case "architecture": info.architecture = value
			case "author", "maintainer": if info.author.isEmpty { info.author = value }
			case "depends":
				info.depends = value.split(separator: ",").map {
					$0.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
				}.filter { !$0.isEmpty }
			default: break
			}
		}
		return info
	}

	private static func _decompress(name: String, data: Data) throws -> Data {
		if name.hasSuffix(".gz") { return try GzipArchive.unarchive(archive: data) }
		if name.hasSuffix(".xz") { return try XZArchive.unarchive(archive: data) }
		if name.hasSuffix(".lzma") { return try LZMA.decompress(data: data) }
		if name.hasSuffix(".bz2") { return try BZip2.decompress(data: data) }
		return data // already .tar
	}
}

struct BTBTweakAnalyzerView: View {
	let url: URL
	@State private var _info: BTBTweakInfo?
	@State private var _loading = true

	var body: some View {
		List {
			if _loading {
				Section { HStack { ProgressView(); Text(.localized("Analyzing…")) } }
			} else if let info = _info {
				NBSection(.localized("Package")) {
					LabeledContent(.localized("Name"), value: info.package.isEmpty ? url.lastPathComponent : info.package)
					if !info.version.isEmpty { LabeledContent(.localized("Version"), value: info.version) }
					if !info.architecture.isEmpty { LabeledContent(.localized("Architecture"), value: info.architecture) }
					if !info.author.isEmpty { LabeledContent(.localized("Developer"), value: info.author) }
				}
				if info.dependsOnSubstrate {
					Section {
						Label(.localized("Depends on Cydia Substrate. Enable \"Replace Substrate with ElleKit\" in signing options so it works sideloaded."), systemImage: "exclamationmark.triangle")
							.foregroundStyle(.orange).font(.footnote)
					}
				}
				NBSection(.localized("Dependencies"), secondary: info.depends.count.description) {
					if info.depends.isEmpty {
						Text(.localized("No declared dependencies.")).foregroundStyle(.secondary).font(.footnote)
					}
					ForEach(info.depends, id: \.self) { Text($0).font(.system(.footnote, design: .monospaced)) }
				}
			} else {
				Section { Text(.localized("Could not read this package.")).foregroundStyle(.secondary) }
			}
		}
		.navigationTitle(.localized("Tweak Info"))
		.task {
			_info = await BTBTweakAnalyzer.analyze(url)
			_loading = false
		}
	}
}
