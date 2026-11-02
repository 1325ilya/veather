//
//  DownloadButtonView.swift
//  Feather
//
//  Created by samsam on 7/25/25.
//

import SwiftUI
import Combine
import CoreData
import AltSourceKit
import NimbleViews

struct DownloadButtonView: View {
	let sourceURL: URL?
	let source: ASRepository?
	let app: ASRepository.App
	@ObservedObject private var downloadManager = DownloadManager.shared

	@State private var downloadProgress: Double = 0
	@State private var cancellable: AnyCancellable?
	@State private var _inLibrary = false

	var body: some View {
		ZStack {
			if let currentDownload = downloadManager.getDownload(by: app.currentUniqueId) {
				ZStack {
					Circle()
						.trim(from: 0, to: downloadProgress)
						.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
						.rotationEffect(.degrees(-90))
						.frame(width: 31, height: 31)
						.animation(.smooth, value: downloadProgress)

					Image(systemName: downloadProgress >= 0.75 ? "archivebox" : "square.fill")
						.foregroundStyle(.tint)
						.font(.footnote).bold()
				}
				.onTapGesture {
					if downloadProgress <= 0.75 {
						downloadManager.cancelDownload(currentDownload)
					}
				}
				.compatTransition()
			} else {
				Button {
					if let url = app.currentDownloadUrl {
						_ = downloadManager.startDownload(
							from: url,
							id: app.currentUniqueId,
							sourceProvenance: _sourceProvenance()
						)
					}
				} label: {
					Group {
						if _inLibrary {
							Label(.localized("In Library"), systemImage: "checkmark")
								.labelStyle(.titleAndIcon)
								.font(.subheadline.bold())
								.foregroundStyle(.green)
						} else {
							Text(.localized("Get"))
								.font(.headline.bold())
								.foregroundStyle(Color.accentColor)
						}
					}
						.lineLimit(1)
						.padding(.horizontal, _inLibrary ? 14 : 24)
						.padding(.vertical, 6)
						.background(Color(uiColor: .quaternarySystemFill))
						.clipShape(Capsule())
				}
				.buttonStyle(.borderless)
				.compatTransition()
				.accessibilityHint(_inLibrary ? String.localized("Already in your Library. Tap to download again.") : "")
			}
		}
		.onAppear {
			setupObserver()
			_inLibrary = _checkInLibrary()
		}
		.onDisappear { cancellable?.cancel() }
		.onChange(of: downloadManager.downloads.description) { _ in
			setupObserver()
			_inLibrary = _checkInLibrary()
		}
		.animation(.easeInOut(duration: 0.3), value: downloadManager.getDownload(by: app.currentUniqueId) != nil)
	}

	private func setupObserver() {
		cancellable?.cancel()
		guard let download = downloadManager.getDownload(by: app.currentUniqueId) else {
			downloadProgress = 0
			return
		}
		downloadProgress = download.overallProgress

		let publisher = Publishers.CombineLatest(
			download.$progress,
			download.$unpackageProgress
		)

		cancellable = publisher.sink { _, _ in
			downloadProgress = download.overallProgress
		}
	}
	
	/// True when this exact version is already imported or signed.
	private func _checkInLibrary() -> Bool {
		guard let id = app.id, !id.isEmpty else { return false }
		let context = Storage.shared.context
		var format = "identifier == %@"
		var args: [Any] = [id]
		if let version = app.currentVersion, !version.isEmpty {
			format += " AND version == %@"
			args.append(version)
		}
		for entity in ["Imported", "Signed"] {
			let request = NSFetchRequest<NSManagedObject>(entityName: entity)
			request.predicate = NSPredicate(format: format, argumentArray: args)
			request.fetchLimit = 1
			if let count = try? context.count(for: request), count > 0 { return true }
		}
		return false
	}
	
	private func _sourceProvenance() -> SourceAppProvenance? {
		guard let source else { return nil }
		return SourceAppProvenance(sourceURL: sourceURL, repository: source, app: app)
	}
}
