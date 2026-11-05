//
//  BTBUpdater.swift
//  Veather
//
//  "Veather Updater": a tiny mode of the same binary that only updates Veather.
//
//  Veather side (BTBUpdaterLauncher): downloads Veather-Updater.ipa from the
//  nightly-dev release, drops the user's certificates and the installed build /
//  bundle id into the app bundle, signs it and offers the install. The Updater
//  never stays in the Library: its Library entries are removed on the next launch.
//
//  Updater side (BTBUpdaterView): the CI builds Veather-Updater.ipa from Veather.ipa
//  by changing the bundle id and adding BTBUpdaterMode = true to Info.plist. In that
//  mode the app shows one screen with "Check for updates" / "Install new version",
//  signs the new Veather with the chosen certificate and installs it over the old one.
//

// micro-update marker (build bump to test the updater)
import CoreData
import SwiftUI
import UIKit

// MARK: - Shared

enum BTBUpdaterMode {
	/// true in the Veather-Updater build (Info.plist key added by CI)
	static var isActive: Bool {
		Bundle.main.object(forInfoDictionaryKey: "BTBUpdaterMode") as? Bool ?? false
	}

	struct Config: Codable {
		/// changes on every launch of the updater from Veather: tells when to re-import certificates
		var stamp: String
		/// build number of the Veather that created the updater
		var installedBuild: Int
		/// bundle id the installed Veather has (may be changed by signing options)
		var bundleID: String
	}

	static let configName = "BTBUpdaterConfig.json"
	static let assetsName = "BTBUpdaterCerts"
	static let stampKey = "BTB.updater.certStamp"
	static let tempKey = "BTB.updater.tempUUIDs"
	static let installedCompletedNotification = Notification.Name("Veather.installCompleted")

	static var config: Config? {
		guard
			let url = Bundle.main.url(forResource: "BTBUpdaterConfig", withExtension: "json"),
			let data = try? Data(contentsOf: url)
		else { return nil }
		return try? JSONDecoder().decode(Config.self, from: data)
	}

	/// Updater only: copy the certificates the bundle carries into its own storage (once per stamp).
	static func importBundledCertificates() {
		guard
			let config,
			UserDefaults.standard.string(forKey: stampKey) != config.stamp,
			let root = Bundle.main.url(forResource: assetsName, withExtension: nil),
			let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
		else { return }

		for cert in Storage.shared.getAllCertificates() {
			Storage.shared.deleteCertificate(for: cert)
		}

		for folder in folders where folder.hasDirectoryPath {
			let p12 = folder.appendingPathComponent("cert.p12")
			let provision = folder.appendingPathComponent("cert.mobileprovision")
			let passwordFile = folder.appendingPathComponent("cert.txt")
			guard
				let password = try? String(contentsOf: passwordFile, encoding: .utf8),
				FileManager.default.fileExists(atPath: p12.path),
				FileManager.default.fileExists(atPath: provision.path)
			else { continue }
			let name = (try? String(contentsOf: folder.appendingPathComponent("name.txt"), encoding: .utf8)) ?? ""
			FR.handleCertificateFiles(
				p12URL: p12,
				provisionURL: provision,
				p12Password: password,
				certificateName: name
			) { _ in }
		}
		UserDefaults.standard.set(config.stamp, forKey: stampKey)
	}

	// MARK: Temporary Library entries

	static func rememberTemp(_ uuid: String?) {
		guard let uuid else { return }
		var list = UserDefaults.standard.stringArray(forKey: tempKey) ?? []
		list.append(uuid)
		UserDefaults.standard.set(list, forKey: tempKey)
	}

	/// Removes the Updater's Library entries (imported + signed) left from the previous run.
	static func cleanupTemp() {
		guard let ids = UserDefaults.standard.stringArray(forKey: tempKey), !ids.isEmpty else { return }
		let context = Storage.shared.context
		for entity in ["Imported", "Signed"] {
			let request = NSFetchRequest<NSManagedObject>(entityName: entity)
			request.predicate = NSPredicate(format: "uuid IN %@", ids)
			for object in (try? context.fetch(request)) ?? [] {
				if let app = object as? AppInfoPresentable {
					Storage.shared.deleteApp(for: app)
				}
			}
		}
		UserDefaults.standard.removeObject(forKey: tempKey)
	}

	// MARK: Shared steps

	static func latest<T: NSManagedObject>(_ type: T.Type, entity: String) -> T? {
		let request = NSFetchRequest<T>(entityName: entity)
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		request.fetchLimit = 1
		return try? Storage.shared.context.fetch(request).first
	}

	struct StepError: LocalizedError {
		let message: String
		var errorDescription: String? { message }
	}

	/// Downloads an .ipa to a temp file and imports it into the Library.
	@MainActor
	static func downloadAndImport(_ url: URL) async throws -> Imported {
		let (tmp, response) = try await URLSession.shared.download(from: url)
		if let http = response as? HTTPURLResponse, http.statusCode != 200 {
			throw StepError(message: String.localized("Download failed (HTTP %lld)", arguments: http.statusCode))
		}
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BTBUpdater-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		let ipa = dir.appendingPathComponent(url.lastPathComponent.hasSuffix(".ipa") ? url.lastPathComponent : "update.ipa")
		try FileManager.default.moveItem(at: tmp, to: ipa)
		defer { try? FileManager.default.removeItem(at: dir) }

		let error: Error? = await withCheckedContinuation { continuation in
			FR.handlePackageFile(ipa) { continuation.resume(returning: $0) }
		}
		if let error { throw error }
		guard let imported = latest(Imported.self, entity: "Imported") else {
			throw StepError(message: String.localized("The downloaded file could not be imported."))
		}
		rememberTemp(imported.uuid)
		return imported
	}

	/// Signs an imported app with default options (no user tweaks / renames) and returns the signed entry.
	@MainActor
	static func sign(_ app: Imported, certificate: CertificatePair, bundleID: String?) async throws -> Signed {
		var options = Options.defaultOptions
		options.ppqString = OptionsManager.shared.options.ppqString
		if let bundleID {
			options.appIdentifier = bundleID
		}
		let error: Error? = await withCheckedContinuation { continuation in
			FR.signPackageFile(app, using: options, icon: nil, certificate: certificate) {
				continuation.resume(returning: $0)
			}
		}
		if let error { throw error }
		guard let signed = latest(Signed.self, entity: "Signed") else {
			throw StepError(message: String.localized("The signed app was not found."))
		}
		rememberTemp(signed.uuid)
		return signed
	}
}

// MARK: - Veather side

@MainActor
final class BTBUpdaterLauncher: ObservableObject {
	enum Phase: Equatable {
		case idle
		case working(String)
		case failed(String)
	}

	@Published var phase: Phase = .idle
	@Published var installApp: AnyApp?

	var isWorking: Bool {
		if case .working = phase { return true }
		return false
	}

	func start(_ release: BTBSelfUpdate.Release) {
		guard !isWorking else { return }
		guard let asset = release.updaterIPA else {
			phase = .failed(String.localized("This release has no Updater package yet. Wait for the next build."))
			return
		}
		Task {
			do {
				BTBUpdaterMode.cleanupTemp()
				let certificates = Storage.shared.getAllCertificates().filter { !$0.revoked }
				guard !certificates.isEmpty else {
					throw BTBUpdaterMode.StepError(message: String.localized("Please go to settings and import a valid certificate"))
				}
				let selected = UserDefaults.standard.integer(forKey: "feather.selectedCert")
				let signingCert = Storage.shared.getCertificate(for: selected).flatMap { $0.revoked ? nil : $0 } ?? certificates[0]

				phase = .working(String.localized("Downloading Updater…"))
				let imported = try await BTBUpdaterMode.downloadAndImport(asset.browser_download_url)

				phase = .working(String.localized("Preparing Updater…"))
				try _inject(into: imported, certificates: certificates)

				phase = .working(String.localized("Signing Updater…"))
				var bundleID: String?
				if OptionsManager.shared.options.ppqProtection, signingCert.ppQCheck == true, let id = imported.identifier {
					bundleID = "\(id).\(OptionsManager.shared.options.ppqString)"
				}
				let signed = try await BTBUpdaterMode.sign(imported, certificate: signingCert, bundleID: bundleID)

				phase = .idle
				installApp = AnyApp(base: signed)
			} catch {
				phase = .failed(error.localizedDescription)
			}
		}
	}

	private func _inject(into app: Imported, certificates: [CertificatePair]) throws {
		guard let appURL = Storage.shared.getAppDirectory(for: app) else {
			throw BTBUpdaterMode.StepError(message: String.localized("The downloaded file could not be imported."))
		}
		let fm = FileManager.default
		let root = appURL.appendingPathComponent(BTBUpdaterMode.assetsName, isDirectory: true)
		try? fm.removeItem(at: root)
		try fm.createDirectory(at: root, withIntermediateDirectories: true)

		for cert in certificates {
			guard
				let p12 = Storage.shared.getFile(.certificate, from: cert),
				let provision = Storage.shared.getFile(.provision, from: cert)
			else { continue }
			let folder = root.appendingPathComponent(cert.uuid ?? UUID().uuidString, isDirectory: true)
			try fm.createDirectory(at: folder, withIntermediateDirectories: true)
			try fm.copyItem(at: p12, to: folder.appendingPathComponent("cert.p12"))
			try fm.copyItem(at: provision, to: folder.appendingPathComponent("cert.mobileprovision"))
			try (cert.password ?? "").write(to: folder.appendingPathComponent("cert.txt"), atomically: true, encoding: .utf8)
			try (cert.nickname ?? "").write(to: folder.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)
		}

		let config = BTBUpdaterMode.Config(
			stamp: UUID().uuidString,
			installedBuild: BTBSelfUpdate.currentBuild,
			bundleID: Bundle.main.bundleIdentifier ?? "com.veather.app"
		)
		try JSONEncoder().encode(config).write(to: appURL.appendingPathComponent(BTBUpdaterMode.configName))
	}
}

// MARK: - Updater side

struct BTBUpdaterView: View {
	private enum Phase: Equatable {
		case idle
		case checking
		case upToDate
		case available(Int)
		case working(String)
		case failed(String)
		case finished
	}

	@State private var _phase: Phase = .idle
	@State private var _release: BTBSelfUpdate.Release?
	@State private var _certificates: [CertificatePair] = []
	@State private var _installApp: AnyApp?
	@AppStorage("feather.selectedCert") private var _selectedCert = 0

	private let _config = BTBUpdaterMode.config

	private var _installedBuild: Int {
		let stored = UserDefaults.standard.integer(forKey: "BTB.updater.installed.\(_config?.stamp ?? "")")
		return max(_config?.installedBuild ?? 0, stored)
	}

	var body: some View {
		VStack(spacing: 22) {
			Spacer()
			Image(systemName: "arrow.down.app.fill")
				.font(.system(size: 64))
				.foregroundStyle(.tint)
			Text(verbatim: "Veather Updater").font(.title2.bold())

			if _config == nil {
				Text(.localized("Open this app from Veather → Settings → Updates."))
					.multilineTextAlignment(.center)
					.foregroundStyle(.secondary)
			} else {
				Text(String.localized("Installed build: %lld", arguments: _installedBuild))
					.foregroundStyle(.secondary)
				_status()
				if _certificates.count > 1 {
					Picker(String.localized("Certificate"), selection: $_selectedCert) {
						ForEach(Array(_certificates.enumerated()), id: \.offset) { index, cert in
							Text(cert.nickname ?? cert.uuid ?? "?").tag(index)
						}
					}
					.pickerStyle(.menu)
				}
				_buttons()
			}
			Spacer()
		}
		.padding(28)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.sheet(item: $_installApp) { app in
			InstallPreviewView(app: app.base)
				.presentationDetents([.height(200)])
				.presentationDragIndicator(.visible)
		}
		.onAppear { _reloadCertificates() }
		.onReceive(NotificationCenter.default.publisher(for: BTBUpdaterMode.installedCompletedNotification)) { _ in
			_installCompleted()
		}
	}

	@ViewBuilder
	private func _status() -> some View {
		switch _phase {
		case .idle:
			EmptyView()
		case .checking:
			ProgressView()
		case .upToDate:
			Label(.localized("You have the latest version"), systemImage: "checkmark.circle.fill")
				.foregroundStyle(.green)
		case .available(let build):
			Label(String.localized("New build available: %lld", arguments: build), systemImage: "sparkles")
		case .working(let text):
			VStack(spacing: 8) {
				ProgressView()
				Text(text).font(.footnote).foregroundStyle(.secondary)
			}
		case .failed(let message):
			Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
		case .finished:
			Label(.localized("Installing… Veather will open when it is done"), systemImage: "checkmark.circle")
		}
	}

	@ViewBuilder
	private func _buttons() -> some View {
		switch _phase {
		case .available:
			Button {
				_install()
			} label: {
				Text(.localized("Install new version")).frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
		case .checking, .working:
			EmptyView()
		default:
			Button {
				_check()
			} label: {
				Text(.localized("Check for updates")).frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
		}
	}

	private func _reloadCertificates() {
		// certificates are imported in the background on the first launch
		_certificates = Storage.shared.getAllCertificates()
		if _certificates.isEmpty {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				_certificates = Storage.shared.getAllCertificates()
			}
		}
	}

	private func _check() {
		_phase = .checking
		Task {
			do {
				let release = try await BTBSelfUpdate.fetch()
				_release = release
				if let build = release.build, build > _installedBuild, release.ipa != nil {
					_phase = .available(build)
				} else {
					_phase = .upToDate
				}
			} catch {
				_phase = .failed(error.localizedDescription)
			}
		}
	}

	private func _install() {
		guard let ipa = _release?.ipa else { return }
		_reloadCertificates()
		let usable = _certificates.filter { !$0.revoked }
		guard !usable.isEmpty else {
			_phase = .failed(String.localized("Please go to settings and import a valid certificate"))
			return
		}
		let chosen = Storage.shared.getCertificate(for: _selectedCert).flatMap { $0.revoked ? nil : $0 } ?? usable[0]
		Task {
			do {
				BTBUpdaterMode.cleanupTemp()
				_phase = .working(String.localized("Downloading Veather…"))
				let imported = try await BTBUpdaterMode.downloadAndImport(ipa.browser_download_url)
				_phase = .working(String.localized("Signing Veather…"))
				let signed = try await BTBUpdaterMode.sign(imported, certificate: chosen, bundleID: _config?.bundleID)
				_phase = .finished
				_installApp = AnyApp(base: signed)
			} catch {
				_phase = .failed(error.localizedDescription)
			}
		}
	}

	private func _installCompleted() {
		if let build = _release?.build {
			UserDefaults.standard.set(build, forKey: "BTB.updater.installed.\(_config?.stamp ?? "")")
		}
		_installApp = nil
		// give iOS a moment to finish replacing the app, then open it
		DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
			if let url = URL(string: "veather://") {
				UIApplication.shared.open(url)
			}
		}
	}
}
