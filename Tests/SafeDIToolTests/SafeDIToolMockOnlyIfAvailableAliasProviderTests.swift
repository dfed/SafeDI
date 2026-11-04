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
@testable import SafeDITool

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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
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
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Holder", productionExpression: "Top().holder")
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
	mutating func mock_handsOverrideToTypeRequiringAlias_whenNonRootMockedTypesSiblingReceivesAliasOnlyIfAvailableAndTypeBuiltAsFulfillingConstantRequiresAlias() async throws {
		// The override `Sibling`'s receive gives the mock stands for what an ancestor of `Holder` provides, which every
		// root that builds `Holder` must, or production rejects it. So `Service` reads that override rather than require
		// `Child`'s alias, which is not created. No such root is declared here, so no values are compared.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .constant, outsideReceiver: .sibling),
				Self.child(fulfillingProperty: .constant),
				Self.receiver(named: "Service", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: false),
				Self.receiver(named: "Sibling", fulfillingProperty: .constant, receivesAliasOnlyIfAvailable: true),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

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
			            let service = if let safeDIBuilder = safeDIOverrides.child.service { safeDIBuilder(serviceAlias) } else { Service(serviceAlias: serviceAlias) }
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
	mutating func mock_handsOverrideToTypeRequiringAlias_whenNonRootMockedTypesSiblingReceivesAliasOnlyIfAvailableAndTypeBuiltByFulfillingInstantiatorRequiresAlias() async throws {
		// The override `Sibling`'s receive gives the mock stands for what an ancestor of `Holder` provides, which every
		// root that builds `Holder` must, or production rejects it. So `Leaf` reads that override rather than require
		// `Child`'s alias, which is not created. No such root is declared here, so no values are compared.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.mockedType(named: "Holder", isRoot: false, fulfillingProperty: .instantiator, outsideReceiver: .sibling),
				Self.child(fulfillingProperty: .instantiator),
				Self.receiver(named: "Leaf", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: false),
				Self.receiver(named: "Sibling", fulfillingProperty: .instantiator, receivesAliasOnlyIfAvailable: true),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

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
			                if let safeDIBuilder = safeDIOverrides.child.leafBuilder { safeDIBuilder(leafBuilderAlias) } else { Leaf(leafBuilderAlias: leafBuilderAlias) }
			            }
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
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
	mutating func generate_passesEnclosingPropertyAndCreatesNoAlias_whenRootInstantiatesAliasesProperty() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.rootInstantiatingAliasesProperty(generateMock: false), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let serviceAlias = Service(serviceAlias: nil)
			        func __safeDI_child() -> Child {
			            // Did not create `serviceAlias: Service?` because `service: Service` is unavailable.
			            let service = Service(serviceAlias: serviceAlias)
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
	mutating func mock_passesEnclosingPropertyAndCreatesNoAlias_whenRootInstantiatesAliasesProperty() async throws {
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
			            let service = if let safeDIBuilder = safeDIOverrides.child.service { safeDIBuilder(serviceAlias) } else { Service(serviceAlias: serviceAlias) }
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(service, serviceAlias) } else { Child(service: service, serviceAlias: serviceAlias) }
			        }
			        let child: Child = __safeDI_child()
			        return Root(serviceAlias: serviceAlias, child: child)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output, mockedType: "Root", productionExpression: "Root()")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesForwardedPropertyToTypeRequiringAlias_whenMockedTypesAncestorForwardsAliasesProperty() async throws {
		// Generating `Holder`'s mock does not reject the production tree, which hands `Service` the property `Middle`
		// forwards and creates no alias.
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.middleForwardingAliasesPropertyAboveMockedType, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		#expect(output.dependencyTreeFiles == [
			"Top+SafeDI.swift": generatedFileHeader + """
			extension Top {
			    public convenience init() {
			        func __safeDI_middleBuilder(serviceAlias: Service) -> Middle {
			            func __safeDI_holder() -> Holder {
			                func __safeDI_child() -> Child {
			                    // Did not create `serviceAlias: Service?` because `service: Service` is unavailable.
			                    let service = Service(serviceAlias: serviceAlias)
			                    return Child(service: service, serviceAlias: serviceAlias)
			                }
			                let child: Child = __safeDI_child()
			                let sibling = Sibling(serviceAlias: serviceAlias)
			                return Holder(child: child, sibling: sibling)
			            }
			            let holder: Holder = __safeDI_holder()
			            return Middle(serviceAlias: serviceAlias, holder: holder)
			        }
			        let middleBuilder = Instantiator<Middle> {
			            __safeDI_middleBuilder(serviceAlias: $0)
			        }
			        self.init(middleBuilder: middleBuilder)
			    }
			}
			""",
		], "Unexpected output \(output.dependencyTreeFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsOverrideToTypeRequiringAlias_whenMockedTypesAncestorForwardsAliasesProperty() async throws {
		// The override `Sibling`'s receive gives the mock stands for the property `Middle` forwards, so `Service` reads
		// it, `nil` by default, and `Child`'s alias is not created, as in production. The values are not compared:
		// `mock()` is not passed what `Middle` forwards.
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.middleForwardingAliasesPropertyAboveMockedType, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

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
			            let service = if let safeDIBuilder = safeDIOverrides.child.service { safeDIBuilder(serviceAlias) } else { Service(serviceAlias: serviceAlias) }
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
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The property `Child` builds and declares an `onlyIfAvailable` alias of.
	private enum FulfillingProperty {
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
	private enum OutsideReceiver {
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
	) throws {
		let fixtureFiles = Dictionary(uniqueKeysWithValues: fixture.enumerated().map { ("File\($0.offset).swift", $0.element) })
		try expectDifferentialValuesAgree(
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
