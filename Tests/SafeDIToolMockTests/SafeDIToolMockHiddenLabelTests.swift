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

import Foundation
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A type in a mock's tree and the types it builds receive one label from the same declaration in production: in the
/// mocked type's own tree, the declaration above the mocked type, and in the tree of a dependency the mock promotes,
/// which stands for one built above the mocked type, the declaration above that tree. A type in either tree that
/// requires a label as one type above a type that requires the label as another, with no declaration of the label
/// between, is therefore rejected, as production rejects the pair wherever the tree is built. The mock passes the first
/// type the property under its label inside the function that builds it and the types it builds, where the second
/// would read it. Where one of the two receives is only if available, production always passes it `nil`, and so does
/// the mock (issue #718).
struct SafeDIToolMockHiddenLabelTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Error Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeBuiltInsidePromotedDependencyAliasesLabelThatPromotedDependencyReceivesAsAnotherType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `leaf: Leaf` is hidden in chain: Promoted -> Child. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Unbuildable` with the same label, so the types below `Promoted` receive `leaf: Unbuildable` instead, as they do wherever `Promoted` is built. Receive `leaf: Leaf` and `leaf: Unbuildable` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Unbuildable` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(leaf: Leaf, promoted: Promoted) { self.leaf = leaf; self.promoted = promoted }
					    @Instantiated let leaf: Leaf
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: Unbuildable, child: Child) { self.leaf = leaf; self.child = child }
					    @Received let leaf: Unbuildable
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(renamedLeaf: Leaf) { self.renamedLeaf = renamedLeaf }
					    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let renamedLeaf: Leaf
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPromotedDependencyTreeOfMockBuildsInProductionWithTheSamePair() async {
		// The production twin: `Host` forwards `leaf: Unbuildable` above `Promoted`, so `Child`'s alias of `leaf: Leaf`,
		// which `Root` declares further up, is hidden.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `leaf: Leaf` is hidden in chain: Root -> Instantiator<Host> -> Promoted -> Child. `Host` declares `leaf: Unbuildable` with the same label, so the types below `Host` receive `leaf: Unbuildable` instead. Give `leaf: Unbuildable` on `Host` a different label to fix.
				\(fixtures["Host.swift"]):4:5: note: `leaf: Unbuildable` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(leaf: Leaf, hostBuilder: Instantiator<Host>) { self.leaf = leaf; self.hostBuilder = hostBuilder }
					    @Instantiated let leaf: Leaf
					    @Instantiated let hostBuilder: Instantiator<Host>
					}
					""",
					"""
					@Instantiable
					public final class Host: Instantiable {
					    public init(leaf: Unbuildable, promoted: Promoted) { self.leaf = leaf; self.promoted = promoted }
					    @Forwarded let leaf: Unbuildable
					    @Instantiated let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: Unbuildable, child: Child) { self.leaf = leaf; self.child = child }
					    @Received let leaf: Unbuildable
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(renamedLeaf: Leaf) { self.renamedLeaf = renamedLeaf }
					    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let renamedLeaf: Leaf
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeBuiltInsidePromotedDependencyReceivesLabelThatPromotedDependencyReceivesAsAnotherType() async {
		// The mock promotes `leaf: Leaf` under its label and takes `leaf: Unbuildable` as `leaf_Unbuildable`, which it
		// passes `Promoted` under the label inside the function that also builds `Child`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `leaf: Leaf` is hidden in chain: Promoted -> Child. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Unbuildable` with the same label, so the types below `Promoted` receive `leaf: Unbuildable` instead, as they do wherever `Promoted` is built. Receive `leaf: Leaf` and `leaf: Unbuildable` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Unbuildable` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(promoted: Promoted) { self.promoted = promoted }
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: Unbuildable, child: Child) { self.leaf = leaf; self.child = child }
					    @Received let leaf: Unbuildable
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(leaf: Leaf) { self.leaf = leaf }
					    @Received let leaf: Leaf
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeBuiltInsidePromotedDependencyReceivesInstanceOfLabelThatPromotedDependencyReceivesAsInstantiator() async {
		// The mock promotes both forms under names of their own, so its code would compile, but no production tree can
		// build `Promoted`'s tree.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `leaf: Leaf` is hidden in chain: Promoted -> Child. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Instantiator<Leaf>` with the same label, so the types below `Promoted` receive `leaf: Instantiator<Leaf>` instead, as they do wherever `Promoted` is built. Receive `leaf: Leaf` and `leaf: Instantiator<Leaf>` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Instantiator<Leaf>` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(promoted: Promoted) { self.promoted = promoted }
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: Instantiator<Leaf>, child: Child) { self.leaf = leaf; self.child = child }
					    @Received let leaf: Instantiator<Leaf>
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(leaf: Leaf) { self.leaf = leaf }
					    @Received let leaf: Leaf
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeBuiltInsidePromotedDependencyReceivesLabelAsTypeTheMockCannotBuild() async {
		// The mock binds the `leaf: Leaf` it promotes under its label and passes `Child` the parameter it takes for
		// `leaf: Unbuildable` by name, so its code would compile, but no production tree can build `Promoted`'s tree.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `leaf: Unbuildable` is hidden in chain: Promoted -> Child. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Leaf` with the same label, so the types below `Promoted` receive `leaf: Leaf` instead, as they do wherever `Promoted` is built. Receive `leaf: Unbuildable` and `leaf: Leaf` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Leaf` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(promoted: Promoted) { self.promoted = promoted }
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: Leaf, child: Child) { self.leaf = leaf; self.child = child }
					    @Received let leaf: Leaf
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(leaf: Unbuildable) { self.leaf = leaf }
					    @Received let leaf: Unbuildable
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenPromotedDependencyReceivesLabelAsLazilyInstantiatedTypeTheMockCannotBuildAboveTypeThatReceivesItAsAnotherType() async {
		// The mock passes `Promoted` the parameter it takes for the wrapper by name, so its code would compile, but no
		// production tree can build `Promoted`'s tree.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `leaf: Leaf` is hidden in chain: Promoted -> Child. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: LazilyInstantiated<Unbuildable>` with the same label, so the types below `Promoted` receive `leaf: LazilyInstantiated<Unbuildable>` instead, as they do wherever `Promoted` is built. Receive `leaf: Leaf` and `leaf: LazilyInstantiated<Unbuildable>` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: LazilyInstantiated<Unbuildable>` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(promoted: Promoted) { self.promoted = promoted }
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: LazilyInstantiated<Unbuildable>, child: Child) { self.leaf = leaf; self.child = child }
					    @Received let leaf: LazilyInstantiated<Unbuildable>
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(leaf: Leaf) { self.leaf = leaf }
					    @Received let leaf: Leaf
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenPromotedDependencyAliasesLabelAboveTypeThatReceivesItAsAnotherType() async {
		// `Promoted` receives `leaf: Leaf` through its alias, so the alias's label does not matter.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `leaf: Unbuildable` is hidden in chain: Promoted -> Child. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Leaf` with the same label, so the types below `Promoted` receive `leaf: Leaf` instead, as they do wherever `Promoted` is built. Receive `leaf: Unbuildable` and `leaf: Leaf` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Leaf` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(promoted: Promoted) { self.promoted = promoted }
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(renamedLeaf: Leaf, child: Child) { self.renamedLeaf = renamedLeaf; self.child = child }
					    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let renamedLeaf: Leaf
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(leaf: Unbuildable) { self.leaf = leaf }
					    @Received let leaf: Unbuildable
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenPromotedDependencyAliasesLabelItReceivesAsAnotherType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Promoted.swift"]):5:5: error: @Received property `leaf: Leaf` is hidden in chain: Promoted. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Unbuildable` with the same label, so `Promoted` and the types below it receive `leaf: Unbuildable` instead, as they do wherever `Promoted` is built. Receive `leaf: Leaf` and `leaf: Unbuildable` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Unbuildable` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(leaf: Leaf, promoted: Promoted) { self.leaf = leaf; self.promoted = promoted }
					    @Instantiated let leaf: Leaf
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: Unbuildable, renamedLeaf: Leaf) { self.leaf = leaf; self.renamedLeaf = renamedLeaf }
					    @Received let leaf: Unbuildable
					    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let renamedLeaf: Leaf
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTypeAliasesLabelItReceivesAsAnotherTypeInProduction() async {
		// The production twin of a promoted dependency that aliases a label it receives as another type.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Promoted.swift"]):5:5: error: @Received property `leaf: Leaf` is hidden in chain: Root -> Instantiator<Host> -> Promoted. `Host` declares `leaf: Unbuildable` with the same label, so the types below `Host` receive `leaf: Unbuildable` instead. Give `leaf: Unbuildable` on `Host` a different label to fix.
				\(fixtures["Host.swift"]):4:5: note: `leaf: Unbuildable` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(leaf: Leaf, hostBuilder: Instantiator<Host>) { self.leaf = leaf; self.hostBuilder = hostBuilder }
					    @Instantiated let leaf: Leaf
					    @Instantiated let hostBuilder: Instantiator<Host>
					}
					""",
					"""
					@Instantiable
					public final class Host: Instantiable {
					    public init(leaf: Unbuildable, promoted: Promoted) { self.leaf = leaf; self.promoted = promoted }
					    @Forwarded let leaf: Unbuildable
					    @Instantiated let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: Unbuildable, renamedLeaf: Leaf) { self.leaf = leaf; self.renamedLeaf = renamedLeaf }
					    @Received let leaf: Unbuildable
					    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let renamedLeaf: Leaf
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenPromotedDependencyAliasesLabelItReceivesAsTypeTheMockBuilds() async {
		// The mock binds the `leaf: Leaf` it promotes under its label and passes the alias the parameter it takes for
		// `leaf: Unbuildable` by name, so its code would compile, but no production tree can build `Promoted`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Promoted.swift"]):5:5: error: @Received property `leaf: Unbuildable` is hidden in chain: Promoted. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Leaf` with the same label, so `Promoted` and the types below it receive `leaf: Leaf` instead, as they do wherever `Promoted` is built. Receive `leaf: Unbuildable` and `leaf: Leaf` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Leaf` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(promoted: Promoted) { self.promoted = promoted }
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: Leaf, renamedLeaf: Unbuildable) { self.leaf = leaf; self.renamedLeaf = renamedLeaf }
					    @Received let leaf: Leaf
					    @Received(fulfilledByDependencyNamed: "leaf", ofType: Unbuildable.self) let renamedLeaf: Unbuildable
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenPromotedDependencyAliasesLabelTwiceAsTwoTypes() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Promoted.swift"]):5:5: error: @Received property `leaf: Unbuildable` is hidden in chain: Promoted. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Leaf` with the same label, so `Promoted` and the types below it receive `leaf: Leaf` instead, as they do wherever `Promoted` is built. Receive `leaf: Unbuildable` and `leaf: Leaf` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Leaf` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(promoted: Promoted) { self.promoted = promoted }
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(renamedA: Leaf, renamedB: Unbuildable) { self.renamedA = renamedA; self.renamedB = renamedB }
					    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let renamedA: Leaf
					    @Received(fulfilledByDependencyNamed: "leaf", ofType: Unbuildable.self) let renamedB: Unbuildable
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeBuiltInsidePromotedDependencyRetypesLabelUnderItThatPromotedDependencyReceivesAsAnotherType() async {
		// An alias that keeps the label it retypes declares the label and receives it from above.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Middle.swift"]):4:5: error: @Received property `leaf: Leaf` is hidden in chain: Promoted -> Middle. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Unbuildable` with the same label, so the types below `Promoted` receive `leaf: Unbuildable` instead, as they do wherever `Promoted` is built. Receive `leaf: Leaf` and `leaf: Unbuildable` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Unbuildable` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(promoted: Promoted) { self.promoted = promoted }
					    @Received let promoted: Promoted
					}
					""",
					"""
					@Instantiable
					public final class Promoted: Instantiable {
					    public init(leaf: Unbuildable, middle: Middle) { self.leaf = leaf; self.middle = middle }
					    @Received let leaf: Unbuildable
					    @Instantiated let middle: Middle
					}
					""",
					"""
					@Instantiable
					public final class Middle: Instantiable {
					    public init(leaf: any LeafProtocol) { self.leaf = leaf }
					    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let leaf: any LeafProtocol
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable, LeafProtocol {
					    public init() {}
					}

					public protocol LeafProtocol {}

					public final class Unbuildable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenMockedTypeReceivesLabelAboveTypeItBuildsThatReceivesItAsAnotherType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Bool` is hidden in chain: Screen -> Child. In the mock of `Screen`, `Screen` receives `count: String` with the same label, so the types below `Screen` receive `count: String` instead, as they do wherever `Screen` is built. Receive `count: Bool` and `count: String` under different labels to fix.
				\(fixtures["Screen.swift"]):4:5: note: `count: String` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(count: String, child: Child) { self.count = count; self.child = child }
					    @Received let count: String
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(count: Bool) { self.count = count }
					    @Received let count: Bool
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenMockedTypeReceivesLabelAboveTypeItBuildsThatReceivesItAsTypeTheMockBuilds() async {
		// Production rejects the pair wherever `Screen` is built, and the mock rejects it as it does in a promoted
		// dependency's tree.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Leaf` is hidden in chain: Screen -> Child. In the mock of `Screen`, `Screen` receives `count: String` with the same label, so the types below `Screen` receive `count: String` instead, as they do wherever `Screen` is built. Receive `count: Leaf` and `count: String` under different labels to fix.
				\(fixtures["Screen.swift"]):4:5: note: `count: String` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(count: String, child: Child) { self.count = count; self.child = child }
					    @Received let count: String
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(count: Leaf) { self.count = count }
					    @Received let count: Leaf
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenMockedTypeReceivesLabelAboveLazilyInstantiatedTypeItBuildsThatReceivesItAsAnotherType() async {
		// Reduced from graph fuzzer seed 106445, which a 2.2.0 mock accepted. The sibling form is accepted
		// (`mock_passesMockedTypeItsReceivedDependencyByItsSiblingName_whenPromotedLazilyInstantiatedDependencyReceivesItsLabelAsAnotherType`).
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):4:5: error: @Received property `x: B` is hidden in chain: Mocked -> A. In the mock of `Mocked`, `Mocked` receives `x: A` with the same label, so the types below `Mocked` receive `x: A` instead, as they do wherever `Mocked` is built. Receive `x: B` and `x: A` under different labels to fix.
				\(fixtures["Mocked.swift"]):8:5: note: `x: A` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Mocked: Instantiable {
					    public init(lazyX: LazilyInstantiated<A>, x: A) {
					        self.lazyX = lazyX
					        self.x = x
					    }
					    @Instantiated let lazyX: LazilyInstantiated<A>
					    @Received let x: A
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    public init(x: B) { self.x = x }
					    @Received let x: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenMockedTypeReceivesInstantiatorBuildingADependencyCycleAboveTypeItBuildsThatReceivesItsLabelAsAnotherType() async {
		// A 2.2.0 mock accepted this. The sibling form is accepted
		// (`mock_passesMockedTypeItsReceivedInstantiatorByItsSiblingName_whenItBuildsADependencyCycleAndAPromotedDependencyReceivesItsLabelAsAnotherType`).
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Other.swift"]):4:5: error: @Received property `nodeBuilder: Instantiator<Leaf>` is hidden in chain: Mocked -> Other. In the mock of `Mocked`, `Mocked` receives `nodeBuilder: Instantiator<Node>` with the same label, so the types below `Mocked` receive `nodeBuilder: Instantiator<Node>` instead, as they do wherever `Mocked` is built. Receive `nodeBuilder: Instantiator<Leaf>` and `nodeBuilder: Instantiator<Node>` under different labels to fix.
				\(fixtures["Mocked.swift"]):7:5: note: `nodeBuilder: Instantiator<Node>` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Mocked: Instantiable {
					    public init(nodeBuilder: Instantiator<Node>, other: Other) {
					        self.nodeBuilder = nodeBuilder
					        self.other = other
					    }
					    @Received let nodeBuilder: Instantiator<Node>
					    @Instantiated let other: Other
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Other: Instantiable {
					    public init(nodeBuilder: Instantiator<Leaf>) { self.nodeBuilder = nodeBuilder }
					    @Received let nodeBuilder: Instantiator<Leaf>
					}
					""",
					"""
					@Instantiable
					public final class Node: Instantiable {
					    public init(childBuilder: Instantiator<Child>) { self.childBuilder = childBuilder }
					    @Instantiated let childBuilder: Instantiator<Child>
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(nodeBuilder: Instantiator<Node>) { self.nodeBuilder = nodeBuilder }
					    @Instantiated let nodeBuilder: Instantiator<Node>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeInMockedTypesTreeReceivesLabelAboveTypeItBuildsThatReceivesItAsAnotherType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Bool` is hidden in chain: Screen -> Middle -> Child. In the mock of `Screen`, `Middle` receives `count: String` with the same label, so the types below `Middle` receive `count: String` instead, as they do wherever `Screen` is built. Receive `count: Bool` and `count: String` under different labels to fix.
				\(fixtures["Middle.swift"]):4:5: note: `count: String` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(middle: Middle) { self.middle = middle }
					    @Instantiated let middle: Middle
					}
					""",
					"""
					@Instantiable
					public final class Middle: Instantiable {
					    public init(count: String, child: Child) { self.count = count; self.child = child }
					    @Received let count: String
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(count: Bool) { self.count = count }
					    @Received let count: Bool
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeInMockedTypesTreeReceivesLabelAboveTypeItBuildsThatReceivesItAsTypeTheMockBuilds() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Leaf` is hidden in chain: Screen -> Middle -> Child. In the mock of `Screen`, `Middle` receives `count: String` with the same label, so the types below `Middle` receive `count: String` instead, as they do wherever `Screen` is built. Receive `count: Leaf` and `count: String` under different labels to fix.
				\(fixtures["Middle.swift"]):4:5: note: `count: String` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(middle: Middle) { self.middle = middle }
					    @Instantiated let middle: Middle
					}
					""",
					"""
					@Instantiable
					public final class Middle: Instantiable {
					    public init(count: String, child: Child) { self.count = count; self.child = child }
					    @Received let count: String
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(count: Leaf) { self.count = count }
					    @Received let count: Leaf
					}
					""",
					"""
					@Instantiable
					public final class Leaf: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenMockedTypeForwardsLabelAboveTypeItBuildsThatReceivesItAsAnotherType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Bool` is hidden in chain: Screen -> Child. `Screen` declares `count: String` with the same label, so the types below `Screen` receive `count: String` instead. Give `count: String` on `Screen` a different label to fix.
				\(fixtures["Screen.swift"]):4:5: note: `count: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(count: String, child: Child) { self.count = count; self.child = child }
					    @Forwarded let count: String
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(count: Bool) { self.count = count }
					    @Received let count: Bool
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenMockedTypeRequiresLabelAboveReceiveOnlyIfAvailableAboveTypeThatRequiresItAsAnotherType() async {
		// `Middle`'s receive only if available pins nothing, so `Child`'s required `token: Token` meets `Screen`'s required
		// `token: Instantiator<Token>`, which no one declaration provides with it: production cannot build `Child`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `token: Token` is hidden in chain: Screen -> Middle -> Child. In the mock of `Screen`, `Screen` receives `token: Instantiator<Token>` with the same label, so the types below `Screen` receive `token: Instantiator<Token>` instead, as they do wherever `Screen` is built. Receive `token: Token` and `token: Instantiator<Token>` under different labels to fix.
				\(fixtures["Screen.swift"]):4:5: note: `token: Instantiator<Token>` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(token: Instantiator<Token>, middle: Middle) { self.token = token; self.middle = middle }
					    @Received let token: Instantiator<Token>
					    @Instantiated let middle: Middle
					}
					""",
					"""
					@Instantiable
					public final class Middle: Instantiable {
					    public init(token: Token?, child: Child) { self.token = token; self.child = child }
					    @Received(onlyIfAvailable: true) let token: Token?
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(token: Token) { self.token = token }
					    @Received let token: Token
					}
					""",
					"""
					@Instantiable
					public final class Token: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Generation Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenTypeItBuildsReceivesLabelAsAnotherForm() async throws {
		// Issue #718. `Screen` receives `token: Token?` only if available and `Child`, which it builds, requires
		// `token: Instantiator<Token>`, which no one declaration provides with it. Production always passes `Screen` `nil`,
		// since `Child`'s required receive pins the declaration above `Screen` to the instantiator, so the mock passes `nil`
		// too and offers no override for it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Token: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(token: Instantiator<Token>) {
				        self.token = token
				    }

				    @Received let token: Instantiator<Token>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(token: Token?, child: Child) {
				        self.token = token
				        self.child = child
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class Parent: Instantiable {
				    public init(token: Instantiator<Token>, screen: Screen) {
				        self.token = token
				        self.screen = screen
				    }

				    @Instantiated let token: Instantiator<Token>
				    @Instantiated let screen: Screen
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Parent+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Parent {
		    public convenience init() {
		        func __safeDI_token() -> Token {
		            Token()
		        }
		        let token = Instantiator<Token>(__safeDI_token)
		        func __safeDI_screen() -> Screen {
		            let child = Child(token: token)
		            return Screen(token: nil, child: child)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(token: token, screen: screen)
		    }
		}
		""", "Unexpected output \(output.dependencyTreeFiles["Parent+SafeDI.swift"] ?? "")")
		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            child: ((Instantiator<Token>) -> Child)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                child: child
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var child: ((Instantiator<Token>) -> Child)? { __safeDI_storage.child }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                child: ((Instantiator<Token>) -> Child)?
		            ) {
		                self.token = token
		                self.child = child
		            }

		            let token: (() -> Token)?
		            let child: ((Instantiator<Token>) -> Child)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_token() -> Token {
		            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        }
		        let token = Instantiator<Token>(__safeDI_token)
		        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(token) } else { Child(token: token) }
		        return Screen(token: nil, child: child)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsAliasToNil_whenTypeBuiltInsidePromotedDependencyAliasesLabelOnlyIfAvailableThatPromotedDependencyReceivesAsAnotherType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(leaf: Leaf, promoted: Promoted) { self.leaf = leaf; self.promoted = promoted }
				    @Instantiated let leaf: Leaf
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(leaf: Unbuildable, child: Child) { self.leaf = leaf; self.child = child }
				    @Received let leaf: Unbuildable
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(renamedLeaf: Leaf?) { self.renamedLeaf = renamedLeaf }
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self, onlyIfAvailable: true) let renamedLeaf: Leaf?
				}
				""",
				"""
				@Instantiable
				public final class Leaf: Instantiable {
				    public init() {}
				}

				public final class Unbuildable {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            leaf: (() -> Leaf)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                leaf: leaf,
		                promoted: promoted
		            )
		        }

		        var leaf: (() -> Leaf)? { __safeDI_storage.leaf }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                leaf: (() -> Leaf)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.leaf = leaf
		                self.promoted = promoted
		            }

		            let leaf: (() -> Leaf)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        leaf_Unbuildable: Unbuildable,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		        func __safeDI_promoted() -> Promoted {
		            let leaf: Unbuildable = leaf_Unbuildable
		            func __safeDI_child() -> Child {
		                #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
		                let renamedLeaf: Leaf? = nil
		                #sourceLocation()
		                return if let safeDIBuilder = safeDIOverrides.promoted.child { safeDIBuilder(renamedLeaf) } else { Child(renamedLeaf: renamedLeaf) }
		            }
		            let child: Child = __safeDI_child()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(leaf, child) } else { Promoted(leaf: leaf, child: child) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(leaf: leaf, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenPromotedDependencyReceivesLabelOnlyIfAvailableAsAnotherTypeThanTypeBuiltInsideIt() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(leaf: Leaf, promoted: Promoted) { self.leaf = leaf; self.promoted = promoted }
				    @Instantiated let leaf: Leaf
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(leaf: Unbuildable?, child: Child) { self.leaf = leaf; self.child = child }
				    @Received(onlyIfAvailable: true) let leaf: Unbuildable?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(renamedLeaf: Leaf) { self.renamedLeaf = renamedLeaf }
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let renamedLeaf: Leaf
				}
				""",
				"""
				@Instantiable
				public final class Leaf: Instantiable {
				    public init() {}
				}

				public final class Unbuildable {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            leaf: (() -> Leaf)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                leaf: leaf,
		                promoted: promoted
		            )
		        }

		        var leaf: (() -> Leaf)? { __safeDI_storage.leaf }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                leaf: (() -> Leaf)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.leaf = leaf
		                self.promoted = promoted
		            }

		            let leaf: (() -> Leaf)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_child() -> Child {
		                #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
		                let renamedLeaf: Leaf = leaf
		                #sourceLocation()
		                return if let safeDIBuilder = safeDIOverrides.promoted.child { safeDIBuilder(renamedLeaf) } else { Child(renamedLeaf: renamedLeaf) }
		            }
		            let child: Child = __safeDI_child()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(nil, child) } else { Promoted(leaf: nil, child: child) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(leaf: leaf, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsAliasToNil_whenPromotedDependencyAliasesLabelOnlyIfAvailableThatItReceivesAsAnotherType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(leaf: Leaf, promoted: Promoted) { self.leaf = leaf; self.promoted = promoted }
				    @Instantiated let leaf: Leaf
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(leaf: Unbuildable, renamedLeaf: Leaf?) { self.leaf = leaf; self.renamedLeaf = renamedLeaf }
				    @Received let leaf: Unbuildable
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self, onlyIfAvailable: true) let renamedLeaf: Leaf?
				}
				""",
				"""
				@Instantiable
				public final class Leaf: Instantiable {
				    public init() {}
				}

				public final class Unbuildable {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            leaf: (() -> Leaf)? = nil,
		            promoted: ((Unbuildable, Leaf?) -> Promoted)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                leaf: leaf,
		                promoted: promoted
		            )
		        }

		        var leaf: (() -> Leaf)? { __safeDI_storage.leaf }
		        var promoted: ((Unbuildable, Leaf?) -> Promoted)? { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                leaf: (() -> Leaf)?,
		                promoted: ((Unbuildable, Leaf?) -> Promoted)?
		            ) {
		                self.leaf = leaf
		                self.promoted = promoted
		            }

		            let leaf: (() -> Leaf)?
		            let promoted: ((Unbuildable, Leaf?) -> Promoted)?
		        }
		    }

		    static func mock(
		        leaf_Unbuildable: Unbuildable,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		        func __safeDI_promoted() -> Promoted {
		            let leaf: Unbuildable = leaf_Unbuildable
		            #sourceLocation(file: "\(output.fixtures["Promoted.swift"])", line: 5)
		            let renamedLeaf: Leaf? = nil
		            #sourceLocation()
		            return if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(leaf, renamedLeaf) } else { Promoted(leaf: leaf, renamedLeaf: renamedLeaf) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(leaf: leaf, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenMockedTypeReceivesLabelAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsAnotherType() async throws {
		// `Screen`'s required receive pins the declaration above `Screen` to `count: String`, so production always passes
		// `Child` `nil`. So does the mock, which offers no `count: Bool?` override.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(count: String, child: Child) { self.count = count; self.child = child }
				    @Received let count: String
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool?) { self.count = count }
				    @Received(onlyIfAvailable: true) let count: Bool?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            child: ((Bool?) -> Child)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                child: child
		            )
		        }

		        var child: ((Bool?) -> Child)? { __safeDI_storage.child }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                child: ((Bool?) -> Child)?
		            ) {
		                self.child = child
		            }

		            let child: ((Bool?) -> Child)?
		        }
		    }

		    static func mock(
		        count: String,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(nil) } else { Child(count: nil) }
		        return Screen(count: count, child: child)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenMockedTypeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItAsAnotherType() async throws {
		// `Child`'s required receive pins the declaration above `Screen` to `count: Bool`, so production always passes
		// `Screen` `nil`. So does the mock, which offers no `count: String?` override.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(count: String?, child: Child) { self.count = count; self.child = child }
				    @Received(onlyIfAvailable: true) let count: String?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool) { self.count = count }
				    @Received let count: Bool
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            child: ((Bool) -> Child)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                child: child
		            )
		        }

		        var child: ((Bool) -> Child)? { __safeDI_storage.child }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                child: ((Bool) -> Child)?
		            ) {
		                self.child = child
		            }

		            let child: ((Bool) -> Child)?
		        }
		    }

		    static func mock(
		        count: Bool,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(count) } else { Child(count: count) }
		        return Screen(count: nil, child: child)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenTypeInMockedTypesTreeReceivesLabelAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsAnotherType() async throws {
		// `Middle`'s required receive pins the declaration above `Screen` to `count: String`, so production always passes
		// `Child` `nil`. So does the mock, which binds no `count: Bool?` (public fuzzer seed 574).
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(count: String, child: Child) { self.count = count; self.child = child }
				    @Received let count: String
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool?) { self.count = count }
				    @Received(onlyIfAvailable: true) let count: Bool?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            middle: Middle.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                middle: middle
		            )
		        }

		        var middle: Middle.SafeDIMockConfiguration { __safeDI_storage.middle }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                middle: Middle.SafeDIMockConfiguration
		            ) {
		                self.middle = middle
		            }

		            let middle: Middle.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        count: String,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_middle() -> Middle {
		            let child = if let safeDIBuilder = safeDIOverrides.middle.child { safeDIBuilder(nil) } else { Child(count: nil) }
		            return if let safeDIBuilder = safeDIOverrides.middle.safeDIBuilder { safeDIBuilder(count, child) } else { Middle(count: count, child: child) }
		        }
		        let middle: Middle = __safeDI_middle()
		        return Screen(middle: middle)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenTypeInMockedTypesTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItAsAnotherType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(count: String?, child: Child) { self.count = count; self.child = child }
				    @Received(onlyIfAvailable: true) let count: String?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool) { self.count = count }
				    @Received let count: Bool
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            middle: Middle.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                middle: middle
		            )
		        }

		        var middle: Middle.SafeDIMockConfiguration { __safeDI_storage.middle }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                middle: Middle.SafeDIMockConfiguration
		            ) {
		                self.middle = middle
		            }

		            let middle: Middle.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        count: Bool,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_middle() -> Middle {
		            let child = if let safeDIBuilder = safeDIOverrides.middle.child { safeDIBuilder(count) } else { Child(count: count) }
		            return if let safeDIBuilder = safeDIOverrides.middle.safeDIBuilder { safeDIBuilder(nil, child) } else { Middle(count: nil, child: child) }
		        }
		        let middle: Middle = __safeDI_middle()
		        return Screen(middle: middle)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenTypeInPromotedDependencysTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItAsAnotherType() async throws {
		// `Child`'s required receive pins the declaration above `Promoted` to `count: Bool`, so production always passes
		// `Middle` `nil`. So does the mock, which offers no `count: String?` override.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(promoted: Promoted) { self.promoted = promoted }
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(count: String?, child: Child) { self.count = count; self.child = child }
				    @Received(onlyIfAvailable: true) let count: String?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool) { self.count = count }
				    @Received let count: Bool
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            promoted: Promoted.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                promoted: promoted
		            )
		        }

		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.promoted = promoted
		            }

		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        count: Bool,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                let child = if let safeDIBuilder = safeDIOverrides.promoted.middle.child { safeDIBuilder(count) } else { Child(count: count) }
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(nil, child) } else { Middle(count: nil, child: child) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middle) } else { Promoted(middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenPublicMockedTypesTreeReceivesLabelAboveTypeThatReceivesItOnlyIfAvailableAsAnotherType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(count: String, child: Child) { self.count = count; self.child = child }
				    @Received let count: String
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool?) { self.count = count }
				    @Received(onlyIfAvailable: true) let count: Bool?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            middle: __safeDI_Middle_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                middle: middle
		            )
		        }

		        public var middle: __safeDI_Middle_MockConfiguration { __safeDI_storage.middle }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                middle: __safeDI_Middle_MockConfiguration
		            ) {
		                self.middle = middle
		            }

		            let middle: __safeDI_Middle_MockConfiguration
		        }
		    }

		    public static func mock(
		        count: String,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(count: count, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        count: String,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_middle() -> Middle {
		            let child = if let safeDIBuilder = safeDIOverrides.middle.child { safeDIBuilder(nil) } else { Child(count: nil) }
		            return Middle.__safeDI_init(count: count, child: child, safeDIBuilder: safeDIOverrides.middle.safeDIBuilder)
		        }
		        let middle: Middle = __safeDI_middle()
		        return Screen(middle: middle)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_4F5A40BF3DA5309D {}
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenMockedTypeRequiresInstantiatorAboveTypeItBuildsThatReceivesInstanceOnlyIfAvailable() async throws {
		// `Screen` requires `token: Instantiator<Token>`, which pins the declaration above it to the instantiator, so
		// production always passes `Child` `nil` for its `token: Token?`. The mock builds the instantiator for `Screen`
		// and passes `Child` `nil`, with no override for it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Token: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(token: Instantiator<Token>, child: Child) {
				        self.token = token
				        self.child = child
				    }

				    @Received let token: Instantiator<Token>
				    @Instantiated let child: Child
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            child: ((Token?) -> Child)? = nil,
		            token: (() -> Token)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                child: child,
		                token: token
		            )
		        }

		        var child: ((Token?) -> Child)? { __safeDI_storage.child }
		        var token: (() -> Token)? { __safeDI_storage.token }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                child: ((Token?) -> Child)?,
		                token: (() -> Token)?
		            ) {
		                self.child = child
		                self.token = token
		            }

		            let child: ((Token?) -> Child)?
		            let token: (() -> Token)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(nil) } else { Child(token: nil) }
		        func __safeDI_token() -> Token {
		            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        }
		        let token = Instantiator<Token>(__safeDI_token)
		        return Screen(token: token, child: child)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenItsTypeAliasesLabelAsAnotherForm() async throws {
		// `Child` receives `token: Token?` only if available and aliases `token` as `Instantiator<Token>`, which it requires,
		// so production always passes its receive `nil`. The mock does too, and offers it nothing.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Token: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(token: Token?, tokenBuilder: Instantiator<Token>) {
				        self.token = token
				        self.tokenBuilder = tokenBuilder
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				    @Received(fulfilledByDependencyNamed: "token", ofType: Instantiator<Token>.self) let tokenBuilder: Instantiator<Token>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            child: ((Token?, Instantiator<Token>) -> Child)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                child: child
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var child: ((Token?, Instantiator<Token>) -> Child)? { __safeDI_storage.child }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                child: ((Token?, Instantiator<Token>) -> Child)?
		            ) {
		                self.token = token
		                self.child = child
		            }

		            let token: (() -> Token)?
		            let child: ((Token?, Instantiator<Token>) -> Child)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_token() -> Token {
		            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        }
		        let token = Instantiator<Token>(__safeDI_token)
		        func __safeDI_child() -> Child {
		            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
		            let tokenBuilder: Instantiator<Token> = token
		            #sourceLocation()
		            return if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(nil, tokenBuilder) } else { Child(token: nil, tokenBuilder: tokenBuilder) }
		        }
		        let child: Child = __safeDI_child()
		        return Screen(child: child)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesDeclarationToReceiveOnlyIfAvailable_whenTypeBetweenDeclaresLabelBeneathReceivePassedNil() async throws {
		// `Child`'s required `token: Instantiator<Token>` pins the declaration above `Screen`, so `Screen` is passed `nil`,
		// but `Leaf` receives `token: Token?` beneath `Holder`, which declares `token: Token`, so it is passed `Holder`'s.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Token: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(token: Instantiator<Token>) {
				        self.token = token
				    }

				    @Received let token: Instantiator<Token>
				}
				""",
				"""
				@Instantiable
				public final class Holder: Instantiable {
				    public init(token: Token, leaf: Leaf) {
				        self.token = token
				        self.leaf = leaf
				    }

				    @Instantiated let token: Token
				    @Instantiated let leaf: Leaf
				}
				""",
				"""
				@Instantiable
				public final class Leaf: Instantiable {
				    public init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(token: Token?, child: Child, holder: Holder) {
				        self.token = token
				        self.child = child
				        self.holder = holder
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				    @Instantiated let child: Child
				    @Instantiated let holder: Holder
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            child: ((Instantiator<Token>) -> Child)? = nil,
		            holder: Holder.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                child: child,
		                holder: holder
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var child: ((Instantiator<Token>) -> Child)? { __safeDI_storage.child }
		        var holder: Holder.SafeDIMockConfiguration { __safeDI_storage.holder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                child: ((Instantiator<Token>) -> Child)?,
		                holder: Holder.SafeDIMockConfiguration
		            ) {
		                self.token = token
		                self.child = child
		                self.holder = holder
		            }

		            let token: (() -> Token)?
		            let child: ((Instantiator<Token>) -> Child)?
		            let holder: Holder.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_token() -> Token {
		            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        }
		        let token = Instantiator<Token>(__safeDI_token)
		        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(token) } else { Child(token: token) }
		        func __safeDI_holder() -> Holder {
		            let token = if let safeDIBuilder = safeDIOverrides.holder.token { safeDIBuilder() } else { Token() }
		            let leaf = if let safeDIBuilder = safeDIOverrides.holder.leaf { safeDIBuilder(token) } else { Leaf(token: token) }
		            return if let safeDIBuilder = safeDIOverrides.holder.safeDIBuilder { safeDIBuilder(token, leaf) } else { Holder(token: token, leaf: leaf) }
		        }
		        let holder: Holder = __safeDI_holder()
		        return Screen(token: nil, child: child, holder: holder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_offersOverrideToPromotedDependency_whenMockedTypesTreePassesItsReceiveOfThatFormNil() async throws {
		// `Child`'s required `token: Instantiator<Token>` pins the declaration above `Screen`, so `Screen` is passed `nil`.
		// `Promoted` stands for a dependency built above `Screen`, where nothing pins the declaration above it, so the mock
		// binds `token: Token?` for `Promoted` alone and offers it an override.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Token: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(token: Instantiator<Token>) {
				        self.token = token
				    }

				    @Received let token: Instantiator<Token>
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(token: Token?, child: Child, promoted: Promoted) {
				        self.token = token
				        self.child = child
				        self.promoted = promoted
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				    @Instantiated let child: Child
				    @Received let promoted: Promoted
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            child: ((Instantiator<Token>) -> Child)? = nil,
		            promoted: ((Token?) -> Promoted)? = nil,
		            token_Token: Token? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                child: child,
		                promoted: promoted
		            )
		            self.token_Token = token_Token
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var child: ((Instantiator<Token>) -> Child)? { __safeDI_storage.child }
		        var promoted: ((Token?) -> Promoted)? { __safeDI_storage.promoted }
		        let token_Token: Token?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                child: ((Instantiator<Token>) -> Child)?,
		                promoted: ((Token?) -> Promoted)?
		            ) {
		                self.token = token
		                self.child = child
		                self.promoted = promoted
		            }

		            let token: (() -> Token)?
		            let child: ((Instantiator<Token>) -> Child)?
		            let promoted: ((Token?) -> Promoted)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let token_Token: Token? = safeDIOverrides.token_Token
		        func __safeDI_token() -> Token {
		            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        }
		        let token = Instantiator<Token>(__safeDI_token)
		        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(token) } else { Child(token: token) }
		        func __safeDI_promoted() -> Promoted {
		            let token: Token? = token_Token
		            return if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(token) } else { Promoted(token: token) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(token: nil, child: child, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilToReceiveOnlyIfAvailable_whenTypeThatPinsItBuildsItselfAgainThroughInstantiator() async throws {
		// `A` requires `token: Instantiator<Token>` and builds itself again through `B`, so the walk meets `A` beneath its
		// own required receive, which it carries once: the walk ends, and `Screen` is passed `nil`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class A: Instantiable {
				    public init(token: Instantiator<Token>, bBuilder: Instantiator<B>) {
				        self.token = token
				        self.bBuilder = bBuilder
				    }

				    @Received let token: Instantiator<Token>
				    @Instantiated let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public final class B: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(token: Token?, a: A) {
				        self.token = token
				        self.a = a
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				    @Instantiated let a: A
				}
				""",
				"""
				@Instantiable
				public final class Token: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            a: A.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                a: a
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var a: A.SafeDIMockConfiguration { __safeDI_storage.a }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                a: A.SafeDIMockConfiguration
		            ) {
		                self.token = token
		                self.a = a
		            }

		            let token: (() -> Token)?
		            let a: A.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_token() -> Token {
		            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        }
		        let token = Instantiator<Token>(__safeDI_token)
		        func __safeDI_a() -> A {
		            func __safeDI_bBuilder() -> B {
		                func __safeDI_aBuilder() -> A {
		                    let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		                    return if let safeDIBuilder = safeDIOverrides.a.safeDIBuilder { safeDIBuilder(token, bBuilder) } else { A(token: token, bBuilder: bBuilder) }
		                }
		                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		                return if let safeDIBuilder = safeDIOverrides.a.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
		            }
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return if let safeDIBuilder = safeDIOverrides.a.safeDIBuilder { safeDIBuilder(token, bBuilder) } else { A(token: token, bBuilder: bBuilder) }
		        }
		        let a: A = __safeDI_a()
		        return Screen(token: nil, a: a)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesNoParameterForReceivePassedNil_whenPublicMockIsCalledFromAnotherModule() async throws {
		// Issue #718's shape with a public mock: `Child`'s required `token: Instantiator<Token>` pins the declaration above
		// `Screen`, so `Screen`'s public mock passes it `nil` and takes no parameter for it. `Host`'s mock, in another
		// package, calls it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					@Instantiable
					public final class Token: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(token: Instantiator<Token>) {
					        self.token = token
					    }

					    @Received public let token: Instantiator<Token>
					}
					""",
					"""
					@Instantiable(generateMock: .public)
					public final class Screen: Instantiable {
					    init(token: Token?, child: Child) {
					        self.token = token
					        self.child = child
					    }

					    @Received(onlyIfAvailable: true) public let token: Token?
					    @Instantiated public let child: Child
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateMock: true)
					public final class Host: Instantiable {
					    public init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}

					func tokenOfScreen() -> Token? {
					    Screen.mock().token
					}
					""",
				], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            token: (() -> Token)? = nil,
		            child: ((Instantiator<Token>) -> Child)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                child: child
		            )
		        }

		        public var token: (() -> Token)? { __safeDI_storage.token }
		        public var child: ((Instantiator<Token>) -> Child)? { __safeDI_storage.child }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                child: ((Instantiator<Token>) -> Child)?
		            ) {
		                self.token = token
		                self.child = child
		            }

		            let token: (() -> Token)?
		            let child: ((Instantiator<Token>) -> Child)?
		        }
		    }

		    public static func mock(
		        token: Instantiator<Token>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(token: token, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        token: Instantiator<Token>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_token() -> Token {
		            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        }
		        let token = if let token { token } else { Instantiator<Token>(__safeDI_token) }
		        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(token) } else { Child(token: token) }
		        return Screen(token: nil, child: child)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_65AF11639C4ED97D {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if canImport(Feature)
		import Feature
		#endif

		#if DEBUG
		extension Host {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                screen: screen
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                screen: Screen.SafeDIOverrides
		            ) {
		                self.token = token
		                self.screen = screen
		            }

		            let token: (() -> Token)?
		            let screen: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Host {
		        func __safeDI_token() -> Token {
		            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        }
		        let token = Instantiator<Token>(__safeDI_token)
		        _ = Screen.__safeDI_Screen_mock_65AF11639C4ED97D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let screen = Screen.__safeDI_mock(token: token, safeDIOverrides: safeDIOverrides.screen)
		        return Host(screen: screen)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsPromotedDependency_whenTypeBuiltInsideItAliasesLazilyInstantiatedPropertyOfLabelItReceivesByValue() async throws {
		// One `leaf: LazilyInstantiated<Leaf>` above `Promoted` provides both receives, in production and in the mock.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(promoted: Promoted) { self.promoted = promoted }
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(leaf: Leaf, child: Child) { self.leaf = leaf; self.child = child }
				    @Received let leaf: Leaf
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(lazyLeaf: LazilyInstantiated<Leaf>) { self.lazyLeaf = lazyLeaf }
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: LazilyInstantiated<Leaf>.self) let lazyLeaf: LazilyInstantiated<Leaf>
				}
				""",
				"""
				@Instantiable
				public final class Leaf: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            leaf: (() -> Leaf)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                leaf: leaf,
		                promoted: promoted
		            )
		        }

		        var leaf: (() -> Leaf)? { __safeDI_storage.leaf }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                leaf: (() -> Leaf)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.leaf = leaf
		                self.promoted = promoted
		            }

		            let leaf: (() -> Leaf)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_leaf() -> Leaf {
		            if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		        }
		        let leaf = LazilyInstantiated<Leaf>(__safeDI_leaf)
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_child() -> Child {
		                #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
		                let lazyLeaf: LazilyInstantiated<Leaf> = leaf
		                #sourceLocation()
		                return if let safeDIBuilder = safeDIOverrides.promoted.child { safeDIBuilder(lazyLeaf) } else { Child(lazyLeaf: lazyLeaf) }
		            }
		            let child: Child = __safeDI_child()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(leaf.instance, child) } else { Promoted(leaf: leaf.instance, child: child) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsPromotedDependency_whenTypeInItsTreeDeclaresLabelAboveTypeThatReceivesItAsAnotherType() async throws {
		// `Middle` declares `leaf: Leaf` between `Promoted`'s receive of `leaf: Unbuildable` and `Child`'s of `leaf: Leaf`,
		// so `Child` receives `Middle`'s, as in production.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(promoted: Promoted) { self.promoted = promoted }
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(leaf: Unbuildable, middle: Middle) { self.leaf = leaf; self.middle = middle }
				    @Received let leaf: Unbuildable
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(leaf: Leaf, child: Child) { self.leaf = leaf; self.child = child }
				    @Instantiated let leaf: Leaf
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(leaf: Leaf) { self.leaf = leaf }
				    @Received let leaf: Leaf
				}
				""",
				"""
				@Instantiable
				public final class Leaf: Instantiable {
				    public init() {}
				}

				public final class Unbuildable {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            promoted: Promoted.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                promoted: promoted
		            )
		        }

		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.promoted = promoted
		            }

		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        leaf: Unbuildable,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                let leaf = if let safeDIBuilder = safeDIOverrides.promoted.middle.leaf { safeDIBuilder() } else { Leaf() }
		                let child = if let safeDIBuilder = safeDIOverrides.promoted.middle.child { safeDIBuilder(leaf) } else { Child(leaf: leaf) }
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(leaf, child) } else { Middle(leaf: leaf, child: child) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(leaf, middle) } else { Promoted(leaf: leaf, middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsMockedTypesTree_whenTypeBetweenDeclaresLabelThatMockedTypeReceivesAsAnotherType() async throws {
		// `Middle` declares `count: Leaf` between `Screen`'s receive of `count: String` and `Child`'s of `count: Leaf`, so
		// `Child` receives `Middle`'s, as in production.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(count: String, middle: Middle) { self.count = count; self.middle = middle }
				    @Received let count: String
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(count: Leaf, child: Child) { self.count = count; self.child = child }
				    @Instantiated let count: Leaf
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Leaf) { self.count = count }
				    @Received let count: Leaf
				}
				""",
				"""
				@Instantiable
				public final class Leaf: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            middle: Middle.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                middle: middle
		            )
		        }

		        var middle: Middle.SafeDIMockConfiguration { __safeDI_storage.middle }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                middle: Middle.SafeDIMockConfiguration
		            ) {
		                self.middle = middle
		            }

		            let middle: Middle.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        count: String,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_middle() -> Middle {
		            let count = if let safeDIBuilder = safeDIOverrides.middle.count { safeDIBuilder() } else { Leaf() }
		            let child = if let safeDIBuilder = safeDIOverrides.middle.child { safeDIBuilder(count) } else { Child(count: count) }
		            return if let safeDIBuilder = safeDIOverrides.middle.safeDIBuilder { safeDIBuilder(count, child) } else { Middle(count: count, child: child) }
		        }
		        let middle: Middle = __safeDI_middle()
		        return Screen(count: count, middle: middle)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsPromotedDependency_whenTypeInItsTreeAliasesLabelItInstantiatesBeneathReceiveOfAnotherType() async throws {
		// `Middle`'s alias renames the `leaf: Leaf` `Middle` instantiates, not the `leaf: Unbuildable` `Promoted` receives.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(leaf: Leaf, promoted: Promoted) { self.leaf = leaf; self.promoted = promoted }
				    @Instantiated let leaf: Leaf
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(leaf: Unbuildable, middle: Middle) { self.leaf = leaf; self.middle = middle }
				    @Received let leaf: Unbuildable
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(leaf: Leaf, renamedLeaf: Leaf) { self.leaf = leaf; self.renamedLeaf = renamedLeaf }
				    @Instantiated let leaf: Leaf
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let renamedLeaf: Leaf
				}
				""",
				"""
				@Instantiable
				public final class Leaf: Instantiable {
				    public init() {}
				}

				public final class Unbuildable {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            leaf: (() -> Leaf)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                leaf: leaf,
		                promoted: promoted
		            )
		        }

		        var leaf: (() -> Leaf)? { __safeDI_storage.leaf }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                leaf: (() -> Leaf)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.leaf = leaf
		                self.promoted = promoted
		            }

		            let leaf: (() -> Leaf)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        leaf_Unbuildable: Unbuildable,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		        func __safeDI_promoted() -> Promoted {
		            let leaf: Unbuildable = leaf_Unbuildable
		            func __safeDI_middle() -> Middle {
		                let leaf = if let safeDIBuilder = safeDIOverrides.promoted.middle.leaf { safeDIBuilder() } else { Leaf() }
		                #sourceLocation(file: "\(output.fixtures["Middle.swift"])", line: 5)
		                let renamedLeaf: Leaf = leaf
		                #sourceLocation()
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(leaf, renamedLeaf) } else { Middle(leaf: leaf, renamedLeaf: renamedLeaf) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(leaf, middle) } else { Promoted(leaf: leaf, middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(leaf: leaf, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_offersEachFormItsOwnOverride_whenMockedTypeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsAnotherType() async throws {
		// Neither receive pins the declaration above them, so production fulfills each where it is built beneath a
		// declaration of its type, and the mock offers each its own override, as it does for siblings.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(count: String?, child: Child) { self.count = count; self.child = child }
				    @Received(onlyIfAvailable: true) let count: String?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool?) { self.count = count }
				    @Received(onlyIfAvailable: true) let count: Bool?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            child: ((Bool?) -> Child)? = nil,
		            count_Bool: Bool? = nil,
		            count_String: String? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                child: child
		            )
		            self.count_Bool = count_Bool
		            self.count_String = count_String
		        }

		        var child: ((Bool?) -> Child)? { __safeDI_storage.child }
		        let count_Bool: Bool?
		        let count_String: String?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                child: ((Bool?) -> Child)?
		            ) {
		                self.child = child
		            }

		            let child: ((Bool?) -> Child)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let count_Bool: Bool? = safeDIOverrides.count_Bool
		        let count_String: String? = safeDIOverrides.count_String
		        let count: String? = count_String
		        func __safeDI_child() -> Child {
		            let count: Bool? = count_Bool
		            return if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(count) } else { Child(count: count) }
		        }
		        let child: Child = __safeDI_child()
		        return Screen(count: count, child: child)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_offersEachFormItsOwnOverride_whenTypeInMockedTypesTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsAnotherType() async throws {
		// Neither receive pins the declaration above them, so production fulfills each where it is built beneath a
		// declaration of its type, and the mock offers each its own override, as it does for siblings.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(count: String?, child: Child) { self.count = count; self.child = child }
				    @Received(onlyIfAvailable: true) let count: String?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool?) { self.count = count }
				    @Received(onlyIfAvailable: true) let count: Bool?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            middle: Middle.SafeDIMockConfiguration = .init(),
		            count_Bool: Bool? = nil,
		            count_String: String? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                middle: middle
		            )
		            self.count_Bool = count_Bool
		            self.count_String = count_String
		        }

		        var middle: Middle.SafeDIMockConfiguration { __safeDI_storage.middle }
		        let count_Bool: Bool?
		        let count_String: String?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                middle: Middle.SafeDIMockConfiguration
		            ) {
		                self.middle = middle
		            }

		            let middle: Middle.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let count_Bool: Bool? = safeDIOverrides.count_Bool
		        let count_String: String? = safeDIOverrides.count_String
		        func __safeDI_middle() -> Middle {
		            let count: String? = count_String
		            func __safeDI_child() -> Child {
		                let count: Bool? = count_Bool
		                return if let safeDIBuilder = safeDIOverrides.middle.child { safeDIBuilder(count) } else { Child(count: count) }
		            }
		            let child: Child = __safeDI_child()
		            return if let safeDIBuilder = safeDIOverrides.middle.safeDIBuilder { safeDIBuilder(count, child) } else { Middle(count: count, child: child) }
		        }
		        let middle: Middle = __safeDI_middle()
		        return Screen(middle: middle)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_offersEachFormItsOwnOverride_whenPromotedDependencyReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsAnotherType() async throws {
		// Neither receive pins the declaration above them, so production fulfills each where it is built beneath a
		// declaration of its type, and the mock offers each its own override, as it does for siblings.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(promoted: Promoted) { self.promoted = promoted }
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(count: String?, child: Child) { self.count = count; self.child = child }
				    @Received(onlyIfAvailable: true) let count: String?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool?) { self.count = count }
				    @Received(onlyIfAvailable: true) let count: Bool?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            promoted: Promoted.SafeDIMockConfiguration = .init(),
		            count_Bool: Bool? = nil,
		            count_String: String? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                promoted: promoted
		            )
		            self.count_Bool = count_Bool
		            self.count_String = count_String
		        }

		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }
		        let count_Bool: Bool?
		        let count_String: String?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.promoted = promoted
		            }

		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let count_Bool: Bool? = safeDIOverrides.count_Bool
		        let count_String: String? = safeDIOverrides.count_String
		        func __safeDI_promoted() -> Promoted {
		            let count: String? = count_String
		            func __safeDI_child() -> Child {
		                let count: Bool? = count_Bool
		                return if let safeDIBuilder = safeDIOverrides.promoted.child { safeDIBuilder(count) } else { Child(count: count) }
		            }
		            let child: Child = __safeDI_child()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(count, child) } else { Promoted(count: count, child: child) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesEachFormAsItsOwnParameter_whenTypeInPublicMocksPromotedDependencysTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsAnotherType() async throws {
		// Neither receive pins the declaration above them, so production fulfills each where it is built beneath a
		// declaration of its type, and the public mock takes each as its own parameter, as it does for siblings.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(promoted: Promoted) { self.promoted = promoted }
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(count: String?, child: Child) { self.count = count; self.child = child }
				    @Received(onlyIfAvailable: true) let count: String?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(count: Bool?) { self.count = count }
				    @Received(onlyIfAvailable: true) let count: Bool?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            promoted: __safeDI_Promoted_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                promoted: promoted
		            )
		        }

		        public var promoted: __safeDI_Promoted_MockConfiguration { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                promoted: __safeDI_Promoted_MockConfiguration
		            ) {
		                self.promoted = promoted
		            }

		            let promoted: __safeDI_Promoted_MockConfiguration
		        }
		    }

		    public static func mock(
		        count_Bool: Bool? = nil,
		        count_String: String? = nil,
		        promoted: Promoted? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(count_Bool: count_Bool, count_String: count_String, promoted: promoted, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        count_Bool: Bool? = nil,
		        count_String: String? = nil,
		        promoted: Promoted? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                let count: String? = count_String
		                func __safeDI_child() -> Child {
		                    let count: Bool? = count_Bool
		                    return if let safeDIBuilder = safeDIOverrides.promoted.middle.child { safeDIBuilder(count) } else { Child(count: count) }
		                }
		                let child: Child = __safeDI_child()
		                return Middle.__safeDI_init(count: count, child: child, safeDIBuilder: safeDIOverrides.promoted.middle.safeDIBuilder)
		            }
		            let middle: Middle = __safeDI_middle()
		            return Promoted.__safeDI_init(middle: middle, safeDIBuilder: safeDIOverrides.promoted.safeDIBuilder)
		        }
		        let promoted: Promoted = if let promoted { promoted } else { __safeDI_promoted() }
		        return Screen(promoted: promoted)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_970F432B205C8AA5 {}
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_offersLowerReceiveItsOwnOverride_whenTypeInPromotedDependencysTreeReceivesLabelOnlyIfAvailableAsTypeTheMockBindsAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsAnotherType() async throws {
		// `Middle` reads the `user: User` the mock binds for `Screen`, and `Child` its own override, bound inside the
		// function that builds `Child`, where nothing else reads the label. Production beneath a `user: User` passes
		// `Middle` the user and `Child` `nil`, as the mock does by default.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(user: User, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received let user: User
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: User?, child: Child) { self.user = user; self.child = child }
				    @Received(onlyIfAvailable: true) let user: User?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(user: Draft?) { self.user = user }
				    @Received(onlyIfAvailable: true) let user: Draft?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init(),
		            user_Draft: Draft? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		            self.user_Draft = user_Draft
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }
		        let user_Draft: Draft?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user_Draft: Draft? = safeDIOverrides.user_Draft
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                func __safeDI_child() -> Child {
		                    let user: Draft? = user_Draft
		                    return if let safeDIBuilder = safeDIOverrides.promoted.middle.child { safeDIBuilder(user) } else { Child(user: user) }
		                }
		                let child: Child = __safeDI_child()
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(user, child) } else { Middle(user: user, child: child) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middle) } else { Promoted(middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(user: user, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesBothReceivesTheBindingOfTheMock_whenTypeInPromotedDependencysTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItTheSameWay() async throws {
		// One `user: User` fulfills both receives, in production and in the mock.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(user: User, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received let user: User
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: User?, child: Child) { self.user = user; self.child = child }
				    @Received(onlyIfAvailable: true) let user: User?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(user: User?) { self.user = user }
				    @Received(onlyIfAvailable: true) let user: User?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                let child = if let safeDIBuilder = safeDIOverrides.promoted.middle.child { safeDIBuilder(user) } else { Child(user: user) }
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(user, child) } else { Middle(user: user, child: child) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middle) } else { Promoted(middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(user: user, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesLowerReceiveTheBindingOfTheMock_whenTypeInPromotedDependencysTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsTypeTheMockBinds() async throws {
		// Production beneath a `user: User` passes `Middle` `nil` and `Child` the user. The mock offers `Middle` its own
		// override, which defaults to `nil`, and passes it by name, so `Child` reads the `user: User` the mock binds.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(user: User, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received let user: User
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: Draft?, child: Child) { self.user = user; self.child = child }
				    @Received(onlyIfAvailable: true) let user: Draft?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(user: User?) { self.user = user }
				    @Received(onlyIfAvailable: true) let user: User?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init(),
		            user_Draft: Draft? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		            self.user_Draft = user_Draft
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }
		        let user_Draft: Draft?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user_Draft: Draft? = safeDIOverrides.user_Draft
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                let child = if let safeDIBuilder = safeDIOverrides.promoted.middle.child { safeDIBuilder(user) } else { Child(user: user) }
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(user_Draft, child) } else { Middle(user: user_Draft, child: child) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middle) } else { Promoted(middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(user: user, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesLowerReceiveTheBindingOfTheMock_whenTypeTwoScopesAboveItReceivesLabelOnlyIfAvailableAsAnotherType() async throws {
		// `Child` is built two scopes beneath `Middle`, inside the function that builds `Inner`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(user: User, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received let user: User
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: Draft?, inner: Inner) { self.user = user; self.inner = inner }
				    @Received(onlyIfAvailable: true) let user: Draft?
				    @Instantiated let inner: Inner
				}
				""",
				"""
				@Instantiable
				public final class Inner: Instantiable {
				    public init(child: Child) { self.child = child }
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(user: User?) { self.user = user }
				    @Received(onlyIfAvailable: true) let user: User?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init(),
		            user_Draft: Draft? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		            self.user_Draft = user_Draft
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }
		        let user_Draft: Draft?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user_Draft: Draft? = safeDIOverrides.user_Draft
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                func __safeDI_inner() -> Inner {
		                    let child = if let safeDIBuilder = safeDIOverrides.promoted.middle.inner.child { safeDIBuilder(user) } else { Child(user: user) }
		                    return if let safeDIBuilder = safeDIOverrides.promoted.middle.inner.safeDIBuilder { safeDIBuilder(child) } else { Inner(child: child) }
		                }
		                let inner: Inner = __safeDI_inner()
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(user_Draft, inner) } else { Middle(user: user_Draft, inner: inner) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middle) } else { Promoted(middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(user: user, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsUpperReceive_whenTypeItBuildsDeclaresLabelAboveTypeThatReceivesItOnlyIfAvailableAsAnotherType() async throws {
		// `Inner` declares `user: User`, which is what `Child` reads, so `Middle`'s override is rebound under the label
		// inside the function that builds `Middle`, as for any receive whose form the mock renames.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(user: User, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received let user: User
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: Draft?, inner: Inner) { self.user = user; self.inner = inner }
				    @Received(onlyIfAvailable: true) let user: Draft?
				    @Instantiated let inner: Inner
				}
				""",
				"""
				@Instantiable
				public final class Inner: Instantiable {
				    public init(user: User, child: Child) { self.user = user; self.child = child }
				    @Instantiated let user: User
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(user: User?) { self.user = user }
				    @Received(onlyIfAvailable: true) let user: User?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init(),
		            user_Draft: Draft? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		            self.user_Draft = user_Draft
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }
		        let user_Draft: Draft?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user_Draft: Draft? = safeDIOverrides.user_Draft
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                let user: Draft? = user_Draft
		                func __safeDI_inner() -> Inner {
		                    let user = if let safeDIBuilder = safeDIOverrides.promoted.middle.inner.user { safeDIBuilder() } else { User() }
		                    let child = if let safeDIBuilder = safeDIOverrides.promoted.middle.inner.child { safeDIBuilder(user) } else { Child(user: user) }
		                    return if let safeDIBuilder = safeDIOverrides.promoted.middle.inner.safeDIBuilder { safeDIBuilder(user, child) } else { Inner(user: user, child: child) }
		                }
		                let inner: Inner = __safeDI_inner()
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(user, inner) } else { Middle(user: user, inner: inner) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middle) } else { Promoted(middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(user: user, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesLowerReceiveTheBindingOfTheMock_whenTypeInMockedTypesTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsTypeTheMockBinds() async throws {
		// The mock binds the `user: User` that `Promoted` requires beside `Screen`'s own tree, which `Child` reads.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(middle: Middle, promoted: Promoted) { self.middle = middle; self.promoted = promoted }
				    @Instantiated let middle: Middle
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(user: User) { self.user = user }
				    @Received let user: User
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: Draft?, child: Child) { self.user = user; self.child = child }
				    @Received(onlyIfAvailable: true) let user: Draft?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(user: User?) { self.user = user }
				    @Received(onlyIfAvailable: true) let user: User?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            middle: Middle.SafeDIMockConfiguration = .init(),
		            promoted: ((User) -> Promoted)? = nil,
		            user_Draft: Draft? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                middle: middle,
		                promoted: promoted
		            )
		            self.user_Draft = user_Draft
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var middle: Middle.SafeDIMockConfiguration { __safeDI_storage.middle }
		        var promoted: ((User) -> Promoted)? { __safeDI_storage.promoted }
		        let user_Draft: Draft?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                middle: Middle.SafeDIMockConfiguration,
		                promoted: ((User) -> Promoted)?
		            ) {
		                self.user = user
		                self.middle = middle
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let middle: Middle.SafeDIMockConfiguration
		            let promoted: ((User) -> Promoted)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user_Draft: Draft? = safeDIOverrides.user_Draft
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_middle() -> Middle {
		            let child = if let safeDIBuilder = safeDIOverrides.middle.child { safeDIBuilder(user) } else { Child(user: user) }
		            return if let safeDIBuilder = safeDIOverrides.middle.safeDIBuilder { safeDIBuilder(user_Draft, child) } else { Middle(user: user_Draft, child: child) }
		        }
		        let middle: Middle = __safeDI_middle()
		        let promoted = if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(user) } else { Promoted(user: user) }
		        return Screen(middle: middle, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesAliasTheBindingOfTheMock_whenTypeInPromotedDependencysTreeAliasesLabelOnlyIfAvailableAsTypeTheMockBindsBesideReceivingItOnlyIfAvailableAsAnotherType() async throws {
		// `Middle`'s alias reads the `user: User` the mock binds, and its receive of `user: Draft?` its own override.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(user: User, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received let user: User
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(currentUser: User?, user: Draft?) { self.currentUser = currentUser; self.user = user }
				    @Received(fulfilledByDependencyNamed: "user", ofType: User.self, onlyIfAvailable: true) let currentUser: User?
				    @Received(onlyIfAvailable: true) let user: Draft?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init(),
		            user_Draft: Draft? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		            self.user_Draft = user_Draft
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }
		        let user_Draft: Draft?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user_Draft: Draft? = safeDIOverrides.user_Draft
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                #sourceLocation(file: "\(output.fixtures["Middle.swift"])", line: 4)
		                let currentUser: User? = user
		                #sourceLocation()
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle { safeDIBuilder(currentUser, user_Draft) } else { Middle(currentUser: currentUser, user: user_Draft) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middle) } else { Promoted(middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(user: user, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesLowerReceiveTheBindingOfTheMock_whenInstantiatedTypeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsTypeTheMockBinds() async throws {
		// `Middle` is built by an `Instantiator`, whose builder function passes it its override by name.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(user: User, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received let user: User
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middleBuilder: Instantiator<Middle>) { self.middleBuilder = middleBuilder }
				    @Instantiated let middleBuilder: Instantiator<Middle>
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: Draft?, child: Child) { self.user = user; self.child = child }
				    @Received(onlyIfAvailable: true) let user: Draft?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(user: User?) { self.user = user }
				    @Received(onlyIfAvailable: true) let user: User?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init(),
		            user_Draft: Draft? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		            self.user_Draft = user_Draft
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }
		        let user_Draft: Draft?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user_Draft: Draft? = safeDIOverrides.user_Draft
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middleBuilder() -> Middle {
		                let child = if let safeDIBuilder = safeDIOverrides.promoted.middleBuilder.child { safeDIBuilder(user) } else { Child(user: user) }
		                return if let safeDIBuilder = safeDIOverrides.promoted.middleBuilder.safeDIBuilder { safeDIBuilder(user_Draft, child) } else { Middle(user: user_Draft, child: child) }
		            }
		            let middleBuilder = Instantiator<Middle>(__safeDI_middleBuilder)
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middleBuilder) } else { Promoted(middleBuilder: middleBuilder) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(user: user, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesLowerReceiveTheBindingOfTheMock_whenTypeInPublicMocksPromotedDependencysTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsTypeTheMockBinds() async throws {
		// A public mock takes `Middle`'s `user: Draft?` as a parameter, which it passes `Middle` by name.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(user: User, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received public let user: User
				    @Received public let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated public let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: Draft?, child: Child) { self.user = user; self.child = child }
				    @Received(onlyIfAvailable: true) public let user: Draft?
				    @Instantiated public let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(user: User?) { self.user = user }
				    @Received(onlyIfAvailable: true) public let user: User?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            user: (() -> User)? = nil,
		            promoted: __safeDI_Promoted_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		        }

		        public var user: (() -> User)? { __safeDI_storage.user }
		        public var promoted: __safeDI_Promoted_MockConfiguration { __safeDI_storage.promoted }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: __safeDI_Promoted_MockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: __safeDI_Promoted_MockConfiguration
		        }
		    }

		    public static func mock(
		        promoted: Promoted? = nil,
		        user: User? = nil,
		        user_Draft: Draft? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(promoted: promoted, user: user, user_Draft: user_Draft, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        promoted: Promoted? = nil,
		        user: User? = nil,
		        user_Draft: Draft? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                let child = if let safeDIBuilder = safeDIOverrides.promoted.middle.child { safeDIBuilder(user) } else { Child(user: user) }
		                return Middle.__safeDI_init(user: user_Draft, child: child, safeDIBuilder: safeDIOverrides.promoted.middle.safeDIBuilder)
		            }
		            let middle: Middle = __safeDI_middle()
		            return Promoted.__safeDI_init(middle: middle, safeDIBuilder: safeDIOverrides.promoted.safeDIBuilder)
		        }
		        let promoted: Promoted = if let promoted { promoted } else { __safeDI_promoted() }
		        return Screen(user: user, promoted: promoted)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_23867305D587FCE5 {}
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesLowerReceiveTheInstanceOfTheMocksWrapper_whenTypeInPromotedDependencysTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesInstanceOfLabelOnlyIfAvailable() async throws {
		// `Child` reads the instance of the `LazilyInstantiated<User>` the mock binds as `user`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(user: LazilyInstantiated<User>, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received let user: LazilyInstantiated<User>
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: Draft?, child: Child) { self.user = user; self.child = child }
				    @Received(onlyIfAvailable: true) let user: Draft?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(user: User?) { self.user = user }
				    @Received(onlyIfAvailable: true) let user: User?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init(),
		            user_Draft: Draft? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		            self.user_Draft = user_Draft
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }
		        let user_Draft: Draft?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user_Draft: Draft? = safeDIOverrides.user_Draft
		        func __safeDI_user() -> User {
		            if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                let child = if let safeDIBuilder = safeDIOverrides.promoted.middle.child { safeDIBuilder(user.instance) } else { Child(user: user.instance) }
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(user_Draft, child) } else { Middle(user: user_Draft, child: child) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middle) } else { Promoted(middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(user: user, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsUpperReceive_whenTypeItBuildsAliasesLabelOnlyIfAvailableAsTheTypeItReceives() async throws {
		// `Child`'s alias reads the override `Middle` reads, by its name, so nothing beneath `Middle` reads the label by
		// name, and `Middle`'s override is rebound under the label inside the function that builds `Middle`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(user: User, promoted: Promoted) { self.user = user; self.promoted = promoted }
				    @Received let user: User
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				public final class Promoted: Instantiable {
				    public init(middle: Middle) { self.middle = middle }
				    @Instantiated let middle: Middle
				}
				""",
				"""
				@Instantiable
				public final class Middle: Instantiable {
				    public init(user: Draft?, child: Child) { self.user = user; self.child = child }
				    @Received(onlyIfAvailable: true) let user: Draft?
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(draft: Draft?) { self.draft = draft }
				    @Received(fulfilledByDependencyNamed: "user", ofType: Draft.self, onlyIfAvailable: true) let draft: Draft?
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}

				public final class Draft {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            promoted: Promoted.SafeDIMockConfiguration = .init(),
		            user_Draft: Draft? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                promoted: promoted
		            )
		            self.user_Draft = user_Draft
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var promoted: Promoted.SafeDIMockConfiguration { __safeDI_storage.promoted }
		        let user_Draft: Draft?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                promoted: Promoted.SafeDIMockConfiguration
		            ) {
		                self.user = user
		                self.promoted = promoted
		            }

		            let user: (() -> User)?
		            let promoted: Promoted.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let user_Draft: Draft? = safeDIOverrides.user_Draft
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_promoted() -> Promoted {
		            func __safeDI_middle() -> Middle {
		                let user: Draft? = user_Draft
		                func __safeDI_child() -> Child {
		                    #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
		                    let draft: Draft? = user_Draft
		                    #sourceLocation()
		                    return if let safeDIBuilder = safeDIOverrides.promoted.middle.child { safeDIBuilder(draft) } else { Child(draft: draft) }
		                }
		                let child: Child = __safeDI_child()
		                return if let safeDIBuilder = safeDIOverrides.promoted.middle.safeDIBuilder { safeDIBuilder(user, child) } else { Middle(user: user, child: child) }
		            }
		            let middle: Middle = __safeDI_middle()
		            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(middle) } else { Promoted(middle: middle) }
		        }
		        let promoted: Promoted = __safeDI_promoted()
		        return Screen(user: user, promoted: promoted)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
