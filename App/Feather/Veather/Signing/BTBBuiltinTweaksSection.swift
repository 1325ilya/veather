//
//  BTBBuiltinTweaksSection.swift
//  Veather
//
//  All built-in tweaks as toggles. Used on the main signing screen and in the
//  signing properties, so they are never hidden deep in a sub-menu.
//

import SwiftUI
import NimbleViews

struct BTBBuiltinTweaksSection: View {
	@Binding var options: Options

	var body: some View {
		if BTBBuiltinTweak.isAvailable {
			NBSection(.localized("Built-in Tweaks")) {
				ForEach(BTBBuiltinTweak.allCases) { tweak in
					Toggle(isOn: _binding(for: tweak)) {
						BTBRowLabel(
							tweak.title,
							systemImage: tweak.systemImage,
							color: .accentColor,
							subtitle: tweak.subtitle
						)
					}
				}
			} footer: {
				Text(.localized("Tweaks can be combined. They are added as one small library without Substrate."))
			}
		}
	}

	private func _binding(for tweak: BTBBuiltinTweak) -> Binding<Bool> {
		Binding(
			get: { options.btb_builtinTweaks.contains(tweak.rawValue) },
			set: { on in
				if on, let warning = tweak.warning {
					// the warning must be accepted before the tweak is switched on
					UIAlertController.showAlert(
						title: tweak.title,
						message: warning,
						actions: [
							UIAlertAction(title: .localized("Offline Games Only — Enable"), style: .destructive) { _ in
								options.btb_builtinTweaks.removeAll { $0 == tweak.rawValue }
								options.btb_builtinTweaks.append(tweak.rawValue)
							},
							UIAlertAction(title: .localized("Cancel"), style: .cancel)
						]
					)
					return
				}
				options.btb_builtinTweaks.removeAll { $0 == tweak.rawValue }
				if on { options.btb_builtinTweaks.append(tweak.rawValue) }
			}
		)
	}
}

/// "No signing": apply tweaks and options only and keep the result as an unsigned IPA
/// (signed later by another tool, or shared as it is).
struct BTBUnsignedExportSection: View {
	@Binding var options: Options

	var body: some View {
		NBSection(.localized("Unsigned IPA")) {
			Toggle(isOn: Binding(
				get: { options.signingOption == .onlyModify },
				set: { options.signingOption = $0 ? .onlyModify : .default }
			)) {
				BTBRowLabel(
					.localized("Add tweaks without signing"),
					systemImage: "shippingbox",
					color: .orange,
					subtitle: .localized("Get an unsigned IPA with your tweaks. No certificate needed.")
				)
			}
		} footer: {
			Text(.localized("When finished, tap Save IPA to put the file in Files or send it to another installer. It will not install by itself until it is signed."))
		}
	}
}
