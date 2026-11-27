// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftParser
import SwiftSyntax
import Testing
@testable import SafeDICore

/// A snapshot looks a value up to the ID its builder gave it: every value interned before the snapshot was published, at
/// the ID it was given, and no value interned after. Two spellings of one type, or two encodings of one label, are two
/// values with two IDs.
struct ConstructionInternerLookupTests {
	private static func parsedType(_ source: String) -> TypeDescription {
		var parser = Parser(source)
		return TypeSyntax.parse(from: &parser).typeDescription
	}

	/// Spellings a run meets, with two that differ only in spelling, and two that differ only in their bytes.
	static let spellings = [
		"Service", "any Service", "Service?", "(any Service)?", "Instantiator<any Service>", "Instantiator<Service>",
		"SendableErasedInstantiator<(id: Int, name: String), any Service>", "Swift.Int", "Int", "[String: [Int]]",
		"@Sendable () async throws(MyError) -> Void", "A & B", "B & A", "Service.Protocol", "(any Service).Type",
		"inout Int", "T!", "caf\u{E9}", "cafe\u{301}", "Outer.Inner<Int>.Leaf", "some Service", "Int...",
	]

	@Test
	func id_answersEachValueAtItsID_inEverySnapshotPublishedAfterItWasInterned() {
		var builder = ConstructionInterner.Builder()
		var snapshots = [(interner: ConstructionInterner, typeCount: Int)]()
		var typeIDs = [TypeID]()
		var propertyIDs = [PropertyID]()
		var labelIDs = [LabelID]()
		// One value at a time, a snapshot after each, so that the snapshots hold every arrangement of frozen layers.
		for (index, spelling) in Self.spellings.enumerated() {
			let type = Self.parsedType(spelling)
			typeIDs.append(builder.intern(type))
			labelIDs.append(builder.intern(label: "label\(index)"))
			propertyIDs.append(builder.intern(Property(label: "label\(index)", typeDescription: type)))
			snapshots.append((builder.snapshot(), index + 1))
		}
		for (interner, typeCount) in snapshots {
			for (index, spelling) in Self.spellings.enumerated() {
				let type = Self.parsedType(spelling)
				let property = Property(label: "label\(index)", typeDescription: type)
				if index < typeCount {
					#expect(interner.id(of: type) == typeIDs[index], "\(spelling)")
					#expect(interner.id(ofLabel: "label\(index)") == labelIDs[index])
					#expect(interner.id(of: property) == propertyIDs[index], "\(spelling)")
					#expect(interner.label(of: propertyIDs[index]) == labelIDs[index])
					#expect(interner.type(of: propertyIDs[index]) == typeIDs[index])
				} else {
					#expect(interner.id(ofLabel: "label\(index)") == nil)
					#expect(interner.id(of: property) == nil, "\(spelling)")
				}
			}
		}
	}

	@Test
	func id_tellsSpellingsApart_whenTypesAreEqual() {
		var builder = ConstructionInterner.Builder()
		let anyService = builder.intern(Self.parsedType("any Service"))
		let service = builder.intern(Self.parsedType("Service"))
		let composed = builder.intern(label: "caf\u{E9}")
		let decomposed = builder.intern(label: "cafe\u{301}")
		let interner = builder.snapshot()
		#expect(anyService != service)
		#expect(interner.id(of: Self.parsedType("any Service")) == anyService)
		#expect(interner.id(of: Self.parsedType("Service")) == service)
		#expect(composed != decomposed)
		#expect(interner.id(ofLabel: "caf\u{E9}") == composed)
		#expect(interner.id(ofLabel: "cafe\u{301}") == decomposed)
	}

	@Test
	func id_answersNil_whenAPartOfTheValueWasNeverInterned() {
		var builder = ConstructionInterner.Builder()
		_ = builder.intern(Property(label: "service", typeDescription: Self.parsedType("Service")))
		let interner = builder.snapshot()
		// The generic argument, the label, or the type was never interned.
		#expect(interner.id(of: Self.parsedType("Instantiator<Gadget>")) == nil)
		#expect(interner.id(of: Self.parsedType("Instantiator<Service>")) == nil)
		#expect(interner.id(of: Property(label: "gadget", typeDescription: Self.parsedType("Service"))) == nil)
		#expect(interner.id(of: Property(label: "service", typeDescription: Self.parsedType("Gadget"))) == nil)
	}

	@Test
	func id_answersEveryValue_whenManySnapshotsAreMergedIntoFewLayers() {
		var builder = ConstructionInterner.Builder()
		var typeIDs = [TypeID]()
		for index in 0..<300 {
			typeIDs.append(builder.intern(.simple(name: "Type\(index)", generics: [])))
			// Publish after a varying number of values, so that layers of every size are merged.
			if index % (index % 5 + 1) == 0 {
				_ = builder.snapshot()
			}
		}
		let interner = builder.snapshot()
		#expect(interner.layerCount <= 10)
		for index in 0..<300 {
			#expect(interner.id(of: .simple(name: "Type\(index)", generics: [])) == typeIDs[index])
		}
	}
}
