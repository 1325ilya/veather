//
//  BTBAppLock.swift
//  BetterThanBox
//
//  App Lock (idea: VexSign AppLockManager): Face ID / Touch ID / passcode
//  before BetterThanBox shows anything — it holds your certificates.
//

import SwiftUI
import LocalAuthentication

final class BTBAppLock: ObservableObject {
	static let shared = BTBAppLock()
	static let enabledKey = "BTB.appLock.enabled"
	
	@Published private(set) var isLocked: Bool
	private var _isAuthenticating = false
	
	var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
	
	private init() {
		isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey)
	}
	
	func lockIfNeeded() {
		if isEnabled { isLocked = true }
	}
	
	func unlock() {
		guard isLocked, !_isAuthenticating else { return }
		_isAuthenticating = true
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
			// no passcode set on the device: nothing to authenticate against
			isLocked = false
			_isAuthenticating = false
			return
		}
		context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String.localized("Unlock BetterThanBox")) { success, _ in
			DispatchQueue.main.async {
				self._isAuthenticating = false
				if success { self.isLocked = false }
			}
		}
	}
	
	/// Asks for authentication before turning the lock on or off.
	func setEnabled(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
			completion(false)
			return
		}
		context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String.localized("Change App Lock")) { success, _ in
			DispatchQueue.main.async {
				if success { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
				completion(success)
			}
		}
	}
}

struct BTBAppLockOverlay: View {
	@ObservedObject private var _lock = BTBAppLock.shared
	@Environment(\.scenePhase) private var _scenePhase
	
	var body: some View {
		ZStack {
			if _lock.isLocked {
				Rectangle()
					.fill(.ultraThinMaterial)
					.ignoresSafeArea()
				VStack(spacing: 16) {
					Image(systemName: "lock.fill").font(.system(size: 44))
					Text(verbatim: "BetterThanBox").font(.title2.bold())
					Button {
						_lock.unlock()
					} label: {
						Label(.localized("Unlock"), systemImage: "faceid")
							.padding(.horizontal, 24).padding(.vertical, 10)
					}
					.buttonStyle(.borderedProminent)
				}
			}
		}
		.animation(.easeInOut(duration: 0.2), value: _lock.isLocked)
		.onAppear { _lock.unlock() }
		.onChange(of: _scenePhase) { phase in
			switch phase {
			case .background: _lock.lockIfNeeded()
			case .active: _lock.unlock()
			default: break
			}
		}
	}
}

struct BTBAppLockToggle: View {
	@State private var _enabled = BTBAppLock.shared.isEnabled
	
	var body: some View {
		Toggle(isOn: Binding(
			get: { _enabled },
			set: { newValue in
				BTBAppLock.shared.setEnabled(newValue) { success in
					_enabled = success ? newValue : BTBAppLock.shared.isEnabled
				}
			}
		)) {
			BTBRowLabel(.localized("App Lock (Face ID)"), systemImage: "faceid", color: .green)
		}
	}
}
