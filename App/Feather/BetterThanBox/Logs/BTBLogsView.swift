//
//  BTBLogsView.swift
//  BetterThanBox
//
//  Log viewer for this app's own unified log (OSLogStore, current process).
//  Filter by level/category, search, export as text with secrets redacted.
//

import SwiftUI
import OSLog
import NimbleViews

struct BTBLogEntry: Identifiable, Hashable {
	let id = UUID()
	let date: Date
	let level: OSLogEntryLog.Level
	let category: String
	let message: String
	
	var levelName: String {
		switch level {
		case .debug: "DEBUG"
		case .info: "INFO"
		case .notice: "NOTICE"
		case .error: "ERROR"
		case .fault: "FAULT"
		default: "LOG"
		}
	}
	
	var color: Color {
		switch level {
		case .error, .fault: .red
		case .notice: .orange
		case .debug: .secondary
		default: .primary
		}
	}
	
	func line() -> String {
		"[\(date.formatted(.iso8601))] [\(levelName)] [\(category)] \(message)"
	}
}

enum BTBLogReader {
	static func read(onlyOwnSubsystem: Bool) throws -> [BTBLogEntry] {
		let store = try OSLogStore(scope: .currentProcessIdentifier)
		let position = store.position(timeIntervalSinceLatestBoot: 0)
		let subsystem = Bundle.main.bundleIdentifier ?? ""
		let entries = try store.getEntries(at: position)
		
		var result: [BTBLogEntry] = []
		for case let entry as OSLogEntryLog in entries {
			if onlyOwnSubsystem && entry.subsystem != subsystem { continue }
			result.append(
				BTBLogEntry(
					date: entry.date,
					level: entry.level,
					category: entry.category.isEmpty ? entry.subsystem : entry.category,
					message: entry.composedMessage
				)
			)
		}
		return Array(result.suffix(5000).reversed())
	}
	
	/// Removes passwords and base64 blobs before the log leaves the device.
	static func redact(_ text: String) -> String {
		var output = text
		let patterns = [
			"(?i)(password|pass|pwd)[=:]\\s*\\S+",
			"[A-Za-z0-9+/]{120,}={0,2}"
		]
		for pattern in patterns {
			if let regex = try? NSRegularExpression(pattern: pattern) {
				output = regex.stringByReplacingMatches(
					in: output,
					range: NSRange(output.startIndex..., in: output),
					withTemplate: "<redacted>"
				)
			}
		}
		return output
	}
}

struct BTBLogsView: View {
	@State private var _entries: [BTBLogEntry] = []
	@State private var _query = ""
	@State private var _onlyErrors = false
	@State private var _onlyOwn = true
	@State private var _isLoading = false
	@State private var _error: String?
	
	private var _filtered: [BTBLogEntry] {
		_entries.filter { entry in
			(!_onlyErrors || entry.level == .error || entry.level == .fault) &&
			(_query.isEmpty || entry.message.localizedCaseInsensitiveContains(_query) || entry.category.localizedCaseInsensitiveContains(_query))
		}
	}
	
	var body: some View {
		List {
			Section {
				Toggle(isOn: $_onlyErrors) {
					Label(.localized("Errors only"), systemImage: "exclamationmark.triangle")
				}
				Toggle(isOn: $_onlyOwn) {
					Label(.localized("Only Veather messages"), systemImage: "line.3.horizontal.decrease.circle")
				}
			} footer: {
				if let _error { Text(_error).foregroundStyle(.red) }
			}
			
			NBSection(.localized("Entries"), secondary: _filtered.count.description) {
				ForEach(_filtered) { entry in
					VStack(alignment: .leading, spacing: 2) {
						HStack {
							Text(entry.levelName).font(.caption2.bold()).foregroundStyle(entry.color)
							Text(entry.category).font(.caption2).foregroundStyle(.secondary)
							Spacer()
							Text(entry.date.formatted(date: .omitted, time: .standard))
								.font(.caption2).foregroundStyle(.secondary)
						}
						Text(entry.message)
							.font(.system(.footnote, design: .monospaced))
							.textSelection(.enabled)
					}
				}
			}
		}
		.navigationTitle(.localized("Logs"))
		.searchable(text: $_query, placement: .platform())
		.overlay { if _isLoading { ProgressView() } }
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Button(.localized("Refresh"), systemImage: "arrow.clockwise") { _load() }
					Button(.localized("Share (secrets redacted)"), systemImage: "square.and.arrow.up") { _share() }
					Button(.localized("Copy"), systemImage: "doc.on.doc") {
						UIPasteboard.general.string = _export()
					}
				} label: {
					Image(systemName: "ellipsis.circle")
				}
			}
		}
		.onAppear(perform: _load)
		.onChange(of: _onlyOwn) { _ in _load() }
		.refreshable { _load() }
	}
	
	private func _load() {
		_isLoading = true
		let own = _onlyOwn
		DispatchQueue.global(qos: .userInitiated).async {
			let result = Result { try BTBLogReader.read(onlyOwnSubsystem: own) }
			DispatchQueue.main.async {
				_isLoading = false
				switch result {
				case .success(let entries):
					_entries = entries
					_error = nil
				case .failure(let error):
					_error = error.localizedDescription
				}
			}
		}
	}
	
	private func _export() -> String {
		let device = "\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)"
		let app = "\(Bundle.main.name) \(Bundle.main.version)"
		let body = _filtered.reversed().map { $0.line() }.joined(separator: "\n")
		return BTBLogReader.redact("\(app) — \(device)\n\n\(body)")
	}
	
	private func _share() {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("Veather-log-\(Int(Date().timeIntervalSince1970)).txt")
		try? _export().write(to: url, atomically: true, encoding: .utf8)
		let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
		if let top = UIApplication.topViewController() {
			controller.popoverPresentationController?.sourceView = top.view
			top.present(controller, animated: true)
		}
	}
}
