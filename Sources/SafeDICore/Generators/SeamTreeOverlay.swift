// PROTOTYPE of D2's overlay: never commit.
import Foundation

/// What a seam's emission reads of the generators of the tree its first signature pass built, in place of what each
/// stored at construction, by generator identity: filled by one walk of the settled tree, from the final signature.
struct SeamTreeOverlay: Sendable {
	struct Entry: Sendable {
		let scopeData: ScopeGenerator.ScopeData
		let seamAndFillFieldsStorage: ScopeGenerator.SeamAndFillFieldsStorage?
		let fieldsCarriedBySites: Set<Property>
	}

	var entries = [ObjectIdentifier: Entry]()

	/// The overlay the writer reads; `nil` outside a reused seam tree's emission.
	@TaskLocal static var current: SeamTreeOverlay?

	/// Joins `other`, another seam's overlay. A generator two seams' trees share must have one entry.
	mutating func merge(_ other: SeamTreeOverlay) {
		for (key, entry) in other.entries {
			if entries[key] != nil {
				SeamTreeOverlayConflicts.record()
			}
			entries[key] = entry
		}
	}
}

/// Counts generators two seams' first-pass trees share (PROTOTYPE diagnostics: printed with SAFEDI_OVERLAY_REPORT).
enum SeamTreeOverlayConflicts {
	static func reportReuse(of seam: String, entries: Int) {
		if ProcessInfo.processInfo.environment["SAFEDI_OVERLAY_REPORT"] != nil {
			FileHandle.standardError.write("SAFEDI_OVERLAY reused \(seam) entries \(entries)\n".data(using: .utf8)!)
		}
	}

	static func record() {
		if ProcessInfo.processInfo.environment["SAFEDI_OVERLAY_REPORT"] != nil {
			FileHandle.standardError.write("SAFEDI_OVERLAY conflict: a generator in two seams' trees\n".data(using: .utf8)!)
		}
	}
}
