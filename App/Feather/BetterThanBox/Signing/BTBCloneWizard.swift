//
//  BTBCloneWizard.swift
//  BetterThanBox
//
//  Clone Wizard (ideas: VexSign CloneWizard, SignOs App Cloner):
//  signs 2…20 copies of one app with numbered bundle IDs and names,
//  so several accounts of the same app can live side by side.
//  The number is drawn as a badge on the icon.
//

import UIKit

enum BTBCloneWizard {
	static let maxClones = 20

	static func sign(
		_ app: AppInfoPresentable,
		using options: Options,
		icon: UIImage?,
		certificate: CertificatePair?,
		count: Int,
		progress: @escaping (Int) -> Void,
		completion: @escaping (Error?) -> Void
	) {
		let baseIdentifier = options.appIdentifier ?? app.identifier ?? "app"
		let baseName = options.appName ?? app.name ?? "App"
		let baseIcon = icon ?? appIcon(for: app)

		Task {
			for index in 1...max(1, min(count, maxClones)) {
				await MainActor.run { progress(index) }
				var cloneOptions = options
				cloneOptions.appIdentifier = "\(baseIdentifier).clone\(index)"
				cloneOptions.appName = "\(baseName) \(index)"
				let badged = baseIcon.map { badge($0, number: index) }

				let error: Error? = await withCheckedContinuation { continuation in
					FR.signPackageFile(app, using: cloneOptions, icon: badged, certificate: certificate) { error in
						continuation.resume(returning: error)
					}
				}
				if let error {
					await MainActor.run { completion(error) }
					return
				}
			}
			await MainActor.run { completion(nil) }
		}
	}

	/// Largest icon PNG listed in the app's Info.plist.
	static func appIcon(for app: AppInfoPresentable) -> UIImage? {
		guard let dir = Storage.shared.getAppDirectory(for: app) else { return nil }
		if let name = app.icon, let image = UIImage(contentsOfFile: dir.appendingPathComponent(name).path) {
			return image
		}
		let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
		let candidates = files
			.filter { $0.lowercased().hasPrefix("appicon") && $0.hasSuffix(".png") }
			.compactMap { UIImage(contentsOfFile: dir.appendingPathComponent($0).path) }
		return candidates.max { $0.size.width < $1.size.width }
	}

	static func badge(_ image: UIImage, number: Int) -> UIImage {
		let size = CGSize(width: 512, height: 512)
		let renderer = UIGraphicsImageRenderer(size: size)
		return renderer.image { context in
			image.draw(in: CGRect(origin: .zero, size: size))
			let diameter: CGFloat = 190
			let circle = CGRect(x: size.width - diameter - 16, y: 16, width: diameter, height: diameter)
			UIColor.systemRed.setFill()
			context.cgContext.fillEllipse(in: circle)
			let text = "\(number)" as NSString
			let attributes: [NSAttributedString.Key: Any] = [
				.font: UIFont.systemFont(ofSize: number >= 10 ? 100 : 130, weight: .heavy),
				.foregroundColor: UIColor.white
			]
			let textSize = text.size(withAttributes: attributes)
			text.draw(
				at: CGPoint(x: circle.midX - textSize.width / 2, y: circle.midY - textSize.height / 2),
				withAttributes: attributes
			)
		}
	}
}
