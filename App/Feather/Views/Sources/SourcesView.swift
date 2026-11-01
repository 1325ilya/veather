//
//  SourcesView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import CoreData
import AltSourceKit
import SwiftUI
import NimbleViews

// MARK: - View
struct SourcesView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@StateObject var viewModel = SourcesViewModel.shared
	@State private var _isAddingPresenting = false
	@State private var _addingSourceLoading = false
	@State private var _searchText = ""
	
	private var _filteredSources: [AltSource] {
		_sources.filter { _searchText.isEmpty || ($0.name?.localizedCaseInsensitiveContains(_searchText) ?? false) }
	}
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Sources")) {
			NBListAdaptable {
				Section {
					NavigationLink {
						BTBBrowserView()
					} label: {
						BTBRowLabel(.localized("Browser"), systemImage: "safari.fill", color: .blue, subtitle: .localized("Download IPA files from websites"))
					}
					if !_sources.isEmpty {
						NavigationLink {
							BTBUniversalSearchView()
						} label: {
							BTBRowLabel(.localized("Search Sources"), systemImage: "magnifyingglass", color: .indigo, subtitle: .localized("Newest version across all sources"))
						}
						NavigationLink {
							BTBSourceHealthView()
						} label: {
							BTBRowLabel(.localized("Source Health"), systemImage: "stethoscope", color: .teal, subtitle: .localized("Check which sources respond"))
						}
					}
				}
				if _sources.isEmpty {
					Section {
						VStack(alignment: .leading, spacing: 12) {
							BTBRowLabel(
								.localized("No Repositories"),
								systemImage: "globe.desk.fill",
								color: .purple,
								subtitle: .localized("Repositories are app catalogs (AltStore format). Add one to browse and download apps right here.")
							)
							Button {
								_isAddingPresenting = true
							} label: {
								Label(.localized("Add Source"), systemImage: "plus")
									.font(.subheadline.weight(.semibold))
									.frame(maxWidth: .infinity)
							}
							.buttonStyle(.borderedProminent)
							.controlSize(.large)
						}
						.padding(.vertical, 6)
					}
				}
				
				if !_filteredSources.isEmpty {
					Section {
						NavigationLink {
							SourceAppsView(object: Array(_sources), viewModel: viewModel)
						} label: {
							let isRegular = horizontalSizeClass != .compact
							HStack(spacing: 18) {
								Image("Repositories").appIconStyle()
								NBTitleWithSubtitleView(
									title: .localized("All Repositories"),
									subtitle: .localized("See all apps from your sources")
								)
							}
							.padding(isRegular ? 12 : 0)
							.background(
								isRegular
									? RoundedRectangle(cornerRadius: 18, style: .continuous)
									.fill(Color(.quaternarySystemFill))
									: nil
							)
						}
						.buttonStyle(.plain)
					}
					
					NBSection(
						.localized("Repositories"),
						secondary: _filteredSources.count.description
					) {
						ForEach(_filteredSources) { source in
							NavigationLink {
								SourceAppsView(object: [source], viewModel: viewModel)
							} label: {
								SourcesCellView(source: source)
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
			.searchable(text: $_searchText, placement: .platform())
			.overlay {
				if !_searchText.isEmpty, !_sources.isEmpty, _filteredSources.isEmpty {
					if #available(iOS 17, *) {
						ContentUnavailableView.search(text: _searchText)
					}
				}
			}
			.toolbar {
				NBToolbarButton(
					systemImage: "plus",
					style: .icon,
					placement: .topBarTrailing,
					isDisabled: _addingSourceLoading
				) {
					_isAddingPresenting = true
				}
			}
			.refreshable {
				await viewModel.fetchSources(_sources, refresh: true)
			}
			.sheet(isPresented: $_isAddingPresenting) {
				SourcesAddView()
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}
}
