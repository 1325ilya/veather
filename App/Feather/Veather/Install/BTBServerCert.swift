//
//  BTBServerCert.swift
//  Veather
//
//  The on-device install server needs a publicly trusted TLS certificate for
//  a domain that resolves to 127.0.0.1, otherwise iOS silently refuses the
//  itms-services manifest and the install sheet hangs on "Ready".
//  The certificate bundled at build time expires every ~90 days, so we keep a
//  fresh copy in Application Support and pick whichever one is still valid.
//

import Foundation
import NIOSSL

enum BTBServerCert {
	/// One provider of a "localhost" wildcard certificate with a public key.
	private struct Provider {
		let name: String
		let fetch: () async throws -> (crt: String, key: String, host: String)
	}

	private static let _providers: [Provider] = [
		Provider(name: "local-ip.sh") {
			let crt = try await _string("https://local-ip.sh/server.pem")
			let key = try await _string("https://local-ip.sh/server.key")
			return (crt, key, "127-0-0-1.local-ip.sh")
		},
		Provider(name: "backloop.dev") {
			let data = try await _data("https://backloop.dev/pack.json")
			guard
				let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
				let crt = json["cert"] as? String,
				let key1 = json["key1"] as? String
			else {
				throw URLError(.cannotParseResponse)
			}
			let key2 = json["key2"] as? String ?? ""
			return (crt, key1 + "\n" + key2, "local.backloop.dev")
		}
	]

	static var directory: URL {
		URL.applicationSupportDirectory.appendingPathComponent("BTBServerCert", isDirectory: true)
	}

	private static var _crtURL: URL { directory.appendingPathComponent("server.crt") }
	private static var _keyURL: URL { directory.appendingPathComponent("server.pem") }
	private static var _hostURL: URL { directory.appendingPathComponent("commonName.txt") }

	// MARK: Expiry

	static func expiry(ofPEMFile url: URL) -> Date? {
		guard let first = try? NIOSSLCertificate.fromPEMFile(url.path).first else { return nil }
		return Date(timeIntervalSince1970: TimeInterval(first.notValidAfter))
	}

	static func expiry(ofPEM pem: String) -> Date? {
		guard let first = try? NIOSSLCertificate.fromPEMBytes(Array(pem.utf8)).first else { return nil }
		return Date(timeIntervalSince1970: TimeInterval(first.notValidAfter))
	}

	/// True when the certificate file exists and is valid for at least `margin` more seconds.
	static func isUsable(_ url: URL?, margin: TimeInterval = 3600) -> Bool {
		guard let url, let date = expiry(ofPEMFile: url) else { return false }
		return date.timeIntervalSinceNow > margin
	}

	/// Expiry of the certificate the install server would use right now.
	static var currentExpiry: Date? {
		ServerInstaller.getUrl("server", ext: "crt").flatMap { expiry(ofPEMFile: $0) }
	}

	static var currentIsUsable: Bool {
		isUsable(ServerInstaller.getUrl("server", ext: "crt"))
	}

	/// Called from `ServerInstaller.getUrl`: the cached file wins while its certificate is valid.
	static func cachedURL(name: String, ext: String) -> URL? {
		guard isUsable(_crtURL) else { return nil }
		// a certificate and key from two different downloads (interrupted save) would stop the TLS server
		guard
			let crt = try? String(contentsOf: _crtURL, encoding: .utf8),
			let key = try? String(contentsOf: _keyURL, encoding: .utf8),
			_keyMatches(crt: crt, key: key)
		else { return nil }
		let url = directory.appendingPathComponent("\(name).\(ext)")
		return FileManager.default.fileExists(atPath: url.path) ? url : nil
	}

	// MARK: Refresh

	private static let _lock = NSLock()
	nonisolated(unsafe) private static var _running: Task<Bool, Never>?

	/// Downloads a fresh certificate when the current one expires within two days.
	/// Returns true when a new certificate was installed.
	@discardableResult
	static func refreshIfNeeded(force: Bool = false) async -> Bool {
		if !force, let date = currentExpiry, date.timeIntervalSinceNow > 2 * 86400 {
			return false
		}

		// a refresh already running (started at launch): wait for it instead of answering "nothing new",
		// so the caller reloads the TLS server with the certificate that arrives
		_lock.lock()
		if let running = _running { _lock.unlock(); return await running.value }
		let task = Task { await _refresh(force: force) }
		_running = task
		_lock.unlock()
		let result = await task.value
		_lock.lock(); _running = nil; _lock.unlock()
		return result
	}

	private static func _refresh(force: Bool) async -> Bool {
		var best: (crt: String, key: String, host: String, expiry: Date, name: String)?
		for provider in _providers {
			do {
				let result = try await provider.fetch()
				guard
					let date = expiry(ofPEM: result.crt),
					date.timeIntervalSinceNow > 86400,
					_keyMatches(crt: result.crt, key: result.key)
				else {
					BTBLiveLog.log("Install certificate from \(provider.name) is expired or invalid", .warning)
					continue
				}
				if best == nil || date > best!.expiry {
					best = (result.crt, result.key, result.host, date, provider.name)
				}
			} catch {
				BTBLiveLog.log("Could not fetch install certificate from \(provider.name): \(error.localizedDescription)", .warning)
			}
		}

		guard let best else { return false }

		// don't replace a cached certificate that lives longer
		if !force, let current = currentExpiry, current >= best.expiry {
			return false
		}

		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			// the certificate goes last: it is what marks the cache as usable
			try best.key.write(to: _keyURL, atomically: true, encoding: .utf8)
			try best.host.write(to: _hostURL, atomically: true, encoding: .utf8)
			try best.crt.write(to: _crtURL, atomically: true, encoding: .utf8)
			BTBLiveLog.log("Install certificate updated (\(best.name), valid until \(best.expiry.formatted(date: .abbreviated, time: .omitted)))", .success)
			return true
		} catch {
			BTBLiveLog.log("Could not save install certificate: \(error.localizedDescription)", .error)
			return false
		}
	}

	private static func _keyMatches(crt: String, key: String) -> Bool {
		do {
			let chain = try NIOSSLCertificate.fromPEMBytes(Array(crt.utf8))
			let privateKey = try NIOSSLPrivateKey(bytes: Array(key.utf8), format: .pem)
			let config = TLSConfiguration.makeServerConfiguration(
				certificateChain: chain.map { .certificate($0) },
				privateKey: .privateKey(privateKey)
			)
			_ = try NIOSSLContext(configuration: config)
			return true
		} catch {
			return false
		}
	}

	private static func _data(_ string: String) async throws -> Data {
		guard let url = URL(string: string) else { throw URLError(.badURL) }
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
		request.setValue("Veather", forHTTPHeaderField: "User-Agent")
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw URLError(.badServerResponse)
		}
		return data
	}

	private static func _string(_ url: String) async throws -> String {
		String(decoding: try await _data(url), as: UTF8.self)
	}
}
