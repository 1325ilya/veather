//
//  ContentView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

// MARK: - View
struct LibraryView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var updateManager = UpdateManager.shared
	
	@State private var _confirmBulkDelete = false
	@State private var _selectedInfoAppPresenting: AnyApp?
	@State private var _selectedSigningAppPresenting: AnyApp?
	@State private var _selectedInstallAppPresenting: AnyApp?
	@State private var _deleteAppPresenting: AnyApp?
	@State private var _isImportingPresenting = false
	@State private var _isDownloadingPresenting = false
	@State private var _alertDownloadString: String = "" // for _isDownloadingPresenting
	@State private var _updateCheckRotation = 0.0
	@State private var _isUpdateCheckCompleteVisible = false
	
	// MARK: Selection State
	@State private var _selectedAppUUIDs: Set<String> = []
	@State private var _editMode: EditMode = .inactive
	@State private var _bulkProgress: (Int, Int)?
	
	@State private var _searchText = ""
	@AppStorage("BTB.librarySort") private var _sortRaw: String = SortMode.date.rawValue
	private var _sort: SortMode { SortMode(rawValue: _sortRaw) ?? .date }
	@State private var _selectedScope: Scope = .all
	
	
	@Namespace private var _namespace
	
	// horror
	private func filteredAndSortedApps<T>(from apps: FetchedResults<T>) -> [T] where T: NSManagedObject {
		let filtered = apps.filter {
			_searchText.isEmpty ||
				(($0.value(forKey: "name") as? String)?.localizedCaseInsensitiveContains(_searchText) ?? false) ||
				(($0.value(forKey: "identifier") as? String)?.localizedCaseInsensitiveContains(_searchText) ?? false)
		}
		switch _sort {
		case .date:
			return filtered
		case .name:
			return filtered.sorted {
				let a = ($0.value(forKey: "name") as? String) ?? ""
				let b = ($1.value(forKey: "name") as? String) ?? ""
				return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
			}
		}
	}
	
	private var _filteredSignedApps: [Signed] {
		filteredAndSortedApps(from: _signedApps)
	}
	
	private var _filteredImportedApps: [Imported] {
		filteredAndSortedApps(from: _importedApps)
	}
	
	// MARK: Self-heal (apps whose certificate is revoked or expired)
	private var _healthyCertificate: CertificatePair? {
		let index = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		guard
			let cert = Storage.shared.getCertificate(for: index),
			!cert.revoked,
			(cert.expiration ?? .distantFuture) > Date()
		else { return nil }
		return cert
	}
	
	private var _certificateDaysLeft: Int? {
		guard let expiration = _healthyCertificate?.expiration else { return nil }
		return Calendar.current.dateComponents([.day], from: Date(), to: expiration).day
	}
	
	private var _appsNeedingResign: [Signed] {
		guard let healthy = _healthyCertificate else { return [] }
		return _signedApps.filter { app in
			guard let cert = Storage.shared.getCertificate(from: app), cert.objectID != healthy.objectID else { return false }
			return cert.revoked || (cert.expiration ?? .distantFuture) <= Date()
		}
	}
	
	// MARK: Fetch
	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .snappy
	) private var _signedApps: FetchedResults<Signed>
	
	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Library")) {
			NBListAdaptable {
				if _searchText.isEmpty, !_editMode.isEditing {
					let broken = _appsNeedingResign
					if !broken.isEmpty {
						Section {
							_resignBanner(broken)
						}
					} else if let days = _certificateDaysLeft, days <= 7 {
						Section {
							NavigationLink {
								BTBCertHealthView()
							} label: {
								BTBRowLabel(
									.localized("Certificate Expires Soon"),
									systemImage: "clock.badge.exclamationmark.fill",
									color: .orange,
									subtitle: days <= 0
										? String.localized("Your certificate expires today. Apps signed with it will stop opening.")
										: String.localized("%lld days left. Get a new certificate and re-sign your apps before then.", arguments: days)
								)
							}
						}
					}
				}
				
				if
					horizontalSizeClass == .compact,
					_searchText.isEmpty,
					!_editMode.isEditing,
					!(_signedApps.isEmpty && _importedApps.isEmpty)
				{
					Section {
						_quickImportRow()
					}
				}
				
				if
					!_filteredSignedApps.isEmpty,
					_selectedScope == .all || _selectedScope == .signed
				{
					NBSection(
						.localized("Signed"),
						secondary: _filteredSignedApps.count.description
					) {
						ForEach(_filteredSignedApps, id: \.uuid) { app in
							LibraryCellView(
								app: app,
								selectedInfoAppPresenting: $_selectedInfoAppPresenting,
								selectedSigningAppPresenting: $_selectedSigningAppPresenting,
								selectedInstallAppPresenting: $_selectedInstallAppPresenting,
								selectedAppUUIDs: $_selectedAppUUIDs,
								deleteAppPresenting: $_deleteAppPresenting
							)
							.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
						}
					}
				}
				
				if
					!_filteredImportedApps.isEmpty,
					_selectedScope == .all || _selectedScope == .imported
				{
					NBSection(
						.localized("Imported"),
						secondary: _filteredImportedApps.count.description
					) {
						ForEach(_filteredImportedApps, id: \.uuid) { app in
							LibraryCellView(
								app: app,
								selectedInfoAppPresenting: $_selectedInfoAppPresenting,
								selectedSigningAppPresenting: $_selectedSigningAppPresenting,
								selectedInstallAppPresenting: $_selectedInstallAppPresenting,
								selectedAppUUIDs: $_selectedAppUUIDs,
								deleteAppPresenting: $_deleteAppPresenting
							)
							.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
						}
					}
				}
			}
			.searchable(text: $_searchText, placement: .platform())
			.compatSearchScopes($_selectedScope) {
				ForEach(Scope.allCases, id: \.displayName) { scope in
					Text(scope.displayName).tag(scope)
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.refreshable {
				await _checkForUpdates()
			}
			.overlay {
				if
					_filteredSignedApps.isEmpty,
					_filteredImportedApps.isEmpty
				{
					if #available(iOS 17, *) {
						if _searchText.isEmpty {
							ContentUnavailableView {
								Label(.localized("No Apps"), systemImage: "square.stack.3d.up.fill")
							} description: {
								Text(.localized("Get started by importing your first IPA file."))
								+ Text(verbatim: "\n\n")
								+ Text(.localized("Tip: in the Files app, tap Share on an .ipa and choose Veather."))
							} actions: {
								VStack(spacing: 10) {
									Button {
										_isImportingPresenting = true
									} label: {
										Label(.localized("Import from Files"), systemImage: "folder.fill")
											.frame(minWidth: 200)
									}
									.buttonStyle(.borderedProminent)
									.controlSize(.large)
									
									Button {
										_isDownloadingPresenting = true
									} label: {
										Label(.localized("Import from URL"), systemImage: "link")
											.frame(minWidth: 200)
									}
									.buttonStyle(.bordered)
									.controlSize(.large)
								}
							}
						} else {
							ContentUnavailableView.search(text: _searchText)
						}
					}
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					EditButton()
				}
				
				if _editMode.isEditing {
					NBToolbarButton(
						_bulkProgress.map { String.localized("Signing %lld of %lld", arguments: $0.0, $0.1) } ?? String.localized("Sign"),
						systemImage: "signature",
						isDisabled: _selectedAppUUIDs.isEmpty || _bulkProgress != nil
					) {
						_bulkSignSelectedApps()
					}
					NBToolbarButton(
						.localized("Delete"),
						systemImage: "trash",
						isDisabled: _selectedAppUUIDs.isEmpty || _bulkProgress != nil
					) {
						_confirmBulkDelete = true
					}
				} else {
					ToolbarItem(placement: .topBarTrailing) {
						Button {
							Task {
								await _checkForUpdates()
							}
						} label: {
							Image(systemName: _isUpdateCheckCompleteVisible ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
								.rotationEffect(.degrees(_updateCheckRotation))
								.animation(
									updateManager.isChecking
										? .linear(duration: 0.8).repeatForever(autoreverses: false)
										: .default,
									value: _updateCheckRotation
								)
						}
						.disabled(updateManager.isChecking)
						.accessibilityLabel(.localized("Check for Updates"))
					}
					
					ToolbarItem(placement: .topBarTrailing) {
						Menu {
							Picker(selection: $_sortRaw) {
								ForEach(SortMode.allCases, id: \.rawValue) { mode in
									Label(mode.title, systemImage: mode.icon).tag(mode.rawValue)
								}
							} label: {
								Text(.localized("Sort By"))
							}
						} label: {
							Image(systemName: "arrow.up.arrow.down")
						}
						.accessibilityLabel(.localized("Sort By"))
					}
					
					NBToolbarMenu(
						systemImage: "plus",
						style: .icon,
						placement: .topBarTrailing
					) {
						_importActions()
					}
				}
			}
			.environment(\.editMode, $_editMode)
			.confirmationDialog(
				String.localized("Delete “%@”?", arguments: _deleteAppPresenting?.base.name ?? .localized("Unknown")),
				isPresented: Binding(
					get: { _deleteAppPresenting != nil },
					set: { if !$0 { _deleteAppPresenting = nil } }
				),
				titleVisibility: .visible,
				presenting: _deleteAppPresenting
			) { app in
				Button(.localized("Delete"), role: .destructive) {
					Storage.shared.deleteApp(for: app.base)
				}
				Button(.localized("Cancel"), role: .cancel) {}
			} message: { _ in
				Text(.localized("The file is removed from Veather. Apps already installed on your iPhone stay."))
			}
			.confirmationDialog(
				String.localized("Delete %lld apps?", arguments: _selectedAppUUIDs.count),
				isPresented: $_confirmBulkDelete,
				titleVisibility: .visible
			) {
				Button(.localized("Delete"), role: .destructive) {
					_bulkDeleteSelectedApps()
				}
				Button(.localized("Cancel"), role: .cancel) {}
			} message: {
				Text(.localized("The file is removed from Veather. Apps already installed on your iPhone stay."))
			}
			.sheet(item: $_selectedInfoAppPresenting) { app in
				LibraryInfoView(
					app: app.base,
					onSign: { _selectedSigningAppPresenting = AnyApp(base: app.base) },
					onInstall: { _selectedInstallAppPresenting = AnyApp(base: app.base) }
				)
			}
			.sheet(item: $_selectedInstallAppPresenting) { app in
				InstallPreviewView(app: app.base, isSharing: app.archive)
					.presentationDetents([.height(200)])
					.presentationDragIndicator(.visible)
			}
			.fullScreenCover(item: $_selectedSigningAppPresenting) { app in
				SigningView(app: app.base)
					.compatNavigationTransition(id: app.base.uuid ?? "", ns: _namespace)
			}
			.sheet(isPresented: $_isImportingPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes:  [.ipa, .tipa],
					allowsMultipleSelection: true,
					onDocumentsPicked: { urls in
						guard !urls.isEmpty else { return }
						
						for url in urls {
							let id = "FeatherManualDownload_\(UUID().uuidString)"
							let dl = downloadManager.startArchive(from: url, id: id)
							try? downloadManager.handlePachageFile(url: url, dl: dl)
						}
					}
				)
				.ignoresSafeArea()
			}
			.alert(.localized("Import from URL"), isPresented: $_isDownloadingPresenting) {
				TextField(.localized("https://example.com/app.ipa"), text: $_alertDownloadString)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.keyboardType(.URL)
				Button(.localized("Cancel"), role: .cancel) {
					_alertDownloadString = ""
				}
				Button(.localized("Download")) {
					let text = _alertDownloadString.trimmingCharacters(in: .whitespacesAndNewlines)
					_alertDownloadString = ""
					guard
						let url = URL(string: text),
						let scheme = url.scheme?.lowercased(),
						scheme == "http" || scheme == "https"
					else {
						UIAlertController.showAlertWithOk(
							title: .localized("Invalid Link"),
							message: .localized("Paste a direct link that starts with https:// and points to an .ipa or .tipa file.")
						)
						return
					}
					UINotificationFeedbackGenerator().notificationOccurred(.success)
					_ = downloadManager.startDownload(from: url, id: "FeatherManualDownload_\(UUID().uuidString)")
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: Notification.Name("Veather.shareApp"))) { _ in
				// export the newest result as an IPA (share sheet / Files)
				if let latest = _signedApps.first {
					_selectedInstallAppPresenting = AnyApp(base: latest, archive: true)
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: Notification.Name("Feather.installApp"))) { _ in
				if let latest = _signedApps.first {
					_selectedInstallAppPresenting = AnyApp(base: latest)
				}
			}
			.onChange(of: _editMode) { mode in
				if mode == .inactive {
					_selectedAppUUIDs.removeAll()
				}
			}
			.onChange(of: updateManager.isChecking) { isChecking in
				_handleUpdateCheckStateChange(isChecking)
			}
		}
	}
}

// MARK: - Extension: View
extension LibraryView {
	@ViewBuilder
	private func _importActions() -> some View {
		Button(.localized("Import from Files"), systemImage: "folder") {
			_isImportingPresenting = true
		}
		Button(.localized("Import from URL"), systemImage: "globe") {
			_isDownloadingPresenting = true
		}
		Button(.localized("Paste Link"), systemImage: "doc.on.clipboard") {
			_importFromClipboard()
		}
	}
	
	@ViewBuilder
	private func _resignBanner(_ apps: [Signed]) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			BTBRowLabel(
				.localized("Certificate Problem"),
				systemImage: "exclamationmark.shield.fill",
				color: .red,
				subtitle: .localized("%lld apps were signed with a revoked or expired certificate. Re-sign them with your current certificate, then install again.", arguments: apps.count)
			)
			Button {
				_bulkProgress = (0, apps.count)
				BTBBulkSigner.sign(apps, progress: { _bulkProgress = ($0, $1) }) { ok, errors in
					_bulkProgress = nil
					UINotificationFeedbackGenerator().notificationOccurred(errors.isEmpty ? .success : .warning)
					UIAlertController.showAlertWithOk(
						title: String.localized("Signed %lld of %lld", arguments: ok, apps.count),
						message: errors.isEmpty ? String.localized("Open each app in Library and tap Install.") : errors.joined(separator: "\n")
					)
				}
			} label: {
				Label(
					_bulkProgress.map { String.localized("Signing %lld of %lld", arguments: $0.0, $0.1) } ?? String.localized("Re-sign All"),
					systemImage: "arrow.triangle.2.circlepath"
				)
				.font(.subheadline.weight(.semibold))
				.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.tint(.red)
			.controlSize(.large)
			.disabled(_bulkProgress != nil)
		}
		.padding(.vertical, 6)
	}
	
	@ViewBuilder
	private func _quickImportRow() -> some View {
		HStack(spacing: 10) {
			Button {
				_isImportingPresenting = true
			} label: {
				BTBQuickTile(title: .localized("Files"), systemImage: "folder.fill", color: .blue)
			}
			Button {
				_isDownloadingPresenting = true
			} label: {
				BTBQuickTile(title: .localized("Link"), systemImage: "link", color: .green)
			}
			Button {
				_importFromClipboard()
			} label: {
				BTBQuickTile(title: .localized("Paste Link"), systemImage: "doc.on.clipboard.fill", color: .orange)
			}
		}
		.buttonStyle(BTBPressableStyle())
		.listRowSeparator(.hidden)
		.listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
	}
	
	private func _importFromClipboard() {
		let pasteboard = UIPasteboard.general
		let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines)
		let candidate = pasteboard.url ?? text.flatMap { URL(string: $0) }
		guard
			let url = candidate,
			let scheme = url.scheme?.lowercased(),
			scheme == "http" || scheme == "https"
		else {
			UINotificationFeedbackGenerator().notificationOccurred(.warning)
			UIAlertController.showAlertWithOk(
				title: .localized("No Link in Clipboard"),
				message: .localized("Copy a link to an .ipa file first, then tap Paste Link.")
			)
			return
		}
		UINotificationFeedbackGenerator().notificationOccurred(.success)
		_ = downloadManager.startDownload(from: url, id: "FeatherManualDownload_\(UUID().uuidString)")
	}
}

// MARK: - Extension: Bulk Delete
extension LibraryView {
	private func _bulkSignSelectedApps() {
		let selectedApps = _getAllApps().filter { app in
			guard let uuid = app.uuid else { return false }
			return _selectedAppUUIDs.contains(uuid)
		}
		guard !selectedApps.isEmpty else { return }
		BTBBulkSigner.sign(selectedApps, progress: { _bulkProgress = ($0, $1) }) { ok, errors in
			_bulkProgress = nil
			_selectedAppUUIDs.removeAll()
			UIAlertController.showAlertWithOk(
				title: String.localized("Signed %lld of %lld", arguments: ok, selectedApps.count),
				message: errors.joined(separator: "\n")
			)
		}
	}
	
	private func _bulkDeleteSelectedApps() {
		let selectedApps = _getAllApps().filter { app in
			guard let uuid = app.uuid else { return false }
			return _selectedAppUUIDs.contains(uuid)
		}
		
		for app in selectedApps {
			Storage.shared.deleteApp(for: app)
		}
		
		_selectedAppUUIDs.removeAll()
		
		// _editMode = .inactive
	}
	
	private func _getAllApps() -> [AppInfoPresentable] {
		var allApps: [AppInfoPresentable] = []
		
		if _selectedScope == .all || _selectedScope == .signed {
			allApps.append(contentsOf: _filteredSignedApps)
		}
		
		if _selectedScope == .all || _selectedScope == .imported {
			allApps.append(contentsOf: _filteredImportedApps)
		}
		
		return allApps
	}
	
	private func _checkForUpdates() async {
		let localApps = _signedApps.map { $0 as AppInfoPresentable } + _importedApps.map { $0 as AppInfoPresentable }
		await updateManager.checkForUpdates(
			sources: Array(_sources),
			localApps: localApps
		)
	}
	
	private func _handleUpdateCheckStateChange(_ isChecking: Bool) {
		if isChecking {
			_isUpdateCheckCompleteVisible = false
			_updateCheckRotation = 0
			withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
				_updateCheckRotation = 360
			}
		} else {
			withAnimation(.none) {
				_updateCheckRotation = 0
			}
			
			_isUpdateCheckCompleteVisible = true
			Task { @MainActor in
				try? await Task.sleep(nanoseconds: 900_000_000)
				if !updateManager.isChecking {
					_isUpdateCheckCompleteVisible = false
				}
			}
		}
	}
}

// MARK: - Extension: View (Sort)
extension LibraryView {
	enum SortMode: String, CaseIterable {
		case date
		case name
		
		var title: String {
			switch self {
			case .date: return .localized("Newest First")
			case .name: return .localized("Name")
			}
		}
		
		var icon: String {
			switch self {
			case .date: return "clock"
			case .name: return "textformat"
			}
		}
	}
	
	enum Scope: CaseIterable {
		case all
		case signed
		case imported
		
		var displayName: String {
			switch self {
			case .all: return .localized("All")
			case .signed: return .localized("Signed")
			case .imported: return .localized("Imported")
			}
		}
	}
}
