//
//  InstallProgressView.swift
//  Feather
//
//  Created by samara on 23.04.2025.
//

import SwiftUI
import IDeviceSwift

struct InstallProgressView: View {
	@State private var _isPulsing = false
	
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel
	
	var body: some View {
		VStack(spacing: 12) {
			_appIcon()
				.scaleEffect(_isPulsing ? 0.85 : 0.81)
				.animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: _isPulsing)
				.onAppear {
					_isPulsing = true
				}
		}
	}
	
	@ViewBuilder
	private func _appIcon() -> some View {
		ZStack {
			FRAppIconView(app: app)
				.opacity(0.2)
				.frame(width: 54, height: 54)
				.foregroundStyle(Color.black)
			
			FRAppIconView(app: app)
				.frame(width: 54, height: 54)
				.mask(
					ZStack {
						Circle().strokeBorder(Color.white, lineWidth: 4.5)
						PieShape(progress: viewModel.overallProgress)
							.scaleEffect(viewModel.isCompleted ? 2.2 : 1)
							.animation(.smooth, value: viewModel.isCompleted)
					}
				)
				.animation(.smooth, value: viewModel.overallProgress)
		}
		.overlay(alignment: .bottomTrailing) {
			if viewModel.isCompleted {
				Image(systemName: "checkmark.circle.fill")
					.font(.system(size: 22, weight: .bold))
					.symbolRenderingMode(.palette)
					.foregroundStyle(.white, Color.green)
					.background(Circle().fill(Color(UIColor.secondarySystemBackground)).padding(-2))
					.offset(x: 8, y: 8)
					.transition(.scale.combined(with: .opacity))
			}
		}
		.animation(.spring(response: 0.4, dampingFraction: 0.6), value: viewModel.isCompleted)
	}
	
	struct PieShape: Shape {
		var progress: Double
		
		func path(in rect: CGRect) -> Path {
			var path = Path()
			let center = CGPoint(x: rect.midX, y: rect.midY)
			let radius = min(rect.width, rect.height) / 2
			let startAngle = Angle(degrees: -90)
			let endAngle = Angle(degrees: -90 + progress * 360)
			
			path.move(to: center)
			path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
			path.closeSubpath()
			
			return path
		}
		
		var animatableData: Double {
			get { progress }
			set { progress = newValue }
		}
	}
}
