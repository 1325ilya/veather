//
//  BTBBrowserView.swift
//  BetterThanBox
//
//  Built-in browser downloader (ideas: Ksign WebViewSheet/DownloaderView,
//  ABox web-page IPA parsing): taps on .ipa / .tipa or itms-services links
//  go straight to BetterThanBox's download manager; "Find IPA links" lists
//  every IPA link on the current page.
//

import SwiftUI
import UIKit
import WebKit

final class BTBBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
	@Published var address = ""
	@Published var title = ""
	@Published var progress: Double = 0
	@Published var canGoBack = false
	@Published var canGoForward = false
	@Published var foundLinks: [URL] = []
	@Published var lastDownload: String?
	
	let webView: WKWebView
	private var _observers: [NSKeyValueObservation] = []
	
	static let homeKey = "BTB.browser.home"
	
	override init() {
		let config = WKWebViewConfiguration()
		config.websiteDataStore = .default()
		webView = WKWebView(frame: .zero, configuration: config)
		super.init()
		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.allowsBackForwardNavigationGestures = true
		_observers = [
			webView.observe(\.estimatedProgress) { [weak self] wv, _ in DispatchQueue.main.async { self?.progress = wv.estimatedProgress } },
			webView.observe(\.url) { [weak self] wv, _ in DispatchQueue.main.async { self?.address = wv.url?.absoluteString ?? "" } },
			webView.observe(\.title) { [weak self] wv, _ in DispatchQueue.main.async { self?.title = wv.title ?? "" } },
			webView.observe(\.canGoBack) { [weak self] wv, _ in DispatchQueue.main.async { self?.canGoBack = wv.canGoBack } },
			webView.observe(\.canGoForward) { [weak self] wv, _ in DispatchQueue.main.async { self?.canGoForward = wv.canGoForward } }
		]
	}
	
	func go(_ text: String) {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		var url: URL?
		if trimmed.contains(".") && !trimmed.contains(" ") {
			url = URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)")
		}
		if url == nil {
			var comps = URLComponents(string: "https://duckduckgo.com/")!
			comps.queryItems = [URLQueryItem(name: "q", value: trimmed)]
			url = comps.url
		}
		if let url { webView.load(URLRequest(url: url)) }
	}
	
	static func isPackage(_ url: URL) -> Bool {
		["ipa", "tipa"].contains(url.pathExtension.lowercased())
	}
	
	func download(_ url: URL) {
		_ = DownloadManager.shared.startDownload(from: url)
		lastDownload = url.lastPathComponent
	}
	
	/// itms-services://?action=download-manifest&url=<manifest.plist>
	func handleITMS(_ url: URL) {
		guard
			let manifestString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
				.queryItems?.first(where: { $0.name == "url" })?.value,
			let manifestURL = URL(string: manifestString)
		else { return }
		URLSession.shared.dataTask(with: manifestURL) { data, _, _ in
			guard
				let data,
				let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
				let items = plist["items"] as? [[String: Any]],
				let assets = items.first?["assets"] as? [[String: Any]],
				let package = assets.first(where: { ($0["kind"] as? String) == "software-package" }),
				let urlString = package["url"] as? String,
				let ipaURL = URL(string: urlString)
			else { return }
			DispatchQueue.main.async { self.download(ipaURL) }
		}.resume()
	}
	
	func findLinks() {
		let js = """
		Array.from(document.querySelectorAll('a[href]')).map(a => a.href)
		"""
		webView.evaluateJavaScript(js) { [weak self] result, _ in
			let hrefs = (result as? [String]) ?? []
			let urls = hrefs.compactMap(URL.init(string:)).filter {
				BTBBrowserModel.isPackage($0) || $0.scheme == "itms-services"
			}
			DispatchQueue.main.async {
				self?.foundLinks = Array(NSOrderedSet(array: urls)) as? [URL] ?? urls
			}
		}
	}
	
	// MARK: WKNavigationDelegate
	
	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
		guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
		if url.scheme == "itms-services" {
			handleITMS(url)
			return decisionHandler(.cancel)
		}
		if Self.isPackage(url) {
			download(url)
			return decisionHandler(.cancel)
		}
		if let scheme = url.scheme, !["http", "https", "about", "data", "blob"].contains(scheme) {
			UIApplication.shared.open(url)
			return decisionHandler(.cancel)
		}
		decisionHandler(.allow)
	}
	
	func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
		// servers that hide the .ipa behind a redirect or a Content-Disposition header
		if
			let response = navigationResponse.response as? HTTPURLResponse,
			let url = response.url
		{
			let disposition = (response.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
			if disposition.contains(".ipa") || disposition.contains(".tipa") || Self.isPackage(url) {
				download(url)
				return decisionHandler(.cancel)
			}
		}
		decisionHandler(.allow)
	}
	
	// open target=_blank links in the same view
	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
		return nil
	}
}

struct BTBWebView: UIViewRepresentable {
	let webView: WKWebView
	func makeUIView(context: Context) -> WKWebView { webView }
	func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BTBBrowserView: View {
	@StateObject private var _model = BTBBrowserModel()
	@State private var _field = ""
	@State private var _showLinks = false
	@AppStorage(BTBBrowserModel.homeKey) private var _home = ""
	@FocusState private var _focused: Bool
	
	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				TextField(.localized("Address or search"), text: $_field)
					.textFieldStyle(.roundedBorder)
					.keyboardType(.webSearch)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.focused($_focused)
					.onSubmit { _model.go(_field) }
				if _model.progress < 1 && _model.progress > 0 {
					ProgressView(value: _model.progress).frame(width: 40)
				}
			}
			.padding(.horizontal)
			.padding(.top, 8)
			
			HStack(spacing: 22) {
				Button { _model.webView.goBack() } label: { Image(systemName: "chevron.left") }
					.disabled(!_model.canGoBack)
				Button { _model.webView.goForward() } label: { Image(systemName: "chevron.right") }
					.disabled(!_model.canGoForward)
				Button { _model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
				Spacer()
				Button {
					_model.findLinks()
					_showLinks = true
				} label: {
					Label(.localized("Find IPA links"), systemImage: "doc.viewfinder")
						.font(.subheadline)
				}
			}
			.buttonStyle(.borderless)
			.padding(.horizontal)
			.padding(.vertical, 8)
			
			BTBWebView(webView: _model.webView)
			
			if let name = _model.lastDownload {
				Label(String.localized("Downloading %@ into the Library", arguments: name), systemImage: "arrow.down.circle")
					.font(.footnote)
					.padding(8)
					.frame(maxWidth: .infinity)
					.background(.thinMaterial)
					.onTapGesture { _model.lastDownload = nil }
			}
		}
		.navigationTitle(_model.title.isEmpty ? String.localized("Browser") : _model.title)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Button(.localized("Set as Home Page"), systemImage: "house") { _home = _model.address }
					Button(.localized("Copy Address"), systemImage: "doc.on.doc") { UIPasteboard.general.string = _model.address }
				} label: {
					Image(systemName: "ellipsis.circle")
				}
			}
		}
		.sheet(isPresented: $_showLinks) {
			NavigationStack {
				List {
					if _model.foundLinks.isEmpty {
						Text(.localized("No IPA links on this page.")).foregroundStyle(.secondary)
					}
					ForEach(_model.foundLinks, id: \.self) { url in
						Button {
							if url.scheme == "itms-services" { _model.handleITMS(url) } else { _model.download(url) }
							_showLinks = false
						} label: {
							VStack(alignment: .leading) {
								Text(url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent).lineLimit(1)
								Text(url.host ?? url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
							}
						}
					}
				}
				.navigationTitle(.localized("IPA links"))
				.navigationBarTitleDisplayMode(.inline)
			}
			.presentationDetents([.medium, .large])
		}
		.onReceive(_model.$address) { if !_focused { _field = $0 } }
		.onAppear {
			if _model.webView.url == nil, !_home.isEmpty { _model.go(_home) }
			else if _model.webView.url == nil { _focused = true }
		}
	}
}
