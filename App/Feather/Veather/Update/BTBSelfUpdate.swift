//
//  BTBSelfUpdate.swift
//  Veather
//
//  Self-update (idea: VexSign SelfUpdateManager). CI publishes every build to
//  the `nightly-dev` release with "Build N" in its notes; CFBundleVersion of the
//  app is the same N. A newer build is downloaded into the Library, where it can
//  be signed and installed like any other app.
//

import Foundation
import SwiftUI

enum BTBSelfUpdate {
	static let repo = "1325ilya/veather"
	static let tag = "nightly-dev"
	
	struct Release: Decodable {
		struct Asset: Decodable {
			let name: String
			let browser_download_url: URL
			let size: Int64
		}
		let body: String?
		let published_at: String?
		let assets: [Asset]
		
		var build: Int? {
			guard let body, let range = body.range(of: #"Build (\d+)"#, options: .regularExpression) else { return nil }
			return Int(body[range].dropFirst("Build ".count))
		}
		var ipa: Asset? { assets.first { $0.name.hasSuffix(".ipa") } }
	}
	
	static var currentBuild: Int {
		Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
	}
	
	enum FetchError: LocalizedError {
		case http(Int, String?)
		var errorDescription: String? {
			switch self {
			case .http(403, _): String.localized("GitHub refused the request (rate limit). Try again later.")
			case .http(404, _): String.localized("No release found yet.")
			case .http(let code, let message): String.localized("GitHub answered with HTTP %lld.", arguments: code) + (message.map { "\n\($0)" } ?? "")
			}
		}
	}
	
	private struct GitHubError: Decodable { let message: String? }
	
	static func fetch() async throws -> Release {
		let url = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
		var request = URLRequest(url: url)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
		// GitHub rejects API requests without a User-Agent
		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
		request.setValue("Veather/\(version) (build \(currentBuild))", forHTTPHeaderField: "User-Agent")
		let (data, response) = try await URLSession.shared.data(for: request)
		if let http = response as? HTTPURLResponse, http.statusCode != 200 {
			let message = (try? JSONDecoder().decode(GitHubError.self, from: data))?.message
			throw FetchError.http(http.statusCode, message)
		}
		return try JSONDecoder().decode(Release.self, from: data)
	}
}

struct BTBSelfUpdateView: View {
	@State private var _release: BTBSelfUpdate.Release?
	@State private var _error: String?
	@State private var _loading = false
	@State private var _started = false
	
	var body: some View {
		List {
			Section {
				LabeledContent(.localized("Installed build"), value: "\(BTBSelfUpdate.currentBuild)")
				if let build = _release?.build {
					LabeledContent(.localized("Latest build"), value: "\(build)")
				}
				if _loading { ProgressView() }
				if let _error { Text(_error).foregroundStyle(.red).font(.footnote) }
			}
			
			if let release = _release, let ipa = release.ipa {
				Section {
					if (release.build ?? 0) > BTBSelfUpdate.currentBuild {
						Button {
							_ = DownloadManager.shared.startDownload(from: ipa.browser_download_url)
							_started = true
						} label: {
							Label(String.localized("Download update (%@)", arguments: btbFormatBytes(ipa.size)), systemImage: "arrow.down.circle")
						}
						.disabled(_started)
					} else {
						Label(.localized("You have the latest build"), systemImage: "checkmark.circle")
					}
				} footer: {
					Text(_started
						 ? String.localized("Downloading into the Library. Sign it there and install over the current app (same bundle ID keeps your data).")
						 : String.localized("Updates come from the nightly-dev release on GitHub."))
				}
			}
		}
		.navigationTitle(.localized("Updates"))
		.task { await _check() }
		.refreshable { await _check() }
	}
	
	private func _check() async {
		_loading = true
		defer { _loading = false }
		do {
			_release = try await BTBSelfUpdate.fetch()
			_error = nil
		} catch {
			_error = error.localizedDescription
		}
	}
}
