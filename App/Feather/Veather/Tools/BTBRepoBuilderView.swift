//
//  BTBRepoBuilderView.swift
//  Veather
//
//  Repository builder (idea: VexSign RepositoryBuilderView/Exporter):
//  build an AltStore-format source JSON from signed library apps whose IPA
//  you host somewhere, then export it to Files. You fill in each app's
//  download URL and version.
//

import SwiftUI
import UIKit
import CoreData
import NimbleViews

struct BTBRepoEntry: Identifiable, Hashable {
	let id = UUID()
	var name: String
	var bundleID: String
	var version: String
	var downloadURL: String
	var iconURL: String
	var developer: String
	var sizeBytes: Int64
	var localizedDescription: String
}

struct BTBRepoBuilderView: View {
	@State private var _repoName = "My Repo"
	@State private var _repoIdentifier = "com.veather.myrepo"
	@State private var _repoIconURL = ""
	@State private var _entries: [BTBRepoEntry] = []
	@State private var _didLoad = false
	
	var body: some View {
		List {
			NBSection(.localized("Repository")) {
				TextField(.localized("Name"), text: $_repoName)
				TextField(.localized("Identifier"), text: $_repoIdentifier)
					.autocorrectionDisabled().textInputAutocapitalization(.never)
				TextField(.localized("Icon URL"), text: $_repoIconURL)
					.autocorrectionDisabled().textInputAutocapitalization(.never)
			} footer: {
				Text(.localized("Builds an AltStore-compatible source JSON. Host the IPA files yourself and paste each download URL below."))
			}
			
			NBSection(.localized("Apps"), secondary: _entries.count.description) {
				ForEach($_entries) { $entry in
					NavigationLink {
						_editor(for: $entry)
					} label: {
						VStack(alignment: .leading, spacing: 2) {
							Text(entry.name.isEmpty ? entry.bundleID : entry.name)
							Text(entry.downloadURL.isEmpty ? String.localized("No download URL") : entry.downloadURL)
								.font(.caption).foregroundStyle(entry.downloadURL.isEmpty ? .red : .secondary).lineLimit(1)
						}
					}
				}
				.onDelete { _entries.remove(atOffsets: $0) }
			}
			
			Section {
				Button(.localized("Export source.json"), systemImage: "square.and.arrow.up") {
					_export()
				}
				.disabled(_entries.isEmpty)
			}
		}
		.navigationTitle(.localized("Repository Builder"))
		.onAppear {
			guard !_didLoad else { return }
			_didLoad = true
			_loadFromLibrary()
		}
	}
	
	@ViewBuilder
	private func _editor(for entry: Binding<BTBRepoEntry>) -> some View {
		Form {
			Section {
				TextField(.localized("Name"), text: entry.name)
				TextField(.localized("Identifier"), text: entry.bundleID).autocorrectionDisabled().textInputAutocapitalization(.never)
				TextField(.localized("Version"), text: entry.version).autocorrectionDisabled().textInputAutocapitalization(.never)
				TextField(.localized("Developer"), text: entry.developer)
			}
			Section {
				TextField(.localized("Download URL"), text: entry.downloadURL).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
				TextField(.localized("Icon URL"), text: entry.iconURL).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
			}
			Section {
				TextField(.localized("Description"), text: entry.localizedDescription, axis: .vertical)
			}
		}
		.navigationTitle(entry.wrappedValue.name)
	}
	
	private func _loadFromLibrary() {
		let request = Signed.fetchRequest() as NSFetchRequest<Signed>
		let apps = (try? Storage.shared.context.fetch(request)) ?? []
		_entries = apps.map { app in
			BTBRepoEntry(
				name: app.name ?? "",
				bundleID: app.identifier ?? "",
				version: app.version ?? "1.0",
				downloadURL: "",
				iconURL: "",
				developer: "",
				sizeBytes: 0,
				localizedDescription: ""
			)
		}
	}
	
	private func _export() {
		var apps: [[String: Any]] = []
		for e in _entries {
			var app: [String: Any] = [
				"name": e.name,
				"bundleIdentifier": e.bundleID,
				"version": e.version,
				"versionDate": ISO8601DateFormatter().string(from: Date()),
				"downloadURL": e.downloadURL,
				"localizedDescription": e.localizedDescription
			]
			if !e.developer.isEmpty { app["developerName"] = e.developer }
			if !e.iconURL.isEmpty { app["iconURL"] = e.iconURL }
			if e.sizeBytes > 0 { app["size"] = e.sizeBytes }
			app["versions"] = [[
				"version": e.version,
				"date": ISO8601DateFormatter().string(from: Date()),
				"downloadURL": e.downloadURL
			]]
			apps.append(app)
		}
		var repo: [String: Any] = [
			"name": _repoName,
			"identifier": _repoIdentifier,
			"apps": apps
		]
		if !_repoIconURL.isEmpty { repo["iconURL"] = _repoIconURL }
		
		guard let data = try? JSONSerialization.data(withJSONObject: repo, options: [.prettyPrinted, .sortedKeys]) else { return }
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("source.json")
		try? data.write(to: url, options: .atomic)
		let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
		UIApplication.topViewController()?.present(picker, animated: true)
	}
}
