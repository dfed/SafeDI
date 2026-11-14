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

/// The levels of the places of one computation of a seam's holes: for each place the seam's tree builds, what each scope
/// on the path from the seam's root to the place binds before the next property on the path, beside the fields the
/// place's scope struct carries today.
///
/// A level is a fact of the type that binds it, the same on every path the type is built on, which is what lets a scope
/// enum nest one level per type. Generated code does not read them yet: they are computed beside the path's fields and
/// handed to `observer`, which the tests and the graph fuzzer set to check that the levels of each place, nearest first,
/// hold the place's fields, and that every build of a type gives the same levels.
public struct SeamPlaceLevels: Sendable, Equatable {
	/// The seam whose holes were computed.
	public let seamType: TypeDescription
	/// Each place the seam's tree builds, in the order the generated code builds them.
	public let places: [Place]

	/// One place of a hole, with its levels and the fields of its scope struct.
	public struct Place: Sendable, Equatable {
		/// The properties from the seam's root to the hole's property.
		public let sitePath: [Property]
		/// The levels of the scopes on the path, nearest first: the hole's owner's, then each enclosing scope's, then the
		/// seam's root's.
		public let levels: [Level]
		/// The fields of the place's path as its levels decide them, in their order, a `@Sendable` function on the path aside.
		public let fields: [Property]
		/// The declarations on the path the scope struct carries no field of, which hide the farther declarations of their
		/// labels, in the order they are bound.
		public let uncarriedProperties: [Property]
	}

	/// What one scope on a place's path declares, in the order it binds the declarations, each marked by whether it is
	/// bound before the next property on the path.
	public struct Level: Sendable, Hashable {
		/// The type the scope builds, or `nil` for a fill of a seam the tree calls, which binds the fields of the filled
		/// seam's struct and is followed by the scope of the property it fills.
		public let builtType: TypeDescription?
		/// The next property on the path from this scope: the next scope's, or the hole's. `nil` where the next scope is a
		/// fill.
		public let nextProperty: Property?
		/// Whether the scope is a fill or in a fill's tree, which is built with the stack of the seam whose hole it fills.
		public let isInFill: Bool
		/// The declarations, in the order the scope binds them: for the seam's root, its parameters, then its children; for
		/// any other type, its forwarded properties, then its children; for a fill, the declarations the filled seam's
		/// struct does not carry, then the fields it binds.
		public let declarations: [Declaration]

		/// The values the level holds: the declarations bound before the next property.
		public var fields: [Property] {
			declarations.filter(\.isBoundBeforeNextProperty).map(\.property)
		}

		/// The values the level holds that its type binds: `fields` but the parameters of the scope's builder function and the
		/// instantiators it wraps again. A lazy cycle that closes on that function makes the parameters (`CycleParameter`), and
		/// a loop of builders the function's scope is a member of makes the wrappers (`ScopeGenerator.reboundProperties`),
		/// which another build of the type, in another function, need not take or make, so they are a fact of the function,
		/// not of the type. A level nested by type carries both of any build of the type.
		public var fieldsOfType: [Property] {
			declarations.filter { $0.isBoundBeforeNextProperty && !$0.isCycleParameter && !$0.isReboundByBuilderFunction }.map(\.property)
		}

		/// A declaration of a level.
		public struct Declaration: Sendable, Hashable {
			public let property: Property
			/// Whether the scope binds it before the next property on the path. A declaration bound later, the next property
			/// among them, holds no value there, but hides the farther declarations of its label.
			public let isBoundBeforeNextProperty: Bool
			/// Whether it is a parameter of the scope's builder function that a lazy cycle closes on (`CycleParameter`).
			public var isCycleParameter = false
			/// Whether the scope's builder function wraps it again as a member of a loop of builders
			/// (`ScopeGenerator.reboundProperties`).
			public var isReboundByBuilderFunction = false
		}
	}

	/// Called with the levels of every computation of a seam's holes, when set: by the tests and the graph fuzzer, never by
	/// the tool.
	@TaskLocal public static var observer: (@Sendable (SeamPlaceLevels) -> Void)?
}
