//
//  InstallPreview.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift
import OSLog

// MARK: - View
struct InstallPreviewView: View {
	@Environment(\.dismiss) var dismiss

	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@State private var _isWebviewPresenting = false
	@State private var progressTask: Task<Void, Never>?
	@AppStorage(BTBLiveLog.enabledKey) private var _liveLogs = true
	@State private var _readySince: Date?
	@State private var _showStuckHint = false
	@State private var _stuckTimer: Timer?
	
	var app: AppInfoPresentable
	@StateObject var viewModel: InstallerStatusViewModel
	@StateObject var installer: ServerInstaller
	
	@State var isSharing: Bool
	
	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self.isSharing = isSharing
		let viewModel = InstallerStatusViewModel(isIdevice: UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1)
		self._viewModel = StateObject(wrappedValue: viewModel)
		self._installer = StateObject(wrappedValue: try! ServerInstaller(app: app, viewModel: viewModel))
	}
	
	// MARK: Body
	var body: some View {
		let cornerRadius = {
			if #available(iOS 26.0, *) {
				28.0
			} else {
				10.5
			}
		}()
		
		ZStack {
			if _liveLogs {
				BTBLiveLogView(fontSize: 9.5)
					.opacity(0.5)
					.padding(.bottom, 44)
			}
			InstallProgressView(app: app, viewModel: viewModel)
			_status()
			_button()
			if _showStuckHint {
				_stuckHint()
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.animation(.smooth, value: _showStuckHint)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.background(Color(UIColor.secondarySystemBackground))
		.cornerRadius(cornerRadius)
		.padding()
		.sheet(isPresented: $_isWebviewPresenting) {
			SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
		}
		.onReceive(viewModel.$status) { newStatus in
			_logStatus(newStatus)
			_trackStuck(newStatus)
			
			switch newStatus {
			case .completed(.success):
				BTBActivityLog.shared.add(.installed, name: app.name, version: app.version, bundleID: app.identifier)
			case .broken(let error):
				BTBActivityLog.shared.add(.failed, name: app.name, version: app.version, bundleID: app.identifier, detail: error.localizedDescription)
			default:
				break
			}
			
			if _installationMethod == 0 {
				if case .ready = newStatus {
					_openInstallPrompt()
					// watch install progress from the start: server callbacks can be missed
					if progressTask == nil, let bundleID = app.identifier {
						progressTask = startInstallProgressPolling(bundleID: bundleID, viewModel: viewModel)
					}
				}
				
				if case .sendingPayload = newStatus, _serverMethod == 1 {
					_isWebviewPresenting = false
				}
				
				if case .installing = newStatus {
					if progressTask == nil {
						progressTask = startInstallProgressPolling(
							bundleID: app.identifier!,
							viewModel: viewModel
						)
					}
				}
				
				switch newStatus {
				case .completed, .broken(_):
					progressTask?.cancel()
					progressTask = nil
					#if !targetEnvironment(macCatalyst)
					BackgroundAudioManager.shared.stop()
					#endif
				default:
					break
				}
			}
		}
		.onAppear {
			BTBLiveLog.shared.begin(String.localized("Installing %@", arguments: app.name ?? ""))
			_install()
		}
		
		#if !targetEnvironment(macCatalyst)
		.onAppear {
			BackgroundAudioManager.shared.start()
		}
		#endif
		
		.onDisappear {
			progressTask?.cancel()
			progressTask = nil
			_stuckTimer?.invalidate()
			_stuckTimer = nil
			BTBLiveLog.shared.end()
			
			#if !targetEnvironment(macCatalyst)
			BackgroundAudioManager.shared.stop()
			#endif
		}
	}
	
	@ViewBuilder
	private func _status() -> some View {
		Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}
	
	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if viewModel.isCompleted {
				Button {
					UIApplication.openApp(with: app.identifier ?? "")
				} label: {
					NBButton(.localized("Open"), systemImage: "", style: .text)
				}
				.padding()
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}
	
	private func _install() {
		guard isSharing || app.identifier != Bundle.main.bundleIdentifier! || _installationMethod == 1 else {
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: .localized("You cannot update ‘%@‘ with itself, please use an alternative tool to update it.", arguments: Bundle.main.name)
			)
			return
		}
				
		Task.detached {
			do {
				let handler = await ArchiveHandler(app: app, viewModel: viewModel)
				try await handler.move()
				
				let packageUrl = try await handler.archive()
				
				if await !isSharing {
					if await _installationMethod == 0 {
						if await _serverMethod == 0, !BTBServerCert.currentIsUsable {
							BTBLiveLog.log("Install server certificate expired, downloading a fresh one…", .warning)
							if await BTBServerCert.refreshIfNeeded(force: true) {
								try? await MainActor.run { try installer.reloadTLS() }
							}
						}
						let endpoint = await MainActor.run { "\(installer.plistEndpoint.host ?? "?"):\(installer.port)" }
						BTBLiveLog.log("Local install server: \(endpoint)")
						await MainActor.run {
							installer.packageUrl = packageUrl
							viewModel.status = .ready
						}
						
						if case .installing = await viewModel.status, await progressTask == nil {
							let task = await startInstallProgressPolling(
								bundleID: app.identifier!,
								viewModel: viewModel
							)

							await MainActor.run {
								progressTask = task
							}
						}
					} else if await _installationMethod == 1 {
						let handler = await InstallationProxy(viewModel: viewModel)
						try await handler.install(at: packageUrl, suspend: app.identifier == Bundle.main.bundleIdentifier!)
					}
				} else {
					let package = try await handler.moveToArchive(packageUrl, shouldOpen: !_useShareSheet)
					
					if await !_useShareSheet {
						await MainActor.run {
							dismiss()
						}
					} else {
						if let package {
							await MainActor.run {
								dismiss()
								UIActivityViewController.show(activityItems: [package])
							}
						}
					}
				}
			} catch {
				await progressTask?.cancel()
				
				await MainActor.run {
					UIAlertController.showAlertWithOk(
						title: .localized("Install"),
						message: String(describing: error),
						action: {
							HeartbeatManager.shared.start(true)
							dismiss()
						}
					)
				}
			}
		}
	}
	
	private func startInstallProgressPolling(
		bundleID: String,
		viewModel: InstallerStatusViewModel
	) -> Task<Void, Never> {

		Task.detached(priority: .background) {
			var hasStarted = false
			var lastLogged = -1

			while !Task.isCancelled {
				let rawProgress = await UIApplication.installProgress(for: bundleID) ?? 0.0

				if rawProgress > 0 {
					hasStarted = true
				}

				let progress = await hasStarted
					? _normalizeInstallProgress(rawProgress)
					: 0.0

				let percent = Int(progress * 100)
				if percent != lastLogged, percent % 10 == 0 {
					lastLogged = percent
					Logger.misc.info("Install progress for \(bundleID): \(progress)")
					if hasStarted { BTBLiveLog.log("Installing… \(percent)%") }
				}

				await MainActor.run {
					viewModel.installProgress = progress
				}

				if hasStarted && rawProgress == 0 {
					await MainActor.run {
						viewModel.installProgress = 1.0
						viewModel.status = .completed(.success(()))
					}
					break
				}

				try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms
			}
		}
	}

	// MARK: BetterThanBox: logs and "stuck on Ready" help
	
	private func _openInstallPrompt() {
		if _serverMethod == 0 {
			BTBLiveLog.log("Asking iOS to install (itms-services)", .step)
			UIApplication.shared.open(URL(string: installer.iTunesLink)!)
		} else if _serverMethod == 1 {
			BTBLiveLog.log("Opening install page in Safari", .step)
			_isWebviewPresenting = true
		}
	}
	
	private func _logStatus(_ status: InstallerStatusViewModel.InstallerStatus) {
		let label = InstallerStatusViewModel.label(for: status)
		switch status {
		case .completed(.success):
			BTBLiveLog.shared.add(String.localized("Installed: %@", arguments: app.name ?? ""), .success)
		case .completed(.failure(let error)), .broken(let error):
			BTBLiveLog.shared.add("\(label): \(error.localizedDescription)", .error)
		case .none:
			break
		default:
			BTBLiveLog.shared.add(label, .step)
		}
	}
	
	private func _trackStuck(_ status: InstallerStatusViewModel.InstallerStatus) {
		_stuckTimer?.invalidate()
		_stuckTimer = nil
		_showStuckHint = false
		
		guard case .ready = status, _installationMethod == 0 else { return }
		_stuckTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { _ in
			DispatchQueue.main.async {
				if case .ready = viewModel.status {
					BTBLiveLog.shared.add(String.localized("iOS has not requested the app yet"), .warning)
					_showStuckHint = true
				}
			}
		}
	}
	
	@ViewBuilder
	private func _stuckHint() -> some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(.localized("iOS has not started the install"))
				.font(.subheadline.weight(.semibold))
			Text(
				BTBServerCert.currentIsUsable
					? String.localized("Tap “Install” in the iOS pop-up. If there was no pop-up, try again.")
					: String.localized("The install server certificate has expired. Connect to the internet and try again — a fresh one will be downloaded.")
			)
			.font(.caption)
			.foregroundStyle(.secondary)
			.fixedSize(horizontal: false, vertical: true)
			HStack {
				Button {
					_retry()
				} label: {
					Label(.localized("Try Again"), systemImage: "arrow.clockwise")
						.font(.subheadline.weight(.semibold))
				}
				.buttonStyle(.borderedProminent)
				Spacer()
				Button(.localized("Cancel"), role: .cancel) {
					dismiss()
				}
				.font(.subheadline)
			}
		}
		.padding(14)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		.padding(10)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
	}
	
	private func _retry() {
		_showStuckHint = false
		Task {
			if _serverMethod == 0, !BTBServerCert.currentIsUsable {
				BTBLiveLog.shared.add(String.localized("Downloading a fresh install certificate…"), .step)
				if await BTBServerCert.refreshIfNeeded(force: true) {
					try? installer.reloadTLS()
				}
			}
			_openInstallPrompt()
			_trackStuck(viewModel.status)
		}
	}
	
	private func _normalizeInstallProgress(_ rawProgress: Double) -> Double {
		min(1.0, max(0.0, (rawProgress - 0.6) / 0.3))
	}
}
