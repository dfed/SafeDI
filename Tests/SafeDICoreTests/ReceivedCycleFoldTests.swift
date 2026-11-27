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

import Testing
@testable import SafeDICore

struct ReceivedCycleFoldTests {
	@Test
	func edgeThatMayCloseCycle_isNil_whenRequiredPropertyIsBuiltNowhereAbove() {
		// The root builds scope 1 as value 0, and scope 1 requires property 1, which the walk follows to no scope.
		let fold = World(
			scopes: [.init(), .init(requires: [1])],
			edges: [.value(0, from: 0, to: 1)],
		).fold

		#expect(fold.edgeThatMayCloseCycle == nil)
	}

	@Test(arguments: [false, true])
	func edgeThatMayCloseCycle_isEdgeOfValue_whenScopeBeneathItRequiresIt(requiredByChildItself: Bool) {
		// Scope 1 is built as value 0 and builds scope 2 as value 1; one of them requires value 0.
		let fold = World(
			scopes: [.init(), .init(requires: requiredByChildItself ? [0] : []), .init(requires: requiredByChildItself ? [] : [0])],
			edges: [.value(0, from: 0, to: 1), .value(1, from: 1, to: 2)],
		).fold

		#expect(fold.edgeThatMayCloseCycle == 0)
	}

	@Test
	func edgeThatMayCloseCycle_isEdgeOfValue_whenTypeOfRequiredPropertyRequiresIt() {
		// Scope 1, built as value 0, requires property 1, whose type's scope 2 no tree builds; scope 2 requires value 0.
		let fold = World(
			scopes: [.init(), .init(requires: [1]), .init(requires: [0])],
			edges: [.value(0, from: 0, to: 1)],
			scopeOfProperty: [1: 2],
		).fold

		#expect(fold.edgeThatMayCloseCycle == 0)
	}

	@Test
	func edgeThatMayCloseCycle_isNil_whenScopeBuiltByTypeOfRequiredPropertyRequiresValue() {
		// Scope 1, built as value 0, requires property 1. The scope of property 1's type, scope 2, is a sibling of scope 1
		// and builds scope 3, which requires value 0: the walk follows what a scope requires, never what it builds, and
		// scope 3 is not built inside value 0.
		let fold = World(
			scopes: [.init(), .init(requires: [1]), .init(), .init(requires: [0])],
			edges: [.value(0, from: 0, to: 1), .value(1, from: 0, to: 2), .value(2, from: 2, to: 3)],
			scopeOfProperty: [1: 2],
		).fold

		#expect(fold.edgeThatMayCloseCycle == nil)
	}

	@Test(arguments: [false, true])
	func edgeThatMayCloseCycle_isNil_whenInstantiatorBeingBuiltIsReceivedBeneathIt(receivedByChildItself: Bool) {
		// Scope 1 is built by instantiator 0 and builds scope 2 as value 1; one of them requires instantiator 0.
		let fold = World(
			scopes: [.init(), .init(requires: receivedByChildItself ? [0] : []), .init(requires: receivedByChildItself ? [] : [0])],
			edges: [.builder(0, from: 0, to: 1), .value(1, from: 1, to: 2)],
		).fold

		#expect(fold.edgeThatMayCloseCycle == nil)
	}

	@Test
	func edgeThatMayCloseCycle_isEdgeOfInstantiator_whenTypeItsChildRequiresRequiresIt() {
		// Scope 1, built by instantiator 0, requires value 1, whose type's scope 2 requires instantiator 0: a loop with
		// a value on it.
		let fold = World(
			scopes: [.init(), .init(requires: [0, 1]), .init(requires: [0])],
			edges: [.builder(0, from: 0, to: 1)],
			scopeOfProperty: [1: 2],
		).fold

		#expect(fold.edgeThatMayCloseCycle == 0)
	}

	@Test
	func edgeThatMayCloseCycle_isNil_whenNoValidatedTreeReachesEdge() {
		let fold = World(
			scopes: [.init(), .init(requires: [0])],
			edges: [.init(parent: 0, child: 1, property: 0, isBuilder: false, isJudged: false)],
		).fold

		#expect(fold.edgeThatMayCloseCycle == nil)
	}

	@Test
	func edgeThatMayCloseCycle_isNil_whenReceivedTypesRequireEachOtherAndNoneIsBeingBuilt() {
		// Scope 1, built as value 0, requires property 1; the scopes of properties 1 and 2 require each other.
		let fold = World(
			scopes: [.init(), .init(requires: [1]), .init(requires: [2]), .init(requires: [1])],
			edges: [.value(0, from: 0, to: 1)],
			scopeOfProperty: [1: 2, 2: 3],
		).fold

		#expect(fold.edgeThatMayCloseCycle == nil)
	}

	@Test(arguments: [false, true])
	func edgeThatMayCloseCycle_isEdgeIntoScopeDeclaringRename_whenPropertyRenameIsBoundFromReachesIt(isBuiltByInstantiator: Bool) {
		// Scope 1 declares a rename only if available bound from property 1, whose type's scope 2 requires the property
		// scope 1 is built as.
		let fold = World(
			scopes: [.init(), .init(walkStarts: [1]), .init(requires: [0])],
			edges: [isBuiltByInstantiator ? .builder(0, from: 0, to: 1) : .value(0, from: 0, to: 1)],
			scopeOfProperty: [1: 2],
		).fold

		#expect(fold.edgeThatMayCloseCycle == 0)
	}

	@Test(arguments: [false, true])
	func renameThatMayCloseCycle_isRename_onlyWhenTreeOfSiblingItIsFulfilledByRequiresIt(isRequiredInSiblingsTree: Bool) {
		// Scope 0 renames property 0, which builds scope 1, as property 2. Scope 2, built by scope 1 or beside it,
		// requires property 2 as declared.
		let fold = World(
			scopes: [.init(), .init(), .init(declaredRequirements: [2])],
			edges: [.value(0, from: 0, to: 1), .value(1, from: isRequiredInSiblingsTree ? 1 : 0, to: 2)],
			renames: [.init(edge: 0, receivableProperties: [2])],
		).fold

		#expect(fold.renameThatMayCloseCycle == (isRequiredInSiblingsTree ? 0 : nil))
		#expect(fold.edgeThatMayCloseCycle == nil)
	}

	/// A hand-built input: scope 0 is the root of the one tree.
	private struct World {
		struct Scope {
			var requires = [Int32]()
			var declaredRequirements = [Int32]()
			var walkStarts = [Int32]()
		}

		var scopes: [Scope]
		var edges: [ReceivedCycleFold.Edge]
		var scopeOfProperty = [Int32: Int32]()
		var renames = [ReceivedCycleFold.Rename]()

		var fold: ReceivedCycleFold {
			let propertyCount = 3
			return ReceivedCycleFold(ReceivedCycleFold.Input(
				propertyCount: propertyCount,
				roots: [0],
				edges: edges,
				requiredProperties: scopes.map(\.requires),
				declaredRequiredProperties: scopes.map(\.declaredRequirements),
				scopeOfProperty: (0..<Int32(propertyCount)).map { scopeOfProperty[$0] ?? -1 },
				walkStarts: scopes.map(\.walkStarts),
				renames: renames,
			))
		}
	}
}

extension ReceivedCycleFold.Edge {
	fileprivate static func value(_ property: Int32, from parent: Int32, to child: Int32) -> Self {
		.init(parent: parent, child: child, property: property, isBuilder: false, isJudged: true)
	}

	fileprivate static func builder(_ property: Int32, from parent: Int32, to child: Int32) -> Self {
		.init(parent: parent, child: child, property: property, isBuilder: true, isJudged: true)
	}
}
