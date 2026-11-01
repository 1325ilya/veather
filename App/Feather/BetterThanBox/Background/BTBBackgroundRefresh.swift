//
//  BTBBackgroundRefresh.swift
//  BetterThanBox
//
//  Background checks (idea: BatSign AutoUpdateManager / BSBackgroundTasks):
//  iOS wakes the app every few hours; it looks for library updates in the
//  user's sources and for revoked / expiring certificates, and posts a local
//  notification. Wi-Fi-only option.
//

import Foundation
import SwiftUI
import BackgroundTasks
import UserNotifications
import Network
import CoreData
import OSLog

enum BTBBackgroundRefresh {
	static let taskID = (Bundle.main.bundleIdentifier ?? "com.betterthanbox.app") + ".refresh"
	static let enabledKey = "BTB.background.enabled"
	static let wifiOnlyKey = "BTB.background.wifiOnly"
	private static let _notifiedKey = "BTB.background.notified"
	
	static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
	
	/// Must be called before the app finishes launching.
	static func register() {
		BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
			guard let task = task as? BGAppRefreshTask else { return }
			handle(task)
		}
	}
	
	static func schedule() {
		guard isEnabled else {
			BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
			return
		}
		let request = BGAppRefreshTaskRequest(identifier: taskID)
		request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
		do {
			try BGTaskScheduler.shared.submit(request)
		} catch {
			Logger.misc.error("Background refresh not scheduled: \(error.localizedDescription)")
		}
	}
	
	static func requestNotifications(completion: @escaping (Bool) -> Void) {
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
			DispatchQueue.main.async { completion(granted) }
		}
	}
	
	private static func handle(_ task: BGAppRefreshTask) {
		schedule() // next run
		let work = Task { @MainActor in
			if UserDefaults.standard.bool(forKey: wifiOnlyKey), await !_isOnWiFi() {
				task.setTaskCompleted(success: true)
				return
			}
			await runChecks()
			task.setTaskCompleted(success: true)
		}
		task.expirationHandler = { work.cancel() }
	}
	
	@MainActor
	static func runChecks() async {
		var lines: [String] = []
		
		// library updates
		let context = Storage.shared.context
		let signed = (try? context.fetch(Signed.fetchRequest() as NSFetchRequest<Signed>)) ?? []
		let imported = (try? context.fetch(Imported.fetchRequest() as NSFetchRequest<Imported>)) ?? []
		let apps: [AppInfoPresentable] = signed.map { $0 as AppInfoPresentable } + imported.map { $0 as AppInfoPresentable }
		await UpdateManager.shared.checkForUpdates(sources: Storage.shared.getSources(), localApps: apps)
		let updates = UpdateManager.shared.updates.values
		
		var notified = Set(UserDefaults.standard.stringArray(forKey: _notifiedKey) ?? [])
		let fresh = updates.filter { !notified.contains("\($0.bundleIdentifier)@\($0.remoteVersion)") }
		if !fresh.isEmpty {
			let names = fresh.prefix(3).map { "\($0.appName) \($0.remoteVersion)" }.joined(separator: ", ")
			lines.append(String.localized("Updates: %@", arguments: names + (fresh.count > 3 ? "…" : "")))
			fresh.forEach { notified.insert("\($0.bundleIdentifier)@\($0.remoteVersion)") }
			UserDefaults.standard.set(Array(notified), forKey: _notifiedKey)
		}
		
		// certificates
		for cert in Storage.shared.getAllCertificates() {
			let name = cert.nickname ?? Storage.shared.getProvisionFileDecoded(for: cert)?.Name ?? "?"
			let status: BTBCertStatus = await withCheckedContinuation { continuation in
				BTBCertHealth.check(cert) { continuation.resume(returning: $0) }
			}
			if status == .revoked {
				lines.append(String.localized("Certificate revoked: %@", arguments: name))
			} else if let exp = cert.expiration, exp > Date(), exp.timeIntervalSinceNow < 2 * 86400 {
				lines.append(String.localized("Certificate expires soon: %@", arguments: name))
			}
		}
		
		guard !lines.isEmpty else { return }
		let content = UNMutableNotificationContent()
		content.title = "BetterThanBox"
		content.body = lines.joined(separator: "\n")
		content.sound = .default
		let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
		try? await UNUserNotificationCenter.current().add(request)
	}
	
	private static func _isOnWiFi() async -> Bool {
		await withCheckedContinuation { continuation in
			let monitor = NWPathMonitor()
			monitor.pathUpdateHandler = { path in
				monitor.cancel()
				continuation.resume(returning: path.usesInterfaceType(.wifi))
			}
			monitor.start(queue: DispatchQueue(label: "BTBWiFiCheck"))
		}
	}
}

struct BTBBackgroundSettingsView: View {
	@AppStorage(BTBBackgroundRefresh.enabledKey) private var _enabled = false
	@AppStorage(BTBBackgroundRefresh.wifiOnlyKey) private var _wifiOnly = true
	@State private var _isChecking = false
	
	var body: some View {
		List {
			Section {
				Toggle(isOn: Binding(
					get: { _enabled },
					set: { on in
						if on {
							BTBBackgroundRefresh.requestNotifications { granted in
								_enabled = granted
								BTBBackgroundRefresh.schedule()
							}
						} else {
							_enabled = false
							BTBBackgroundRefresh.schedule()
						}
					}
				)) {
					Label(.localized("Background Checks"), systemImage: "bell.badge")
				}
				Toggle(isOn: $_wifiOnly) {
					Label(.localized("Only on Wi-Fi"), systemImage: "wifi")
				}
				.disabled(!_enabled)
			} footer: {
				Text(.localized("Every few hours iOS lets BetterThanBox look for updates of your library apps (in your sources) and for revoked or expiring certificates, and you get a notification. iOS decides the exact time; Low Power Mode pauses it."))
			}
			Section {
				Button {
					_isChecking = true
					Task {
						await BTBBackgroundRefresh.runChecks()
						_isChecking = false
					}
				} label: {
					Label(.localized("Run Check Now"), systemImage: "arrow.clockwise")
				}
				.disabled(_isChecking)
			}
		}
		.navigationTitle(.localized("Background Checks"))
	}
}
