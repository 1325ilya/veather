//
//  BTBPreflight.swift
//  BetterThanBox
//
//  Checks before signing (ideas: VexSign PreflightChecks, ForgeSign IPA preflight):
//  encrypted (FairPlay) binaries, missing arm64 slice, dead certificate,
//  provisioning profile that does not cover the bundle ID, extension count.
//

import Foundation
import SwiftUI

struct BTBPreflightIssue: Identifiable, Hashable {
	enum Level { case error, warning, info }
	let id = UUID()
	let level: Level
	let title: String
	let detail: String
}

enum BTBPreflight {
	static func run(app: AppInfoPresentable, options: Options, certificate: CertificatePair?) -> [BTBPreflightIssue] {
		var issues: [BTBPreflightIssue] = []
		guard let appURL = Storage.shared.getAppDirectory(for: app) else { return issues }

		if let exec = Bundle(url: appURL)?.executableURL {
			let info = BTBMachOInspector.inspect(exec)
			if info.encrypted {
				issues.append(.init(
					level: .error,
					title: .localized("Encrypted app"),
					detail: .localized("The main binary is still FairPlay-encrypted (App Store copy). After re-signing it will not launch. Use a decrypted IPA.")
				))
			}
			if !info.isMachO {
				issues.append(.init(level: .error, title: .localized("Executable not found"), detail: exec.lastPathComponent))
			} else if !info.hasArm64 {
				issues.append(.init(
					level: .error,
					title: .localized("No arm64 code"),
					detail: .localized("The app has no 64-bit ARM slice and cannot run on this device.")
				))
			}
		}

		let extensions = BTBSigningExtras.machOFiles(in: appURL).filter { $0.path.contains(".appex/") }.count
		if extensions > 0 && !options.btb_removeExtensions {
			issues.append(.init(
				level: .info,
				title: String.localized("%lld app extensions", arguments: extensions),
				detail: .localized("If installation fails with a free/limited certificate, enable \"Remove App Extensions\".")
			))
		}

		if options.signingOption == .default {
			if let cert = certificate {
				if cert.revoked {
					issues.append(.init(level: .error, title: .localized("Certificate revoked"), detail: .localized("Apps signed with it will not open. Choose another certificate.")))
				}
				if let exp = cert.expiration, exp < Date() {
					issues.append(.init(level: .error, title: .localized("Certificate expired"), detail: exp.formatted()))
				} else if let exp = cert.expiration, exp.timeIntervalSinceNow < 3 * 86400 {
					issues.append(.init(level: .warning, title: .localized("Certificate expires soon"), detail: exp.formatted()))
				}
				if
					let decoded = Storage.shared.getProvisionFileDecoded(for: cert),
					let appID = decoded.Entitlements?["application-identifier"]?.value as? String
				{
					let prefix = (decoded.TeamIdentifier.first ?? "") + "."
					let pattern = appID.hasPrefix(prefix) ? String(appID.dropFirst(prefix.count)) : appID
					let bundleID = options.appIdentifier ?? app.identifier ?? ""
					if !pattern.hasSuffix("*") && pattern != bundleID {
						issues.append(.init(
							level: .warning,
							title: .localized("Profile is not a wildcard"),
							detail: String.localized("The profile is for %@, the app will be signed as %@. Set the bundle ID to match or use a wildcard profile.", arguments: pattern, bundleID)
						))
					}
				}
			}
		}
		return issues
	}
}

enum BTBMachOInspector {
	struct Info {
		var isMachO = false
		var hasArm64 = false
		var encrypted = false
	}

	private static let MH_MAGIC_64: UInt32 = 0xfeedfacf
	private static let FAT_MAGIC: UInt32 = 0xcafebabe
	private static let FAT_MAGIC_64: UInt32 = 0xcafebabf
	private static let CPU_TYPE_ARM64: UInt32 = 0x0100000c
	private static let LC_ENCRYPTION_INFO_64: UInt32 = 0x2c

	static func inspect(_ url: URL) -> Info {
		var info = Info()
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 32 else { return info }

		func le32(_ o: Int) -> UInt32 {
			guard o + 4 <= data.count else { return 0 }
			return data.subdata(in: o..<o + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
		}
		func be32(_ o: Int) -> UInt32 {
			guard o + 4 <= data.count else { return 0 }
			return data.subdata(in: o..<o + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
		}
		func be64(_ o: Int) -> UInt64 {
			guard o + 8 <= data.count else { return 0 }
			return data.subdata(in: o..<o + 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.bigEndian
		}

		/// Reads a thin 64-bit Mach-O at `base`.
		func readThin(_ base: Int) {
			guard le32(base) == MH_MAGIC_64 else { return }
			info.isMachO = true
			if le32(base + 4) == CPU_TYPE_ARM64 { info.hasArm64 = true }
			let ncmds = Int(le32(base + 16))
			var offset = base + 32
			for _ in 0..<min(ncmds, 4096) {
				let cmd = le32(offset)
				let size = Int(le32(offset + 4))
				guard size > 0 else { break }
				if cmd == LC_ENCRYPTION_INFO_64, le32(offset + 16) != 0 {
					info.encrypted = true
				}
				offset += size
			}
		}

		let magic = be32(0)
		if magic == FAT_MAGIC || magic == FAT_MAGIC_64 {
			let is64 = magic == FAT_MAGIC_64
			let count = Int(be32(4))
			let archSize = is64 ? 32 : 20
			for i in 0..<min(count, 32) {
				let base = 8 + i * archSize
				let offset = is64 ? Int(be64(base + 8)) : Int(be32(base + 8))
				readThin(offset)
			}
		} else {
			readThin(0)
		}
		return info
	}
}

struct BTBPreflightSection: View {
	let app: AppInfoPresentable
	let options: Options
	let certificate: CertificatePair?
	@State private var _issues: [BTBPreflightIssue] = []
	
	private var _key: String {
		"\(options.appIdentifier ?? "")|\(options.signingOption.rawValue)|\(options.btb_removeExtensions)|\(certificate?.uuid ?? "")"
	}
	
	var body: some View {
		Group {
			if !_issues.isEmpty {
				Section {
					ForEach(_issues) { issue in
						Label {
							VStack(alignment: .leading, spacing: 2) {
								Text(issue.title).font(.subheadline.bold())
								Text(issue.detail).font(.caption).foregroundStyle(.secondary)
							}
						} icon: {
							Image(systemName: _icon(issue.level)).foregroundStyle(_color(issue.level))
						}
					}
				} header: {
					Text(.localized("Preflight"))
				}
			}
		}
		.task(id: _key) {
			// Core Data objects must stay on the main thread; the checks only read headers
			_issues = BTBPreflight.run(app: app, options: options, certificate: certificate)
		}
	}
	
	private func _icon(_ level: BTBPreflightIssue.Level) -> String {
		switch level {
		case .error: "xmark.octagon.fill"
		case .warning: "exclamationmark.triangle.fill"
		case .info: "info.circle.fill"
		}
	}
	
	private func _color(_ level: BTBPreflightIssue.Level) -> Color {
		switch level {
		case .error: .red
		case .warning: .orange
		case .info: .blue
		}
	}
}
