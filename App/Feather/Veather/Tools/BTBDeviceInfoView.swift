//
//  BTBDeviceInfoView.swift
//  Veather
//
//  Device info (idea: MobileGestalt device detection). Uses only public APIs
//  (UIDevice + sysctl) — no private MobileGestalt calls, which are blocked on
//  modern iOS anyway.
//

import SwiftUI
import UIKit
import NimbleViews

enum BTBDeviceInfo {
	static func sysctl(_ name: String) -> String {
		var size = 0
		sysctlbyname(name, nil, &size, nil, 0)
		guard size > 0 else { return "" }
		var buffer = [CChar](repeating: 0, count: size)
		sysctlbyname(name, &buffer, &size, nil, 0)
		return String(cString: buffer)
	}

	static var model: String { sysctl("hw.machine") }
	static var freeDisk: Int64 {
		let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
		return values?.volumeAvailableCapacityForImportantUsage ?? 0
	}
	static var totalDisk: Int64 {
		let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeTotalCapacityKey])
		return Int64(values?.volumeTotalCapacity ?? 0)
	}
}

struct BTBDeviceInfoView: View {
	var body: some View {
		List {
			NBSection(.localized("Device")) {
				_row(.localized("Name"), UIDevice.current.name)
				_row(.localized("Model"), BTBDeviceInfo.model)
				_row(.localized("System"), "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
				_row("CPU", BTBDeviceInfo.sysctl("hw.cputype").isEmpty ? BTBDeviceInfo.model : BTBDeviceInfo.sysctl("machdep.cpu.brand_string"))
			}
			NBSection(.localized("Storage")) {
				_row(.localized("Free"), btbFormatBytes(BTBDeviceInfo.freeDisk))
				_row(.localized("Total"), btbFormatBytes(BTBDeviceInfo.totalDisk))
			}
		}
		.navigationTitle(.localized("Device Info"))
	}

	private func _row(_ title: String, _ value: String) -> some View {
		LabeledContent(title) { Text(value).foregroundStyle(.secondary) }
	}
}
