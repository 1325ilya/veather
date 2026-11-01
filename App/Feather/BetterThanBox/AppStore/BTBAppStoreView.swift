//
//  BTBAppStoreView.swift
//  BetterThanBox
//
//  App Store catalogue lookup. Uses Apple's public iTunes Search/Lookup API
//  to find an app and show its info, icon and screenshots (works even for
//  apps with very few downloads). It does NOT sign in, download from Apple, or
//  decrypt anything — to actually get an installable IPA it looks the app up
//  in the sources YOU added (via the newest-version resolver) and otherwise
//  just links out to the App Store.
//

import SwiftUI
import UIKit
import CoreData
import AltSourceKit
import NukeUI
import NimbleViews

struct BTBStoreApp: Decodable, Identifiable, Hashable {
	let trackId: Int
	let trackName: String
	let bundleId: String
	let version: String?
	let sellerName: String?
	let artworkUrl512: URL?
	let artworkUrl100: URL?
	let description: String?
	let screenshotUrls: [URL]?
	let formattedPrice: String?
	let averageUserRating: Double?
	let minimumOsVersion: String?
	let trackViewUrl: URL?
	let primaryGenreName: String?

	var id: Int { trackId }
	var icon: URL? { artworkUrl512 ?? artworkUrl100 }
}

enum BTBAppStoreAPI {
	private struct Response: Decodable { let results: [BTBStoreApp] }

	static var country: String {
		UserDefaults.standard.string(forKey: "BTB.appStore.country")
			?? Locale.current.region?.identifier.lowercased()
			?? "us"
	}

	/// A pasted App Store link contains the numeric track id after "id".
	static func trackID(in text: String) -> String? {
		guard let r = text.range(of: #"id\d{3,}"#, options: .regularExpression) else { return nil }
		return String(text[r].dropFirst(2))
	}

	static func lookup(trackID: String) async throws -> [BTBStoreApp] {
		var c = URLComponents(string: "https://itunes.apple.com/lookup")!
		c.queryItems = [.init(name: "id", value: trackID), .init(name: "country", value: country)]
		return try await _fetch(c.url!)
	}

	static func search(term: String) async throws -> [BTBStoreApp] {
		var c = URLComponents(string: "https://itunes.apple.com/search")!
		c.queryItems = [
			.init(name: "term", value: term),
			.init(name: "country", value: country),
			.init(name: "media", value: "software"),
			.init(name: "limit", value: "25")
		]
		return try await _fetch(c.url!)
	}

	private static func _fetch(_ url: URL) async throws -> [BTBStoreApp] {
		let (data, _) = try await URLSession.shared.data(from: url)
		return try JSONDecoder().decode(Response.self, from: data).results
	}
}

struct BTBAppStoreView: View {
	@ObservedObject private var _sourcesVM = SourcesViewModel.shared
	@State private var _query = ""
	@State private var _results: [BTBStoreApp] = []
	@State private var _loading = false
	@State private var _error: String?

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>

	var body: some View {
		List {
			Section {
				if _loading { ProgressView() }
				if let _error { Text(_error).foregroundStyle(.red).font(.footnote) }
			} footer: {
				Text(.localized("Search Apple's catalogue by name, or paste an App Store link. BetterThanBox shows the app info only; the installable file comes from the sources you added or from the App Store itself."))
			}

			NBSection(.localized("Results"), secondary: _results.count.description) {
				ForEach(_results) { app in
					NavigationLink {
						BTBStoreAppDetailView(app: app, sources: _sourcesVM.sources)
					} label: {
						FRIconCellView(
							title: app.trackName,
							subtitle: _subtitle(app),
							iconUrl: app.icon
						)
					}
				}
			}
		}
		.navigationTitle(.localized("App Store"))
		.searchable(text: $_query, placement: .platform(), prompt: Text(.localized("Name or App Store link")))
		.onSubmit(of: .search) { Task { await _run() } }
		.task { await _sourcesVM.fetchSources(_sources) }
	}

	private func _subtitle(_ app: BTBStoreApp) -> String {
		[app.sellerName, app.version.map { "v\($0)" }, app.formattedPrice]
			.compactMap { $0 }.joined(separator: " • ")
	}

	private func _run() async {
		let q = _query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { _results = []; return }
		_loading = true; _error = nil
		defer { _loading = false }
		do {
			if let id = BTBAppStoreAPI.trackID(in: q) {
				_results = try await BTBAppStoreAPI.lookup(trackID: id)
			} else {
				_results = try await BTBAppStoreAPI.search(term: q)
			}
			if _results.isEmpty { _error = .localized("Nothing found.") }
		} catch {
			_error = error.localizedDescription
		}
	}
}

struct BTBStoreAppDetailView: View {
	let app: BTBStoreApp
	let sources: [AltSource: ASRepository]

	private var _inSources: [BTBCandidate] {
		let resolved = BTBSourceResolver.resolve(sources: sources, query: app.bundleId)
			+ BTBSourceResolver.resolve(sources: sources, query: app.trackName)
		let match = resolved.first { $0.key == app.bundleId.lowercased() } ?? resolved.first
		return match.map { BTBSourceResolver.sort($0.candidates) } ?? []
	}

	var body: some View {
		List {
			Section {
				FRIconCellView(title: app.trackName, subtitle: app.bundleId, iconUrl: app.icon)
				if let genre = app.primaryGenreName { LabeledContent(.localized("Category"), value: genre) }
				if let v = app.version { LabeledContent(.localized("Version"), value: v) }
				if let os = app.minimumOsVersion { LabeledContent(.localized("Minimum OS"), value: os) }
				if let r = app.averageUserRating { LabeledContent(.localized("Rating"), value: String(format: "%.1f", r)) }
			}

			if let shots = app.screenshotUrls, !shots.isEmpty {
				Section {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 12) {
							ForEach(shots, id: \.self) { url in
								LazyImage(url: url) { state in
									if let image = state.image {
										image.resizable().scaledToFit()
											.frame(height: 360)
											.clipShape(RoundedRectangle(cornerRadius: 16))
									} else {
										RoundedRectangle(cornerRadius: 16).fill(Color(.quaternarySystemFill)).frame(width: 200, height: 360)
									}
								}
							}
						}
						.padding(.vertical, 4)
					}
					.listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
				}
			}

			NBSection(.localized("Get the IPA")) {
				if _inSources.isEmpty {
					Text(.localized("Not found in your sources. Add a source that offers this app, then it appears here with the newest version.")).font(.footnote).foregroundStyle(.secondary)
				} else {
					ForEach(_inSources) { c in
						HStack {
							VStack(alignment: .leading, spacing: 2) {
								Text(c.sourceName).font(.headline)
								Text(c.version.map { "v\($0)" } ?? "").font(.caption).foregroundStyle(.secondary)
							}
							Spacer()
							DownloadButtonView(sourceURL: c.source.sourceURL, source: c.repository, app: c.app)
						}
					}
				}
			}

			if let url = app.trackViewUrl {
				Section {
					Button(.localized("Open in App Store"), systemImage: "arrow.up.forward.app") {
						UIApplication.open(url)
					}
				}
			}

			if let desc = app.description, !desc.isEmpty {
				NBSection(.localized("Description")) {
					Text(desc).font(.footnote)
				}
			}
		}
		.navigationTitle(app.trackName)
		.navigationBarTitleDisplayMode(.inline)
	}
}
