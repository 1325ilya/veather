//
//  BTBCertHealthView.swift
//  BetterThanBox
//
//  Certificate health dashboard (idea: BatSign CertHealthView):
//  days-left rings, OCSP revocation re-check for every certificate,
//  number of signed apps that depend on each one.
//

import SwiftUI
import CoreData
import Zsign
import NimbleViews

enum BTBCertStatus: Equatable {
	case unknown, checking, valid, revoked, failed(String)
	
	var title: String {
		switch self {
		case .unknown: .localized("Not checked")
		case .checking: .localized("Checking…")
		case .valid: .localized("Valid")
		case .revoked: .localized("Revoked")
		case .failed: .localized("Check failed")
		}
	}
	
	var color: Color {
		switch self {
		case .valid: .green
		case .revoked: .red
		case .failed: .orange
		default: .secondary
		}
	}
}

enum BTBCertHealth {
	/// Re-checks a certificate with OCSP (works both ways: also clears a stale "revoked" flag).
	static func check(_ cert: CertificatePair, completion: @escaping (BTBCertStatus) -> Void) {
		Zsign.checkRevokage(
			provisionPath: Storage.shared.getFile(.provision, from: cert)?.path ?? "",
			p12Path: Storage.shared.getFile(.certificate, from: cert)?.path ?? "",
			p12Password: cert.password ?? ""
		) { status, _, error in
			DispatchQueue.main.async {
				switch status {
				case 0:
					cert.revoked = false
					Storage.shared.saveContext()
					completion(.valid)
				case 1:
					cert.revoked = true
					Storage.shared.saveContext()
					completion(.revoked)
				default:
					completion(.failed(error ?? ""))
				}
			}
		}
	}
	
	static let lastCheckKey = "BTB.certHealth.lastCheck"
	
	/// Background re-check of all certificates, at most every 6 hours.
	static func checkAllIfNeeded() {
		let last = UserDefaults.standard.double(forKey: lastCheckKey)
		guard Date().timeIntervalSince1970 - last > 6 * 3600 else { return }
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
		for cert in Storage.shared.getAllCertificates() {
			check(cert) { _ in }
		}
	}
}

struct BTBCertHealthView: View {
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>
	
	@State private var _statuses: [NSManagedObjectID: BTBCertStatus] = [:]
	
	private var _summary: (valid: Int, expiring: Int, dead: Int) {
		var valid = 0, expiring = 0, dead = 0
		for cert in _certificates {
			let days = _daysLeft(cert)
			if cert.revoked || days < 0 { dead += 1 }
			else if days <= 7 { expiring += 1 }
			else { valid += 1 }
		}
		return (valid, expiring, dead)
	}
	
	var body: some View {
		List {
			Section {
				let s = _summary
				HStack {
					_summaryCell(count: s.valid, title: .localized("Healthy"), color: .green)
					_summaryCell(count: s.expiring, title: .localized("Expiring"), color: .orange)
					_summaryCell(count: s.dead, title: .localized("Dead"), color: .red)
				}
				Button(.localized("Check All Now"), systemImage: "arrow.clockwise.circle") {
					_checkAll()
				}
				.disabled(_certificates.isEmpty)
			} footer: {
				Text(.localized("Revocation is checked with Apple's OCSP responder. Certificates are also re-checked automatically in the background every few hours."))
			}
			
			NBSection(.localized("Certificates"), secondary: _certificates.count.description) {
				ForEach(_certificates) { cert in
					_row(cert)
				}
			}
		}
		.navigationTitle(.localized("Certificate Health"))
		.overlay {
			if _certificates.isEmpty {
				Text(.localized("No certificates imported yet.")).foregroundStyle(.secondary)
			}
		}
	}
	
	@ViewBuilder
	private func _summaryCell(count: Int, title: String, color: Color) -> some View {
		VStack {
			Text("\(count)").font(.title2.bold()).foregroundStyle(color)
			Text(title).font(.caption).foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
	}
	
	@ViewBuilder
	private func _row(_ cert: CertificatePair) -> some View {
		let days = _daysLeft(cert)
		let decoded = Storage.shared.getProvisionFileDecoded(for: cert)
		let total = max(1, decoded.map { Calendar.current.dateComponents([.day], from: $0.CreationDate, to: $0.ExpirationDate).day ?? 365 } ?? 365)
		let status = _statuses[cert.objectID] ?? (cert.revoked ? .revoked : .unknown)
		
		HStack(spacing: 14) {
			ZStack {
				Circle().stroke(Color(.quaternarySystemFill), lineWidth: 5)
				Circle()
					.trim(from: 0, to: max(0, min(1, CGFloat(days) / CGFloat(total))))
					.stroke(_ringColor(days: days, revoked: cert.revoked), style: StrokeStyle(lineWidth: 5, lineCap: .round))
					.rotationEffect(.degrees(-90))
				Text(days < 0 ? "✕" : "\(days)")
					.font(.caption.bold())
			}
			.frame(width: 44, height: 44)
			
			VStack(alignment: .leading, spacing: 3) {
				Text(cert.nickname ?? decoded?.Name ?? .localized("Unknown"))
					.font(.headline)
					.lineLimit(1)
				Text(decoded?.TeamName ?? "")
					.font(.footnote).foregroundStyle(.secondary)
				HStack(spacing: 6) {
					Text(status.title).foregroundStyle(status.color)
					Text("•")
					Text(.localized("%lld signed apps", arguments: cert.signedApps?.count ?? 0))
				}
				.font(.caption)
			}
			Spacer()
			if status == .checking {
				ProgressView()
			} else {
				Button {
					_check(cert)
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.buttonStyle(.borderless)
			}
		}
	}
	
	private func _daysLeft(_ cert: CertificatePair) -> Int {
		guard let exp = cert.expiration else { return -1 }
		let seconds = exp.timeIntervalSinceNow
		return seconds < 0 ? -1 : Int(seconds / 86400)
	}
	
	private func _ringColor(days: Int, revoked: Bool) -> Color {
		if revoked || days < 0 { return .red }
		if days <= 7 { return .orange }
		return .green
	}
	
	private func _check(_ cert: CertificatePair) {
		_statuses[cert.objectID] = .checking
		BTBCertHealth.check(cert) { status in
			_statuses[cert.objectID] = status
		}
	}
	
	private func _checkAll() {
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: BTBCertHealth.lastCheckKey)
		for cert in _certificates { _check(cert) }
	}
}
