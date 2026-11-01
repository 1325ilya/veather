//
//  BTBIPSWView.swift
//  BetterThanBox
//
//  IPSW browser (idea: VexSign IPSWBrowser). Lists signed/unsigned firmware
//  for the current device from the public ipsw.me API. Read-only reference.
//

import SwiftUI
import UIKit
import NimbleViews

struct BTBFirmware: Decodable, Identifiable, Hashable {
	let identifier: String
	let version: String
	let buildid: String
	let url: URL
	let filesize: Int64
	let signed: Bool
	var id: String { buildid + version }
}

private struct BTBDeviceFirmwares: Decodable {
	let name: String?
	let firmwares: [BTBFirmware]
}

enum BTBIPSWAPI {
	static func current() async throws -> (name: String, firmwares: [BTBFirmware]) {
		let model = BTBIPSWAPI.deviceModel()
		let url = URL(string: "https://api.ipsw.me/v4/device/\(model)?type=ipsw")!
		let (data, _) = try await URLSession.shared.data(from: url)
		let decoded = try JSONDecoder().decode(BTBDeviceFirmwares.self, from: data)
		return (decoded.name ?? model, decoded.firmwares)
	}
	
	static func deviceModel() -> String {
		var size = 0
		sysctlbyname("hw.machine", nil, &size, nil, 0)
		var machine = [CChar](repeating: 0, count: size)
		sysctlbyname("hw.machine", &machine, &size, nil, 0)
		return String(cString: machine)
	}
}

struct BTBIPSWView: View {
	@State private var _firmwares: [BTBFirmware] = []
	@State private var _deviceName = ""
	@State private var _error: String?
	@State private var _loading = true
	@State private var _onlySigned = false
	
	private var _shown: [BTBFirmware] {
		_onlySigned ? _firmwares.filter { $0.signed } : _firmwares
	}
	
	var body: some View {
		List {
			Section {
				Toggle(isOn: $_onlySigned) {
					Label(.localized("Signed only"), systemImage: "checkmark.seal")
				}
			} footer: {
				if let _error { Text(_error).foregroundStyle(.red) }
				else { Text(verbatim: String.localized("Firmware for %@ from ipsw.me. \"Signed\" means Apple still allows installing it.", arguments: _deviceName)) }
			}
			NBSection(.localized("Firmware"), secondary: _shown.count.description) {
				ForEach(_shown) { fw in
					HStack {
						VStack(alignment: .leading, spacing: 2) {
							Text("iOS \(fw.version)").font(.headline)
							Text("\(fw.buildid) • \(btbFormatBytes(fw.filesize))")
								.font(.caption).foregroundStyle(.secondary)
						}
						Spacer()
						if fw.signed {
							Text(.localized("Signed")).font(.caption2.bold())
								.padding(.horizontal, 6).padding(.vertical, 2)
								.background(Capsule().fill(Color.green.opacity(0.2)))
						}
					}
					.contextMenu {
						Button(.localized("Copy Download URL"), systemImage: "doc.on.doc") {
							UIPasteboard.general.string = fw.url.absoluteString
						}
						Button(.localized("Open"), systemImage: "safari") {
							UIApplication.open(fw.url)
						}
					}
				}
			}
		}
		.navigationTitle(.localized("IPSW"))
		.overlay { if _loading { ProgressView() } }
		.task { await _load() }
		.refreshable { await _load() }
	}
	
	private func _load() async {
		_loading = true
		defer { _loading = false }
		do {
			let result = try await BTBIPSWAPI.current()
			_deviceName = result.name
			_firmwares = result.firmwares
			_error = nil
		} catch {
			_error = error.localizedDescription
		}
	}
}
