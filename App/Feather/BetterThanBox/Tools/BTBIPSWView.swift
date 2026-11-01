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

enum BTBIPSWError: LocalizedError {
	case unknownModel(String)
	case http(Int)
	var errorDescription: String? {
		switch self {
		case .unknownModel(let m): String.localized("ipsw.me does not know the model \"%@\". Enter the identifier manually (e.g. iPhone17,1).", arguments: m)
		case .http(let code): String.localized("ipsw.me answered with HTTP %lld.", arguments: code)
		}
	}
}

enum BTBIPSWAPI {
	static let overrideKey = "BTB.ipsw.model"

	/// Endpoint: https://api.ipsw.me/v4/device/<identifier>?type=ipsw
	static func firmwares(for model: String) async throws -> (name: String, firmwares: [BTBFirmware]) {
		let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
		let url = URL(string: "https://api.ipsw.me/v4/device/\(escaped)?type=ipsw")!
		let (data, response) = try await URLSession.shared.data(from: url)
		if let http = response as? HTTPURLResponse, http.statusCode != 200 {
			throw http.statusCode == 404 ? BTBIPSWError.unknownModel(model) : BTBIPSWError.http(http.statusCode)
		}
		guard let decoded = try? JSONDecoder().decode(BTBDeviceFirmwares.self, from: data) else {
			throw BTBIPSWError.unknownModel(model)
		}
		return (decoded.name ?? model, decoded.firmwares)
	}

	/// Manual override, else the simulated device in the Simulator, else hw.machine.
	static func deviceModel() -> String {
		if let manual = UserDefaults.standard.string(forKey: overrideKey), !manual.isEmpty {
			return manual
		}
		if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
			return simulated
		}
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
	@AppStorage(BTBIPSWAPI.overrideKey) private var _manualModel = ""
	
	private var _shown: [BTBFirmware] {
		_onlySigned ? _firmwares.filter { $0.signed } : _firmwares
	}
	
	var body: some View {
		List {
			Section {
				TextField(String.localized("Model identifier (auto: %@)", arguments: BTBIPSWAPI.deviceModel()), text: $_manualModel)
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
					.onSubmit { Task { await _load() } }
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
			let result = try await BTBIPSWAPI.firmwares(for: BTBIPSWAPI.deviceModel())
			_deviceName = result.name
			_firmwares = result.firmwares
			_error = nil
		} catch {
			_firmwares = []
			_error = error.localizedDescription
		}
	}
}
