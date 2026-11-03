//
//  BTBBackupManager.swift
//  Veather
//
//  Backup / restore of Veather itself (idea: VexSign BackupManager/BackupCrypto):
//  certificates (+ passwords, nicknames), sources, signing options and settings
//  go into one password-protected .btbbackup (zip) file that can be saved to Files.
//

import Foundation
import CryptoKit
import Zip
import CoreData
import OSLog

enum BTBBackupManager {
	struct Manifest: Codable {
		struct Cert: Codable {
			let folder: String
			let nickname: String?
			let password: String?
		}
		var version = 1
		var created = Date()
		var appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		var certificates: [Cert] = []
		var sources: [String] = []
		/// Our own UserDefaults keys (signing options, appearance, BTB settings)
		var defaults: Data?
	}

	enum BackupError: LocalizedError {
		case invalid
		var errorDescription: String? { .localized("This file is not a Veather backup or the password is wrong.") }
	}

	private static let _defaultsPrefixes = ["signing_options", "Feather.", "feather.", "BTB."]

	/// Runs a block on the main thread and returns its result (directly if already there).
	private static func _onMain<T>(_ work: () -> T) -> T {
		Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
	}

	// MARK: Export

	static func export(password: String) throws -> URL {
		let fm = FileManager.default
		let work = fm.temporaryDirectory.appendingPathComponent("BTBBackup_\(UUID().uuidString)")
		let content = work.appendingPathComponent("VeatherBackup")
		try fm.createDirectory(at: content, withIntermediateDirectories: true)

		var manifest = Manifest()

		let certsDir = content.appendingPathComponent("Certificates")
		try fm.createDirectory(at: certsDir, withIntermediateDirectories: true)
		// Core Data's view context belongs to the main thread: read everything there, work with files here
		let snapshot = Self._onMain { () -> (certs: [(p12: URL, provision: URL, nickname: String?, password: String?)], sources: [String]) in
			let certs = Storage.shared.getAllCertificates().compactMap { cert -> (p12: URL, provision: URL, nickname: String?, password: String?)? in
				guard
					let p12 = Storage.shared.getFile(.certificate, from: cert),
					let provision = Storage.shared.getFile(.provision, from: cert)
				else { return nil }
				return (p12: p12, provision: provision, nickname: cert.nickname, password: cert.password)
			}
			return (certs: certs, sources: Storage.shared.getSources().compactMap { $0.sourceURL?.absoluteString })
		}
		for (index, cert) in snapshot.certs.enumerated() {
			let folder = "cert\(index)"
			let dest = certsDir.appendingPathComponent(folder)
			try fm.createDirectory(at: dest, withIntermediateDirectories: true)
			try fm.copyItem(at: cert.p12, to: dest.appendingPathComponent("cert.p12"))
			try fm.copyItem(at: cert.provision, to: dest.appendingPathComponent("cert.mobileprovision"))
			manifest.certificates.append(.init(folder: folder, nickname: cert.nickname, password: cert.password))
		}

		manifest.sources = snapshot.sources

		let all = UserDefaults.standard.dictionaryRepresentation()
		let ours = all.filter { key, _ in _defaultsPrefixes.contains { key.hasPrefix($0) } }
		manifest.defaults = try? PropertyListSerialization.data(fromPropertyList: ours, format: .binary, options: 0)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted]
		try encoder.encode(manifest).write(to: content.appendingPathComponent("manifest.json"))

		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd_HH-mm"
		let zipURL = work.appendingPathComponent("Veather_\(formatter.string(from: Date())).zip")
		try Zip.zipFiles(
			paths: [content],
			zipFilePath: zipURL,
			password: password.isEmpty ? nil : password,
			compression: .BestCompression,
			progress: nil
		)
		let final = zipURL.deletingPathExtension().appendingPathExtension("btbbackup")
		try fm.moveItem(at: zipURL, to: final)
		try? fm.removeItem(at: content)
		return final
	}

	// MARK: Restore

	struct RestoreResult {
		var certificates = 0
		var sources = 0
		var settings = false
	}

	static func restore(from url: URL, password: String) async throws -> RestoreResult {
		let fm = FileManager.default
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }

		let work = fm.temporaryDirectory.appendingPathComponent("BTBRestore_\(UUID().uuidString)")
		try fm.createDirectory(at: work, withIntermediateDirectories: true)
		defer { try? fm.removeItem(at: work) }

		let zipCopy = work.appendingPathComponent("backup.zip")
		try fm.copyItem(at: url, to: zipCopy)
		do {
			try Zip.unzipFile(zipCopy, destination: work, overwrite: true, password: password.isEmpty ? nil : password, progress: nil)
		} catch {
			throw BackupError.invalid
		}

		// the folder inside the archive is named after the app; older backups use another name
		let content = ((try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)) ?? [])
			.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
			?? work.appendingPathComponent("VeatherBackup")
		guard
			let data = try? Data(contentsOf: content.appendingPathComponent("manifest.json")),
			let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
		else {
			throw BackupError.invalid
		}

		var result = RestoreResult()

		// certificates already in the app are skipped (same .p12 file), so restoring twice does not duplicate them
		let existingHashes = Self._onMain {
			Set(Storage.shared.getAllCertificates().compactMap { Storage.shared.getFile(.certificate, from: $0) }
				.compactMap { try? Data(contentsOf: $0) }
				.map { SHA256.hash(data: $0).description })
		}
		for cert in manifest.certificates {
			let dir = content.appendingPathComponent("Certificates").appendingPathComponent(cert.folder)
			if let p12 = try? Data(contentsOf: dir.appendingPathComponent("cert.p12")),
			   existingHashes.contains(SHA256.hash(data: p12).description) { continue }
			let error: Error? = await withCheckedContinuation { continuation in
				FR.handleCertificateFiles(
					p12URL: dir.appendingPathComponent("cert.p12"),
					provisionURL: dir.appendingPathComponent("cert.mobileprovision"),
					p12Password: cert.password ?? "",
					certificateName: cert.nickname ?? ""
				) { continuation.resume(returning: $0) }
			}
			if error == nil { result.certificates += 1 }
		}

		let existing = Self._onMain { Set(Storage.shared.getSources().compactMap { $0.sourceURL?.absoluteString }) }
		for source in manifest.sources where !existing.contains(source) {
			guard let sourceURL = URL(string: source) else { continue }
			await MainActor.run {
				Storage.shared.addSource(sourceURL, identifier: source) { _ in }
			}
			result.sources += 1
		}

		if
			let defaultsData = manifest.defaults,
			let dict = (try? PropertyListSerialization.propertyList(from: defaultsData, format: nil)) as? [String: Any]
		{
			for (key, value) in dict {
				UserDefaults.standard.set(value, forKey: key)
			}
			result.settings = true
		}

		Logger.misc.info("Restored backup: \(result.certificates) certs, \(result.sources) sources")
		return result
	}
}
