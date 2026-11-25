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

/// The interner's class projection of a type is `TypeDescription.==`, exactly: two types get one class ID exactly when
/// `==` holds, and then equal hashes. Its exact ID tells every two spellings apart, and its alike ID is the class and the
/// spelling's bytes together.
struct ConstructionInternerProjectionTests {
	private static func parsedType(_ source: String) -> TypeDescription {
		var parser = Parser(source)
		return TypeSyntax.parse(from: &parser).typeDescription
	}

	/// Pairs of spellings, and whether `==` holds between them.
	static let pairs: [(String, String, Bool)] = [
		("any Service", "Service", true),
		("(any Service)?", "Service?", true),
		("Instantiator<any Service>", "Instantiator<Service>", true),
		("some Service", "Service", false),
		("Void", "()", true),
		("A & B", "B & A", true),
		("A & B & A", "A & B", true),
		("A & (any B)", "B & A", true),
		("Service.Protocol", "(any Service).Type", true),
		("Service.Type", "(any Service).Type", false),
		("Service.Protocol", "Service.Type", false),
		("() throws -> Void", "() throws(any Error) -> Void", true),
		("() throws -> Void", "() throws(Swift.Error) -> Void", true),
		("() throws -> Void", "() throws(any Swift.Error) -> Void", true),
		("() throws(MyError) -> Void", "() throws -> Void", false),
		("@Sendable () -> Void", "@escaping @Sendable () -> Void", false),
		("inout Int", "Int", false),
		("caf\u{E9}", "cafe\u{301}", true),
		("(a: Int, c: Int)", "(b: Int, c: Int)", false),
		("Swift.Int", "Int", false),
		("T!", "T?", false),
	]

	@Test(arguments: pairs)
	func classID_equalsExactlyWhenTypesAreEqual_forHandwrittenPair(_ pair: (String, String, Bool)) {
		let lhs = Self.parsedType(pair.0)
		let rhs = Self.parsedType(pair.1)
		#expect((lhs == rhs) == pair.2)
		var builder = ConstructionInterner.Builder()
		let lhsID = builder.intern(lhs)
		let rhsID = builder.intern(rhs)
		let interner = builder.snapshot()
		#expect((interner.classID(of: lhsID) == interner.classID(of: rhsID)) == pair.2)
		if pair.2 {
			#expect(lhs.hashValue == rhs.hashValue)
		}
	}

	@Test(arguments: pairs)
	func exactID_differs_whenSpellingsDiffer(_ pair: (String, String, Bool)) {
		var builder = ConstructionInterner.Builder()
		let lhsID = builder.intern(Self.parsedType(pair.0))
		let rhsID = builder.intern(Self.parsedType(pair.1))
		let interner = builder.snapshot()
		#expect(lhsID != rhsID)
		#expect(interner.alikeID(of: lhsID) != interner.alikeID(of: rhsID))
	}

	@Test
	func exactID_isOneID_whenOneSpellingIsInternedTwice() {
		var builder = ConstructionInterner.Builder()
		let first = builder.intern(Self.parsedType("Instantiator<any Service>"))
		let second = builder.intern(Self.parsedType("Instantiator<any Service>"))
		#expect(first == second)
	}

	@Test
	func labelClassID_equalsAndLabelID_differs_whenLabelsAreCanonicallyEquivalent() {
		var builder = ConstructionInterner.Builder()
		let composed = builder.intern(label: "caf\u{E9}")
		let decomposed = builder.intern(label: "cafe\u{301}")
		let interner = builder.snapshot()
		#expect(composed != decomposed)
		#expect(interner.classID(of: composed) == interner.classID(of: decomposed))
	}

	/// Spellings of every kind of type, each against all the others.
	static let spellings = [
		"Int", "Swift.Int", "any Service", "Service", "some Service", "Service?", "Service!", "(any Service)?",
		"[Int]", "Array<Int>", "[Int: String]", "[String: Int]", "Dictionary<Int, String>", "(Int...) -> Void",
		"(Int) -> Void", "(Int) async -> Void", "(Int) async throws -> Void", "() throws(MyError) -> Int",
		"(a: Int, c: Int)", "(Int, Int)", "InlineArray<3, Int>", "InlineArray<4, Int>", "Void", "()",
		"Service.Type", "Service.Protocol", "(any Service).Type", "A & B", "B & A", "A & B & C",
		"@Sendable () -> Void", "@MainActor () -> Void", "inout Int", "Outer.Inner<Int>", "Outer.Inner<any Service>",
		"Instantiator<Service>", "Instantiator<any Service>", "caf\u{E9}", "cafe\u{301}",
	]

	@Test
	func classID_equalsExactlyWhenTypesAreEqual_forEveryPairOfSpellings() {
		let types = Self.spellings.map(Self.parsedType)
		var builder = ConstructionInterner.Builder()
		let ids = types.map { builder.intern($0) }
		let interner = builder.snapshot()
		for (lhsIndex, lhs) in types.enumerated() {
			for (rhsIndex, rhs) in types.enumerated() {
				#expect(
					(interner.classID(of: ids[lhsIndex]) == interner.classID(of: ids[rhsIndex])) == (lhs == rhs),
					"\(Self.spellings[lhsIndex]) against \(Self.spellings[rhsIndex])",
				)
				#expect(
					(interner.alikeID(of: ids[lhsIndex]) == interner.alikeID(of: ids[rhsIndex])) == (lhs == rhs && lhs.asSource.utf8.elementsEqual(rhs.asSource.utf8)),
					"\(Self.spellings[lhsIndex]) against \(Self.spellings[rhsIndex])",
				)
			}
		}
	}

	@Test
	func snapshot_answersEveryEarlierID_whenBuilderGrowsPastSeveralChunks() {
		var builder = ConstructionInterner.Builder()
		let earlierIDs = (0..<(ChunkedTable<LabelID>.chunkSize + 4)).map { builder.intern(label: "label\($0)") }
		let earlier = builder.snapshot()
		let earlierClasses = earlierIDs.map { earlier.classID(of: $0) }
		let laterIDs = (0..<(ChunkedTable<LabelID>.chunkSize * 2)).map { builder.intern(label: "other\($0)") }
		let later = builder.snapshot()
		#expect(earlierIDs.map { later.classID(of: $0) } == earlierClasses)
		#expect(Set(earlierClasses).count == earlierIDs.count)
		#expect(Set(laterIDs.map { later.classID(of: $0) }).isDisjoint(with: earlierClasses))
	}

	/// Labels and types of properties, each property against all the others: a label's canonically equivalent spellings,
	/// and wrappers whose instance and validated forms differ.
	static let propertyLabels = ["service", "caf\u{E9}", "cafe\u{301}"]
	static let propertyTypes = [
		"Service", "any Service", "Service?", "LazilyInstantiated<Service>", "LazilyInstantiated<any Service>",
		"LazilyInstantiated<Service>?", "LazilyInstantiated<Service?>", "SendableLazilyInstantiated<Service>",
		"Kit.LazilyInstantiated<Service>", "Instantiator<Service>",
	]

	static var properties: [Property] {
		propertyLabels.flatMap { label in
			propertyTypes.map { Property(label: label, typeDescription: parsedType($0)) }
		}
	}

	@Test
	func propertyClassID_equalsExactlyWhenPropertiesAreEqual_forEveryPairOfProperties() {
		let properties = Self.properties
		var builder = ConstructionInterner.Builder()
		let ids = properties.map { builder.intern($0) }
		let interner = builder.snapshot()
		for (lhsIndex, lhs) in properties.enumerated() {
			for (rhsIndex, rhs) in properties.enumerated() {
				#expect(
					(interner.classID(of: ids[lhsIndex]) == interner.classID(of: ids[rhsIndex])) == (lhs == rhs),
					"\(lhs.asSource) against \(rhs.asSource)",
				)
				#expect((ids[lhsIndex] == ids[rhsIndex]) == (lhs.label.utf8.elementsEqual(rhs.label.utf8) && lhs.typeDescription.asSource == rhs.typeDescription.asSource))
			}
		}
	}

	@Test
	func derivedForms_areTheIDsOfWhatPropertyHelpersReturn_forEveryProperty() {
		var builder = ConstructionInterner.Builder()
		let ids = Self.properties.map { builder.intern($0) }
		let validatedIDs = Self.properties.map { builder.intern($0.asValidatedForDependencyCycles) }
		let instanceIDs = Self.properties.map { $0.asLazilyInstantiatedInstanceProperty.map { builder.intern($0) } }
		let interner = builder.snapshot()
		for (index, property) in Self.properties.enumerated() {
			#expect(interner.asValidatedForDependencyCycles(ids[index]) == validatedIDs[index], "\(property.asSource)")
			#expect(interner.lazilyInstantiated(ids[index]).map { interner.instance(of: $0) } == instanceIDs[index], "\(property.asSource)")
		}
		#expect(instanceIDs.contains(nil))
		#expect(instanceIDs.contains { $0 != nil })
	}

	@Test
	func internDeclarations_internsWhatDeclarationsSpellBeforeAnythingElse_whenGivenInstantiables() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		@Instantiable
		public final class Root: Instantiable {
			public init(service: any Service, renamed: Service, lazy: LazilyInstantiated<Store>, value: Int) {
				fatalError()
			}

			@Instantiated(fulfilledByType: "DefaultService", erasedToConcreteExistential: false) let service: any Service
			@Received(fulfilledByDependencyNamed: "service", ofType: (any Service).self) let renamed: Service
			@Instantiated let lazy: LazilyInstantiated<Store>
			@Forwarded let value: Int
		}
		"""))
		var builder = ConstructionInterner.Builder()
		builder.internDeclarations(of: fileVisitor.instantiables)
		let dependencies = fileVisitor.instantiables.flatMap(\.dependencies)
		#expect(dependencies.count == 4)
		var spelled = dependencies.map(\.property)
		spelled.append(Property(label: "service", typeDescription: Self.parsedType("Service")))
		spelled.append(Property(label: "lazy", typeDescription: Self.parsedType("Store")))
		let types = ["Root", "DefaultService", "Store"].map(Self.parsedType)
		let afterwards = builder.intern(Property(label: "unseen", typeDescription: Self.parsedType("Unseen")))
		let afterwardsType = builder.intern(Self.parsedType("Unseen"))
		for property in spelled {
			#expect(builder.intern(property).raw < afterwards.raw, "\(property.asSource)")
		}
		for type in types {
			#expect(builder.intern(type).raw < afterwardsType.raw, "\(type.asSource)")
		}
	}
}
