//
//  ArchiveView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import Zip
import NimbleViews

// MARK: - View
struct ArchiveView: View {
	@AppStorage("Feather.compressionLevel") private var _compressionLevel: Int = ZipCompression.DefaultCompression.rawValue
	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("BTB.archive.extension") private var _archiveExtension: String = "ipa"
	@AppStorage("BTB.archive.nameTemplate") private var _nameTemplate: String = "{name}_{version}_{date}"
	
	// MARK: Body
	var body: some View {
		NBList(.localized("Archive & Compression")) {
			Section {
				Picker(.localized("Compression Level"), systemImage: "archivebox", selection: $_compressionLevel) {
					ForEach(ZipCompression.allCases, id: \.rawValue) { level in
						Text(level.label).tag(level)
					}
				}
			}
			
			Section {
				Picker(.localized("File Type"), systemImage: "doc.zipper", selection: $_archiveExtension) {
					Text(verbatim: ".ipa").tag("ipa")
					Text(verbatim: ".tipa (TrollStore)").tag("tipa")
				}
				TextField(.localized("File name"), text: $_nameTemplate)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
			} footer: {
				Text(.localized("Placeholders: {name}, {version}, {bundle}, {date} (yyyy-MM-dd_HH-mm), {timestamp}."))
			}
			
			Section {
				Toggle(.localized("Show Sheet when Exporting"), systemImage: "square.and.arrow.up", isOn: $_useShareSheet)
			} footer: {
				Text(.localized("Toggling show sheet will present a share sheet after exporting to your files."))
			}
		}
	}
}
