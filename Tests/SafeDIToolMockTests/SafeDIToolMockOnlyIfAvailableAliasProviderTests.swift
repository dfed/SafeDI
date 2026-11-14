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

/// A mock binds each property its tree receives only if available, and that nothing in its tree provides, to an
/// override at its root, which defaults to `nil` and stands for what an ancestor of the mocked type may provide. A
/// receiver reads that override as it would the ancestor's property, but the override alone does not keep an
/// `onlyIfAvailable` alias a type in the tree declares from being created: the alias is created from its fulfilling
/// property after that property is built, where that closes no cycle, as production creates it where no ancestor
/// provides its property, and only the receivers the alias does not reach read the override.
///
/// `Child` builds `service` (or `leafBuilder`) and declares an `onlyIfAvailable` alias of it, which the type it builds
/// receives, only if available or required. The mocked type is a root, or a type no root is, which a `Top` root builds
/// where production values are compared; beside `Child` it builds a type that receives the alias's label only if
/// available, or none.
struct SafeDIToolMockOnlyIfAvailableAliasProviderTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – A root's mock, the receiver inside the alias's tree receiving it only if available

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromConstant_whenRootsSiblingReceivesAliasOnlyIfAvailable() async throws {
		let fixture = [
			Self.mockedType(named: "Root", isRoot: true, fulfillingProperty: .constant, outsideReceiver: .sibling),
			Self.child(fulfillingProperty: .constant),
			Self.receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
			Self.receiver(named: "Sibling", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration = .init(),
			            sibling: ((Service?) -> Sibling)? = nil,
			            serviceAlias: Service? = nil
			        ) {
			            self.child = child
			            self.sibling = sibling
			            self.serviceAlias = serviceAlias
			        }

			        let child: Child.SafeDIMockConfiguration
			        let sibling: ((Service?) -> Sibling)?
			        let serviceAlias: Service?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let serviceAlias: Service? = safeDIOverrides.serviceAlias
			        func __safeDI_child() -> Child {
			            let service = if let safeDIBuilder = safeDIOverrides.child.service { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let serviceAlias: Service? = service
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(service, serviceAlias) } else { Child(service: service, serviceAlias: serviceAlias) }
			        }
			        let child: Child = __safeDI_child()
			        let sibling = if let safeDIBuilder = safeDIOverrides.sibling { safeDIBuilder(serviceAlias) } else { Sibling(serviceAlias: serviceAlias) }
			        return Root(child: child, sibling: sibling)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromConstant_whenNothingOutsideAliasesTreeReceivesItsLabel() async throws {
		let fixture = [
			Self.mockedType(named: "Root", isRoot: true, fulfillingProperty: .constant, outsideReceiver: nil),
			Self.child(fulfillingProperty: .constant),
			Self.receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        let child: Child.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_child() -> Child {
			            let service = if let safeDIBuilder = safeDIOverrides.child.service { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let serviceAlias: Service? = service
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(service, serviceAlias) } else { Child(service: service, serviceAlias: serviceAlias) }
			        }
			        let child: Child = __safeDI_child()
			        return Root(child: child)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromInstantiator_whenRootsSiblingReceivesAliasOnlyIfAvailable() async throws {
		let fixture = [
			Self.mockedType(named: "Root", isRoot: true, fulfillingProperty: .instantiator, outsideReceiver: .sibling),
			Self.child(fulfillingProperty: .instantiator),
			Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
			Self.receiver(named: "Sibling", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration = .init(),
			            sibling: ((Instantiator<Leaf>?) -> Sibling)? = nil,
			            leafBuilderAlias: Instantiator<Leaf>? = nil
			        ) {
			            self.child = child
			            self.sibling = sibling
			            self.leafBuilderAlias = leafBuilderAlias
			        }

			        let child: Child.SafeDIMockConfiguration
			        let sibling: ((Instantiator<Leaf>?) -> Sibling)?
			        let leafBuilderAlias: Instantiator<Leaf>?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let leafBuilderAlias: Instantiator<Leaf>? = safeDIOverrides.leafBuilderAlias
			        func __safeDI_child() -> Child {
			            func __safeDI_leafBuilder() -> Leaf {
			                if let safeDIBuilder = safeDIOverrides.child.leafBuilder { safeDIBuilder(nil) } else { Leaf(leafBuilderAlias: nil) }
			            }
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let leafBuilderAlias: Instantiator<Leaf>? = leafBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(leafBuilder, leafBuilderAlias) } else { Child(leafBuilder: leafBuilder, leafBuilderAlias: leafBuilderAlias) }
			        }
			        let child: Child = __safeDI_child()
			        let sibling = if let safeDIBuilder = safeDIOverrides.sibling { safeDIBuilder(leafBuilderAlias) } else { Sibling(leafBuilderAlias: leafBuilderAlias) }
			        return Root(child: child, sibling: sibling)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromInstantiator_whenRootBuildsAnotherInstantiatorWhoseTypeReceivesAliasOnlyIfAvailable() async throws {
		// Graph fuzzer seed 4724's shape: the type the instantiator builds receives the alias's label inside and outside
		// the alias's tree. The one the root builds reads the override; the one `Child` builds is passed `nil`, as in
		// production.
		let fixture = [
			Self.mockedType(named: "Root", isRoot: true, fulfillingProperty: .instantiator, outsideReceiver: .instantiatorOfFulfillingType),
			Self.child(fulfillingProperty: .instantiator),
			Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            leafBuilder: ((Instantiator<Leaf>?) -> Leaf)? = nil,
			            child: Child.SafeDIMockConfiguration = .init(),
			            leafBuilderAlias: Instantiator<Leaf>? = nil
			        ) {
			            self.leafBuilder = leafBuilder
			            self.child = child
			            self.leafBuilderAlias = leafBuilderAlias
			        }

			        let leafBuilder: ((Instantiator<Leaf>?) -> Leaf)?
			        let child: Child.SafeDIMockConfiguration
			        let leafBuilderAlias: Instantiator<Leaf>?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let leafBuilderAlias: Instantiator<Leaf>? = safeDIOverrides.leafBuilderAlias
			        func __safeDI_leafBuilder() -> Leaf {
			            if let safeDIBuilder = safeDIOverrides.leafBuilder { safeDIBuilder(leafBuilderAlias) } else { Leaf(leafBuilderAlias: leafBuilderAlias) }
			        }
			        let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			        func __safeDI_child() -> Child {
			            func __safeDI_leafBuilder() -> Leaf {
			                if let safeDIBuilder = safeDIOverrides.child.leafBuilder { safeDIBuilder(nil) } else { Leaf(leafBuilderAlias: nil) }
			            }
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let leafBuilderAlias: Instantiator<Leaf>? = leafBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(leafBuilder, leafBuilderAlias) } else { Child(leafBuilder: leafBuilder, leafBuilderAlias: leafBuilderAlias) }
			        }
			        let child: Child = __safeDI_child()
			        return Root(leafBuilder: leafBuilder, child: child)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromInstantiator_whenNothingOutsideAliasesTreeReceivesItsLabel() async throws {
		let fixture = [
			Self.mockedType(named: "Root", isRoot: true, fulfillingProperty: .instantiator, outsideReceiver: nil),
			Self.child(fulfillingProperty: .instantiator),
			Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        let child: Child.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_child() -> Child {
			            func __safeDI_leafBuilder() -> Leaf {
			                if let safeDIBuilder = safeDIOverrides.child.leafBuilder { safeDIBuilder(nil) } else { Leaf(leafBuilderAlias: nil) }
			            }
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let leafBuilderAlias: Instantiator<Leaf>? = leafBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(leafBuilder, leafBuilderAlias) } else { Child(leafBuilder: leafBuilder, leafBuilderAlias: leafBuilderAlias) }
			        }
			        let child: Child = __safeDI_child()
			        return Root(child: child)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
	}

	// MARK: Tests – A mock of a type no root is, the receiver inside the alias's tree receiving it only if available

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromConstant_whenNonRootMockedTypesSiblingReceivesAliasOnlyIfAvailable() async throws {
		let fixture = [
			Self.top,
			Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .constant, outsideReceiver: .sibling),
			Self.child(fulfillingProperty: .constant),
			Self.receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
			Self.receiver(named: "Sibling", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Holder+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration = .init(),
			            sibling: ((Service?) -> Sibling)? = nil,
			            serviceAlias: Service? = nil
			        ) {
			            self.child = child
			            self.sibling = sibling
			            self.serviceAlias = serviceAlias
			        }

			        let child: Child.SafeDIMockConfiguration
			        let sibling: ((Service?) -> Sibling)?
			        let serviceAlias: Service?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Holder {
			        let serviceAlias: Service? = safeDIOverrides.serviceAlias
			        func __safeDI_child() -> Child {
			            let service = if let safeDIBuilder = safeDIOverrides.child.service { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let serviceAlias: Service? = service
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(service, serviceAlias) } else { Child(service: service, serviceAlias: serviceAlias) }
			        }
			        let child: Child = __safeDI_child()
			        let sibling = if let safeDIBuilder = safeDIOverrides.sibling { safeDIBuilder(serviceAlias) } else { Sibling(serviceAlias: serviceAlias) }
			        return Holder(child: child, sibling: sibling)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromConstant_whenNothingOutsideNonRootMockedTypesAliasTreeReceivesItsLabel() async throws {
		let fixture = [
			Self.top,
			Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .constant, outsideReceiver: nil),
			Self.child(fulfillingProperty: .constant),
			Self.receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Holder+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        let child: Child.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Holder {
			        func __safeDI_child() -> Child {
			            let service = if let safeDIBuilder = safeDIOverrides.child.service { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let serviceAlias: Service? = service
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(service, serviceAlias) } else { Child(service: service, serviceAlias: serviceAlias) }
			        }
			        let child: Child = __safeDI_child()
			        return Holder(child: child)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromInstantiator_whenNonRootMockedTypesSiblingReceivesAliasOnlyIfAvailable() async throws {
		let fixture = [
			Self.top,
			Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .instantiator, outsideReceiver: .sibling),
			Self.child(fulfillingProperty: .instantiator),
			Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
			Self.receiver(named: "Sibling", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Holder+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration = .init(),
			            sibling: ((Instantiator<Leaf>?) -> Sibling)? = nil,
			            leafBuilderAlias: Instantiator<Leaf>? = nil
			        ) {
			            self.child = child
			            self.sibling = sibling
			            self.leafBuilderAlias = leafBuilderAlias
			        }

			        let child: Child.SafeDIMockConfiguration
			        let sibling: ((Instantiator<Leaf>?) -> Sibling)?
			        let leafBuilderAlias: Instantiator<Leaf>?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Holder {
			        let leafBuilderAlias: Instantiator<Leaf>? = safeDIOverrides.leafBuilderAlias
			        func __safeDI_child() -> Child {
			            func __safeDI_leafBuilder() -> Leaf {
			                if let safeDIBuilder = safeDIOverrides.child.leafBuilder { safeDIBuilder(nil) } else { Leaf(leafBuilderAlias: nil) }
			            }
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let leafBuilderAlias: Instantiator<Leaf>? = leafBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(leafBuilder, leafBuilderAlias) } else { Child(leafBuilder: leafBuilder, leafBuilderAlias: leafBuilderAlias) }
			        }
			        let child: Child = __safeDI_child()
			        let sibling = if let safeDIBuilder = safeDIOverrides.sibling { safeDIBuilder(leafBuilderAlias) } else { Sibling(leafBuilderAlias: leafBuilderAlias) }
			        return Holder(child: child, sibling: sibling)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromInstantiator_whenNonRootMockedTypeBuildsAnotherInstantiatorWhoseTypeReceivesAliasOnlyIfAvailable() async throws {
		let fixture = [
			Self.top,
			Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .instantiator, outsideReceiver: .instantiatorOfFulfillingType),
			Self.child(fulfillingProperty: .instantiator),
			Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Holder+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            leafBuilder: ((Instantiator<Leaf>?) -> Leaf)? = nil,
			            child: Child.SafeDIMockConfiguration = .init(),
			            leafBuilderAlias: Instantiator<Leaf>? = nil
			        ) {
			            self.leafBuilder = leafBuilder
			            self.child = child
			            self.leafBuilderAlias = leafBuilderAlias
			        }

			        let leafBuilder: ((Instantiator<Leaf>?) -> Leaf)?
			        let child: Child.SafeDIMockConfiguration
			        let leafBuilderAlias: Instantiator<Leaf>?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Holder {
			        let leafBuilderAlias: Instantiator<Leaf>? = safeDIOverrides.leafBuilderAlias
			        func __safeDI_leafBuilder() -> Leaf {
			            if let safeDIBuilder = safeDIOverrides.leafBuilder { safeDIBuilder(leafBuilderAlias) } else { Leaf(leafBuilderAlias: leafBuilderAlias) }
			        }
			        let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			        func __safeDI_child() -> Child {
			            func __safeDI_leafBuilder() -> Leaf {
			                if let safeDIBuilder = safeDIOverrides.child.leafBuilder { safeDIBuilder(nil) } else { Leaf(leafBuilderAlias: nil) }
			            }
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let leafBuilderAlias: Instantiator<Leaf>? = leafBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(leafBuilder, leafBuilderAlias) } else { Child(leafBuilder: leafBuilder, leafBuilderAlias: leafBuilderAlias) }
			        }
			        let child: Child = __safeDI_child()
			        return Holder(leafBuilder: leafBuilder, child: child)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasFromInstantiator_whenNothingOutsideNonRootMockedTypesAliasTreeReceivesItsLabel() async throws {
		let fixture = [
			Self.top,
			Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .instantiator, outsideReceiver: nil),
			Self.child(fulfillingProperty: .instantiator),
			Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Holder+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        let child: Child.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Holder {
			        func __safeDI_child() -> Child {
			            func __safeDI_leafBuilder() -> Leaf {
			                if let safeDIBuilder = safeDIOverrides.child.leafBuilder { safeDIBuilder(nil) } else { Leaf(leafBuilderAlias: nil) }
			            }
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let leafBuilderAlias: Instantiator<Leaf>? = leafBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(leafBuilder, leafBuilderAlias) } else { Child(leafBuilder: leafBuilder, leafBuilderAlias: leafBuilderAlias) }
			        }
			        let child: Child = __safeDI_child()
			        return Holder(child: child)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
	}

	// MARK: Tests – The receiver inside the alias's tree requiring it

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenRootsSiblingReceivesAliasOnlyIfAvailableAndTypeBuiltAsFulfillingConstantRequiresAlias() async {
		await assertThrowsError(diagnostics: { fixtures in Self.constantRequiredInsideItsOwnTreeError(fixtures) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.mockedType(named: "Root", isRoot: true, fulfillingProperty: .constant, outsideReceiver: .sibling),
					Self.child(fulfillingProperty: .constant),
					Self.receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: false),
					Self.receiver(named: "Sibling", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTypeBuiltAsRootsFulfillingConstantRequiresAlias() async {
		await assertThrowsError(diagnostics: { fixtures in Self.constantRequiredInsideItsOwnTreeError(fixtures) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.mockedType(named: "Root", isRoot: true, fulfillingProperty: .constant, outsideReceiver: nil),
					Self.child(fulfillingProperty: .constant),
					Self.receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: false),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenRootsSiblingReceivesAliasOnlyIfAvailableAndTypeBuiltByFulfillingInstantiatorRequiresAlias() async {
		await assertThrowsError(diagnostics: { fixtures in Self.instantiatorRequiredInsideItsOwnTreeError(fixtures) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.mockedType(named: "Root", isRoot: true, fulfillingProperty: .instantiator, outsideReceiver: .sibling),
					Self.child(fulfillingProperty: .instantiator),
					Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: false),
					Self.receiver(named: "Sibling", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTypeBuiltByRootsFulfillingInstantiatorRequiresAlias() async {
		await assertThrowsError(diagnostics: { fixtures in Self.instantiatorRequiredInsideItsOwnTreeError(fixtures) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.mockedType(named: "Root", isRoot: true, fulfillingProperty: .instantiator, outsideReceiver: nil),
					Self.child(fulfillingProperty: .instantiator),
					Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: false),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenNonRootMockedTypesSiblingReceivesAliasOnlyIfAvailableAndTypeBuiltAsFulfillingConstantRequiresAlias() async {
		// `Service` requires `Child`'s alias of `service`, the `Service` being built: the alias is the nearest declaration of
		// `serviceAlias`, whatever override the mock binds for `Sibling`, so `Service` must be built after itself, as in production.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Service.swift"]):7:5: error: Dependency cycle: @Instantiated `service: Service` -> @Received `serviceAlias: Service?` -> @Received `service: Service`. `service: Service` is received while it is still being instantiated. `serviceAlias: Service?` renames `service: Service` only if available, so a type that receives `serviceAlias` without `onlyIfAvailable` must be built after `service: Service`. Receive `serviceAlias` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `service: Service` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .constant, outsideReceiver: .sibling),
					Self.child(fulfillingProperty: .constant),
					Self.receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: false),
					Self.receiver(named: "Sibling", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeBuiltAsNonRootMockedTypesFulfillingConstantRequiresAlias() async {
		await assertThrowsError(diagnostics: { fixtures in Self.constantRequiredInsideItsOwnTreeError(fixtures) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .constant, outsideReceiver: nil),
					Self.child(fulfillingProperty: .constant),
					Self.receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: false),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenNonRootMockedTypesSiblingReceivesAliasOnlyIfAvailableAndTypeBuiltByFulfillingInstantiatorRequiresAlias() async {
		// The `Instantiator` twin of the test above.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Leaf.swift"]):7:5: error: Dependency cycle: @Instantiated `leafBuilder: Instantiator<Leaf>` -> @Received `leafBuilderAlias: Instantiator<Leaf>?` -> @Received `leafBuilder: Instantiator<Leaf>`. `leafBuilder: Instantiator<Leaf>` is received while it is still being instantiated. `leafBuilderAlias: Instantiator<Leaf>?` renames `leafBuilder: Instantiator<Leaf>` only if available, so a type that receives `leafBuilderAlias` without `onlyIfAvailable` must be built after `leafBuilder: Instantiator<Leaf>`. Receive `leafBuilderAlias` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `leafBuilder: Instantiator<Leaf>` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .instantiator, outsideReceiver: .sibling),
					Self.child(fulfillingProperty: .instantiator),
					Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: false),
					Self.receiver(named: "Sibling", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeBuiltByNonRootMockedTypesFulfillingInstantiatorRequiresAlias() async {
		await assertThrowsError(diagnostics: { fixtures in Self.instantiatorRequiredInsideItsOwnTreeError(fixtures) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .instantiator, outsideReceiver: nil),
					Self.child(fulfillingProperty: .instantiator),
					Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: false),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – A provider production builds above the alias

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromItsDependency_whenRootInstantiatesAliasesName() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.rootInstantiatingAliasesProperty(generateMock: false), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let serviceAlias = Service(serviceAlias: nil)
			        func __safeDI_child() -> Child {
			            let service = Service(serviceAlias: nil)
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let serviceAlias: Service? = service
			            #sourceLocation()
			            return Child(service: service, serviceAlias: serviceAlias)
			        }
			        let child: Child = __safeDI_child()
			        self.init(serviceAlias: serviceAlias, child: child)
			    }
			}
			""",
		], "Unexpected output \(output.dependencyTreeFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsAliasFromItsDependency_whenRootInstantiatesAliasesName() async throws {
		let fixture = Self.rootInstantiatingAliasesProperty(generateMock: true)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            serviceAlias: ((Service?) -> Service)? = nil,
			            child: Child.SafeDIMockConfiguration = .init()
			        ) {
			            self.serviceAlias = serviceAlias
			            self.child = child
			        }

			        let serviceAlias: ((Service?) -> Service)?
			        let child: Child.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let serviceAlias = if let safeDIBuilder = safeDIOverrides.serviceAlias { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			        func __safeDI_child() -> Child {
			            let service = if let safeDIBuilder = safeDIOverrides.child.service { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 9)
			            let serviceAlias: Service? = service
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(service, serviceAlias) } else { Child(service: service, serviceAlias: serviceAlias) }
			        }
			        let child: Child = __safeDI_child()
			        return Root(serviceAlias: serviceAlias, child: child)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTypeBuiltAsFulfillingConstantRequiresAliasAndMockedTypesAncestorForwardsItsLabel() async {
		// `Middle` forwards `serviceAlias`, but `Child`'s alias is its nearest declaration for `Service`, which requires it
		// inside the `service` it is bound from: the dependency cycle the same tree gets with nothing above `Child`. The
		// mock of `Holder` is never generated, since the production tree is rejected first.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Service.swift"]):7:5: error: Dependency cycle: @Instantiated `service: Service` -> @Received `serviceAlias: Service?` -> @Received `service: Service`. `service: Service` is received while it is still being instantiated. `serviceAlias: Service?` renames `service: Service` only if available, so a type that receives `serviceAlias` without `onlyIfAvailable` must be built after `service: Service`. Receive `serviceAlias` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `service: Service` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: Self.middleForwardingAliasesPropertyAboveMockedType, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – The alias inside a lazy cycle whose closed-on function takes its label

	// The mocked type builds `A`, which receives the alias's label only if available, through `aBuilder`; `A` builds `Mid`,
	// which builds the fulfilling property, declares the alias, and builds `A` again, so `A`'s builder function takes the
	// alias's label, which the mocked type passes. A label the mock binds only to the override passes the override, which
	// keeps the alias from being created no more than it does beside no lazy cycle.

	@Test(arguments: FulfillingProperty.allCases, [OutsideReceiver.sibling, nil])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_createsTypesOwnAliasOfParameterLabel_whenNonRootMockedTypesLazyCycleClosesBesideIt(fulfillingProperty: FulfillingProperty, outsideReceiver: OutsideReceiver?) async throws {
		let fixture = [Self.top] + Self.lazyCycleAroundAlias(mockedType: "Holder", fulfillingProperty: fulfillingProperty, withSibling: outsideReceiver == .sibling)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Holder+SafeDIMock.swift": generatedFileHeader + Self.expectedLazyCycleAroundAliasMock(fulfillingProperty: fulfillingProperty, withSibling: outsideReceiver == .sibling, fixtures: output.fixtures),
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeBuiltAsFulfillingConstantInsideLazyCycleRequiresAliasOfParameterLabel() async {
		// As beside no lazy cycle, `Service` requires `Mid`'s alias of the `Service` being built, which the alias is the
		// nearest declaration of: a dependency cycle.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Service.swift"]):7:5: error: Dependency cycle: @Instantiated `service: Service` -> @Received `serviceAlias: Service?` -> @Received `service: Service`. `service: Service` is received while it is still being instantiated. `serviceAlias: Service?` renames `service: Service` only if available, so a type that receives `serviceAlias` without `onlyIfAvailable` must be built after `service: Service`. Receive `serviceAlias` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `service: Service` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.lazyCycleAroundAlias(mockedType: "Holder", fulfillingProperty: .constant, withSibling: true, fulfillingTypeRequiresAlias: true),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsAliasFromItsDependency_whenTypeBesideLazyCycleRequiresAliasesName() async throws {
		// `Other` requires `serviceAlias: Service`, which `Top` provides above `Holder` and `Holder`'s mock builds, but `Mid`'s
		// alias is the nearest declaration of `serviceAlias` inside the cycle, bound from `Mid`'s `service`, in production and
		// in the mock alike.
		let fixture = [
			seamFixtureType(named: "Top", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let serviceAlias: Service", "@Instantiated let holder: Holder"]),
			seamFixtureType(named: "Other", isFinalClass: true, declarations: ["@Received let serviceAlias: Service"]),
		] + Self.lazyCycleAroundAlias(mockedType: "Holder", fulfillingProperty: .constant, withSibling: false, mockedTypeDeclares: ["@Instantiated let other: Other"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Holder+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            serviceAlias: ((Service?) -> Service)? = nil,
			            other: ((Service) -> Other)? = nil,
			            aBuilder: A.SafeDIMockConfiguration = .init()
			        ) {
			            self.serviceAlias = serviceAlias
			            self.other = other
			            self.aBuilder = aBuilder
			        }

			        let serviceAlias: ((Service?) -> Service)?
			        let other: ((Service) -> Other)?
			        let aBuilder: A.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Holder {
			        let serviceAlias = if let safeDIBuilder = safeDIOverrides.serviceAlias { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			        let other = if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(serviceAlias) } else { Other(serviceAlias: serviceAlias) }
			        func __safeDI_aBuilder(serviceAlias: Service?) -> A {
			            func __safeDI_midBuilder() -> Mid {
			                let service = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.service { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			                #sourceLocation(file: "\(output.fixtures["Mid.swift"])", line: 10)
			                let serviceAlias: Service? = service
			                #sourceLocation()
			                let aBuilder = Instantiator<A> {
			                    __safeDI_aBuilder(serviceAlias: serviceAlias)
			                }
			                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(service, serviceAlias, aBuilder) } else { Mid(service: service, serviceAlias: serviceAlias, aBuilder: aBuilder) }
			            }
			            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(serviceAlias, midBuilder) } else { A(serviceAlias: serviceAlias, midBuilder: midBuilder) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(serviceAlias: serviceAlias)
			        }
			        return Holder(other: other, aBuilder: aBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsAliasFromItsDependency_whenMockedTypeForwardsAliasesNameAboveLazyCycle() async throws {
		// `Holder` forwards `serviceAlias` above `A`'s builder function, but `Mid`'s alias is the nearest declaration of
		// `serviceAlias` inside the cycle, bound from `Mid`'s `service`, in production and in the mock alike.
		let fixture = [
			seamFixtureType(named: "Top", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let holderBuilder: Instantiator<Holder>"]),
		] + Self.lazyCycleAroundAlias(mockedType: "Holder", fulfillingProperty: .constant, withSibling: false, mockedTypeDeclares: ["@Forwarded let serviceAlias: Service"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.mockFiles == [
			"Holder+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: A.SafeDIMockConfiguration = .init()
			        ) {
			            self.aBuilder = aBuilder
			        }

			        let aBuilder: A.SafeDIMockConfiguration
			    }

			    static func mock(
			        serviceAlias: Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Holder {
			        func __safeDI_aBuilder(serviceAlias: Service?) -> A {
			            func __safeDI_midBuilder() -> Mid {
			                let service = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.service { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			                #sourceLocation(file: "\(output.fixtures["Mid.swift"])", line: 10)
			                let serviceAlias: Service? = service
			                #sourceLocation()
			                let aBuilder = Instantiator<A> {
			                    __safeDI_aBuilder(serviceAlias: serviceAlias)
			                }
			                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(service, serviceAlias, aBuilder) } else { Mid(service: service, serviceAlias: serviceAlias, aBuilder: aBuilder) }
			            }
			            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(serviceAlias, midBuilder) } else { A(serviceAlias: serviceAlias, midBuilder: midBuilder) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(serviceAlias: serviceAlias)
			        }
			        return Holder(serviceAlias: serviceAlias, aBuilder: aBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		let fixtureFiles = Dictionary(uniqueKeysWithValues: fixture.enumerated().map { ("File\($0.offset).swift", $0.element) })
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(
				fixtureFiles: fixtureFiles,
				generatedFiles: output.dependencyTreeFiles.merging(["Holder+ProductionMock.swift": "extension Holder {\n    static func mock(serviceAlias: Service) -> Holder {\n        Top().holderBuilder.instantiate(serviceAlias)\n    }\n}\n"]) { first, _ in first },
			),
			probes: [DifferentialValueProbe("Holder.mock(serviceAlias: Service(serviceAlias: nil))")],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The mock SafeDI generates for `Holder` of `lazyCycleAroundAlias` with nothing else declared: `Mid` builds the
	/// fulfilling property first, passing its type `nil`, creates the alias from it, and builds `A` again with the alias,
	/// while `Holder` passes `A`'s builder function the override.
	private static func expectedLazyCycleAroundAliasMock(fulfillingProperty: FulfillingProperty, withSibling: Bool, fixtures: FixturePaths) -> String {
		let label = fulfillingProperty.label
		let type = fulfillingProperty.typeName
		let fulfillingPropertyConstruction = switch fulfillingProperty {
		case .constant:
			"""
			                let service = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.service { safeDIBuilder(nil) } else { Service(serviceAlias: nil) }
			"""
		case .instantiator:
			"""
			                func __safeDI_leafBuilder() -> Leaf {
			                    if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.leafBuilder { safeDIBuilder(nil) } else { Leaf(leafBuilderAlias: nil) }
			                }
			                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			"""
		}
		let siblingConstruction = withSibling
			? "                let sibling = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.sibling { safeDIBuilder(\(label)Alias) } else { Sibling(\(label)Alias: \(label)Alias) }\n"
			: ""
		// Appended rather than joined with `+` around a ternary: Swift 6.2 on Linux can time out type-checking a `+` chain
		// of arrays with a ternary; later Swift does not.
		var midArguments = [label, "\(label)Alias"]
		if withSibling {
			midArguments.append("sibling")
		}
		midArguments.append("aBuilder")
		return """
		#if DEBUG
		extension Holder {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            \(label)Alias: \(type)? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.\(label)Alias = \(label)Alias
		        }

		        let aBuilder: A.SafeDIMockConfiguration
		        let \(label)Alias: \(type)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Holder {
		        let \(label)Alias: \(type)? = safeDIOverrides.\(label)Alias
		        func __safeDI_aBuilder(\(label)Alias: \(type)?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		\(fulfillingPropertyConstruction)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: \(withSibling ? 11 : 10))
		                let \(label)Alias: \(type)? = \(label)
		                #sourceLocation()
		\(siblingConstruction)                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(\(label)Alias: \(label)Alias)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(\(midArguments.joined(separator: ", "))) } else { Mid(\(midArguments.map { "\($0): \($0)" }.joined(separator: ", "))) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(\(label)Alias, midBuilder) } else { A(\(label)Alias: \(label)Alias, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(\(label)Alias: \(label)Alias)
		        }
		        return Holder(aBuilder: aBuilder)
		    }
		}
		#endif
		"""
	}

	/// The mocked type `name`, which declares `mockedTypeDeclares` and instantiates `aBuilder: Instantiator<A>`; `A`, which
	/// receives the label of `Mid`'s alias only if available and instantiates `midBuilder: Instantiator<Mid>`; `Mid`, which
	/// builds `fulfillingProperty`, declares the `onlyIfAvailable` alias of it, builds a `Sibling` that receives the alias's
	/// label only if available where `withSibling` holds, and instantiates `aBuilder` again; and the type
	/// `fulfillingProperty` builds, which receives the alias's label, only if available unless `fulfillingTypeRequiresAlias`.
	private static func lazyCycleAroundAlias(
		mockedType name: String,
		fulfillingProperty: FulfillingProperty,
		withSibling: Bool,
		fulfillingTypeRequiresAlias: Bool = false,
		mockedTypeDeclares: [String] = [],
	) -> [String] {
		let label = fulfillingProperty.label
		let type = fulfillingProperty.typeName
		let fulfillingTypeName = switch fulfillingProperty {
		case .constant: "Service"
		case .instantiator: "Leaf"
		}
		// Appended rather than joined with `+` around ternaries: Swift 6.2 on Linux can time out type-checking a `+` chain
		// of arrays with ternaries; later Swift does not.
		var midDeclarations = [
			"@Instantiated let \(label): \(type)",
			#"@Received(fulfilledByDependencyNamed: "\#(label)", ofType: \#(type).self, onlyIfAvailable: true) let \#(label)Alias: \#(type)?"#,
		]
		if withSibling {
			midDeclarations.append("@Instantiated let sibling: Sibling")
		}
		midDeclarations.append("@Instantiated let aBuilder: Instantiator<A>")
		var fixture = [
			seamFixtureType(named: name, isFinalClass: true, declarations: mockedTypeDeclares + ["@Instantiated let aBuilder: Instantiator<A>"])
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let \(label)Alias: \(type)?", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: midDeclarations),
			receiver(named: fulfillingTypeName, fulfillingProperty: fulfillingProperty, receivesAliasOnlyIfAvailable: !fulfillingTypeRequiresAlias),
		]
		if withSibling {
			fixture.append(receiver(named: "Sibling", fulfillingProperty: fulfillingProperty, receivesAliasOnlyIfAvailable: true))
		}
		return fixture
	}

	/// The property `Child` builds and declares an `onlyIfAvailable` alias of.
	enum FulfillingProperty: CaseIterable, Sendable {
		/// `service: Service`, aliased as `serviceAlias: Service?`.
		case constant
		/// `leafBuilder: Instantiator<Leaf>`, aliased as `leafBuilderAlias: Instantiator<Leaf>?`.
		case instantiator

		var label: String {
			switch self {
			case .constant: "service"
			case .instantiator: "leafBuilder"
			}
		}

		var typeName: String {
			switch self {
			case .constant: "Service"
			case .instantiator: "Instantiator<Leaf>"
			}
		}
	}

	/// What the mocked type builds beside `Child` that receives the label of `Child`'s alias outside the alias's tree.
	enum OutsideReceiver: Sendable {
		/// A `Sibling` that receives the alias's label only if available.
		case sibling
		/// The `leafBuilder: Instantiator<Leaf>` that `Child` builds too, declared before `child`, whose `Leaf` receives
		/// the alias's label only if available.
		case instantiatorOfFulfillingType
	}

	/// The root that builds a mocked type no root is, so that the values production builds can be compared with its mock's.
	private static let top = """
	@Instantiable(isRoot: true)
	public final class Top: Instantiable {
	    public init(holder: Holder) {
	        self.holder = holder
	    }

	    @Instantiated let holder: Holder
	}
	"""

	private static func mockedType(named name: String, isRoot: Bool, fulfillingProperty: FulfillingProperty, outsideReceiver: OutsideReceiver?) -> String {
		var dependencies = [(label: "child", type: "Child")]
		switch outsideReceiver {
		case .sibling:
			dependencies.append((label: "sibling", type: "Sibling"))
		case .instantiatorOfFulfillingType:
			dependencies.insert((label: fulfillingProperty.label, type: fulfillingProperty.typeName), at: 0)
		case nil:
			break
		}
		return """
		@Instantiable(\(isRoot ? "isRoot: true, " : "")generateMock: true)
		public final class \(name): Instantiable {
		    public init(\(dependencies.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
		\(dependencies.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
		    }

		\(dependencies.map { "    @Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n"))
		}
		"""
	}

	private static func child(fulfillingProperty: FulfillingProperty) -> String {
		let label = fulfillingProperty.label
		let type = fulfillingProperty.typeName
		return """
		@Instantiable
		public final class Child: Instantiable {
		    public init(\(label): \(type), \(label)Alias: \(type)?) {
		        self.\(label) = \(label)
		        self.\(label)Alias = \(label)Alias
		    }

		    @Instantiated let \(label): \(type)
		    @Received(fulfilledByDependencyNamed: "\(label)", ofType: \(type).self, onlyIfAvailable: true) let \(label)Alias: \(type)?
		}
		"""
	}

	private static func receiver(named name: String, fulfillingProperty: FulfillingProperty, receivesAliasOnlyIfAvailable: Bool) -> String {
		let label = fulfillingProperty.label
		let type = fulfillingProperty.typeName
		return """
		@Instantiable
		public final class \(name): Instantiable {
		    public init(\(label)Alias: \(type)?) {
		        self.\(label)Alias = \(label)Alias
		    }

		    \(receivesAliasOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received") let \(label)Alias: \(type)?
		}
		"""
	}

	/// A `Root` that builds `serviceAlias: Service` above `Child`, whose alias of that label production does not create.
	private static func rootInstantiatingAliasesProperty(generateMock: Bool) -> [String] {
		[
			"""
			@Instantiable(isRoot: true\(generateMock ? ", generateMock: true" : ""))
			public final class Root: Instantiable {
			    public init(serviceAlias: Service, child: Child) {
			        self.serviceAlias = serviceAlias
			        self.child = child
			    }

			    @Instantiated let serviceAlias: Service
			    @Instantiated let child: Child
			}
			""",
			child(fulfillingProperty: .constant),
			receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
		]
	}

	/// A `Top` root whose `Instantiator<Middle>` builds a `Middle` that forwards `serviceAlias: Service` and builds the
	/// mocked `Holder`, whose `Service` requires `Child`'s alias of that label and whose `Sibling` receives it only if
	/// available.
	private static let middleForwardingAliasesPropertyAboveMockedType = [
		"""
		@Instantiable(isRoot: true)
		public final class Top: Instantiable {
		    public init(middleBuilder: Instantiator<Middle>) {
		        self.middleBuilder = middleBuilder
		    }

		    @Instantiated let middleBuilder: Instantiator<Middle>
		}
		""",
		"""
		@Instantiable
		public final class Middle: Instantiable {
		    public init(serviceAlias: Service, holder: Holder) {
		        self.serviceAlias = serviceAlias
		        self.holder = holder
		    }

		    @Forwarded let serviceAlias: Service
		    @Instantiated let holder: Holder
		}
		""",
		mockedType(named: "Holder", isRoot: false, fulfillingProperty: .constant, outsideReceiver: .sibling),
		child(fulfillingProperty: .constant),
		receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: false),
		receiver(named: "Sibling", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
	]

	private static func constantRequiredInsideItsOwnTreeError(_ fixtures: FixturePaths) -> String {
		"""
		\(fixtures["Service.swift"]):7:5: error: Dependency cycle: @Instantiated `service: Service` -> @Received `serviceAlias: Service?` -> @Received `service: Service`. `service: Service` is received while it is still being instantiated. `serviceAlias: Service?` renames `service: Service` only if available, so a type that receives `serviceAlias` without `onlyIfAvailable` must be built after `service: Service`. Receive `serviceAlias` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `service: Service` cannot be built first.
		"""
	}

	private static func instantiatorRequiredInsideItsOwnTreeError(_ fixtures: FixturePaths) -> String {
		"""
		\(fixtures["Leaf.swift"]):7:5: error: Dependency cycle: @Instantiated `leafBuilder: Instantiator<Leaf>` -> @Received `leafBuilderAlias: Instantiator<Leaf>?` -> @Received `leafBuilder: Instantiator<Leaf>`. `leafBuilder: Instantiator<Leaf>` is received while it is still being instantiated. `leafBuilderAlias: Instantiator<Leaf>?` renames `leafBuilder: Instantiator<Leaf>` only if available, so a type that receives `leafBuilderAlias` without `onlyIfAvailable` must be built after `leafBuilder: Instantiator<Leaf>`. Receive `leafBuilderAlias` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `leafBuilder: Instantiator<Leaf>` cannot be built first.
		"""
	}

	/// Expects `mockedType.mock()` to build the values `productionExpression` builds with the generated production code.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectMockBuildsWhatProductionBuilds(
		fixture: [String],
		output: TestOutput,
		mockedType: String,
		productionExpression: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let fixtureFiles = Dictionary(uniqueKeysWithValues: fixture.enumerated().map { ("File\($0.offset).swift", $0.element) })
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(
				fixtureFiles: fixtureFiles,
				generatedFiles: output.dependencyTreeFiles.merging(["\(mockedType)+ProductionMock.swift": "extension \(mockedType) {\n    static func mock() -> \(mockedType) {\n        \(productionExpression)\n    }\n}\n"]) { first, _ in first },
			),
			probes: [DifferentialValueProbe("\(mockedType).mock()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
