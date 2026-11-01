//
//  BTBSourceHealthView.swift
//  BetterThanBox
//
//  Source health dashboard (idea: VexSign SourceHealthDashboardView):
//  which sources load, how many apps each has, duplicates across sources,
//  plain-HTTP warning, one-tap removal of dead sources.
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

struct BTBSourceHealthView: View {
	@ObservedObject private var _viewModel = SourcesViewModel.shared
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	@State private var _isRefreshing = false

	private var _dead: [AltSource] {
		_viewModel.isFinished ? _sources.filter { _viewModel.sources[$0] == nil } : []
	}

	private var _duplicateApps: Int {
		BTBSourceResolver.resolve(sources: _viewModel.sources, query: "").filter { $0.candidates.count > 1 }.count
	}

	var body: some View {
		List {
			Section {
				HStack {
					_stat("\(_sources.count)", .localized("Sources"), .accentColor)
					_stat("\(_sources.count - _dead.count)", .localized("Working"), .green)
					_stat("\(_dead.count)", .localized("Failing"), .red)
					_stat("\(_duplicateApps)", .localized("Shared apps"), .orange)
				}
				if !_dead.isEmpty {
					Button(role: .destructive) {
						for source in _dead { Storage.shared.deleteSource(for: source) }
					} label: {
						Label(.localized("Remove Failing Sources"), systemImage: "trash")
					}
				}
			} footer: {
				Text(.localized("\"Shared apps\" are apps offered by more than one source; Search All Sources picks the newest version among them."))
			}

			NBSection(.localized("Sources")) {
				ForEach(_sources) { source in
					let repo = _viewModel.sources[source]
					HStack {
						Image(systemName: repo != nil ? "checkmark.circle.fill" : (_viewModel.isFinished ? "xmark.octagon.fill" : "clock"))
							.foregroundStyle(repo != nil ? Color.green : (_viewModel.isFinished ? Color.red : Color.secondary))
						VStack(alignment: .leading, spacing: 2) {
							Text(repo?.name ?? source.name ?? source.sourceURL?.host ?? "?").lineLimit(1)
							Text(_details(source, repo)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
						}
					}
					.swipeActions {
						Button(role: .destructive) {
							Storage.shared.deleteSource(for: source)
						} label: {
							Label(.localized("Delete"), systemImage: "trash")
						}
					}
					.contextMenu {
						Button(.localized("Copy URL"), systemImage: "doc.on.doc") {
							UIPasteboard.general.string = source.sourceURL?.absoluteString
						}
					}
				}
			}
		}
		.navigationTitle(.localized("Source Health"))
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					UIPasteboard.general.string = _sources.compactMap { $0.sourceURL?.absoluteString }.joined(separator: "\n")
				} label: {
					Image(systemName: "doc.on.clipboard")
				}
			}
		}
		.refreshable { await _viewModel.fetchSources(_sources, refresh: true) }
		.task { await _viewModel.fetchSources(_sources) }
	}

	@ViewBuilder
	private func _stat(_ value: String, _ title: String, _ color: Color) -> some View {
		VStack {
			Text(value).font(.title3.bold()).foregroundStyle(color)
			Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
		}
		.frame(maxWidth: .infinity)
	}

	private func _details(_ source: AltSource, _ repo: ASRepository?) -> String {
		var parts: [String] = []
		if let repo { parts.append(String.localized("%lld apps", arguments: repo.apps.count)) }
		else if _viewModel.isFinished { parts.append(String.localized("Failed to load")) }
		if source.sourceURL?.scheme?.lowercased() == "http" { parts.append(String.localized("Not encrypted (HTTP)")) }
		if let host = source.sourceURL?.host { parts.append(host) }
		return parts.joined(separator: " • ")
	}
}
