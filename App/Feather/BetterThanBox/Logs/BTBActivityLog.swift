//
//  BTBActivityLog.swift
//  BetterThanBox
//
//  Activity / install ledger (idea: BatSign BSInstallLedger, Activity log):
//  what was imported, signed (with which certificate), installed or failed.
//  Stored as JSON in Application Support, so storage cleaning keeps it.
//

import SwiftUI
import NimbleViews

struct BTBActivityEntry: Codable, Identifiable, Hashable {
	enum Kind: String, Codable {
		case imported, signed, installed, failed
	}
	var id = UUID()
	var date = Date()
	var kind: Kind
	var appName: String
	var version: String?
	var bundleID: String?
	var detail: String?
}

final class BTBActivityLog: ObservableObject {
	static let shared = BTBActivityLog()
	@Published private(set) var entries: [BTBActivityEntry] = []
	private let _url = URL.applicationSupportDirectory.appendingPathComponent("BTBActivity.json")
	private let _queue = DispatchQueue(label: "BTBActivityLog")
	private let _limit = 1000

	init() {
		if let data = try? Data(contentsOf: _url),
		   let decoded = try? JSONDecoder().decode([BTBActivityEntry].self, from: data) {
			entries = decoded
		}
	}

	func add(_ kind: BTBActivityEntry.Kind, name: String?, version: String?, bundleID: String?, detail: String? = nil) {
		let entry = BTBActivityEntry(kind: kind, appName: name ?? "?", version: version, bundleID: bundleID, detail: detail)
		DispatchQueue.main.async {
			self.entries.insert(entry, at: 0)
			if self.entries.count > self._limit { self.entries.removeLast(self.entries.count - self._limit) }
			self._save()
		}
	}

	func clear() {
		entries.removeAll()
		_save()
	}

	private func _save() {
		let snapshot = entries
		let url = _url
		_queue.async {
			try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			if let data = try? JSONEncoder().encode(snapshot) {
				try? data.write(to: url, options: .atomic)
			}
		}
	}
}

struct BTBActivityView: View {
	@ObservedObject private var _log = BTBActivityLog.shared
	@State private var _filter: BTBActivityEntry.Kind?
	@State private var _query = ""

	private var _filtered: [BTBActivityEntry] {
		_log.entries.filter {
			(_filter == nil || $0.kind == _filter) &&
			(_query.isEmpty || $0.appName.localizedCaseInsensitiveContains(_query) || ($0.bundleID?.localizedCaseInsensitiveContains(_query) ?? false))
		}
	}

	var body: some View {
		List {
			Section {
				Picker(selection: $_filter) {
					Text(.localized("All")).tag(BTBActivityEntry.Kind?.none)
					Text(.localized("Imported")).tag(BTBActivityEntry.Kind?.some(.imported))
					Text(.localized("Signed")).tag(BTBActivityEntry.Kind?.some(.signed))
					Text(.localized("Installed")).tag(BTBActivityEntry.Kind?.some(.installed))
					Text(.localized("Failed")).tag(BTBActivityEntry.Kind?.some(.failed))
				} label: {
					Label(.localized("Show"), systemImage: "line.3.horizontal.decrease.circle")
				}
			}
			NBSection(.localized("History"), secondary: _filtered.count.description) {
				ForEach(_filtered) { entry in
					HStack(spacing: 12) {
						Image(systemName: _icon(entry.kind)).foregroundStyle(_color(entry.kind)).frame(width: 24)
						VStack(alignment: .leading, spacing: 2) {
							Text(entry.version.map { "\(entry.appName) \($0)" } ?? entry.appName).lineLimit(1)
							Text(_subtitle(entry)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
						}
					}
				}
			}
		}
		.navigationTitle(.localized("Activity"))
		.searchable(text: $_query, placement: .platform())
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button(role: .destructive) { _log.clear() } label: { Image(systemName: "trash") }
					.disabled(_log.entries.isEmpty)
			}
		}
		.overlay {
			if _log.entries.isEmpty { Text(.localized("No activity yet.")).foregroundStyle(.secondary) }
		}
	}

	private func _subtitle(_ e: BTBActivityEntry) -> String {
		[e.date.formatted(date: .abbreviated, time: .shortened), e.bundleID, e.detail]
			.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
	}

	private func _icon(_ kind: BTBActivityEntry.Kind) -> String {
		switch kind {
		case .imported: "square.and.arrow.down"
		case .signed: "signature"
		case .installed: "checkmark.circle.fill"
		case .failed: "xmark.octagon.fill"
		}
	}

	private func _color(_ kind: BTBActivityEntry.Kind) -> Color {
		switch kind {
		case .imported: .blue
		case .signed: .purple
		case .installed: .green
		case .failed: .red
		}
	}
}
