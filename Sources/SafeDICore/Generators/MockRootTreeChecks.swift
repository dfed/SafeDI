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

/// A check of a mock root's generator tree that can reject the mock.
public enum MockRootTreeCheck: String, CaseIterable, Hashable, Sendable {
	/// `DependencyTreeGenerator.validateCycleLabelsArePassable(inTreesRootedAt:)`: a label a type a lazy cycle builds
	/// again receives in forms no one value can provide together.
	case cycleLabels = "cycle labels"
	/// `DependencyTreeGenerator.validateFills(inTreesRootedAt:callerModule:compilesGeneratedMocks:)`: the fills of the
	/// calls of other modules' public mocks.
	case fills
	/// `DependencyTreeGenerator.validateSendableBuildersCaptureNoNonSendableWrapper(inTreesRootedAt:)`: a `@Sendable`
	/// builder function that captures a wrapper that is not `Sendable`.
	case sendableCaptures = "Sendable captures"
}

/// Which of a mock root's tree checks (`MockRootTreeCheck`) need its generator tree, read from the scopes of its mock
/// tree alone, once per scope, whatever the number of paths through them: each check left out can find nothing in the
/// tree, so it walks only the trees of the roots that need it. A root none of whose checks needs its tree is one step
/// nearer building no tree at all.
///
/// - A label is unpassable only where a scope of the tree declares a label its scopes receive in two forms
///   (`DependencyTreeGenerator.canHoldUnpassableCycleLabel(inTreeRootedAt:)`), or inside a fill, whose receives the
///   function's body makes too but which no scope reaches by an instantiated child.
/// - `validateFills` judges only a tree that holds a call of another module's seam or public mock, or a fill
///   (`ScopeGenerator.treeHoldsCallOrFill`), and each is a scope of the mock tree: mocks build seams inline.
/// - A builder function is `@Sendable` only where its property is a `Sendable` wrapper, a fill makes it so, or a cycle
///   closes on it from inside a `@Sendable` function that already is one (`ScopeGenerator.buildsInSendableFunction`),
///   so a tree no scope of which declares, receives or builds a `Sendable` wrapper, and that holds no call, has none.
///
/// A public mock's tree holds holes, whose sites a `Sendable` wrapper can hold, so each of its checks needs its tree.
///
/// Memory: the set of scopes visited, while the walk runs; afterwards three flags.
struct MockRootTreeChecks: Sendable {
	init(mockRootScope: Scope, isPublicMock: Bool) {
		guard !isPublicMock else {
			needingTree = Set(MockRootTreeCheck.allCases)
			return
		}
		var holdsCall = false
		var holdsSendableWrapper = false
		var visitedScopes: Set<Scope> = [mockRootScope]
		var scopesToVisit = [mockRootScope]
		while let scope = scopesToVisit.popLast() {
			if scope.seamCall != nil || scope.publicMockCall != nil || !scope.holeArguments.isEmpty {
				holdsCall = true
			}
			if scope.instantiable.dependencies.contains(where: \.property.propertyType.isSendable)
				|| scope.propertiesToGenerate.contains(where: \.property.propertyType.isSendable)
			{
				holdsSendableWrapper = true
			}
			for builtScope in scope.propertiesToGenerate.compactMap(\.builtScope) where visitedScopes.insert(builtScope).inserted {
				scopesToVisit.append(builtScope)
			}
		}
		var needingTree = Set<MockRootTreeCheck>()
		if holdsCall || DependencyTreeGenerator.canHoldUnpassableCycleLabel(inTreeRootedAt: mockRootScope) {
			needingTree.insert(.cycleLabels)
		}
		if holdsCall {
			needingTree.insert(.fills)
		}
		if holdsCall || holdsSendableWrapper {
			needingTree.insert(.sendableCaptures)
		}
		self.needingTree = needingTree
	}

	/// The checks that need the root's generator tree.
	let needingTree: Set<MockRootTreeCheck>

	/// Whether `check` needs the root's generator tree.
	func needsTree(_ check: MockRootTreeCheck) -> Bool {
		needingTree.contains(check)
	}
}

/// What the tree checks of a mock root found in its generator tree beside what its scopes said needed the tree
/// (`MockRootTreeChecks`), handed to `comparesTree`, which the tests set, never the tool: a check the scopes left out
/// must find nothing in the tree, on every test graph. The tree is checked for what the scopes left out only where it is
/// set.
public enum MockRootTreeChecksObservation {
	@TaskLocal public static var comparesTree: TaskLocalFunction<@Sendable (MockRootTreeChecksComparison) -> Void>?
}

/// One mock root's tree checks, as its scopes answered them and as its tree does.
public struct MockRootTreeChecksComparison: Sendable {
	/// The mocked type.
	public let root: String
	/// The checks the scopes said need the root's tree.
	public let needingTree: Set<MockRootTreeCheck>
	/// The checks that find something in the root's tree, of those the scopes left out.
	public let findingInTreeWithoutNeed: Set<MockRootTreeCheck>
}
