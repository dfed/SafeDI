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

/// A dependency a mock promotes stands for one the mocked type receives from above it, so in production its tree is
/// built above the mocked type, where a type in that tree and the types it builds receive one label from the same
/// declaration. A type in that tree that receives a label as one type above a type that receives the label as another
/// is therefore rejected, as production rejects the pair wherever the promoted dependency is built. The mock passes the
/// first type the property under its label inside the function that builds it and the types it builds, where the
/// second would read it.
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

		        let leaf: (() -> Leaf)?
		        let promoted: Promoted.SafeDIMockConfiguration
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

		        let promoted: Promoted.SafeDIMockConfiguration
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
	mutating func mock_passesEachFormItsOwnParameter_whenMockedTypeReceivesLabelAsAnotherTypeThanTypeItBuilds() async throws {
		// The mocked type is passed its own `leaf: Unbuildable` by name, so the `leaf: Leaf` the mock builds for `Child`
		// keeps its label. Production rejects the pair wherever `Screen` is built, but a mock of the mocked type's own
		// tree is accepted, as a call of another module's public mock of it is.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
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
		            child: ((Leaf) -> Child)? = nil
		        ) {
		            self.leaf = leaf
		            self.child = child
		        }

		        let leaf: (() -> Leaf)?
		        let child: ((Leaf) -> Child)?
		    }

		    static func mock(
		        leaf_Unbuildable: Unbuildable,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(leaf) } else { Child(leaf: leaf) }
		        return Screen(leaf: leaf_Unbuildable, child: child)
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

		        let leaf: (() -> Leaf)?
		        let promoted: Promoted.SafeDIMockConfiguration
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

	// MARK: Private

	private var filesToDelete: [URL]
}
