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

/// What the type key (`TypeKeyBody`) reads of one place of a production body's walk, recorded where the path key's emitter
/// writes the place: enough to spell the place again in the type key's layout, and to check that layout against the path
/// key's. A place the emitter writes with anything the type key does not plan yet – a seam's call or hosted code, a fill, a
/// public mock's call, a hand-written mock, a member of a loop of builders, a payload binding – records nothing, and its
/// root keeps the path key's body.
enum PlaceRecord: Sendable {
	/// A property the place builds: by a builder function of its own, or, for a constant whose function would write nothing
	/// but its value, in place.
	case built(BuiltPlaceRecord)
	/// A scope that closes a cycle on the function of an enclosing place.
	case closer(ClosingPlaceRecord)
	/// A rename of a value.
	case alias(AliasPlaceRecord)
}

/// A read a construction or a call makes: the argument it passes, the label it reads, the property its receiver declares,
/// and where the path key reads it from.
struct PlaceRead: Sendable {
	/// The argument's label at the call.
	let argumentLabel: String
	/// The label the argument reads.
	let label: String
	/// The property the receiver declares.
	let property: Property
	/// Where the path key reads the value: the nearest declaration of `label`, its lazy wrapper's instance, or `nil`.
	let source: ArgumentSource
}

/// A place that builds `property`.
struct BuiltPlaceRecord: Sendable {
	let property: Property
	let isErased: Bool
	let concreteType: TypeDescription
	/// Whether the built type is declared through an extension, which decides how its bindings are annotated.
	let isExtension: Bool
	let target: ConstructionTarget
	/// The construction's arguments, in the initializer's order.
	let arguments: [PlaceRead]
	/// The properties the place's wrapper forwards, sorted.
	let forwardedProperties: [Property]
	/// The parameters the path key's function takes for a lazy cycle that closes on it.
	let cycleParameters: [Property]
	/// What the place's binding passes those parameters.
	let callCycleArguments: [PlaceRead]
	/// The path key's name of the place's function.
	let functionName: String
	let isSendable: Bool
	let isNonisolated: Bool
	let typesDeclaredEscaping: Set<TypeDescription>
	/// What ends the line that constructs the type.
	let lineEnd: String
	/// Whether the place declares a builder function: `false` only for a constant built in place.
	let hasFunction: Bool
	/// The code of the places the function's body builds, in order.
	let children: [GeneratedCode]
	/// The generator that wrote the place, which the construction memo shares between the places it finds alike.
	let generator: ObjectIdentifier
	/// The place's code as one node of the plan: made once each time a generator writes its code for a context, and
	/// shared by every place that reads that code from the generator's cache.
	let node = PlanNode()
}

/// The identity of one node of a root's plan (`BuiltPlaceRecord.node`), compared by identity.
final class PlanNode: Hashable, Sendable {
	static func == (lhs: PlanNode, rhs: PlanNode) -> Bool {
		lhs === rhs
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(ObjectIdentifier(self))
	}
}

/// A place that closes a cycle on the function the path key names `closedOnFunctionName`.
struct ClosingPlaceRecord: Sendable {
	let property: Property
	let isErased: Bool
	/// Whether the type the closed-on function builds is declared through an extension.
	let isExtension: Bool
	let closedOnFunctionName: String
	/// The properties the place's wrapper forwards, sorted.
	let forwardedProperties: [Property]
	/// What the place passes the parameters of the function it calls.
	let cycleArguments: [PlaceRead]
}

/// A rename of a value, written as the path key writes it.
struct AliasPlaceRecord: Sendable {
	let property: Property
	/// The property the rename reads, or `nil` where it is bound to `nil`.
	let fulfillingProperty: Property?
	/// The rename's code, its lines unindented.
	let text: String
}

/// Which body a production root's code is laid out in. The type key is the tool's; a test sets the path key to compare
/// with it.
public enum ProductionBodyKey: Sendable {
	/// Every place has a builder function of its own.
	case path
	/// Places that build one type alike share one builder function (`TypeKeyBody`).
	case type

	/// The key the current task lays production bodies out with.
	@TaskLocal public static var current = ProductionBodyKey.type
}

/// The classes the type key lays a root's body out by, beside the classes the construction memo's sharing implies, for
/// a test that compares them (R1b §2a): `observer`, when set, is handed both for each root the type key lays out.
public enum TypeKeyClassObservation {
	/// Each body's class under the type key, and under the memo, for one root; body 0, the root's, is class 0 in both.
	public struct Classes: Sendable, Equatable {
		public let typeKey: [Int]
		public let memo: [Int]
		/// Each body's view (R1b §2a): places of one plan node, in one family, whose reads outside it resolve to the
		/// declarations of one view each, and whose closers call the functions of one view each.
		public let views: [Int]

		/// Whether every memo class lies inside one type-key class: the type key may merge memo classes, which differ in
		/// what a read is answered (a value or none, one form or another), but never splits one.
		public var memoRefinesTypeKey: Bool {
			Self.refines(memo, typeKey)
		}

		/// Whether every view lies inside one type-key class.
		public var viewsRefineTypeKey: Bool {
			Self.refines(views, typeKey)
		}

		private static func refines(_ finer: [Int], _ coarser: [Int]) -> Bool {
			guard finer.count == coarser.count else { return false }
			var coarserClassByFinerClass = [Int: Int]()
			for (coarserClass, finerClass) in zip(coarser, finer) {
				guard coarserClassByFinerClass[finerClass, default: coarserClass] == coarserClass else { return false }
				coarserClassByFinerClass[finerClass] = coarserClass
			}
			return true
		}
	}

	@TaskLocal public static var observer: (@Sendable (Classes) -> Void)?
}
