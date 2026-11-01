//
//  BTBToolsView.swift
//  BetterThanBox
//
//  The Tools tab: every extra BetterThanBox feature as a card grid.
//

import SwiftUI
import NimbleViews

enum BTBTool: String, CaseIterable, Identifiable {
	case browser, search, sourceHealth
	case tweakVault, taskCenter, repoBuilder
	case files, storage, backup
	case certHealth, ipsw, deviceInfo
	case activity, logs

	var id: String { rawValue }

	var title: String {
		switch self {
		case .browser: .localized("Browser")
		case .search: .localized("Search Sources")
		case .sourceHealth: .localized("Source Health")
		case .tweakVault: .localized("Tweak Vault")
		case .taskCenter: .localized("Task Center")
		case .repoBuilder: .localized("Repository Builder")
		case .files: .localized("File Manager")
		case .storage: .localized("Storage")
		case .backup: .localized("Backup & Restore")
		case .certHealth: .localized("Certificate Health")
		case .ipsw: .localized("IPSW")
		case .deviceInfo: .localized("Device Info")
		case .activity: .localized("Activity")
		case .logs: .localized("Logs")
		}
	}

	var subtitle: String {
		switch self {
		case .browser: .localized("Download IPA files from websites")
		case .search: .localized("Newest version across all sources")
		case .sourceHealth: .localized("Check which sources respond")
		case .tweakVault: .localized("Your .dylib, .deb and .cyan files")
		case .taskCenter: .localized("Downloads and signing queue")
		case .repoBuilder: .localized("Make your own source JSON")
		case .files: .localized("Browse and edit app files")
		case .storage: .localized("See what takes space, clean up")
		case .backup: .localized("Certificates, sources, settings")
		case .certHealth: .localized("Expiry and status of certificates")
		case .ipsw: .localized("Firmware for this device")
		case .deviceInfo: .localized("Model, iOS version, UDID")
		case .activity: .localized("History of imports and signing")
		case .logs: .localized("Diagnostics for bug reports")
		}
	}

	var icon: String {
		switch self {
		case .browser: "safari.fill"
		case .search: "magnifyingglass"
		case .sourceHealth: "stethoscope"
		case .tweakVault: "puzzlepiece.extension.fill"
		case .taskCenter: "list.bullet.rectangle.fill"
		case .repoBuilder: "hammer.fill"
		case .files: "folder.fill"
		case .storage: "internaldrive.fill"
		case .backup: "externaldrive.fill.badge.timemachine"
		case .certHealth: "checkmark.seal.fill"
		case .ipsw: "cpu.fill"
		case .deviceInfo: "iphone"
		case .activity: "clock.arrow.circlepath"
		case .logs: "doc.text.fill"
		}
	}

	var color: Color {
		switch self {
		case .browser: .blue
		case .search: .indigo
		case .sourceHealth: .teal
		case .tweakVault: .purple
		case .taskCenter: .orange
		case .repoBuilder: .brown
		case .files: .cyan
		case .storage: .gray
		case .backup: .green
		case .certHealth: .mint
		case .ipsw: .pink
		case .deviceInfo: .blue
		case .activity: .yellow
		case .logs: .secondary
		}
	}

	@MainActor @ViewBuilder
	var destination: some View {
		switch self {
		case .browser: BTBBrowserView()
		case .search: BTBUniversalSearchView()
		case .sourceHealth: BTBSourceHealthView()
		case .tweakVault: BTBTweakVaultView()
		case .taskCenter: BTBTaskCenterView()
		case .repoBuilder: BTBRepoBuilderView()
		case .files: BTBFileBrowserView(root: URL.documentsDirectory, title: .localized("Files"))
		case .storage: BTBStorageView()
		case .backup: BTBBackupView()
		case .certHealth: BTBCertHealthView()
		case .ipsw: BTBIPSWView()
		case .deviceInfo: BTBDeviceInfoView()
		case .activity: BTBActivityView()
		case .logs: BTBLogsView()
		}
	}
}

struct BTBToolsView: View {
	private struct ToolGroup: Identifiable {
		let title: String
		let tools: [BTBTool]
		var id: String { title }
	}

	private var _groups: [ToolGroup] {
		[
			ToolGroup(title: .localized("Get Apps"), tools: [.browser, .search, .sourceHealth]),
			ToolGroup(title: .localized("Modify & Sign"), tools: [.tweakVault, .taskCenter, .repoBuilder]),
			ToolGroup(title: .localized("Files & Data"), tools: [.files, .storage, .backup]),
			ToolGroup(title: .localized("Device"), tools: [.certHealth, .ipsw, .deviceInfo]),
			ToolGroup(title: .localized("Diagnostics"), tools: [.activity, .logs]),
		]
	}

	private let _columns = [
		GridItem(.flexible(), spacing: 12),
		GridItem(.flexible(), spacing: 12)
	]

	var body: some View {
		NBNavigationView(.localized("Tools")) {
			ScrollView {
				VStack(alignment: .leading, spacing: 26) {
					ForEach(_groups) { group in
						VStack(alignment: .leading, spacing: 10) {
							Text(group.title)
								.font(.title3.weight(.bold))
								.padding(.horizontal, 4)
							LazyVGrid(columns: _columns, spacing: 12) {
								ForEach(group.tools) { tool in
									NavigationLink {
										tool.destination
									} label: {
										BTBCard(
											title: tool.title,
											subtitle: tool.subtitle,
											systemImage: tool.icon,
											color: tool.color
										)
									}
									.buttonStyle(BTBPressableStyle())
								}
							}
						}
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
			}
			.background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
		}
	}
}
