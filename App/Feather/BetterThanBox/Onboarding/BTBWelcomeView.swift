//
//  BTBWelcomeView.swift
//  BetterThanBox
//
//  One-time welcome sheet: three steps from an .ipa to an installed app.
//

import SwiftUI
import CoreData

struct BTBWelcomeView: View {
	static let seenKey = "BTB.welcomeSeen"

	@Environment(\.dismiss) private var dismiss
	@State private var _showCertificates = false

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 28) {
					VStack(spacing: 12) {
						FRAppIconView(size: 88)
							.shadow(color: Color.accentColor.opacity(0.4), radius: 18, y: 8)
						Text(.localized("Welcome to Veather"))
							.font(.largeTitle.weight(.bold))
							.multilineTextAlignment(.center)
						Text(.localized("Sign and install apps right on your iPhone"))
							.font(.body)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}
					.padding(.top, 32)

					VStack(alignment: .leading, spacing: 22) {
						_step(
							1,
							title: .localized("Add an app"),
							text: .localized("Tap + in Library, paste a link, or share an .ipa from the Files app."),
							systemImage: "square.and.arrow.down.fill",
							color: .blue
						)
						_step(
							2,
							title: .localized("Add your certificate"),
							text: .localized("Import your .p12 and .mobileprovision once — they stay on this device."),
							systemImage: "checkmark.seal.fill",
							color: .green
						)
						_step(
							3,
							title: .localized("Sign and install"),
							text: .localized("Tap Sign next to the app, then Install. Done."),
							systemImage: "signature",
							color: .purple
						)
					}
					.padding(.horizontal, 4)
				}
				.padding(.horizontal, 24)
				.padding(.bottom, 24)
			}
			.safeAreaInset(edge: .bottom) {
				VStack(spacing: 10) {
					Button {
						_finish()
					} label: {
						Text(.localized("Get Started"))
							.font(.headline)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 6)
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.large)

					Button {
						_showCertificates = true
					} label: {
						Text(.localized("Add Certificate Now"))
							.font(.subheadline.weight(.semibold))
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.borderless)
				}
				.padding(.horizontal, 24)
				.padding(.vertical, 12)
				.background(.bar)
			}
			.navigationDestination(isPresented: $_showCertificates) {
				CertificatesView()
			}
		}
		.interactiveDismissDisabled()
	}

	private func _step(_ number: Int, title: String, text: String, systemImage: String, color: Color) -> some View {
		HStack(alignment: .top, spacing: 16) {
			BTBIconTile(systemImage: systemImage, color: color, size: 44)
			VStack(alignment: .leading, spacing: 3) {
				Text(verbatim: "\(number). \(title)")
					.font(.headline)
				Text(text)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	private func _finish() {
		UserDefaults.standard.set(true, forKey: Self.seenKey)
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		dismiss()
	}
}

/// Shows the welcome sheet once, on first launch.
struct BTBWelcomeModifier: ViewModifier {
	@AppStorage(BTBWelcomeView.seenKey) private var _seen = false
	@State private var _isPresented = false

	func body(content: Content) -> some View {
		content
			.onAppear {
				guard !_seen else { return }
				// people updating from an older build already know the app
				if _hasExistingData() {
					_seen = true
				} else {
					_isPresented = true
				}
			}
			.sheet(isPresented: $_isPresented, onDismiss: { _seen = true }) {
				BTBWelcomeView()
			}
	}
}

private func _hasExistingData() -> Bool {
	let context = Storage.shared.context
	for entity in ["CertificatePair", "Imported", "Signed"] {
		let request = NSFetchRequest<NSManagedObject>(entityName: entity)
		request.fetchLimit = 1
		if let count = try? context.count(for: request), count > 0 { return true }
	}
	return false
}

extension View {
	func btbWelcomeOnFirstLaunch() -> some View {
		modifier(BTBWelcomeModifier())
	}
}
