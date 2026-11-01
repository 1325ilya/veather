//
//  BTBDesign.swift
//  BetterThanBox
//
//  Shared visual building blocks: Settings-style coloured icon tiles,
//  list rows that use them, and the card used on the Tools tab.
//

import SwiftUI

enum BTBDesign {
	/// Default accent colour of BetterThanBox.
	static let brandHex = "#7C5CFF"
	static let cardRadius: CGFloat = 20
}

/// A rounded square with a white SF Symbol, like the icons in the system Settings app.
struct BTBIconTile: View {
	let systemImage: String
	let color: Color
	var size: CGFloat = 29

	var body: some View {
		Image(systemName: systemImage)
			.font(.system(size: size * 0.52, weight: .semibold))
			.symbolRenderingMode(.monochrome)
			.foregroundStyle(.white)
			.frame(width: size, height: size)
			.background(
				RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
					.fill(color.gradient)
			)
			.accessibilityHidden(true)
	}
}

/// List row label with a coloured icon tile.
struct BTBRowLabel: View {
	let title: String
	let systemImage: String
	let color: Color
	var subtitle: String? = nil

	init(_ title: String, systemImage: String, color: Color, subtitle: String? = nil) {
		self.title = title
		self.systemImage = systemImage
		self.color = color
		self.subtitle = subtitle
	}

	var body: some View {
		HStack(spacing: 14) {
			BTBIconTile(systemImage: systemImage, color: color)
			VStack(alignment: .leading, spacing: 1) {
				Text(title)
					.foregroundStyle(.primary)
				if let subtitle {
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(2)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
		}
		.padding(.vertical, 1)
	}
}

/// Card used in grids (Tools tab, quick actions).
struct BTBCard: View {
	let title: String
	let subtitle: String
	let systemImage: String
	let color: Color

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			BTBIconTile(systemImage: systemImage, color: color, size: 38)
			VStack(alignment: .leading, spacing: 3) {
				Text(title)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.primary)
					.lineLimit(2, reservesSpace: true)
					.minimumScaleFactor(0.8)
					.multilineTextAlignment(.leading)
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(Color(uiColor: .secondaryLabel))
					.lineLimit(2, reservesSpace: true)
					.minimumScaleFactor(0.85)
					.multilineTextAlignment(.leading)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.background(
			RoundedRectangle(cornerRadius: BTBDesign.cardRadius, style: .continuous)
				.fill(Color(uiColor: .secondarySystemGroupedBackground))
		)
		.overlay(
			RoundedRectangle(cornerRadius: BTBDesign.cardRadius, style: .continuous)
				.strokeBorder(color.opacity(0.12), lineWidth: 1)
		)
		.contentShape(RoundedRectangle(cornerRadius: BTBDesign.cardRadius, style: .continuous))
	}
}

/// Compact vertical tile for a row of quick actions inside a list.
struct BTBQuickTile: View {
	let title: String
	let systemImage: String
	let color: Color

	var body: some View {
		VStack(spacing: 8) {
			BTBIconTile(systemImage: systemImage, color: color, size: 40)
			Text(title)
				.font(.caption.weight(.medium))
				.foregroundStyle(.primary)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 12)
		.background(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(color.opacity(0.10))
		)
		.contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
}

/// Press feedback for cards wrapped in NavigationLink / Button.
struct BTBPressableStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.scaleEffect(configuration.isPressed ? 0.97 : 1)
			.opacity(configuration.isPressed ? 0.85 : 1)
			.animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
	}
}
