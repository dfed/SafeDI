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

/// A mock binds the mocked type's own aliases at its root, beside the dependencies it promotes, whose trees then see
/// those bindings. Whether an alias provides a receive in a promoted tree is decided as a scope providing a property to
/// the scopes beneath it is (`ScopeGenerator.provides`): the alias's exact property, or, for an optional receive, its
/// unwrapped form.
///
/// An alias that provides the receive is what the receiver reads, so the mock promotes nothing for it and offers no
/// override of it. An alias that does not provide a receive of its label – an optional alias beside a required
/// non-optional receive, or an alias of another type – is bound under a name of its own, so that it does not hide the
/// parameter or override `mock()` takes for that receive.
struct SafeDIToolMockRootAliasBesidePromotedTreeTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – An alias that does not provide a receive of its label in a promoted tree

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsOnlyIfAvailableAliasApartFromParameter_whenPromotedTreeRequiresNonOptionalFormOfItsLabel() async throws {
		// Reduced from graph fuzzer seed 4628, whose mock handed `Promoted` the optional alias in place of the parameter.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				protocol LeafProtocol {}

				@Instantiable(generateMock: true)
				final class Screen: Instantiable {
				    init(leaf: Leaf, leafProtocol: LeafProtocol?, promoted: Promoted) {
				        self.leaf = leaf
				        self.leafProtocol = leafProtocol
				        self.promoted = promoted
				    }

				    @Instantiated let leaf: Leaf
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self, onlyIfAvailable: true) let leafProtocol: LeafProtocol?
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				final class Promoted: Instantiable {
				    init(leafProtocol: LeafProtocol) {
				        self.leafProtocol = leafProtocol
				    }

				    @Received let leafProtocol: LeafProtocol
				}
				""",
				"""
				@Instantiable
				final class Leaf: Instantiable, LeafProtocol {
				    init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            leaf: (() -> Leaf)? = nil,
			            promoted: ((LeafProtocol) -> Promoted)? = nil
			        ) {
			            self.leaf = leaf
			            self.promoted = promoted
			        }

			        let leaf: (() -> Leaf)?
			        let promoted: ((LeafProtocol) -> Promoted)?
			    }

			    static func mock(
			        leafProtocol: LeafProtocol,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 12)
			        let leafProtocol_LeafProtocol: LeafProtocol? = leaf
			        #sourceLocation()
			        let promoted = if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(leafProtocol) } else { Promoted(leafProtocol: leafProtocol) }
			        return Screen(leaf: leaf, leafProtocol: leafProtocol_LeafProtocol, promoted: promoted)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsRequiredAliasApartFromParameter_whenPromotedTreeRequiresAnotherTypeUnderItsLabel() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				protocol LeafProtocol {}
				protocol OtherProtocol {}

				@Instantiable(generateMock: true)
				final class Screen: Instantiable {
				    init(leaf: Leaf, leafProtocol: LeafProtocol, promoted: Promoted) {
				        self.leaf = leaf
				        self.leafProtocol = leafProtocol
				        self.promoted = promoted
				    }

				    @Instantiated let leaf: Leaf
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let leafProtocol: LeafProtocol
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				final class Promoted: Instantiable {
				    init(leafProtocol: OtherProtocol) {
				        self.leafProtocol = leafProtocol
				    }

				    @Received let leafProtocol: OtherProtocol
				}
				""",
				"""
				@Instantiable
				final class Leaf: Instantiable, LeafProtocol {
				    init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            leaf: (() -> Leaf)? = nil,
			            promoted: ((OtherProtocol) -> Promoted)? = nil
			        ) {
			            self.leaf = leaf
			            self.promoted = promoted
			        }

			        let leaf: (() -> Leaf)?
			        let promoted: ((OtherProtocol) -> Promoted)?
			    }

			    static func mock(
			        leafProtocol: OtherProtocol,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 13)
			        let leafProtocol_LeafProtocol: LeafProtocol = leaf
			        #sourceLocation()
			        let promoted = if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(leafProtocol) } else { Promoted(leafProtocol: leafProtocol) }
			        return Screen(leaf: leaf, leafProtocol: leafProtocol_LeafProtocol, promoted: promoted)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsOnlyIfAvailableAliasApartFromOverride_whenPromotedTreeReceivesAnotherTypeUnderItsLabelOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				protocol LeafProtocol {}
				protocol OtherProtocol {}

				@Instantiable(generateMock: true)
				final class Screen: Instantiable {
				    init(leaf: Leaf, leafProtocol: LeafProtocol?, promoted: Promoted) {
				        self.leaf = leaf
				        self.leafProtocol = leafProtocol
				        self.promoted = promoted
				    }

				    @Instantiated let leaf: Leaf
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self, onlyIfAvailable: true) let leafProtocol: LeafProtocol?
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				final class Promoted: Instantiable {
				    init(leafProtocol: OtherProtocol?) {
				        self.leafProtocol = leafProtocol
				    }

				    @Received(onlyIfAvailable: true) let leafProtocol: OtherProtocol?
				}
				""",
				"""
				@Instantiable
				final class Leaf: Instantiable, LeafProtocol {
				    init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            leaf: (() -> Leaf)? = nil,
			            promoted: ((OtherProtocol?) -> Promoted)? = nil,
			            leafProtocol: OtherProtocol? = nil
			        ) {
			            self.leaf = leaf
			            self.promoted = promoted
			            self.leafProtocol = leafProtocol
			        }

			        let leaf: (() -> Leaf)?
			        let promoted: ((OtherProtocol?) -> Promoted)?
			        let leafProtocol: OtherProtocol?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let leafProtocol: OtherProtocol? = safeDIOverrides.leafProtocol
			        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 13)
			        let leafProtocol_LeafProtocol: LeafProtocol? = leaf
			        #sourceLocation()
			        let promoted = if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(leafProtocol) } else { Promoted(leafProtocol: leafProtocol) }
			        return Screen(leaf: leaf, leafProtocol: leafProtocol_LeafProtocol, promoted: promoted)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsErasedInstantiatorAliasApartFromParameter_whenPromotedTreeRequiresNonOptionalFormOfItsLabel() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				final class AnyValue {}

				@Instantiable(generateMock: true)
				final class Screen: Instantiable {
				    init(valueBuilderAlias: ErasedInstantiator<(), AnyValue>?, promoted: Promoted) {
				        self.valueBuilderAlias = valueBuilderAlias
				        self.promoted = promoted
				    }

				    @Received(fulfilledByDependencyNamed: "valueBuilder", ofType: ErasedInstantiator<(), AnyValue>.self, onlyIfAvailable: true) let valueBuilderAlias: ErasedInstantiator<(), AnyValue>?
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				final class Promoted: Instantiable {
				    init(valueBuilderAlias: ErasedInstantiator<(), AnyValue>) {
				        self.valueBuilderAlias = valueBuilderAlias
				    }

				    @Received let valueBuilderAlias: ErasedInstantiator<(), AnyValue>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            promoted: ((ErasedInstantiator<(), AnyValue>) -> Promoted)? = nil,
			            valueBuilder: ErasedInstantiator<(), AnyValue>? = nil
			        ) {
			            self.promoted = promoted
			            self.valueBuilder = valueBuilder
			        }

			        let promoted: ((ErasedInstantiator<(), AnyValue>) -> Promoted)?
			        let valueBuilder: ErasedInstantiator<(), AnyValue>?
			    }

			    static func mock(
			        valueBuilderAlias: ErasedInstantiator<(), AnyValue>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let valueBuilder: ErasedInstantiator<(), AnyValue>? = safeDIOverrides.valueBuilder
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 10)
			        let valueBuilderAlias_ErasedInstantiator__Void__AnyValue: ErasedInstantiator<(), AnyValue>? = valueBuilder
			        #sourceLocation()
			        let promoted = if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(valueBuilderAlias) } else { Promoted(valueBuilderAlias: valueBuilderAlias) }
			        return Screen(valueBuilderAlias: valueBuilderAlias_ErasedInstantiator__Void__AnyValue, promoted: promoted)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsOnlyIfAvailableAliasApartFromParameter_whenTypeBuiltInPromotedTreeRequiresNonOptionalFormOfItsLabel() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				protocol LeafProtocol {}

				@Instantiable(generateMock: true)
				final class Screen: Instantiable {
				    init(leaf: Leaf, leafProtocol: LeafProtocol?, promoted: Promoted) {
				        self.leaf = leaf
				        self.leafProtocol = leafProtocol
				        self.promoted = promoted
				    }

				    @Instantiated let leaf: Leaf
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self, onlyIfAvailable: true) let leafProtocol: LeafProtocol?
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				final class Promoted: Instantiable {
				    init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated let inner: Inner
				}
				""",
				"""
				@Instantiable
				final class Inner: Instantiable {
				    init(leafProtocol: LeafProtocol) {
				        self.leafProtocol = leafProtocol
				    }

				    @Received let leafProtocol: LeafProtocol
				}
				""",
				"""
				@Instantiable
				final class Leaf: Instantiable, LeafProtocol {
				    init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
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
			        leafProtocol: LeafProtocol,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 12)
			        let leafProtocol_LeafProtocol: LeafProtocol? = leaf
			        #sourceLocation()
			        func __safeDI_promoted() -> Promoted {
			            let inner = if let safeDIBuilder = safeDIOverrides.promoted.inner { safeDIBuilder(leafProtocol) } else { Inner(leafProtocol: leafProtocol) }
			            return if let safeDIBuilder = safeDIOverrides.promoted.safeDIBuilder { safeDIBuilder(inner) } else { Promoted(inner: inner) }
			        }
			        let promoted: Promoted = __safeDI_promoted()
			        return Screen(leaf: leaf, leafProtocol: leafProtocol_LeafProtocol, promoted: promoted)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – An alias that provides a receive of its label in a promoted tree

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsRequiredAliasToPromotedTreesOptionalReceive_whenAliasIsSendableInstantiator() async throws {
		// Reduced from graph fuzzer seed 916, whose mock built a `leafBuilderAlias` node and override nothing read.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				final class Screen: Instantiable, Sendable {
				    init(leafBuilderAlias: SendableInstantiator<Leaf>, promoted: Promoted) {
				        self.leafBuilderAlias = leafBuilderAlias
				        self.promoted = promoted
				    }

				    @Received(fulfilledByDependencyNamed: "leafBuilder", ofType: SendableInstantiator<Leaf>.self) let leafBuilderAlias: SendableInstantiator<Leaf>
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				final class Promoted: Instantiable, Sendable {
				    init(leafBuilderAlias: SendableInstantiator<Leaf>?, leafBuilder: SendableInstantiator<Leaf>?) {
				        self.leafBuilderAlias = leafBuilderAlias
				        self.leafBuilder = leafBuilder
				    }

				    @Received let leafBuilderAlias: SendableInstantiator<Leaf>?
				    @Received let leafBuilder: SendableInstantiator<Leaf>?
				}
				""",
				"""
				@Instantiable
				final class Leaf: Instantiable, Sendable {
				    init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            leafBuilder: (@Sendable () -> Leaf)? = nil,
			            promoted: ((SendableInstantiator<Leaf>?, SendableInstantiator<Leaf>?) -> Promoted)? = nil
			        ) {
			            self.leafBuilder = leafBuilder
			            self.promoted = promoted
			        }

			        let leafBuilder: (@Sendable () -> Leaf)?
			        let promoted: ((SendableInstantiator<Leaf>?, SendableInstantiator<Leaf>?) -> Promoted)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_leafBuilder__safeDIBuilder = safeDIOverrides.leafBuilder
			        @Sendable func __safeDI_leafBuilder() -> Leaf {
			            if let safeDIBuilder = __safeDI_leafBuilder__safeDIBuilder { safeDIBuilder() } else { Leaf() }
			        }
			        let leafBuilder = SendableInstantiator<Leaf>(__safeDI_leafBuilder)
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let leafBuilderAlias: SendableInstantiator<Leaf> = leafBuilder
			        #sourceLocation()
			        let promoted = if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(leafBuilderAlias, leafBuilder) } else { Promoted(leafBuilderAlias: leafBuilderAlias, leafBuilder: leafBuilder) }
			        return Screen(leafBuilderAlias: leafBuilderAlias, promoted: promoted)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsRequiredAliasToPromotedTreesOptionalReceive_whenAliasIsInstantiator() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				final class Screen: Instantiable {
				    init(leafBuilderAlias: Instantiator<Leaf>, promoted: Promoted) {
				        self.leafBuilderAlias = leafBuilderAlias
				        self.promoted = promoted
				    }

				    @Received(fulfilledByDependencyNamed: "leafBuilder", ofType: Instantiator<Leaf>.self) let leafBuilderAlias: Instantiator<Leaf>
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				final class Promoted: Instantiable {
				    init(leafBuilderAlias: Instantiator<Leaf>?) {
				        self.leafBuilderAlias = leafBuilderAlias
				    }

				    @Received let leafBuilderAlias: Instantiator<Leaf>?
				}
				""",
				"""
				@Instantiable
				final class Leaf: Instantiable {
				    init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            leafBuilder: (() -> Leaf)? = nil,
			            promoted: ((Instantiator<Leaf>?) -> Promoted)? = nil
			        ) {
			            self.leafBuilder = leafBuilder
			            self.promoted = promoted
			        }

			        let leafBuilder: (() -> Leaf)?
			        let promoted: ((Instantiator<Leaf>?) -> Promoted)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_leafBuilder() -> Leaf {
			            if let safeDIBuilder = safeDIOverrides.leafBuilder { safeDIBuilder() } else { Leaf() }
			        }
			        let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let leafBuilderAlias: Instantiator<Leaf> = leafBuilder
			        #sourceLocation()
			        let promoted = if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(leafBuilderAlias) } else { Promoted(leafBuilderAlias: leafBuilderAlias) }
			        return Screen(leafBuilderAlias: leafBuilderAlias, promoted: promoted)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsRequiredAliasToPromotedTreesOptionalReceive_whenAliasIsConstant() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				final class Screen: Instantiable {
				    init(leaf: Leaf, leafAlias: Leaf, promoted: Promoted) {
				        self.leaf = leaf
				        self.leafAlias = leafAlias
				        self.promoted = promoted
				    }

				    @Instantiated let leaf: Leaf
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let leafAlias: Leaf
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				final class Promoted: Instantiable {
				    init(leafAlias: Leaf?) {
				        self.leafAlias = leafAlias
				    }

				    @Received let leafAlias: Leaf?
				}
				""",
				"""
				@Instantiable
				final class Leaf: Instantiable {
				    init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            leaf: (() -> Leaf)? = nil,
			            promoted: ((Leaf?) -> Promoted)? = nil
			        ) {
			            self.leaf = leaf
			            self.promoted = promoted
			        }

			        let leaf: (() -> Leaf)?
			        let promoted: ((Leaf?) -> Promoted)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 10)
			        let leafAlias: Leaf = leaf
			        #sourceLocation()
			        let promoted = if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(leafAlias) } else { Promoted(leafAlias: leafAlias) }
			        return Screen(leaf: leaf, leafAlias: leafAlias, promoted: promoted)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsOnlyIfAvailableAliasToPromotedTreesOptionalReceive_whenReceiveRequiresIt() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				final class Screen: Instantiable {
				    init(leaf: Leaf, leafAlias: Leaf?, promoted: Promoted) {
				        self.leaf = leaf
				        self.leafAlias = leafAlias
				        self.promoted = promoted
				    }

				    @Instantiated let leaf: Leaf
				    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self, onlyIfAvailable: true) let leafAlias: Leaf?
				    @Received let promoted: Promoted
				}
				""",
				"""
				@Instantiable
				final class Promoted: Instantiable {
				    init(leafAlias: Leaf?) {
				        self.leafAlias = leafAlias
				    }

				    @Received let leafAlias: Leaf?
				}
				""",
				"""
				@Instantiable
				final class Leaf: Instantiable {
				    init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            leaf: (() -> Leaf)? = nil,
			            promoted: ((Leaf?) -> Promoted)? = nil
			        ) {
			            self.leaf = leaf
			            self.promoted = promoted
			        }

			        let leaf: (() -> Leaf)?
			        let promoted: ((Leaf?) -> Promoted)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 10)
			        let leafAlias: Leaf? = leaf
			        #sourceLocation()
			        let promoted = if let safeDIBuilder = safeDIOverrides.promoted { safeDIBuilder(leafAlias) } else { Promoted(leafAlias: leafAlias) }
			        return Screen(leaf: leaf, leafAlias: leafAlias, promoted: promoted)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
