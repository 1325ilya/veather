//
//  AboutView.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import SwiftUI
import NimbleViews
import NimbleJSON

// MARK: - Extension: Model
extension AboutView {
	struct CreditsModel: Codable, Hashable {
		let name: String?
		let desc: String?
		let github: String
	}
}

// MARK: - View
struct AboutView: View {
	@State private var _credits: [CreditsModel] = [
		.init(name: "Veather", desc: "Veather project", github: "1325ilya/veather"),
		.init(name: "C", desc: "Feather developer", github: "claration"),
		.init(name: "Asami", desc: "Feather developer", github: "Nyasami"),
		.init(name: "Lakhan Lothiyi", desc: "AltStore repositories", github: "llsc12"),
		.init(name: "zhlynn", desc: "zsign signing engine", github: "zhlynn"),
	]
	
	// MARK: Body
	var body: some View {
		NBList(.localized("About")) {
			Section {
				VStack {
					FRAppIconView(size: 84)
						.shadow(color: Color.accentColor.opacity(0.35), radius: 14, y: 6)
					
					Text(verbatim: "Veather")
						.font(.largeTitle.weight(.bold))
						.foregroundStyle(Color.accentColor.gradient)
						.padding(.top, 6)
					
					Text(.localized("Sign and install apps right on your iPhone"))
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
					
					HStack(spacing: 4) {
						Text(.localized("Version"))
						Text(Bundle.main.version)
						if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
							Text(verbatim: "(\(build))")
						}
					}
					.font(.footnote.monospacedDigit())
					.foregroundStyle(.tertiary)
					.padding(.top, 2)
				}
			}
			.frame(maxWidth: .infinity)
			.listRowBackground(EmptyView())
			
			NBSection(.localized("Credits")) {
				ForEach(_credits, id: \.github) { credit in
					_credit(name: credit.name, desc: credit.desc, github: credit.github)
				}
				.transition(.slide)
			}

			Section {
				Text(.localized("Veather is based on Feather and is distributed under the GPL-3.0 license."))
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
	}
}

// MARK: - Extension: view
extension AboutView {
	@ViewBuilder
	private func _credit(
		name: String?,
		desc: String?,
		github: String
	) -> some View {
		Button {
			UIApplication.open("https://github.com/\(github)")
		} label: {
			HStack {
				FRIconCellView(
					title: name ?? github,
					subtitle: desc.map { String.localized($0) } ?? "",
					iconUrl: URL(string: "https://github.com/\(github.split(separator: "/").first.map(String.init) ?? github).png")!,
					size: 45,
					isCircle: true
				)
				
				Image(systemName: "arrow.up.right")
					.foregroundColor(.secondary.opacity(0.65))
			}
		}
	}
}
