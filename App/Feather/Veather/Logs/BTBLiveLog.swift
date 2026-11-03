//
//  BTBLiveLog.swift
//  Veather
//
//  Live log shown behind the signing and install screens.
//  Collects explicit steps plus everything written to stdout/stderr while a
//  session is active (zsign writes its log straight to STDOUT_FILENO).
//

import SwiftUI
import Combine

@MainActor
final class BTBLiveLog: ObservableObject {
	static let shared = BTBLiveLog()
	/// Setting: show the live log during signing and installation.
	static let enabledKey = "BTB.liveLogs"

	enum Kind: Sendable {
		case info, step, warning, error, success

		var color: Color {
			switch self {
			case .info: Color.white.opacity(0.62)
			case .step: Color(red: 0.55, green: 0.85, blue: 1.0)
			case .warning: .orange
			case .error: Color(red: 1.0, green: 0.42, blue: 0.42)
			case .success: Color(red: 0.42, green: 0.95, blue: 0.55)
			}
		}
	}

	struct Line: Identifiable, Equatable {
		let id = UUID()
		let date: Date
		let text: String
		let kind: Kind
	}

	@Published private(set) var lines: [Line] = []

	private let _maxLines = 400
	private var _sessions = 0
	private var _pipe: Pipe?
	private var _savedStdout: Int32 = -1
	private var _savedStderr: Int32 = -1
	private var _partial = ""

	nonisolated static var isEnabled: Bool {
		UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
	}

	/// Thread-safe logging entry point (keeps order: main queue is FIFO).
	nonisolated static func log(_ text: String, _ kind: Kind = .info) {
		DispatchQueue.main.async {
			BTBLiveLog.shared.add(text, kind)
		}
	}

	func add(_ text: String, _ kind: Kind = .info) {
		let clean = BTBLogReader.redact(text).trimmingCharacters(in: .whitespacesAndNewlines)
		guard !clean.isEmpty else { return }
		lines.append(Line(date: Date(), text: clean, kind: kind))
		if lines.count > _maxLines {
			lines.removeFirst(lines.count - _maxLines)
		}
	}

	/// Starts a logging session (signing or install). Sessions nest.
	func begin(_ title: String) {
		if _sessions == 0 {
			// keep the signing log when installing right after it
			let isContinuation = lines.last.map { Date().timeIntervalSince($0.date) < 30 } ?? false
			if !isContinuation { lines.removeAll() }
			_startCapture()
		}
		_sessions += 1
		add(title, .step)
	}

	func end() {
		_sessions = max(0, _sessions - 1)
		if _sessions == 0 {
			_stopCapture()
		}
	}

	// MARK: stdout / stderr capture

	private func _startCapture() {
		guard Self.isEnabled, _pipe == nil else { return }

		fflush(stdout)
		fflush(stderr)
		setvbuf(stdout, nil, _IOLBF, 0)

		let pipe = Pipe()
		let saved = dup(STDOUT_FILENO)
		_savedStdout = saved
		_savedStderr = dup(STDERR_FILENO)
		dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
		dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

		pipe.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			guard !data.isEmpty else { return }
			// keep the original output working (Xcode console, crash logs)
			if saved >= 0 {
				data.withUnsafeBytes { raw in
					_ = write(saved, raw.baseAddress, data.count)
				}
			}
			let text = String(decoding: data, as: UTF8.self)
			DispatchQueue.main.async {
				BTBLiveLog.shared._ingest(text)
			}
		}
		_pipe = pipe
	}

	private func _stopCapture() {
		guard let pipe = _pipe else { return }

		fflush(stdout)
		fflush(stderr)
		if _savedStdout >= 0 {
			dup2(_savedStdout, STDOUT_FILENO)
			close(_savedStdout)
		}
		if _savedStderr >= 0 {
			dup2(_savedStderr, STDERR_FILENO)
			close(_savedStderr)
		}
		_savedStdout = -1
		_savedStderr = -1

		pipe.fileHandleForReading.readabilityHandler = nil
		try? pipe.fileHandleForWriting.close()
		_pipe = nil
		// the write end is closed and stdout/stderr are restored, so this ends right away:
		// the last lines written just before the end must not be lost
		// non-blocking read: never wait for a copy of the write end that something else still holds
		let fd = pipe.fileHandleForReading.fileDescriptor
		_ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
		var rest = Data()
		var buffer = [UInt8](repeating: 0, count: 4096)
		while true {
			let n = read(fd, &buffer, buffer.count)
			if n <= 0 { break }
			rest.append(buffer, count: n)
		}
		if !rest.isEmpty { _ingest(String(decoding: rest, as: UTF8.self)) }

		if !_partial.isEmpty {
			_ingestLine(_partial)
			_partial = ""
		}
	}

	private func _ingest(_ chunk: String) {
		let text = _partial + chunk
		var parts = text.components(separatedBy: .newlines)
		_partial = parts.removeLast()
		for part in parts {
			_ingestLine(part)
		}
	}

	private func _ingestLine(_ raw: String) {
		// strip ANSI colour codes from zsign
		let line = raw.replacingOccurrences(
			of: "\u{1B}\\[[0-9;]*m",
			with: "",
			options: .regularExpression
		)
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "-" || $0 == "=" }) else { return }

		let lower = trimmed.lowercased()
		let kind: Kind
		if lower.contains("error") || lower.contains("failed") || lower.contains("fail!") {
			kind = .error
		} else if lower.contains("warning") || lower.contains("warn") {
			kind = .warning
		} else if lower.hasPrefix(">>>") {
			kind = .step
		} else if lower.contains("ok!") || lower.contains("success") || lower.contains("done") {
			kind = .success
		} else {
			kind = .info
		}
		add(trimmed, kind)
	}
}

// MARK: - View

/// Terminal-style log that scrolls by itself; meant to sit behind other content.
struct BTBLiveLogView: View {
	@ObservedObject private var _log = BTBLiveLog.shared
	var fontSize: CGFloat = 10.5

	var body: some View {
		ScrollViewReader { proxy in
			ScrollView(showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 2) {
					ForEach(_log.lines) { line in
						Text(verbatim: line.text)
							.font(.system(size: fontSize, design: .monospaced))
							.foregroundStyle(line.kind.color)
							.frame(maxWidth: .infinity, alignment: .leading)
							.id(line.id)
					}
				}
				.padding(.horizontal, 14)
				.padding(.vertical, 10)
			}
			.onChange(of: _log.lines.last?.id) { id in
				guard let id else { return }
				withAnimation(.easeOut(duration: 0.18)) {
					proxy.scrollTo(id, anchor: .bottom)
				}
			}
		}
		.mask(
			LinearGradient(
				stops: [
					.init(color: .clear, location: 0),
					.init(color: .black, location: 0.25),
					.init(color: .black, location: 1)
				],
				startPoint: .top,
				endPoint: .bottom
			)
		)
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}
}

/// Full-screen overlay used while signing: dark terminal, progress and a
/// checkmark when finished.
struct BTBSigningOverlay: View {
	var title: String
	var finished: Bool
	var showLogs: Bool
	/// When set, the finished state shows Install / Done buttons right here.
	var onInstall: (() -> Void)? = nil
	var onDone: (() -> Void)? = nil

	var body: some View {
		ZStack {
			Color.black.opacity(0.88).ignoresSafeArea()

			if showLogs {
				BTBLiveLogView(fontSize: 11)
					.padding(.top, 60)
					.padding(.bottom, finished && onInstall != nil ? 340 : 170)
			}

			VStack(spacing: 14) {
				Spacer()
				ZStack {
					if finished {
						Image(systemName: "checkmark.circle.fill")
							.font(.system(size: 64, weight: .semibold))
							.symbolRenderingMode(.palette)
							.foregroundStyle(.white, Color.green)
							.transition(.scale.combined(with: .opacity))
					} else {
						ProgressView()
							.controlSize(.large)
							.tint(.white)
							.transition(.opacity)
					}
				}
				.frame(height: 70)
				Text(verbatim: finished ? String.localized("Signed") : title)
					.font(.headline)
					.foregroundStyle(.white)
				if finished, let onInstall {
					VStack(spacing: 10) {
						Button(action: onInstall) {
							Label(.localized("Install"), systemImage: "square.and.arrow.down")
								.font(.headline)
								.foregroundStyle(.white)
								.frame(maxWidth: .infinity, minHeight: 50)
								.background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor))
						}
						Button(action: { onDone?() }) {
							Text(.localized("Done"))
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(.white.opacity(0.8))
								.frame(maxWidth: .infinity, minHeight: 40)
						}
					}
					.padding(.horizontal, 32)
					.padding(.top, 12)
					.transition(.move(edge: .bottom).combined(with: .opacity))
				}
			}
			.padding(.bottom, 60)
			.animation(.spring(response: 0.4, dampingFraction: 0.7), value: finished)
		}
	}
}
