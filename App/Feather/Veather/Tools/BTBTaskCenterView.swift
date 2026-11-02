//
//  BTBTaskCenterView.swift
//  Veather
//
//  Task Center (idea: VexSign UnifiedTaskCenter): one screen with every
//  active download and its progress; cancel or retry from here.
//

import SwiftUI
import Combine
import NimbleViews

struct BTBTaskCenterView: View {
	@ObservedObject private var _dm = DownloadManager.shared

	var body: some View {
		List {
			if _dm.downloads.isEmpty {
				Section { Text(.localized("No active tasks.")).foregroundStyle(.secondary) }
			}
			ForEach(_dm.downloads) { download in
				BTBTaskRow(download: download)
			}
		}
		.navigationTitle(.localized("Task Center"))
	}
}

private struct BTBTaskRow: View {
	@ObservedObject var download: Download
	@State private var progress: Double = 0
	@State private var failed = false
	@State private var cancellable: AnyCancellable?

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(download.fileName).font(.subheadline).lineLimit(1)
			if failed {
				HStack {
					Text(.localized("Download failed")).foregroundStyle(.red).font(.caption)
					Spacer()
					Button(.localized("Retry")) { DownloadManager.shared.retryDownload(download) }.buttonStyle(.borderless)
					Button(.localized("Cancel"), role: .destructive) { DownloadManager.shared.cancelDownload(download) }.buttonStyle(.borderless)
				}
			} else {
				ProgressView(value: progress)
				HStack {
					Text(verbatim: "\(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
					Spacer()
					Button(.localized("Cancel"), systemImage: "xmark.circle") {
						DownloadManager.shared.cancelDownload(download)
					}
					.labelStyle(.iconOnly).buttonStyle(.borderless)
				}
			}
		}
		.onAppear {
			progress = download.overallProgress
			failed = download.failed
			cancellable = Publishers.CombineLatest3(download.$progress, download.$unpackageProgress, download.$failed)
				.sink { _, _, f in
					progress = download.overallProgress
					failed = f
				}
		}
		.onDisappear { cancellable?.cancel() }
	}
}
