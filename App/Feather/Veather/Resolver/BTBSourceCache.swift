//
//  BTBSourceCache.swift
//  Veather
//
//  Offline source cache with conditional requests (idea: VexSign
//  RepositorySnapshotCache / RepositorySyncEngine). Caches each source's raw
//  JSON + ETag/Last-Modified; sends If-None-Match / If-Modified-Since and on
//  304 or a network error decodes the last-known-good copy.
//

import Foundation
import AltSourceKit
import CryptoKit

enum BTBSourceCache {
	private static var dir: URL {
		let d = URL.applicationSupportDirectory.appendingPathComponent("SourceCache", isDirectory: true)
		try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
		return d
	}

	private struct Meta: Codable { var etag: String?; var lastModified: String?; var date: Date }

	private static func key(_ url: URL) -> String {
		let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
		return hash.map { String(format: "%02x", $0) }.joined()
	}
	private static func dataURL(_ url: URL) -> URL { dir.appendingPathComponent(key(url) + ".json") }
	private static func metaURL(_ url: URL) -> URL { dir.appendingPathComponent(key(url) + ".meta") }

	static func cachedData(for url: URL) -> Data? {
		try? Data(contentsOf: dataURL(url))
	}

	static func cacheDate(for url: URL) -> Date? {
		guard let d = try? Data(contentsOf: metaURL(url)), let m = try? JSONDecoder().decode(Meta.self, from: d) else { return nil }
		return m.date
	}

	/// Fetches a repo, using the cache for conditional requests and offline fallback.
	static func fetch(from url: URL) async -> ASRepository? {
		var request = URLRequest(url: url)
		request.timeoutInterval = 20
		if let metaData = try? Data(contentsOf: metaURL(url)),
		   let meta = try? JSONDecoder().decode(Meta.self, from: metaData) {
			if let etag = meta.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
			if let lm = meta.lastModified { request.setValue(lm, forHTTPHeaderField: "If-Modified-Since") }
		}

		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			let http = response as? HTTPURLResponse
			if http?.statusCode == 304 {
				return _decodeCached(url)
			}
			if let repo = try? JSONDecoder().decode(ASRepository.self, from: data) {
				try? data.write(to: dataURL(url), options: .atomic)
				let meta = Meta(
					etag: http?.value(forHTTPHeaderField: "ETag"),
					lastModified: http?.value(forHTTPHeaderField: "Last-Modified"),
					date: Date()
				)
				if let m = try? JSONEncoder().encode(meta) { try? m.write(to: metaURL(url), options: .atomic) }
				return repo
			}
			// bad body: fall back to cache
			return _decodeCached(url)
		} catch {
			// offline / failure: last-known-good
			return _decodeCached(url)
		}
	}

	private static func _decodeCached(_ url: URL) -> ASRepository? {
		guard let data = cachedData(for: url) else { return nil }
		return try? JSONDecoder().decode(ASRepository.self, from: data)
	}

	static func clear() {
		try? FileManager.default.removeItem(at: dir)
	}
}
