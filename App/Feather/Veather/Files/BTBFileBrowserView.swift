//
//  BTBFileBrowserView.swift
//  Veather
//
//  Built-in file manager (ideas: Ksign FilesView, VexSign IPA Explorer):
//  browse Documents or an app bundle, open plist/text/hex editors,
//  QuickLook, share, rename, delete. Protected files cannot be deleted.
//

import SwiftUI
import QuickLook
import NimbleViews

struct BTBFileItem: Identifiable, Hashable {
	let url: URL
	let isDirectory: Bool
	let size: Int64
	let modified: Date?
	var id: URL { url }
	var name: String { url.lastPathComponent }
	
	enum Kind { case folder, plist, text, image, other }
	
	var kind: Kind {
		if isDirectory { return .folder }
		switch url.pathExtension.lowercased() {
		case "plist", "entitlements": return .plist
		case "txt", "json", "xml", "strings", "js", "css", "html", "htm", "md", "log", "sh", "cfg", "conf", "ini", "yml", "yaml", "csv", "storyboard", "xib":
			return .text
		case "png", "jpg", "jpeg", "gif", "heic", "webp", "pdf": return .image
		default: return .other
		}
	}
	
	var systemImage: String {
		switch kind {
		case .folder:
			switch url.pathExtension.lowercased() {
			case "app", "appex": return "app.dashed"
			case "framework", "bundle": return "shippingbox"
			default: return "folder.fill"
			}
		case .plist: return "list.bullet.indent"
		case .text: return "doc.text"
		case .image: return "photo"
		case .other: return "doc"
		}
	}
}

struct BTBFileBrowserView: View {
	let root: URL
	var title: String?
	
	@State private var _items: [BTBFileItem] = []
	@State private var _query = ""
	@State private var _quickLookURL: URL?
	@State private var _renaming: BTBFileItem?
	@State private var _newName = ""
	@State private var _showHidden = false
	
	private var _filtered: [BTBFileItem] {
		_items.filter { _query.isEmpty || $0.name.localizedCaseInsensitiveContains(_query) }
	}
	
	var body: some View {
		List {
			ForEach(_filtered) { item in
				_link(for: item)
					.contextMenu { _menu(for: item) }
					.swipeActions {
						Button(role: .destructive) { _delete(item) } label: {
							Label(.localized("Delete"), systemImage: "trash")
						}
					}
			}
		}
		.navigationTitle(title ?? root.lastPathComponent)
		.navigationBarTitleDisplayMode(.inline)
		.searchable(text: $_query, placement: .platform())
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Toggle(isOn: $_showHidden) { Label(.localized("Show Hidden Files"), systemImage: "eye") }
					Button(.localized("New Folder"), systemImage: "folder.badge.plus") { _newFolder() }
					Button(.localized("Open in Files app"), systemImage: "folder") {
						if let url = root.toSharedDocumentsURL() { UIApplication.open(url) }
					}
				} label: {
					Image(systemName: "ellipsis.circle")
				}
			}
		}
		.overlay {
			if _items.isEmpty { Text(.localized("Empty folder")).foregroundStyle(.secondary) }
		}
		.quickLookPreview($_quickLookURL)
		.alert(.localized("Rename"), isPresented: Binding(get: { _renaming != nil }, set: { if !$0 { _renaming = nil } })) {
			TextField(.localized("Name"), text: $_newName)
			Button(.localized("Cancel"), role: .cancel) { _renaming = nil }
			Button(.localized("Rename")) { _rename() }
		}
		.onAppear(perform: _reload)
		.onChange(of: _showHidden) { _ in _reload() }
		.refreshable { _reload() }
	}
	
	@ViewBuilder
	private func _link(for item: BTBFileItem) -> some View {
		let label = HStack(spacing: 12) {
			Image(systemName: item.systemImage)
				.frame(width: 28)
				.foregroundStyle(item.kind == .folder ? Color.accentColor : .secondary)
			VStack(alignment: .leading, spacing: 2) {
				Text(item.name).lineLimit(1)
				Text(_subtitle(item)).font(.caption).foregroundStyle(.secondary)
			}
		}
		
		switch item.kind {
		case .folder:
			NavigationLink { BTBFileBrowserView(root: item.url) } label: { label }
		case .plist:
			NavigationLink { BTBPlistEditorView(url: item.url) } label: { label }
		case .text:
			NavigationLink { BTBTextEditorView(url: item.url) } label: { label }
		case .image, .other:
			Button { _open(item) } label: { label }
				.foregroundStyle(.primary)
		}
	}
	
	@ViewBuilder
	private func _menu(for item: BTBFileItem) -> some View {
		if !item.isDirectory {
			Button(.localized("Quick Look"), systemImage: "eye") { _quickLookURL = item.url }
			NavigationLink { BTBHexView(url: item.url) } label: {
				Label(.localized("Hex Viewer"), systemImage: "number")
			}
			NavigationLink { BTBTextEditorView(url: item.url) } label: {
				Label(.localized("Open as Text"), systemImage: "doc.text")
			}
			if BTBPlistEditorView.canOpen(item.url) {
				NavigationLink { BTBPlistEditorView(url: item.url) } label: {
					Label(.localized("Open as Plist"), systemImage: "list.bullet.indent")
				}
			}
		}
		Button(.localized("Share"), systemImage: "square.and.arrow.up") { _share(item.url) }
		Button(.localized("Copy Path"), systemImage: "doc.on.doc") { UIPasteboard.general.string = item.url.path }
		Button(.localized("Rename"), systemImage: "pencil") {
			_newName = item.name
			_renaming = item
		}
		Button(role: .destructive) { _delete(item) } label: {
			Label(.localized("Delete"), systemImage: "trash")
		}
	}
	
	private func _subtitle(_ item: BTBFileItem) -> String {
		var parts: [String] = []
		if !item.isDirectory || item.kind != .folder || item.size > 0 {
			parts.append(btbFormatBytes(item.size))
		}
		if let date = item.modified { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
		return parts.joined(separator: " • ")
	}
	
	private func _open(_ item: BTBFileItem) {
		_quickLookURL = item.url
	}
	
	private func _reload() {
		let fm = FileManager.default
		let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
		let options: FileManager.DirectoryEnumerationOptions = _showHidden ? [] : [.skipsHiddenFiles]
		let urls = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: options)) ?? []
		_items = urls.map { url in
			let values = try? url.resourceValues(forKeys: Set(keys))
			let isDir = values?.isDirectory ?? false
			return BTBFileItem(
				url: url,
				isDirectory: isDir,
				size: isDir ? 0 : Int64(values?.totalFileAllocatedSize ?? 0),
				modified: values?.contentModificationDate
			)
		}
		.sorted {
			if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
			return $0.name.localizedStandardCompare($1.name) == .orderedAscending
		}
	}
	
	private func _delete(_ item: BTBFileItem) {
		UIAlertController.showAlertWithCancel(
			title: .localized("Delete"),
			message: item.name,
			actions: [
				UIAlertAction(title: .localized("Delete"), style: .destructive) { _ in
					do {
						try BTBStorageManager.shared.remove(item.url)
					} catch {
						UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
					}
					_reload()
				}
			]
		)
	}
	
	private func _rename() {
		guard let item = _renaming, !_newName.isEmpty, _newName != item.name else { _renaming = nil; return }
		guard !BTBStorageManager.shared.isProtected(item.url) else {
			UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("\"%@\" is protected and was not deleted.", arguments: item.name))
			_renaming = nil
			return
		}
		let dest = item.url.deletingLastPathComponent().appendingPathComponent(_newName)
		do {
			try FileManager.default.moveItem(at: item.url, to: dest)
		} catch {
			UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
		}
		_renaming = nil
		_reload()
	}
	
	private func _newFolder() {
		var url = root.appendingPathComponent(.localized("New Folder"))
		var i = 2
		while FileManager.default.fileExists(atPath: url.path) {
			url = root.appendingPathComponent(.localized("New Folder") + " \(i)")
			i += 1
		}
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		_reload()
	}
	
	private func _share(_ url: URL) {
		let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
		if let top = UIApplication.topViewController() {
			controller.popoverPresentationController?.sourceView = top.view
			top.present(controller, animated: true)
		}
	}
}
