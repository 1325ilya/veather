//
//  BTBStorageView.swift
//  Veather
//

import SwiftUI
import NimbleViews

struct BTBStorageView: View {
	@State private var _sizes: [BTBStorageCategory: Int64] = [:]
	@State private var _protectedSize: Int64 = 0
	@State private var _isLoading = true
	
	@AppStorage(BTBStorageManager.autoCleanArchivesDaysKey) private var _archivesDays = 0
	@AppStorage(BTBStorageManager.sizeLimitKey) private var _sizeLimitMB = 0
	
	private var _total: Int64 { _sizes.values.reduce(0, +) }
	
	var body: some View {
		List {
			Section {
				HStack {
					VStack(alignment: .leading) {
						Text(.localized("Can be freed"))
							.font(.subheadline).foregroundStyle(.secondary)
						Text(btbFormatBytes(_total)).font(.title.bold())
					}
					Spacer()
					if _isLoading { ProgressView() }
				}
				BTBStorageBar(sizes: _sizes)
					.frame(height: 10)
			}
			
			NBSection(.localized("Categories")) {
				ForEach(BTBStorageCategory.allCases) { category in
					NavigationLink {
						BTBStorageCategoryView(category: category) { _reload() }
					} label: {
						HStack {
							Label(category.title, systemImage: category.systemImage)
							Spacer()
							Text(btbFormatBytes(_sizes[category] ?? 0))
								.foregroundStyle(.secondary)
						}
					}
				}
			}
			
			NBSection(.localized("Protected")) {
				HStack {
					Label(.localized("Certificates, sources, settings"), systemImage: "lock.shield")
					Spacer()
					Text(btbFormatBytes(_protectedSize)).foregroundStyle(.secondary)
				}
			} footer: {
				Text(.localized("Certificates (.p12, .mobileprovision and passwords), the list of sources, the library database and settings are never deleted by cleaning. This is enforced in code."))
			}
			
			NBSection(.localized("Auto Clean")) {
				Picker(selection: $_archivesDays) {
					Text(.localized("Never")).tag(0)
					Text(.localized("After 1 day")).tag(1)
					Text(.localized("After 7 days")).tag(7)
					Text(.localized("After 30 days")).tag(30)
				} label: {
					Label(.localized("Delete exported IPAs"), systemImage: "archivebox")
				}
				Picker(selection: $_sizeLimitMB) {
					Text(.localized("No limit")).tag(0)
					Text("1 GB").tag(1024)
					Text("2 GB").tag(2048)
					Text("5 GB").tag(5120)
					Text("10 GB").tag(10240)
				} label: {
					Label(.localized("Storage limit"), systemImage: "gauge.with.dots.needle.67percent")
				}
			} footer: {
				Text(.localized("Rules run when the app starts. Temporary files are always cleared on launch. The storage limit removes the oldest temporary files and exported IPAs first; library apps are never removed automatically."))
			}
			
			Section {
				Button(role: .destructive) {
					_confirm(title: .localized("Clean Everything"), size: _total) {
						for category in BTBStorageCategory.allCases {
							BTBStorageManager.shared.clean(category)
						}
					}
				} label: {
					Label(.localized("Clean Everything Except Protected"), systemImage: "sparkles")
				}
			}
		}
		.navigationTitle(.localized("Storage"))
		.onAppear(perform: _reload)
		.refreshable { _reload() }
	}
	
	private func _reload() {
		_isLoading = true
		DispatchQueue.global(qos: .userInitiated).async {
			let manager = BTBStorageManager.shared
			var result: [BTBStorageCategory: Int64] = [:]
			for category in BTBStorageCategory.allCases {
				result[category] = manager.size(of: category)
			}
			let protected = manager.size(of: FileManager.default.certificates)
				+ manager.size(of: URL.applicationSupportDirectory)
			DispatchQueue.main.async {
				_sizes = result
				_protectedSize = protected
				_isLoading = false
			}
		}
	}
	
	private func _confirm(title: String, size: Int64, action: @escaping () -> Void) {
		UIAlertController.showAlertWithCancel(
			title: title,
			message: String.localized("%@ will be freed. Certificates, sources and settings are kept.", arguments: btbFormatBytes(size)),
			actions: [
				UIAlertAction(title: .localized("Delete"), style: .destructive) { _ in
					action()
					_reload()
				}
			]
		)
	}
}

func btbFormatBytes(_ bytes: Int64) -> String {
	ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct BTBStorageBar: View {
	let sizes: [BTBStorageCategory: Int64]
	private let _colors: [BTBStorageCategory: Color] = [
		.imported: .blue, .signed: .green, .archives: .orange,
		.temporary: .purple, .networkCache: .pink, .other: .gray
	]
	
	var body: some View {
		GeometryReader { geo in
			let total = max(sizes.values.reduce(0, +), 1)
			HStack(spacing: 1) {
				ForEach(BTBStorageCategory.allCases) { c in
					let value = sizes[c] ?? 0
					if value > 0 {
						Rectangle()
							.fill(_colors[c] ?? .gray)
							.frame(width: max(2, geo.size.width * CGFloat(value) / CGFloat(total)))
					}
				}
				Spacer(minLength: 0)
			}
			.clipShape(Capsule())
			.background(Capsule().fill(Color(.quaternarySystemFill)))
		}
	}
}

struct BTBStorageCategoryView: View {
	let category: BTBStorageCategory
	var onChange: () -> Void
	@State private var _items: [BTBStorageItem] = []
	@State private var _selection = Set<URL>()
	@State private var _total: Int64 = 0
	
	var body: some View {
		List(selection: $_selection) {
			Section {
				HStack {
					Text(.localized("Total"))
					Spacer()
					Text(btbFormatBytes(_total)).foregroundStyle(.secondary)
				}
				Button(role: .destructive) {
					_delete(all: true)
				} label: {
					Label(.localized("Clean Category"), systemImage: "trash")
				}
				.disabled(_total == 0)
			} footer: {
				Text(category.footer)
			}
			
			if !_items.isEmpty {
				NBSection(.localized("Files"), secondary: _items.count.description) {
					ForEach(_items) { item in
						VStack(alignment: .leading, spacing: 2) {
							Text(item.name).lineLimit(1)
							HStack {
								Text(btbFormatBytes(item.size))
								if let date = item.modified {
									Text("•")
									Text(date.formatted(date: .abbreviated, time: .shortened))
								}
							}
							.font(.footnote)
							.foregroundStyle(.secondary)
						}
						.tag(item.url)
						.swipeActions {
							Button(role: .destructive) {
								_deleteItems([item])
							} label: {
								Label(.localized("Delete"), systemImage: "trash")
							}
						}
					}
				}
			}
		}
		.navigationTitle(category.title)
		.toolbar {
			if !_items.isEmpty {
				ToolbarItem(placement: .topBarTrailing) { EditButton() }
				if !_selection.isEmpty {
					ToolbarItem(placement: .topBarTrailing) {
						Button(role: .destructive) {
							_deleteItems(_items.filter { _selection.contains($0.url) })
						} label: {
							Text(String.localized("Delete Selected (%@)", arguments: btbFormatBytes(_selectedSize)))
						}
					}
				}
			}
		}
		.onAppear(perform: _reload)
	}
	
	private var _selectedSize: Int64 {
		_items.filter { _selection.contains($0.url) }.reduce(0) { $0 + $1.size }
	}
	
	private func _reload() {
		_items = BTBStorageManager.shared.items(in: category)
		_total = BTBStorageManager.shared.size(of: category)
		_selection.removeAll()
	}
	
	private func _delete(all: Bool) {
		UIAlertController.showAlertWithCancel(
			title: category.title,
			message: String.localized("%@ will be freed. Certificates, sources and settings are kept.", arguments: btbFormatBytes(_total)),
			actions: [
				UIAlertAction(title: .localized("Delete"), style: .destructive) { _ in
					BTBStorageManager.shared.clean(category)
					_reload()
					onChange()
				}
			]
		)
	}
	
	private func _deleteItems(_ items: [BTBStorageItem]) {
		let size = items.reduce(0) { $0 + $1.size }
		UIAlertController.showAlertWithCancel(
			title: .localized("Delete"),
			message: String.localized("%@ will be freed. Certificates, sources and settings are kept.", arguments: btbFormatBytes(size)),
			actions: [
				UIAlertAction(title: .localized("Delete"), style: .destructive) { _ in
					var errors: [String] = []
					for item in items {
						do { try BTBStorageManager.shared.clean(item, in: category) }
						catch { errors.append(error.localizedDescription) }
					}
					_reload()
					onChange()
					if !errors.isEmpty {
						UIAlertController.showAlertWithOk(title: .localized("Error"), message: errors.joined(separator: "\n"))
					}
				}
			]
		)
	}
}
