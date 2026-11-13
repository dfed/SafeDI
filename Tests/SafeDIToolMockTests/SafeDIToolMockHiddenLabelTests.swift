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
/// receives a label as one type above a type that receives the label as another, with no declaration of the label
/// between, is therefore rejected, as production rejects the pair wherever the tree is built. The mock passes the first
/// type the property under its label inside the function that builds it and the types it builds, where the second
/// would read it.
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
	mutating func mock_throwsError_whenTypeBuiltInsidePromotedDependencyAliasesLabelOnlyIfAvailableThatPromotedDependencyReceivesAsAnotherType() async {
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenPromotedDependencyReceivesLabelOnlyIfAvailableAsAnotherTypeThanTypeBuiltInsideIt() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `leaf: Leaf` is hidden in chain: Promoted -> Child. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Promoted` receives `leaf: Unbuildable?` with the same label, so the types below `Promoted` receive `leaf: Unbuildable?` instead, as they do wherever `Promoted` is built. Receive `leaf: Leaf` and `leaf: Unbuildable?` under different labels to fix.
				\(fixtures["Promoted.swift"]):4:5: note: `leaf: Unbuildable?` is received here
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
	mutating func mock_throwsError_whenPromotedDependencyAliasesLabelOnlyIfAvailableThatItReceivesAsAnotherType() async {
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
	mutating func mock_throwsError_whenMockedTypeReceivesLabelAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsAnotherType() async {
		// The mock compiles, offering `Child` a `count: Bool?` override, but `Screen`'s required receive pins the
		// declaration above `Screen` to `count: String`, so production always passes `Child` `nil`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Bool?` is hidden in chain: Screen -> Child. In the mock of `Screen`, `Screen` receives `count: String` with the same label, so the types below `Screen` receive `count: String` instead, as they do wherever `Screen` is built. Receive `count: Bool?` and `count: String` under different labels to fix.
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
					    public init(count: Bool?) { self.count = count }
					    @Received(onlyIfAvailable: true) let count: Bool?
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
	mutating func mock_throwsError_whenMockedTypeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItAsAnotherType() async {
		// The mock compiles, offering `Screen` a `count: String?` override, but `Child`'s required receive pins the
		// declaration above `Screen` to `count: Bool`, so production always passes `Screen` `nil`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Bool` is hidden in chain: Screen -> Child. In the mock of `Screen`, `Screen` receives `count: String?` with the same label, so the types below `Screen` receive `count: String?` instead, as they do wherever `Screen` is built. Receive `count: Bool` and `count: String?` under different labels to fix.
				\(fixtures["Screen.swift"]):4:5: note: `count: String?` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
	mutating func mock_throwsError_whenTypeInMockedTypesTreeReceivesLabelAboveTypeItBuildsThatReceivesItOnlyIfAvailableAsAnotherType() async {
		// The mock binds `count: Bool?` under the label at its root and passes `Middle` its `count: String` under the
		// label inside the function that builds `Child`, which would read it (public fuzzer seed 574).
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Bool?` is hidden in chain: Screen -> Middle -> Child. In the mock of `Screen`, `Middle` receives `count: String` with the same label, so the types below `Middle` receive `count: String` instead, as they do wherever `Screen` is built. Receive `count: Bool?` and `count: String` under different labels to fix.
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
					    public init(count: Bool?) { self.count = count }
					    @Received(onlyIfAvailable: true) let count: Bool?
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
	mutating func mock_throwsError_whenTypeInMockedTypesTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItAsAnotherType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Bool` is hidden in chain: Screen -> Middle -> Child. In the mock of `Screen`, `Middle` receives `count: String?` with the same label, so the types below `Middle` receive `count: String?` instead, as they do wherever `Screen` is built. Receive `count: Bool` and `count: String?` under different labels to fix.
				\(fixtures["Middle.swift"]):4:5: note: `count: String?` is received here
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeInPromotedDependencysTreeReceivesLabelOnlyIfAvailableAboveTypeItBuildsThatReceivesItAsAnotherType() async {
		// The mock compiles, offering `Middle` a `count: String?` override, but `Child`'s required receive pins the
		// declaration above `Promoted` to `count: Bool`, so production always passes `Middle` `nil`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Bool` is hidden in chain: Promoted -> Middle -> Child. In the mock of `Screen`, `Promoted` stands for a dependency built above `Screen`, and `Middle` receives `count: String?` with the same label, so the types below `Middle` receive `count: String?` instead, as they do wherever `Promoted` is built. Receive `count: Bool` and `count: String?` under different labels to fix.
				\(fixtures["Middle.swift"]):4:5: note: `count: String?` is received here
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenPublicMockedTypesTreeReceivesLabelAboveTypeThatReceivesItOnlyIfAvailableAsAnotherType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `count: Bool?` is hidden in chain: Screen -> Middle -> Child. In the mock of `Screen`, `Middle` receives `count: String` with the same label, so the types below `Middle` receive `count: String` instead, as they do wherever `Screen` is built. Receive `count: Bool?` and `count: String` under different labels to fix.
				\(fixtures["Middle.swift"]):4:5: note: `count: String` is received here
				"""
			},
		) {
			try await executeSafeDIToolTest(
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

	// MARK: Generation Tests

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
		            self.leaf = leaf
		            self.promoted = promoted
		        }

		        private(set) var leaf: (() -> Leaf)?
		        private(set) var promoted: Promoted.SafeDIMockConfiguration
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
		            self.promoted = promoted
		        }

		        private(set) var promoted: Promoted.SafeDIMockConfiguration
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
		            self.middle = middle
		        }

		        private(set) var middle: Middle.SafeDIMockConfiguration
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
		            self.leaf = leaf
		            self.promoted = promoted
		        }

		        private(set) var leaf: (() -> Leaf)?
		        private(set) var promoted: Promoted.SafeDIMockConfiguration
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
		            self.child = child
		            self.count_Bool = count_Bool
		            self.count_String = count_String
		        }

		        private(set) var child: ((Bool?) -> Child)?
		        private(set) var count_Bool: Bool?
		        private(set) var count_String: String?
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
		            self.middle = middle
		            self.count_Bool = count_Bool
		            self.count_String = count_String
		        }

		        private(set) var middle: Middle.SafeDIMockConfiguration
		        private(set) var count_Bool: Bool?
		        private(set) var count_String: String?
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
		            self.promoted = promoted
		            self.count_Bool = count_Bool
		            self.count_String = count_String
		        }

		        private(set) var promoted: Promoted.SafeDIMockConfiguration
		        private(set) var count_Bool: Bool?
		        private(set) var count_String: String?
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
		    public struct SafeDIOverrides {
		        public init(
		            promoted: __safeDI_Promoted_MockConfiguration = .init()
		        ) {
		            self.promoted = promoted
		        }

		        public private(set) var promoted: __safeDI_Promoted_MockConfiguration
		    }

		    public static func mock(
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

	// MARK: Private

	private var filesToDelete: [URL]
}
