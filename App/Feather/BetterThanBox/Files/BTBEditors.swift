//
//  BTBEditors.swift
//  BetterThanBox
//
//  Plist editor, text editor and hex viewer (ideas: Ksign PlistEditorView,
//  TextEditorView, HexEditorView).
//

import SwiftUI
import NimbleViews

// MARK: - Plist model

final class BTBPlistNode: ObservableObject, Identifiable {
	let id = UUID()
	@Published var key: String
	@Published var value: Any
	
	init(key: String, value: Any) {
		self.key = key
		self.value = value
	}
	
	var typeName: String {
		switch value {
		case is NSDictionary, is [String: Any]: return "Dictionary"
		case is NSArray, is [Any]: return "Array"
		case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): return "Boolean"
		case is NSNumber: return "Number"
		case is Date: return "Date"
		case is Data: return "Data"
		default: return "String"
		}
	}
	
	var preview: String {
		switch value {
		case let d as NSDictionary: return String.localized("%lld items", arguments: d.count)
		case let a as NSArray: return String.localized("%lld items", arguments: a.count)
		case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): return n.boolValue ? "YES" : "NO"
		case let n as NSNumber: return n.stringValue
		case let d as Date: return d.formatted()
		case let d as Data: return btbFormatBytes(Int64(d.count))
		default: return "\(value)"
		}
	}
}

// MARK: - Plist editor

struct BTBPlistEditorView: View {
	let url: URL
	@State private var _root: NSMutableDictionary?
	@State private var _rootArray: NSMutableArray?
	@State private var _format: PropertyListSerialization.PropertyListFormat = .xml
	@State private var _error: String?
	@State private var _dirty = false
	@State private var _token = UUID()
	
	static func canOpen(_ url: URL) -> Bool {
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count < 20_000_000 else { return false }
		return (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil
	}
	
	var body: some View {
		Group {
			if let _root {
				BTBPlistContainerView(container: _root, onChange: _markDirty)
					.id(_token)
			} else if let _rootArray {
				BTBPlistContainerView(container: _rootArray, onChange: _markDirty)
					.id(_token)
			} else if let _error {
				Text(_error).foregroundStyle(.red).padding()
			} else {
				ProgressView()
			}
		}
		.navigationTitle(url.lastPathComponent)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button(.localized("Save")) { _save() }
					.disabled(!_dirty)
			}
		}
		.onAppear(perform: _load)
	}
	
	private func _markDirty() { _dirty = true }
	
	private func _load() {
		do {
			let data = try Data(contentsOf: url)
			var format = PropertyListSerialization.PropertyListFormat.xml
			let object = try PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: &format)
			_format = format
			if let dict = object as? NSMutableDictionary {
				_root = dict
			} else if let array = object as? NSMutableArray {
				_rootArray = array
			} else {
				_error = .localized("Unsupported plist root.")
			}
		} catch {
			_error = error.localizedDescription
		}
	}
	
	private func _save() {
		guard let object: Any = _root ?? _rootArray else { return }
		do {
			// keep binary plists binary (Info.plist inside apps), everything else as XML
			let format: PropertyListSerialization.PropertyListFormat = _format == .binary ? .binary : .xml
			let data = try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0)
			try data.write(to: url, options: .atomic)
			_dirty = false
		} catch {
			UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
		}
	}
}

struct BTBPlistContainerView: View {
	/// NSMutableDictionary or NSMutableArray (reference type, edited in place)
	let container: AnyObject
	var onChange: () -> Void
	@State private var _token = UUID()
	@State private var _query = ""
	
	struct Row: Identifiable {
		let key: String
		let value: Any
		var id: String { key }
	}
	
	private var _rows: [Row] {
		_ = _token
		if let dict = container as? NSMutableDictionary {
			return (dict.allKeys as? [String] ?? [])
				.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
				.filter { _query.isEmpty || $0.localizedCaseInsensitiveContains(_query) }
				.map { Row(key: $0, value: dict[$0] as Any) }
		} else if let array = container as? NSMutableArray {
			return array.enumerated().map { Row(key: "\($0.offset)", value: $0.element) }
		}
		return []
	}
	
	var body: some View {
		List {
			ForEach(_rows) { row in
				let node = BTBPlistNode(key: row.key, value: row.value)
				_row(node)
					.swipeActions {
						Button(role: .destructive) { _remove(row.key) } label: {
							Label(.localized("Delete"), systemImage: "trash")
						}
					}
			}
		}
		.searchable(text: $_query, placement: .platform())
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Button("String") { _add("") }
					Button("Number") { _add(NSNumber(value: 0)) }
					Button("Boolean") { _add(NSNumber(value: true)) }
					Button("Dictionary") { _add(NSMutableDictionary()) }
					Button("Array") { _add(NSMutableArray()) }
				} label: {
					Label(.localized("Add"), systemImage: "plus")
				}
			}
		}
	}
	
	@ViewBuilder
	private func _row(_ node: BTBPlistNode) -> some View {
		switch node.value {
		case let child as NSMutableDictionary:
			NavigationLink {
				BTBPlistContainerView(container: child, onChange: onChange).navigationTitle(node.key)
			} label: { _label(node) }
		case let child as NSMutableArray:
			NavigationLink {
				BTBPlistContainerView(container: child, onChange: onChange).navigationTitle(node.key)
			} label: { _label(node) }
		case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID():
			Toggle(isOn: Binding(
				get: { n.boolValue },
				set: { _set(node.key, NSNumber(value: $0)) }
			)) { _label(node, showValue: false) }
		case is Data, is Date:
			_label(node)
		default:
			NavigationLink {
				BTBPlistValueEditor(node: node) { newValue in _set(node.key, newValue) }
			} label: { _label(node) }
		}
	}
	
	private func _label(_ node: BTBPlistNode, showValue: Bool = true) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack {
				Text(node.key).font(.system(.body, design: .monospaced)).lineLimit(1)
				Spacer()
				Text(node.typeName).font(.caption2).foregroundStyle(.secondary)
			}
			if showValue {
				Text(node.preview).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
			}
		}
	}
	
	private func _set(_ key: String, _ value: Any) {
		if let dict = container as? NSMutableDictionary {
			dict[key] = value
		} else if let array = container as? NSMutableArray, let index = Int(key), index < array.count {
			array[index] = value
		}
		_token = UUID()
		onChange()
	}
	
	private func _remove(_ key: String) {
		if let dict = container as? NSMutableDictionary {
			dict.removeObject(forKey: key)
		} else if let array = container as? NSMutableArray, let index = Int(key), index < array.count {
			array.removeObject(at: index)
		}
		_token = UUID()
		onChange()
	}
	
	private func _add(_ value: Any) {
		if let dict = container as? NSMutableDictionary {
			var key = "NewKey"
			var i = 1
			while dict[key] != nil { key = "NewKey\(i)"; i += 1 }
			dict[key] = value
		} else if let array = container as? NSMutableArray {
			array.add(value)
		}
		_token = UUID()
		onChange()
	}
}

struct BTBPlistValueEditor: View {
	@ObservedObject var node: BTBPlistNode
	var onSave: (Any) -> Void
	@State private var _text = ""
	@Environment(\.dismiss) private var _dismiss
	
	var body: some View {
		Form {
			Section(node.typeName) {
				TextField(.localized("Value"), text: $_text, axis: .vertical)
					.font(.system(.body, design: .monospaced))
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
					.keyboardType(node.typeName == "Number" ? .decimalPad : .default)
			}
		}
		.navigationTitle(node.key)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button(.localized("Done")) {
					if node.typeName == "Number" {
						if let i = Int(_text) { onSave(NSNumber(value: i)) }
						else if let d = Double(_text) { onSave(NSNumber(value: d)) }
					} else {
						onSave(_text)
					}
					_dismiss()
				}
			}
		}
		.onAppear { _text = node.preview }
	}
}

// MARK: - Text editor

struct BTBTextEditorView: View {
	let url: URL
	@State private var _text = ""
	@State private var _original = ""
	@State private var _error: String?
	private let _limit = 5_000_000
	
	var body: some View {
		Group {
			if let _error {
				Text(_error).foregroundStyle(.secondary).padding()
			} else {
				TextEditor(text: $_text)
					.font(.system(.footnote, design: .monospaced))
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
			}
		}
		.navigationTitle(url.lastPathComponent)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button(.localized("Save")) {
					do {
						try _text.write(to: url, atomically: true, encoding: .utf8)
						_original = _text
					} catch {
						UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
					}
				}
				.disabled(_text == _original || _error != nil)
			}
		}
		.onAppear {
			guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
				_error = .localized("Unable to read file.")
				return
			}
			guard data.count <= _limit else {
				_error = .localized("File is too large for the text editor. Use the hex viewer.")
				return
			}
			if let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
				_text = string
				_original = string
			} else {
				_error = .localized("Not a text file. Use the hex viewer.")
			}
		}
	}
}

// MARK: - Hex viewer / patcher

struct BTBHexView: View {
	let url: URL
	@State private var _lines: [String] = []
	@State private var _page = 0
	@State private var _fileSize: Int64 = 0
	@State private var _patchOffset = ""
	@State private var _patchBytes = ""
	@State private var _showPatch = false
	private let _bytesPerLine = 16
	private let _pageSize = 16 * 1024
	
	private var _pageCount: Int { max(1, Int((_fileSize + Int64(_pageSize) - 1) / Int64(_pageSize))) }
	
	var body: some View {
		List {
			Section {
				HStack {
					Button { if _page > 0 { _page -= 1; _load() } } label: { Image(systemName: "chevron.left") }
						.disabled(_page == 0)
					Spacer()
					Text(String.localized("Page %lld of %lld", arguments: _page + 1, _pageCount)).font(.footnote)
					Spacer()
					Button { if _page + 1 < _pageCount { _page += 1; _load() } } label: { Image(systemName: "chevron.right") }
						.disabled(_page + 1 >= _pageCount)
				}
				.buttonStyle(.borderless)
			} footer: {
				Text(btbFormatBytes(_fileSize))
			}
			Section {
				ForEach(Array(_lines.enumerated()), id: \.offset) { _, line in
					Text(line)
						.font(.system(size: 11, design: .monospaced))
						.textSelection(.enabled)
						.lineLimit(1)
						.minimumScaleFactor(0.5)
				}
			}
		}
		.navigationTitle(url.lastPathComponent)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button(.localized("Patch"), systemImage: "bandage") { _showPatch = true }
			}
		}
		.alert(.localized("Patch Bytes"), isPresented: $_showPatch) {
			TextField(.localized("Offset (hex, e.g. 1A2B)"), text: $_patchOffset)
				.textInputAutocapitalization(.never)
			TextField(.localized("Bytes (hex, e.g. 1F 20 03 D5)"), text: $_patchBytes)
				.textInputAutocapitalization(.never)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Write")) { _patch() }
		} message: {
			Text(.localized("Overwrites bytes in place. Make a copy first if unsure."))
		}
		.onAppear(perform: _load)
	}
	
	private func _load() {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return }
		defer { try? handle.close() }
		_fileSize = Int64((try? handle.seekToEnd()) ?? 0)
		let start = UInt64(_page * _pageSize)
		try? handle.seek(toOffset: start)
		let data = (try? handle.read(upToCount: _pageSize)) ?? Data()
		var lines: [String] = []
		lines.reserveCapacity(data.count / _bytesPerLine + 1)
		let bytes = [UInt8](data)
		var i = 0
		while i < bytes.count {
			let chunk = bytes[i..<min(i + _bytesPerLine, bytes.count)]
			let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
			let ascii = String(chunk.map { (0x20...0x7e).contains($0) ? Character(UnicodeScalar($0)) : "." })
			let padded = hex.padding(toLength: _bytesPerLine * 3 - 1, withPad: " ", startingAt: 0)
			lines.append(String(format: "%08llX  ", UInt64(start) + UInt64(i)) + padded + "  " + ascii)
			i += _bytesPerLine
		}
		_lines = lines
	}
	
	private func _patch() {
		guard
			let offset = UInt64(_patchOffset.replacingOccurrences(of: "0x", with: ""), radix: 16)
		else { return }
		let cleaned = _patchBytes.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "0x", with: "")
		guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return }
		var bytes: [UInt8] = []
		var index = cleaned.startIndex
		while index < cleaned.endIndex {
			let next = cleaned.index(index, offsetBy: 2)
			guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return }
			bytes.append(byte)
			index = next
		}
		guard offset + UInt64(bytes.count) <= UInt64(_fileSize) else {
			UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Offset is outside the file."))
			return
		}
		do {
			let handle = try FileHandle(forWritingTo: url)
			try handle.seek(toOffset: offset)
			try handle.write(contentsOf: Data(bytes))
			try handle.close()
			_page = Int(offset) / _pageSize
			_load()
		} catch {
			UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
		}
	}
}
