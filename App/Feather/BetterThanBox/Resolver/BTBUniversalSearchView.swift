//
//  BTBUniversalSearchView.swift
//  BetterThanBox
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

struct BTBUniversalSearchView: View {
	@ObservedObject private var _viewModel = SourcesViewModel.shared
	@State private var _query = ""
	@State private var _onlyDuplicates = false
	@State private var _onlyFavorites = false
	@State private var _refreshToken = UUID()
	@AppStorage(BTBUpdateRules.allSourcesKey) private var _updatesFromAllSources = true
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	private var _results: [BTBResolvedApp] {
		_ = _refreshToken
		var all = BTBSourceResolver.resolve(sources: _viewModel.sources, query: _query)
		if _onlyDuplicates { all = all.filter { $0.candidates.count > 1 } }
		if _onlyFavorites { all = all.filter { BTBFavorites.contains($0.key) } }
		return all
	}
	
	var body: some View {
		let results = _results
		List {
			Section {
				Toggle(isOn: $_onlyDuplicates) {
					Label(.localized("Only apps found in several sources"), systemImage: "square.on.square")
				}
				Toggle(isOn: $_updatesFromAllSources) {
					Label(.localized("Library updates from all sources"), systemImage: "arrow.triangle.2.circlepath")
				}
				Toggle(isOn: $_onlyFavorites) {
					Label(.localized("Favorites only"), systemImage: "star")
				}
			} footer: {
				Text(.localized("Searches every source you added. By default the source with the highest version is used; tap an app to pick another source manually."))
			}
			
			NBSection(.localized("Apps"), secondary: results.count.description) {
				ForEach(results) { resolved in
					NavigationLink {
						BTBResolvedAppView(resolved: resolved) { _refreshToken = UUID() }
					} label: {
						HStack(spacing: 2) {
							FRIconCellView(
								title: resolved.name,
								subtitle: _subtitle(resolved),
								iconUrl: resolved.best.app.iconURL
							)
							DownloadButtonView(
								sourceURL: resolved.best.source.sourceURL,
								source: resolved.best.repository,
								app: resolved.best.app
							)
						}
					}
				}
			}
		}
		.navigationTitle(.localized("Search All Sources"))
		.searchable(text: $_query, placement: .platform(), prompt: Text(.localized("Name or bundle ID")))
		.refreshable {
			await _viewModel.fetchSources(_sources, refresh: true)
		}
		.task {
			await _viewModel.fetchSources(_sources)
		}
		.overlay {
			if _sources.isEmpty {
				Text(.localized("Add a source first."))
					.foregroundStyle(.secondary)
			}
		}
	}
	
	private func _subtitle(_ resolved: BTBResolvedApp) -> String {
		var parts: [String] = []
		if let v = resolved.best.version { parts.append("v\(v)") }
		parts.append(resolved.best.sourceName)
		if resolved.candidates.count > 1 {
			parts.append(String.localized("%lld sources", arguments: resolved.candidates.count))
		}
		return parts.joined(separator: " • ")
	}
}

struct BTBResolvedAppView: View {
	let resolved: BTBResolvedApp
	var onChange: () -> Void
	@State private var _pinned: String?
	@State private var _favorite = false
	
	init(resolved: BTBResolvedApp, onChange: @escaping () -> Void) {
		self.resolved = resolved
		self.onChange = onChange
		self.__pinned = State(initialValue: BTBSourceResolver.pinnedSource(for: resolved.key))
		self.__favorite = State(initialValue: BTBFavorites.contains(resolved.key))
	}
	
	var body: some View {
		List {
			Section {
				FRIconCellView(
					title: resolved.name,
					subtitle: resolved.best.app.id ?? "",
					iconUrl: resolved.best.app.iconURL
				)
			} footer: {
				Text(verbatim: _pinned == nil
					 ? String.localized("Automatic: the newest version is downloaded by default.")
					 : String.localized("A source is pinned manually for this app."))
			}
			
			NBSection(.localized("Sources")) {
				ForEach(Array(resolved.candidates.enumerated()), id: \.element.id) { index, candidate in
					HStack {
						VStack(alignment: .leading, spacing: 2) {
							HStack(spacing: 6) {
								Text(candidate.sourceName).font(.headline)
								if index == 0 {
									Text(.localized("Newest"))
										.font(.caption2.bold())
										.padding(.horizontal, 6).padding(.vertical, 2)
										.background(Capsule().fill(Color.green.opacity(0.2)))
								}
								if _pinned == candidate.sourceIdentifier {
									Image(systemName: "pin.fill").foregroundStyle(.orange)
								}
							}
							Text(_details(candidate))
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
						Spacer()
						DownloadButtonView(
							sourceURL: candidate.source.sourceURL,
							source: candidate.repository,
							app: candidate.app
						)
					}
					.swipeActions(edge: .leading) {
						Button {
							_setPin(candidate.sourceIdentifier)
						} label: {
							Label(.localized("Pin"), systemImage: "pin")
						}
						.tint(.orange)
					}
					.contextMenu {
						Button(.localized("Always use this source"), systemImage: "pin") {
							_setPin(candidate.sourceIdentifier)
						}
					}
				}
			}
			
			if _pinned != nil {
				Section {
					Button(.localized("Back to automatic (newest version)"), systemImage: "arrow.uturn.backward") {
						_setPin(nil)
					}
				}
			}
		}
		.navigationTitle(resolved.name)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					BTBFavorites.toggle(resolved.key)
					_favorite.toggle()
					onChange()
				} label: {
					Image(systemName: _favorite ? "star.fill" : "star")
				}
			}
		}
	}
	
	private func _setPin(_ id: String?) {
		BTBSourceResolver.setPinnedSource(id, for: resolved.key)
		_pinned = id
		onChange()
	}
	
	private func _details(_ c: BTBCandidate) -> String {
		var parts: [String] = []
		parts.append(c.version.map { "v\($0)" } ?? .localized("Unknown version"))
		if let date = c.date {
			parts.append(date.formatted(date: .abbreviated, time: .omitted))
		}
		if let size = c.app.currentAppVersion?.size ?? c.app.size.map({ UInt($0) }) {
			parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
		}
		return parts.joined(separator: " • ")
	}
}
