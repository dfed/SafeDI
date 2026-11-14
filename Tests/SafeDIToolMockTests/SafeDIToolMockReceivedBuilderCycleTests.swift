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

/// A mock builds a loop of instantiators that receive one another as production does: each builder function on the loop
/// starts by wrapping again the functions of the members its tree receives inside the loop, and reads its own override,
/// so a type built through a wrapper made again is built by the same override. A mock that promotes a received
/// instantiator whose tree receives another instantiator back builds both as a loop at the mock root.
struct SafeDIToolMockReceivedBuilderCycleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – A root's mock

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsEachOtherBuilderInsideEachFunction_whenRootsBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: ((Instantiator<B>) -> A)? = nil,
			            bBuilder: ((Instantiator<A>) -> B)? = nil
			        ) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			        }

			        let aBuilder: ((Instantiator<B>) -> A)?
			        let bBuilder: ((Instantiator<A>) -> B)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Root(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_growsByTheSameLinesForEachScreen_whenRootsErasedScreenBuildersOpenOneAnother() async throws {
		// Each screen's builder function wraps again only the three builders its screen receives, so the root's mock holds a
		// fixed number of lines for each screen, as production does.
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.screensOpeningOneAnother(screenCount: 24), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + Self.expectedMockOfScreensOpeningOneAnother(screenCount: 24),
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWhatProductionBuilds_whenLoopMemberFunctionTakesCycleParameter() async throws {
		let fixture = Self.loopMemberTakingCycleParameterFixture
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWithOverride_whenTypeIsBuiltThroughWrapperMadeAgainInsideLoop() async throws {
		// Each `B` the probe builds is built through the wrapper of `bBuilder` that `__safeDI_aBuilder` makes again, so the
		// override counts two builds.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let fixtureFiles = Self.fixtureFiles(fixture)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: output.dependencyTreeFiles),
			probes: [DifferentialValueProbe(
				name: "builds through the override",
				expression: """
				{ () -> Int in
				    var builds = 0
				    let root = Root.mock(safeDIOverrides: .init(bBuilder: { aBuilder in
				        builds += 1
				        return B(aBuilder: aBuilder)
				    }))
				    _ = root.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()
				    return builds
				}()
				""",
				knownRightExpression: "2",
			)],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Tests – Promotion

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_promotesBothBuildersAsLoopAndBindsOnlyTheOneItsTypeReceives_whenPromotedBuildersTreeRequiresMockedTypesBuilder() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("A", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<A>) -> B)? = nil,
			            aBuilder: ((Instantiator<B>) -> A)? = nil
			        ) {
			            self.bBuilder = bBuilder
			            self.aBuilder = aBuilder
			        }

			        let bBuilder: ((Instantiator<A>) -> B)?
			        let aBuilder: ((Instantiator<B>) -> A)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsEveryPromotedMember_whenMockedTypeAlsoReceivesBuilderThatBuildsIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("A", attributes: "(generateMock: true)", "@Received let aBuilder: Instantiator<A>", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: ((Instantiator<A>, Instantiator<B>) -> A)? = nil,
			            bBuilder: ((Instantiator<A>) -> B)? = nil
			        ) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			        }

			        let aBuilder: ((Instantiator<A>, Instantiator<B>) -> A)?
			        let bBuilder: ((Instantiator<A>) -> B)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_aBuilder() -> A {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder { safeDIBuilder(aBuilder, bBuilder) } else { A(aBuilder: aBuilder, bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return A(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilderInsideItsOwnFunction_whenMockedTypeReceivesBuilderThatBuildsIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Screen", attributes: "(generateMock: true)", "@Received let screenBuilder: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            screenBuilder: ((Instantiator<Screen>) -> Screen)? = nil
			        ) {
			            self.screenBuilder = screenBuilder
			        }

			        let screenBuilder: ((Instantiator<Screen>) -> Screen)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_screenBuilder() -> Screen {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(screenBuilder) } else { Screen(screenBuilder: screenBuilder) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return Screen(screenBuilder: screenBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsUnderSiblingDisambiguatedName_whenPromotedMemberSharesItsLabelWithMockedTypesProperty() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Screen", attributes: "(generateMock: true)", "@Instantiated let x: X", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let x: Instantiator<X>"),
			Self.type("X", "@Received let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<X>) -> B)? = nil,
			            x_Instantiator__X: ((Instantiator<B>) -> X)? = nil,
			            x_X: ((Instantiator<B>) -> X)? = nil
			        ) {
			            self.bBuilder = bBuilder
			            self.x_Instantiator__X = x_Instantiator__X
			            self.x_X = x_X
			        }

			        let bBuilder: ((Instantiator<X>) -> B)?
			        let x_Instantiator__X: ((Instantiator<B>) -> X)?
			        let x_X: ((Instantiator<B>) -> X)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_bBuilder() -> B {
			            let x_Instantiator__X = Instantiator<X>(__safeDI_x_Instantiator__X)
			            let x: Instantiator<X> = x_Instantiator__X
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(x) } else { B(x: x) }
			        }
			        func __safeDI_x_Instantiator__X() -> X {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.x_Instantiator__X { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let x_X = if let safeDIBuilder = safeDIOverrides.x_X { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        return Screen(x: x_X, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedSendableTwins_whenPromotedSendableBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("A", attributes: "(generateMock: true)", "@Received let bBuilder: SendableInstantiator<B>", conformances: ", Sendable"),
			Self.type("B", "@Received let aBuilder: SendableInstantiator<A>", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: (@Sendable (SendableInstantiator<A>) -> B)? = nil,
			            aBuilder: (@Sendable (SendableInstantiator<B>) -> A)? = nil
			        ) {
			            self.bBuilder = bBuilder
			            self.aBuilder = aBuilder
			        }

			        let bBuilder: (@Sendable (SendableInstantiator<A>) -> B)?
			        let aBuilder: (@Sendable (SendableInstantiator<B>) -> A)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let __safeDI_bBuilder__safeDIBuilder = safeDIOverrides.bBuilder
			        let __safeDI_aBuilder__safeDIBuilder = safeDIOverrides.aBuilder
			        @Sendable func __safeDI_bBuilder() -> B {
			            let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			            return if let safeDIBuilder = __safeDI_bBuilder__safeDIBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        @Sendable func __safeDI_aBuilder() -> A {
			            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = __safeDI_aBuilder__safeDIBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedRenameOfMember_whenMockedTypeRenamesBuilderWhoseTreeReceivesTheRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Screen", attributes: "(generateMock: true)", "@Received(fulfilledByDependencyNamed: \"nodeBuilder\", ofType: Instantiator<Node>.self) let middleBuilder: Instantiator<Node>"),
			Self.type("Node", "@Received(fulfilledByDependencyNamed: \"middleBuilder\", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((Instantiator<Node>) -> Node)? = nil
			        ) {
			            self.nodeBuilder = nodeBuilder
			        }

			        let nodeBuilder: ((Instantiator<Node>) -> Node)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_nodeBuilder() -> Node {
			            let middleBuilder: Instantiator<Node> = Instantiator<Node>(__safeDI_nodeBuilder)
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 7)
			            let childBuilder: Instantiator<Node> = middleBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.nodeBuilder { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 7)
			        let middleBuilder: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        return Screen(middleBuilder: middleBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNoPromotedMemberOnlyItsLoopReads_whenPromotedMembersTreeReceivesBuilderMockedTypeInstantiates() async throws {
		// `X`, which `B` requires, receives `bBuilder` back, so `xBuilder` is promoted onto a loop with `A`'s own `bBuilder`,
		// and only `__safeDI_bBuilder`'s rebinding reads it.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let xBuilder: Instantiator<X>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let xBuilder: Instantiator<X>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("X", "@Received let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<X>) -> B)? = nil,
			            xBuilder: ((Instantiator<B>) -> X)? = nil
			        ) {
			            self.bBuilder = bBuilder
			            self.xBuilder = xBuilder
			        }

			        let bBuilder: ((Instantiator<X>) -> B)?
			        let xBuilder: ((Instantiator<B>) -> X)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder() -> B {
			            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(xBuilder) } else { B(xBuilder: xBuilder) }
			        }
			        func __safeDI_xBuilder() -> X {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.xBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNoPromotedMemberOnlyItsLoopReads_whenPromotedMembersTreeReceivesBuilderMockedTypeInstantiatesThroughRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let xBuilder: Instantiator<X>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received(fulfilledByDependencyNamed: \"xBuilder\", ofType: Instantiator<X>.self) let xAlias: Instantiator<X>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("X", "@Received let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<X>) -> B)? = nil,
			            xBuilder: ((Instantiator<B>) -> X)? = nil
			        ) {
			            self.bBuilder = bBuilder
			            self.xBuilder = xBuilder
			        }

			        let bBuilder: ((Instantiator<X>) -> B)?
			        let xBuilder: ((Instantiator<B>) -> X)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder() -> B {
			            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 7)
			            let xAlias: Instantiator<X> = xBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(xAlias) } else { B(xAlias: xAlias) }
			        }
			        func __safeDI_xBuilder() -> X {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.xBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNoPromotedMemberOnlyItsLoopReads_whenPromotedMembersTreeReceivesSendableBuilderMockedTypeInstantiates() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let xBuilder: SendableInstantiator<X>", "@Instantiated let bBuilder: SendableInstantiator<B>"),
			Self.type("B", "@Received let xBuilder: SendableInstantiator<X>", conformances: ", Sendable"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let bBuilder: SendableInstantiator<B>", conformances: ", Sendable"),
			Self.type("X", "@Received let bBuilder: SendableInstantiator<B>", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: (@Sendable (SendableInstantiator<X>) -> B)? = nil,
			            xBuilder: (@Sendable (SendableInstantiator<B>) -> X)? = nil
			        ) {
			            self.bBuilder = bBuilder
			            self.xBuilder = xBuilder
			        }

			        let bBuilder: (@Sendable (SendableInstantiator<X>) -> B)?
			        let xBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let __safeDI_bBuilder__safeDIBuilder = safeDIOverrides.bBuilder
			        let __safeDI_xBuilder__safeDIBuilder = safeDIOverrides.xBuilder
			        @Sendable func __safeDI_bBuilder() -> B {
			            let xBuilder = SendableInstantiator<X>(__safeDI_xBuilder)
			            return if let safeDIBuilder = __safeDI_bBuilder__safeDIBuilder { safeDIBuilder(xBuilder) } else { B(xBuilder: xBuilder) }
			        }
			        @Sendable func __safeDI_xBuilder() -> X {
			            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = __safeDI_xBuilder__safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsPromotedMember_whenMockedTypesValueChildReceivesItBesideBuilderItsLoopReads() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let xBuilder: Instantiator<X>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let xBuilder: Instantiator<X>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let c: C"),
			Self.type("C", "@Received let xBuilder: Instantiator<X>"),
			Self.type("X", "@Received let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<X>) -> B)? = nil,
			            xBuilder: ((Instantiator<B>) -> X)? = nil,
			            c: ((Instantiator<X>) -> C)? = nil
			        ) {
			            self.bBuilder = bBuilder
			            self.xBuilder = xBuilder
			            self.c = c
			        }

			        let bBuilder: ((Instantiator<X>) -> B)?
			        let xBuilder: ((Instantiator<B>) -> X)?
			        let c: ((Instantiator<X>) -> C)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder() -> B {
			            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(xBuilder) } else { B(xBuilder: xBuilder) }
			        }
			        func __safeDI_xBuilder() -> X {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.xBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			        let c = if let safeDIBuilder = safeDIOverrides.c { safeDIBuilder(xBuilder) } else { C(xBuilder: xBuilder) }
			        return A(bBuilder: bBuilder, c: c)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – Receives only if available

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesDefaultNilEntry_whenTypeInMockedTypesTreeReceivesItsBuilderOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B"),
			Self.type("B", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            b: ((Instantiator<A>?) -> B)? = nil,
			            aBuilder: Instantiator<A>? = nil
			        ) {
			            self.b = b
			            self.aBuilder = aBuilder
			        }

			        let b: ((Instantiator<A>?) -> B)?
			        let aBuilder: Instantiator<A>?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let aBuilder: Instantiator<A>? = safeDIOverrides.aBuilder
			        let b = if let safeDIBuilder = safeDIOverrides.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        return A(b: b)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesEachPromotedBuilderTheOther_whenPromotedBuildersReceiveEachOtherOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(generateMock: true)", "@Received let aBuilder: Instantiator<A>", "@Received let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received(onlyIfAvailable: true) let bBuilder: Instantiator<B>?"),
			Self.type("B", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: ((Instantiator<B>?) -> A)? = nil,
			            bBuilder: ((Instantiator<A>?) -> B)? = nil
			        ) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			        }

			        let aBuilder: ((Instantiator<B>?) -> A)?
			        let bBuilder: ((Instantiator<A>?) -> B)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Root(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – A label promoted in two forms

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsTheFormItsTypeReads_whenMockPromotesLabelInTwoFormsOnOneLoop() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(generateMock: true)", "@Instantiated let childBuilder: Instantiator<Child>"),
			Self.type("Child", "@Received let peerBuilder: Instantiator<Peer>"),
			Self.type("Peer", "@Received let childBuilder: Instantiator<Child>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            childBuilder_Instantiator__Child: ((Instantiator<Peer>) -> Child)? = nil,
			            peerBuilder: ((Instantiator<Child>?) -> Peer)? = nil,
			            childBuilder_Instantiator__Child_Optional: ((Instantiator<Peer>) -> Child)? = nil
			        ) {
			            self.childBuilder_Instantiator__Child = childBuilder_Instantiator__Child
			            self.peerBuilder = peerBuilder
			            self.childBuilder_Instantiator__Child_Optional = childBuilder_Instantiator__Child_Optional
			        }

			        let childBuilder_Instantiator__Child: ((Instantiator<Peer>) -> Child)?
			        let peerBuilder: ((Instantiator<Child>?) -> Peer)?
			        let childBuilder_Instantiator__Child_Optional: ((Instantiator<Peer>) -> Child)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_childBuilder_Instantiator__Child() -> Child {
			            let peerBuilder = Instantiator<Peer>(__safeDI_peerBuilder)
			            return if let safeDIBuilder = safeDIOverrides.childBuilder_Instantiator__Child { safeDIBuilder(peerBuilder) } else { Child(peerBuilder: peerBuilder) }
			        }
			        func __safeDI_peerBuilder() -> Peer {
			            let childBuilder_Instantiator__Child_Optional = Instantiator<Child>(__safeDI_childBuilder_Instantiator__Child_Optional)
			            let childBuilder: Instantiator<Child>? = childBuilder_Instantiator__Child_Optional
			            return if let safeDIBuilder = safeDIOverrides.peerBuilder { safeDIBuilder(childBuilder) } else { Peer(childBuilder: childBuilder) }
			        }
			        func __safeDI_childBuilder_Instantiator__Child_Optional() -> Child {
			            let peerBuilder = Instantiator<Peer>(__safeDI_peerBuilder)
			            return if let safeDIBuilder = safeDIOverrides.childBuilder_Instantiator__Child_Optional { safeDIBuilder(peerBuilder) } else { Child(peerBuilder: peerBuilder) }
			        }
			        let childBuilder_Instantiator__Child = Instantiator<Child>(__safeDI_childBuilder_Instantiator__Child)
			        return Root(childBuilder: childBuilder_Instantiator__Child)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsTheFormEachLabelIsRead_whenMockPromotesSixLabelsInTwoFormsOnOneLoop() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.labelsPromotedInTwoForms(count: 6), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == ["Root+SafeDIMock.swift": generatedFileHeader + Self.expectedMockOfLabelsPromotedInTwoForms(count: 6)], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – Builders whose functions take cycle parameters

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_declaresReceivedFunction_whenLoopMemberFunctionTakesCycleParameter() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIMockConfiguration = .init()
			        ) {
			            self.session = session
			            self.screenBuilder = screenBuilder
			        }

			        let session: (() -> Session)?
			        let screenBuilder: Screen.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let screenBuilder = Instantiator<Screen> {
			                __safeDI_screenBuilder(session: session)
			            }
			            func __safeDI_stepBuilder() -> Step {
			                let session = if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder.detail { safeDIBuilder(screenBuilder) } else { Detail(screenBuilder: screenBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(session, stepBuilder, detail) } else { Screen(session: session, stepBuilder: stepBuilder, detail: detail) }
			        }
			        func __safeDI_screenBuilder_received() -> Screen {
			            __safeDI_screenBuilder(session: session)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			        return Root(session: session, screenBuilder: screenBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_wrapsLoopMemberCycleArgumentInsideReceivedFunction_whenCycleParameterIsMemberOfSameLoop() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Other", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Detail", "@Received let otherBuilder: Instantiator<Other>"),
			Self.type("Screen", "@Instantiated let detail: Detail", "@Instantiated let stepBuilder: Instantiator<Step>"),
			Self.type("Step", "@Instantiated let otherBuilder: Instantiator<Other>", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let otherBuilder: Instantiator<Other>", "@Instantiated let screenBuilder: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            otherBuilder: ((Instantiator<Screen>) -> Other)? = nil,
			            screenBuilder: Screen.SafeDIMockConfiguration = .init()
			        ) {
			            self.otherBuilder = otherBuilder
			            self.screenBuilder = screenBuilder
			        }

			        let otherBuilder: ((Instantiator<Screen>) -> Other)?
			        let screenBuilder: Screen.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_otherBuilder() -> Other {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			            return if let safeDIBuilder = safeDIOverrides.otherBuilder { safeDIBuilder(screenBuilder) } else { Other(screenBuilder: screenBuilder) }
			        }
			        func __safeDI_screenBuilder(otherBuilder: Instantiator<Other>) -> Screen {
			            let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder.detail { safeDIBuilder(otherBuilder) } else { Detail(otherBuilder: otherBuilder) }
			            func __safeDI_stepBuilder() -> Step {
			                func __safeDI_otherBuilder() -> Other {
			                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			                    return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.otherBuilder { safeDIBuilder(screenBuilder) } else { Other(screenBuilder: screenBuilder) }
			                }
			                func __safeDI_screenBuilder_received() -> Screen {
			                    let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			                    return __safeDI_screenBuilder(otherBuilder: otherBuilder)
			                }
			                let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(otherBuilder, screenBuilder) } else { Step(otherBuilder: otherBuilder, screenBuilder: screenBuilder) }
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(detail, stepBuilder) } else { Screen(detail: detail, stepBuilder: stepBuilder) }
			        }
			        func __safeDI_screenBuilder_received() -> Screen {
			            let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			            return __safeDI_screenBuilder(otherBuilder: otherBuilder)
			        }
			        let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			        return Root(otherBuilder: otherBuilder, screenBuilder: screenBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesReceivedFunctionApart_whenSiblingsBuilderFunctionHasItsName() async throws {
		// `Root` declares `screenBuilder_received`, whose builder function is `__safeDI_screenBuilder_received`, so the
		// function every wrapper of `screenBuilder` hands takes another name, as in production.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			Self.type("Other"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let screenBuilder_received: Instantiator<Other>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIMockConfiguration = .init(),
			            screenBuilder_received: (() -> Other)? = nil
			        ) {
			            self.session = session
			            self.screenBuilder = screenBuilder
			            self.screenBuilder_received = screenBuilder_received
			        }

			        let session: (() -> Session)?
			        let screenBuilder: Screen.SafeDIMockConfiguration
			        let screenBuilder_received: (() -> Other)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let screenBuilder = Instantiator<Screen> {
			                __safeDI_screenBuilder(session: session)
			            }
			            func __safeDI_stepBuilder() -> Step {
			                let session = if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder.detail { safeDIBuilder(screenBuilder) } else { Detail(screenBuilder: screenBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(session, stepBuilder, detail) } else { Screen(session: session, stepBuilder: stepBuilder, detail: detail) }
			        }
			        func __safeDI_screenBuilder_received_() -> Screen {
			            __safeDI_screenBuilder(session: session)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			        func __safeDI_screenBuilder_received() -> Other {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder_received { safeDIBuilder() } else { Other() }
			        }
			        let screenBuilder_received = Instantiator<Other>(__safeDI_screenBuilder_received)
			        return Root(session: session, screenBuilder: screenBuilder, screenBuilder_received: screenBuilder_received)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesReceivedFunctionApart_whenCycleClosingNodeBeneathRefersToEnclosingFunctionOfItsName() async throws {
		// `Root` declares `screenBuilder_received`, whose builder function `__safeDI_screenBuilder_received` encloses `Flow`'s level, and `Tail`, beneath that level, closes a cycle on it by name, so the function every wrapper of `screenBuilder` hands takes another name, as in production.
		let fixture = [
			Self.type("Session"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Tail", "@Instantiated let screenBuilder_received: Instantiator<Flow>"),
			Self.type("Flow", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let tail: Tail"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let screenBuilder_received: Instantiator<Flow>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            screenBuilder_received: Flow.SafeDIMockConfiguration = .init()
			        ) {
			            self.screenBuilder_received = screenBuilder_received
			        }

			        let screenBuilder_received: Flow.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_screenBuilder_received() -> Flow {
			            let session = if let safeDIBuilder = safeDIOverrides.screenBuilder_received.session { safeDIBuilder() } else { Session() }
			            func __safeDI_screenBuilder(session: Session) -> Screen {
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                func __safeDI_stepBuilder() -> Step {
			                    let session = if let safeDIBuilder = safeDIOverrides.screenBuilder_received.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
			                    let screenBuilder = Instantiator<Screen> {
			                        __safeDI_screenBuilder(session: session)
			                    }
			                    return if let safeDIBuilder = safeDIOverrides.screenBuilder_received.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
			                }
			                let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			                let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder_received.screenBuilder.detail { safeDIBuilder(screenBuilder) } else { Detail(screenBuilder: screenBuilder) }
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder_received.screenBuilder.safeDIBuilder { safeDIBuilder(session, stepBuilder, detail) } else { Screen(session: session, stepBuilder: stepBuilder, detail: detail) }
			            }
			            func __safeDI_screenBuilder_received_() -> Screen {
			                __safeDI_screenBuilder(session: session)
			            }
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			            func __safeDI_tail() -> Tail {
			                let screenBuilder_received = Instantiator<Flow>(__safeDI_screenBuilder_received)
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder_received.tail.safeDIBuilder { safeDIBuilder(screenBuilder_received) } else { Tail(screenBuilder_received: screenBuilder_received) }
			            }
			            let tail: Tail = __safeDI_tail()
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder_received.safeDIBuilder { safeDIBuilder(session, screenBuilder, tail) } else { Flow(session: session, screenBuilder: screenBuilder, tail: tail) }
			        }
			        let screenBuilder_received = Instantiator<Flow>(__safeDI_screenBuilder_received)
			        return Root(screenBuilder_received: screenBuilder_received)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesReceivedFunctionApart_whenAnotherMembersLevelDeclaresBuilderFunctionOfItsName() async throws {
		// `Peer`, on the loop with `screenBuilder`, declares `screenBuilder_received`, whose builder function in `__safeDI_peerBuilder`'s body would hide the function `Peer`'s rebinding of `screenBuilder` hands, so that function takes another name, as in production.
		let fixture = [
			Self.type("Session"),
			Self.type("Other"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let peerBuilder: Instantiator<Peer>"),
			Self.type("Peer", "@Received let screenBuilder: Instantiator<Screen>", "@Instantiated let screenBuilder_received: Instantiator<Other>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let peerBuilder: Instantiator<Peer>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIMockConfiguration = .init(),
			            peerBuilder: Peer.SafeDIMockConfiguration = .init()
			        ) {
			            self.session = session
			            self.screenBuilder = screenBuilder
			            self.peerBuilder = peerBuilder
			        }

			        let session: (() -> Session)?
			        let screenBuilder: Screen.SafeDIMockConfiguration
			        let peerBuilder: Peer.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let peerBuilder = Instantiator<Peer>(__safeDI_peerBuilder)
			            func __safeDI_stepBuilder() -> Step {
			                let session = if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder.detail { safeDIBuilder(peerBuilder) } else { Detail(peerBuilder: peerBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(session, stepBuilder, detail) } else { Screen(session: session, stepBuilder: stepBuilder, detail: detail) }
			        }
			        func __safeDI_screenBuilder_received_() -> Screen {
			            __safeDI_screenBuilder(session: session)
			        }
			        func __safeDI_peerBuilder() -> Peer {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			            func __safeDI_screenBuilder_received() -> Other {
			                if let safeDIBuilder = safeDIOverrides.peerBuilder.screenBuilder_received { safeDIBuilder() } else { Other() }
			            }
			            let screenBuilder_received = Instantiator<Other>(__safeDI_screenBuilder_received)
			            return if let safeDIBuilder = safeDIOverrides.peerBuilder.safeDIBuilder { safeDIBuilder(screenBuilder, screenBuilder_received) } else { Peer(screenBuilder: screenBuilder, screenBuilder_received: screenBuilder_received) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			        let peerBuilder = Instantiator<Peer>(__safeDI_peerBuilder)
			        return Root(session: session, screenBuilder: screenBuilder, peerBuilder: peerBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsReceivedFunctionAsRawIdentifier_whenLoopMembersLabelIsRawIdentifier() async throws {
		let fixture = [
			Self.type("Session"),
			Self.type("Screen", "@Received let `c d`: Session", "@Instantiated let `a b`: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let `some thing`: Instantiator<Screen>", "@Received let peer: Instantiator<Peer>"),
			Self.type("Peer", "@Received let `some thing`: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let `c d`: Session", "@Instantiated let `some thing`: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let `c d`: Session", "@Instantiated let `some thing`: Instantiator<Screen>", "@Instantiated let peer: Instantiator<Peer>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            `c d`: (() -> Session)? = nil,
			            `some thing`: Screen.SafeDIMockConfiguration = .init(),
			            peer: ((Instantiator<Screen>) -> Peer)? = nil
			        ) {
			            self.`c d` = `c d`
			            self.`some thing` = `some thing`
			            self.peer = peer
			        }

			        let `c d`: (() -> Session)?
			        let `some thing`: Screen.SafeDIMockConfiguration
			        let peer: ((Instantiator<Screen>) -> Peer)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let `c d` = if let safeDIBuilder = safeDIOverrides.`c d` { safeDIBuilder() } else { Session() }
			        func `__safeDI_some thing`(`c d`: Session) -> Screen {
			            let `some thing` = Instantiator<Screen> {
			                `__safeDI_some thing`(`c d`: `c d`)
			            }
			            let peer = Instantiator<Peer>(__safeDI_peer)
			            func `__safeDI_a b`() -> Step {
			                let `c d` = if let safeDIBuilder = safeDIOverrides.`some thing`.`a b`.`c d` { safeDIBuilder() } else { Session() }
			                let `some thing` = Instantiator<Screen> {
			                    `__safeDI_some thing`(`c d`: `c d`)
			                }
			                return if let safeDIBuilder = safeDIOverrides.`some thing`.`a b`.safeDIBuilder { safeDIBuilder(`c d`, `some thing`) } else { Step(`c d`: `c d`, `some thing`: `some thing`) }
			            }
			            let `a b` = Instantiator<Step>(`__safeDI_a b`)
			            let detail = if let safeDIBuilder = safeDIOverrides.`some thing`.detail { safeDIBuilder(`some thing`, peer) } else { Detail(`some thing`: `some thing`, peer: peer) }
			            return if let safeDIBuilder = safeDIOverrides.`some thing`.safeDIBuilder { safeDIBuilder(`c d`, `a b`, detail) } else { Screen(`c d`: `c d`, `a b`: `a b`, detail: detail) }
			        }
			        func `__safeDI_some thing_received`() -> Screen {
			            `__safeDI_some thing`(`c d`: `c d`)
			        }
			        func __safeDI_peer() -> Peer {
			            let `some thing` = Instantiator<Screen>(`__safeDI_some thing_received`)
			            return if let safeDIBuilder = safeDIOverrides.peer { safeDIBuilder(`some thing`) } else { Peer(`some thing`: `some thing`) }
			        }
			        let `some thing` = Instantiator<Screen>(`__safeDI_some thing_received`)
			        let peer = Instantiator<Peer>(__safeDI_peer)
			        return Root(`c d`: `c d`, `some thing`: `some thing`, peer: peer)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	// MARK: Tests – Public mocks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuildersFromCallersValue_whenPublicMocksPromotedBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("A", attributes: "(generateMock: .public)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            bBuilder: ((Instantiator<A>) -> B)? = nil,
			            aBuilder: ((Instantiator<B>) -> A)? = nil
			        ) {
			            self.bBuilder = bBuilder
			            self.aBuilder = aBuilder
			        }

			        public let bBuilder: ((Instantiator<A>) -> B)?
			        public let aBuilder: ((Instantiator<B>) -> A)?
			    }

			    public static func mock(
			        aBuilder: Instantiator<A>? = nil,
			        bBuilder: Instantiator<B>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = if let aBuilder { aBuilder } else { Instantiator<A>(__safeDI_aBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			        return A(bBuilder: bBuilder)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_DC87377F9DD950EC {}
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – Loops a mock reaches beside or beneath the mocked type

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsBuilderInsideItsFunction_whenConstantInsideItsTreeReceivesIt_withRoot() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public struct Root: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<A>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct A: Instantiable {
				    public init(b: B) { self.b = b }
				    @Instantiated let b: B
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Received let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: A.SafeDIMockConfiguration = .init(),
			            b: ((Instantiator<A>) -> B)? = nil
			        ) {
			            self.aBuilder = aBuilder
			            self.b = b
			        }

			        let aBuilder: A.SafeDIMockConfiguration
			        let b: ((Instantiator<A>) -> B)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_aBuilder() -> A {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let b = if let safeDIBuilder = safeDIOverrides.aBuilder.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        let b = if let safeDIBuilder = safeDIOverrides.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        return A(b: b)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: ((Instantiator<A>) -> B)? = nil,
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            self.b = b
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let b: ((Instantiator<A>) -> B)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((B) -> A)?
			    }
			}
			#endif
			""",
			"B+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension B {
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
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_aBuilder() -> A {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let b = if let safeDIBuilder = safeDIOverrides.aBuilder.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        return B(aBuilder: aBuilder)
			    }
			}
			#endif
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
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
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_aBuilder() -> A {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let b = if let safeDIBuilder = safeDIOverrides.aBuilder.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        return Root(aBuilder: aBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsBuilderInsideItsFunction_whenConstantInsideItsTreeReceivesIt_withoutRoot() async throws {
		// The loop of the _withRoot test with no root: `B`'s mock promotes `aBuilder`, whose tree receives it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct A: Instantiable {
				    public init(b: B) { self.b = b }
				    @Instantiated let b: B
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Received let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: A.SafeDIMockConfiguration = .init(),
			            b: ((Instantiator<A>) -> B)? = nil
			        ) {
			            self.aBuilder = aBuilder
			            self.b = b
			        }

			        let aBuilder: A.SafeDIMockConfiguration
			        let b: ((Instantiator<A>) -> B)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_aBuilder() -> A {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let b = if let safeDIBuilder = safeDIOverrides.aBuilder.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        let b = if let safeDIBuilder = safeDIOverrides.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        return A(b: b)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: ((Instantiator<A>) -> B)? = nil,
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            self.b = b
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let b: ((Instantiator<A>) -> B)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((B) -> A)?
			    }
			}
			#endif
			""",
			"B+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension B {
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
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_aBuilder() -> A {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let b = if let safeDIBuilder = safeDIOverrides.aBuilder.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        return B(aBuilder: aBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsEachOtherBuilderInsideEachFunction_whenNonRootMockedTypesBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Parent: Instantiable {
				    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
				        self.aBuilder = aBuilder
				        self.bBuilder = bBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct A: Instantiable {
				    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
				    @Received let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Received let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: ((Instantiator<B>) -> A)? = nil,
			            bBuilder: ((Instantiator<A>) -> B)? = nil
			        ) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			        }

			        let aBuilder: ((Instantiator<B>) -> A)?
			        let bBuilder: ((Instantiator<A>) -> B)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Parent(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsEachOtherBuilderInsideEachFunction_whenBuildersOfPromotedScopeReceiveEachOther() async throws {
		// Only `Top`'s mock reaches `Holder`, by promoting the `holder` that `Top` receives.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Top: Instantiable {
				    public init(holder: Holder) { self.holder = holder }
				    @Received let holder: Holder
				}
				""",
				"""
				@Instantiable
				public struct Holder: Instantiable {
				    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
				        self.aBuilder = aBuilder
				        self.bBuilder = bBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct A: Instantiable {
				    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
				    @Received let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Received let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Top+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Top {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            holder: Holder.SafeDIMockConfiguration = .init()
			        ) {
			            self.holder = holder
			        }

			        let holder: Holder.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Top {
			        func __safeDI_holder() -> Holder {
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return if let safeDIBuilder = safeDIOverrides.holder.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			            }
			            func __safeDI_bBuilder() -> B {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                return if let safeDIBuilder = safeDIOverrides.holder.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.holder.safeDIBuilder { safeDIBuilder(aBuilder, bBuilder) } else { Holder(aBuilder: aBuilder, bBuilder: bBuilder) }
			        }
			        let holder: Holder = __safeDI_holder()
			        return Top(holder: holder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsBuilders_whenSiblingInstantiatorIsReceivedInsideLazyCycleOfEarlierSibling() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Parent: Instantiable {
				    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, qBuilder: Instantiator<Q>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let bBuilder: Instantiator<B>
				    @Instantiated let qBuilder: Instantiator<Q>
				}
				""",
				"""
				@Instantiable
				public struct A: Instantiable {
				    public init(innerBBuilder: Instantiator<B>, qBuilder: Instantiator<Q>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let innerBBuilder: Instantiator<B>
				    @Received let qBuilder: Instantiator<Q>
				}
				""",
				"""
				@Instantiable
				public struct B: Instantiable {
				    public init(innerABuilder: Instantiator<A>) { self.innerABuilder = innerABuilder }
				    @Instantiated let innerABuilder: Instantiator<A>
				}
				""",
				"""
				@Instantiable
				public struct Q: Instantiable {
				    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
				    @Received let bBuilder: Instantiator<B>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init(),
			            qBuilder: ((Instantiator<B>) -> Q)? = nil,
			            aBuilder: A.SafeDIMockConfiguration = .init()
			        ) {
			            self.bBuilder = bBuilder
			            self.qBuilder = qBuilder
			            self.aBuilder = aBuilder
			        }

			        let bBuilder: B.SafeDIMockConfiguration
			        let qBuilder: ((Instantiator<B>) -> Q)?
			        let aBuilder: A.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_bBuilder() -> B {
			            let qBuilder = Instantiator<Q>(__safeDI_qBuilder)
			            func __safeDI_innerABuilder() -> A {
			                func __safeDI_innerBBuilder() -> B {
			                    let innerABuilder = Instantiator<A>(__safeDI_innerABuilder)
			                    return B(innerABuilder: innerABuilder)
			                }
			                let innerBBuilder = Instantiator<B>(__safeDI_innerBBuilder)
			                return A(innerBBuilder: innerBBuilder, qBuilder: qBuilder)
			            }
			            let innerABuilder = Instantiator<A>(__safeDI_innerABuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder.safeDIBuilder { safeDIBuilder(innerABuilder) } else { B(innerABuilder: innerABuilder) }
			        }
			        func __safeDI_qBuilder() -> Q {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.qBuilder { safeDIBuilder(bBuilder) } else { Q(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let qBuilder = Instantiator<Q>(__safeDI_qBuilder)
			        func __safeDI_aBuilder() -> A {
			            func __safeDI_innerBBuilder() -> B {
			                func __safeDI_innerABuilder() -> A {
			                    let innerBBuilder = Instantiator<B>(__safeDI_innerBBuilder)
			                    return A(innerBBuilder: innerBBuilder, qBuilder: qBuilder)
			                }
			                let innerABuilder = Instantiator<A>(__safeDI_innerABuilder)
			                return if let safeDIBuilder = safeDIOverrides.aBuilder.innerBBuilder.safeDIBuilder { safeDIBuilder(innerABuilder) } else { B(innerABuilder: innerABuilder) }
			            }
			            let innerBBuilder = Instantiator<B>(__safeDI_innerBBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(innerBBuilder, qBuilder) } else { A(innerBBuilder: innerBBuilder, qBuilder: qBuilder) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        return Parent(aBuilder: aBuilder, bBuilder: bBuilder, qBuilder: qBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsDisambiguatedBuilder_whenTreeOfTypeReceivedByValueReceivesItsInstantiator_andTypeSortsBeforeInstantiator() async throws {
		// Consumer receives `x: Abc`, and the Inner that Abc instantiates receives `x: Instantiator<Abc>`. The mock
		// builds both forms, under names of their own, and the Abc that the Instantiator builds is passed the wrapper its
		// function makes again of itself.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(consumer: Consumer) { self.consumer = consumer }
				    @Instantiated let consumer: Consumer
				}
				""",
				"""
				@Instantiable
				public struct Consumer: Instantiable {
				    public init(x: Abc) { self.x = x }
				    @Received let x: Abc
				}
				""",
				"""
				@Instantiable
				public struct Abc: Instantiable {
				    public init(inner: Inner) { self.inner = inner }
				    @Instantiated let inner: Inner
				}
				""",
				"""
				@Instantiable
				public struct Inner: Instantiable {
				    public init(x: Instantiator<Abc>) { self.x = x }
				    @Received let x: Instantiator<Abc>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            x_Instantiator__Abc: Abc.SafeDIMockConfiguration = .init(),
			            x_Abc: Abc.SafeDIMockConfiguration = .init(),
			            consumer: ((Abc) -> Consumer)? = nil
			        ) {
			            self.x_Instantiator__Abc = x_Instantiator__Abc
			            self.x_Abc = x_Abc
			            self.consumer = consumer
			        }

			        let x_Instantiator__Abc: Abc.SafeDIMockConfiguration
			        let x_Abc: Abc.SafeDIMockConfiguration
			        let consumer: ((Abc) -> Consumer)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_x_Instantiator__Abc() -> Abc {
			            let x_Instantiator__Abc = Instantiator<Abc>(__safeDI_x_Instantiator__Abc)
			            func __safeDI_inner() -> Inner {
			                let x: Instantiator<Abc> = x_Instantiator__Abc
			                return if let safeDIBuilder = safeDIOverrides.x_Instantiator__Abc.inner { safeDIBuilder(x) } else { Inner(x: x) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.x_Instantiator__Abc.safeDIBuilder { safeDIBuilder(inner) } else { Abc(inner: inner) }
			        }
			        let x_Instantiator__Abc = Instantiator<Abc>(__safeDI_x_Instantiator__Abc)
			        func __safeDI_x_Abc() -> Abc {
			            func __safeDI_inner() -> Inner {
			                let x: Instantiator<Abc> = x_Instantiator__Abc
			                return if let safeDIBuilder = safeDIOverrides.x_Abc.inner { safeDIBuilder(x) } else { Inner(x: x) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.x_Abc.safeDIBuilder { safeDIBuilder(inner) } else { Abc(inner: inner) }
			        }
			        let x_Abc: Abc = __safeDI_x_Abc()
			        func __safeDI_consumer() -> Consumer {
			            let x: Abc = x_Abc
			            return if let safeDIBuilder = safeDIOverrides.consumer { safeDIBuilder(x) } else { Consumer(x: x) }
			        }
			        let consumer: Consumer = __safeDI_consumer()
			        return Root(consumer: consumer)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsDisambiguatedBuilder_whenTreeOfTypeReceivedByValueReceivesItsInstantiator_andTypeSortsAfterInstantiator() async throws {
		// The graph of the test above with `Abc` renamed to `Xyz`, which sorts after `Instantiator<Xyz>`. The mock is
		// the same, with the type renamed.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(consumer: Consumer) { self.consumer = consumer }
				    @Instantiated let consumer: Consumer
				}
				""",
				"""
				@Instantiable
				public struct Consumer: Instantiable {
				    public init(x: Xyz) { self.x = x }
				    @Received let x: Xyz
				}
				""",
				"""
				@Instantiable
				public struct Xyz: Instantiable {
				    public init(inner: Inner) { self.inner = inner }
				    @Instantiated let inner: Inner
				}
				""",
				"""
				@Instantiable
				public struct Inner: Instantiable {
				    public init(x: Instantiator<Xyz>) { self.x = x }
				    @Received let x: Instantiator<Xyz>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            x_Instantiator__Xyz: Xyz.SafeDIMockConfiguration = .init(),
			            x_Xyz: Xyz.SafeDIMockConfiguration = .init(),
			            consumer: ((Xyz) -> Consumer)? = nil
			        ) {
			            self.x_Instantiator__Xyz = x_Instantiator__Xyz
			            self.x_Xyz = x_Xyz
			            self.consumer = consumer
			        }

			        let x_Instantiator__Xyz: Xyz.SafeDIMockConfiguration
			        let x_Xyz: Xyz.SafeDIMockConfiguration
			        let consumer: ((Xyz) -> Consumer)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_x_Instantiator__Xyz() -> Xyz {
			            let x_Instantiator__Xyz = Instantiator<Xyz>(__safeDI_x_Instantiator__Xyz)
			            func __safeDI_inner() -> Inner {
			                let x: Instantiator<Xyz> = x_Instantiator__Xyz
			                return if let safeDIBuilder = safeDIOverrides.x_Instantiator__Xyz.inner { safeDIBuilder(x) } else { Inner(x: x) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.x_Instantiator__Xyz.safeDIBuilder { safeDIBuilder(inner) } else { Xyz(inner: inner) }
			        }
			        let x_Instantiator__Xyz = Instantiator<Xyz>(__safeDI_x_Instantiator__Xyz)
			        func __safeDI_x_Xyz() -> Xyz {
			            func __safeDI_inner() -> Inner {
			                let x: Instantiator<Xyz> = x_Instantiator__Xyz
			                return if let safeDIBuilder = safeDIOverrides.x_Xyz.inner { safeDIBuilder(x) } else { Inner(x: x) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.x_Xyz.safeDIBuilder { safeDIBuilder(inner) } else { Xyz(inner: inner) }
			        }
			        let x_Xyz: Xyz = __safeDI_x_Xyz()
			        func __safeDI_consumer() -> Consumer {
			            let x: Xyz = x_Xyz
			            return if let safeDIBuilder = safeDIOverrides.consumer { safeDIBuilder(x) } else { Consumer(x: x) }
			        }
			        let consumer: Consumer = __safeDI_consumer()
			        return Root(consumer: consumer)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// The time limit only turns a hang into a failure; see
	// `mock_generatesWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesWithinTimeLimit_whenEveryReceivedInstantiatorPathFromEarlierSiblingsEndsInLoopOfInstantiators() async throws {
		// Each layer holds a Left and a Right service that both receive Instantiators of the two
		// services of the next layer, and the last layer's services receive an Instantiator of Ping,
		// which receives one of Pong, which receives one of Ping. Feature's mock promotes every one of
		// those Instantiators, so the number of received paths from any layer to that loop doubles
		// with each layer.
		let layerCount = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["pingBuilder: Instantiator<Ping>"]
				: ["left\(layer + 1)Builder: Instantiator<Left\(layer + 1)>", "right\(layer + 1)Builder: Instantiator<Right\(layer + 1)>"]
			return ["Left\(layer)", "Right\(layer)"].map { type in
				"""
				@Instantiable
				public struct \(type): Instantiable {
				    public init(\(receivedProperties.joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				\(receivedProperties.map { "    @Received let \($0)" }.joined(separator: "\n"))
				}
				"""
			}
		}
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Feature: Instantiable {
				    public init(left0Builder: Instantiator<Left0>, right0Builder: Instantiator<Right0>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let left0Builder: Instantiator<Left0>
				    @Instantiated let right0Builder: Instantiator<Right0>
				}
				""",
				"""
				@Instantiable
				public struct Ping: Instantiable {
				    public init(pongBuilder: Instantiator<Pong>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let pongBuilder: Instantiator<Pong>
				}
				""",
				"""
				@Instantiable
				public struct Pong: Instantiable {
				    public init(pingBuilder: Instantiator<Ping>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let pingBuilder: Instantiator<Ping>
				}
				""",
			] + layerFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
		)
		#expect(output.mockFiles.keys.sorted() == ["Feature+SafeDIMock.swift"])
		#expect(output.dependencyTreeFiles.isEmpty)
	}

	// The time limit only turns a hang into a failure; see
	// `mock_generatesWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesWithinTimeLimit_whenEveryReceivedAliasPathFromEarlierSiblingsEndsInLoopOfInstantiatorsOfLazyCycles() async throws {
		// Each layer holds a Left and a Right service that instantiate Instantiators of each other and
		// receive aliases of the Instantiators of the two services of the next layer. The last layer's
		// services receive an alias of Ping's Instantiator, and Ping and Pong receive aliases of each other's.
		// Feature declares the aliases of the last layer first.
		let layerCount = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["pingAlias: Instantiator<Ping>"]
				: ["left\(layer + 1)Alias: Instantiator<Left\(layer + 1)>", "right\(layer + 1)Alias: Instantiator<Right\(layer + 1)>"]
			return [("Left\(layer)", "Right\(layer)"), ("Right\(layer)", "Left\(layer)")].map { type, otherType in
				let instantiatedProperty = "inner\(otherType)Builder: Instantiator<\(otherType)>"
				return """
				@Instantiable
				public struct \(type): Instantiable {
				    public init(\(([instantiatedProperty] + receivedProperties).joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let \(instantiatedProperty)
				\(receivedProperties.map { "    @Received let \($0)" }.joined(separator: "\n"))
				}
				"""
			}
		}
		func alias(_ label: String, of fulfillingLabel: String, type: String) -> (property: String, declaration: String) {
			("\(label): \(type)", "@Received(fulfilledByDependencyNamed: \"\(fulfillingLabel)\", ofType: \(type).self) let \(label): \(type)")
		}
		let featureBuilders = (0..<layerCount).flatMap { ["left\($0)Builder: Instantiator<Left\($0)>", "right\($0)Builder: Instantiator<Right\($0)>"] } + ["pingBuilder: Instantiator<Ping>", "pongBuilder: Instantiator<Pong>"]
		let featureAliases = (0..<layerCount).reversed().flatMap { layer in
			["Left\(layer)", "Right\(layer)"].map { type in
				let label = type.prefix(1).lowercased() + type.dropFirst()
				return alias("\(label)Alias", of: "\(label)Builder", type: "Instantiator<\(type)>")
			}
		}
			+ [
				alias("pingAlias", of: "pingBuilder", type: "Instantiator<Ping>"),
				alias("pongAlias", of: "pongBuilder", type: "Instantiator<Pong>"),
			]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Feature: Instantiable {
				    public init(\((featureBuilders + featureAliases.map(\.property)).joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				\(featureBuilders.map { "    @Instantiated let \($0)" }.joined(separator: "\n"))
				\(featureAliases.map { "    \($0.declaration)" }.joined(separator: "\n"))
				}
				""",
				"""
				@Instantiable
				public struct Ping: Instantiable {
				    public init(pongAlias: Instantiator<Pong>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let pongAlias: Instantiator<Pong>
				}
				""",
				"""
				@Instantiable
				public struct Pong: Instantiable {
				    public init(pingAlias: Instantiator<Ping>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let pingAlias: Instantiator<Ping>
				}
				""",
			] + layerFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
		)
		#expect(output.mockFiles.keys.sorted() == ["Feature+SafeDIMock.swift"])
		#expect(output.dependencyTreeFiles.isEmpty)
	}

	// MARK: Tests – Renames of a builder that builds the type renaming it

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilderForTypesOwnRename_whenMockedTypeRenamesBuilderThatBuildsIt() async throws {
		// The mock promotes `nodeBuilder` to build Node, and the Node it builds aliases `nodeBuilder`
		// itself, so `__safeDI_nodeBuilder` wraps itself again for the alias.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Node: Instantiable {
				    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((Instantiator<Node>) -> Node)? = nil
			        ) {
			            self.nodeBuilder = nodeBuilder
			        }

			        let nodeBuilder: ((Instantiator<Node>) -> Node)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        func __safeDI_nodeBuilder() -> Node {
			            let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			            let childBuilder: Instantiator<Node> = nodeBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.nodeBuilder { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			        #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			        let childBuilder: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        return Node(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedSendableBuilderForTypesOwnRename_whenMockedTypeRenamesSendableBuilderThatBuildsIt() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Node: Instantiable, Sendable {
				    public init(childBuilder: SendableInstantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: SendableInstantiator<Node>.self) let childBuilder: SendableInstantiator<Node>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: (@Sendable (SendableInstantiator<Node>) -> Node)? = nil
			        ) {
			            self.nodeBuilder = nodeBuilder
			        }

			        let nodeBuilder: (@Sendable (SendableInstantiator<Node>) -> Node)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        let __safeDI_nodeBuilder__safeDIBuilder = safeDIOverrides.nodeBuilder
			        @Sendable func __safeDI_nodeBuilder() -> Node {
			            let nodeBuilder = SendableInstantiator<Node>(__safeDI_nodeBuilder)
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			            let childBuilder: SendableInstantiator<Node> = nodeBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_nodeBuilder__safeDIBuilder { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = SendableInstantiator<Node>(__safeDI_nodeBuilder)
			        #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			        let childBuilder: SendableInstantiator<Node> = nodeBuilder
			        #sourceLocation()
			        return Node(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_erasesBuilderMadeAgain_whenMockedTypeRenamesBuilderThatBuildsItErasingIt() async throws {
		// Holder's erasure lets the mock build `nodeBuilder: ErasedInstantiator<(), AnyNode>` from Node,
		// and the Node it builds aliases that instantiator, erased to another wrapper, which wraps the
		// instantiator `__safeDI_nodeBuilder` makes again of itself.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class AnyNode {
				    public init(_ node: Node) { self.node = node }
				    let node: Node
				}
				public struct AnyNodeFactory {
				    public init(_ builder: ErasedInstantiator<(), AnyNode>) { self.builder = builder }
				    let builder: ErasedInstantiator<(), AnyNode>
				}
				@Instantiable
				public final class Holder: Instantiable {
				    public init(nodeBuilder: ErasedInstantiator<(), AnyNode>) { self.nodeBuilder = nodeBuilder }
				    @Instantiated(fulfilledByType: "Node", erasedToConcreteExistential: true) let nodeBuilder: ErasedInstantiator<(), AnyNode>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Node: Instantiable {
				    public init(childBuilder: AnyNodeFactory) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: ErasedInstantiator<(), AnyNode>.self, erasedToConcreteExistential: true) let childBuilder: AnyNodeFactory
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((AnyNodeFactory) -> AnyNode)? = nil
			        ) {
			            self.nodeBuilder = nodeBuilder
			        }

			        let nodeBuilder: ((AnyNodeFactory) -> AnyNode)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        func __safeDI_nodeBuilder() -> AnyNode {
			            let nodeBuilder = ErasedInstantiator<(), AnyNode>(__safeDI_nodeBuilder)
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			            let childBuilder: AnyNodeFactory = AnyNodeFactory(nodeBuilder)
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.nodeBuilder { safeDIBuilder(childBuilder) } else { AnyNode(Node(childBuilder: childBuilder)) }
			        }
			        let nodeBuilder = ErasedInstantiator<(), AnyNode>(__safeDI_nodeBuilder)
			        #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			        let childBuilder: AnyNodeFactory = AnyNodeFactory(nodeBuilder)
			        #sourceLocation()
			        return Node(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilder_whenChildRenamesAgainMockedTypesRenameOfBuilderThatBuildsIt() async throws {
		// Node renames `nodeBuilder` to `middleBuilder`, and its child renames `middleBuilder` to
		// `childBuilder`. The Node that the promoted `nodeBuilder` builds renames the wrapper its
		// function makes again of itself.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Node: Instantiable {
				    public init(middleBuilder: Instantiator<Node>, child: Child) { self.middleBuilder = middleBuilder; self.child = child }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let middleBuilder: Instantiator<Node>
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "middleBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: Node.SafeDIMockConfiguration = .init(),
			            child: ((Instantiator<Node>) -> Child)? = nil
			        ) {
			            self.nodeBuilder = nodeBuilder
			            self.child = child
			        }

			        let nodeBuilder: Node.SafeDIMockConfiguration
			        let child: ((Instantiator<Node>) -> Child)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        func __safeDI_nodeBuilder() -> Node {
			            let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			            let middleBuilder: Instantiator<Node> = nodeBuilder
			            #sourceLocation()
			            func __safeDI_child() -> Child {
			                #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
			                let childBuilder: Instantiator<Node> = middleBuilder
			                #sourceLocation()
			                return if let safeDIBuilder = safeDIOverrides.nodeBuilder.child { safeDIBuilder(childBuilder) } else { Child(childBuilder: childBuilder) }
			            }
			            let child: Child = __safeDI_child()
			            return if let safeDIBuilder = safeDIOverrides.nodeBuilder.safeDIBuilder { safeDIBuilder(middleBuilder, child) } else { Node(middleBuilder: middleBuilder, child: child) }
			        }
			        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			        #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			        let middleBuilder: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        func __safeDI_child() -> Child {
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
			            let childBuilder: Instantiator<Node> = middleBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(childBuilder) } else { Child(childBuilder: childBuilder) }
			        }
			        let child: Child = __safeDI_child()
			        return Node(middleBuilder: middleBuilder, child: child)
			    }
			}
			#endif

			#if DEBUG
			extension Node {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            child: ((Instantiator<Node>) -> Child)? = nil,
			            _ safeDIBuilder: ((Instantiator<Node>, Child) -> Node)? = nil
			        ) {
			            self.child = child
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let child: ((Instantiator<Node>) -> Child)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Instantiator<Node>, Child) -> Node)?
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilder_whenRenameInsideItsTreeReceivesIt() async throws {
		// Screen receives `nodeBuilder`, which the mock promotes. Child, built inside the Node it builds,
		// aliases `nodeBuilder`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(nodeBuilder: Instantiator<Node>) { self.nodeBuilder = nodeBuilder }
				    @Received let nodeBuilder: Instantiator<Node>
				}
				""",
				"""
				@Instantiable
				public final class Node: Instantiable {
				    public init(child: Child) { self.child = child }
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
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
			            nodeBuilder: Node.SafeDIMockConfiguration = .init()
			        ) {
			            self.nodeBuilder = nodeBuilder
			        }

			        let nodeBuilder: Node.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_nodeBuilder() -> Node {
			            let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			            func __safeDI_child() -> Child {
			                #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
			                let childBuilder: Instantiator<Node> = nodeBuilder
			                #sourceLocation()
			                return if let safeDIBuilder = safeDIOverrides.nodeBuilder.child { safeDIBuilder(childBuilder) } else { Child(childBuilder: childBuilder) }
			            }
			            let child: Child = __safeDI_child()
			            return if let safeDIBuilder = safeDIOverrides.nodeBuilder.safeDIBuilder { safeDIBuilder(child) } else { Node(child: child) }
			        }
			        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			        return Screen(nodeBuilder: nodeBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilder_whenTypeListedInAdditionalMocksToGenerateRenamesBuilderThatBuildsIt() async throws {
		// Node is defined in a dependent module without generateMock: true.
		let dependentModuleOutput = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Node: Instantiable {
				    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
				}
				""",
			],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "DependentModule", "--package-name", "Example"],
		)
		let dependentModuleFixtures = dependentModuleOutput.fixtures

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#SafeDIConfiguration(
				    additionalMocksToGenerate: [
				        "Node",
				    ]
				)
				""",
			],
			dependentModuleInfoPaths: [dependentModuleOutput.writtenModuleInfoOutputPath],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The verifier compiles one module, and `Node` is declared in another.
			skipCompileVerification: true,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(DependentModule)
			import DependentModule
			#endif

			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((Instantiator<Node>) -> Node)? = nil
			        ) {
			            self.nodeBuilder = nodeBuilder
			        }

			        let nodeBuilder: ((Instantiator<Node>) -> Node)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        func __safeDI_nodeBuilder() -> Node {
			            let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			            #sourceLocation(file: "\(dependentModuleFixtures["Node.swift"])", line: 4)
			            let childBuilder: Instantiator<Node> = nodeBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.nodeBuilder { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			        #sourceLocation(file: "\(dependentModuleFixtures["Node.swift"])", line: 4)
			        let childBuilder: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        return Node(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsMockedTypesRenameUnderItsOwnBindingName_whenRenameOnLoopSharesLabelWithPromotedDependency() async throws {
		// `Screen` renames `nodeBuilder` as `middleBuilder`, which `Node` renames again, so the rename is on the loop of
		// `nodeBuilder`. `Other` requires `middleBuilder: Tool`, which the mock promotes beside the rename, so the mock binds
		// the rename under a name of its own, and `__safeDI_nodeBuilder` wraps it again under that name.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Screen", attributes: "(generateMock: true)", "@Received(fulfilledByDependencyNamed: \"nodeBuilder\", ofType: Instantiator<Node>.self) let middleBuilder: Instantiator<Node>", "@Received let other: Other"),
			Self.type("Node", "@Received(fulfilledByDependencyNamed: \"middleBuilder\", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>"),
			Self.type("Other", "@Received let middleBuilder: Tool"),
			Self.type("Tool"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((Instantiator<Node>) -> Node)? = nil,
			            middleBuilder: (() -> Tool)? = nil,
			            other: ((Tool) -> Other)? = nil
			        ) {
			            self.nodeBuilder = nodeBuilder
			            self.middleBuilder = middleBuilder
			            self.other = other
			        }

			        let nodeBuilder: ((Instantiator<Node>) -> Node)?
			        let middleBuilder: (() -> Tool)?
			        let other: ((Tool) -> Other)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_nodeBuilder() -> Node {
			            let middleBuilder_Instantiator__Node: Instantiator<Node> = Instantiator<Node>(__safeDI_nodeBuilder)
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 7)
			            let childBuilder: Instantiator<Node> = middleBuilder_Instantiator__Node
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.nodeBuilder { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let middleBuilder_Instantiator__Node: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        let middleBuilder = if let safeDIBuilder = safeDIOverrides.middleBuilder { safeDIBuilder() } else { Tool() }
			        let other = if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(middleBuilder) } else { Other(middleBuilder: middleBuilder) }
			        return Screen(middleBuilder: middleBuilder_Instantiator__Node, other: other)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – Receives through a cycle-closing scope

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsNothingInsideClosedOnBuildersTree_whenOnlyCycleClosingCallReceivesBuilderThroughRequiredRename() async throws {
		// The `B` inside `A` calls the enclosing `__safeDI_bBuilder`, which binds its own `aBuilder`: nothing in `A`'s function reads one.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Consumer", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self) let aBuilderAlias: Instantiator<A>"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Consumer+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Consumer {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init()
			        ) {
			            self.bBuilder = bBuilder
			        }

			        let bBuilder: B.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Consumer {
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A> = aBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder, aBuilderAlias) } else { B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Consumer(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsNothingInsideClosedOnBuildersTree_whenOnlyCycleClosingCallReceivesBuilderThroughOnlyIfAvailableRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Consumer", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self, onlyIfAvailable: true) let aBuilderAlias: Instantiator<A>?"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Consumer+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Consumer {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init()
			        ) {
			            self.bBuilder = bBuilder
			        }

			        let bBuilder: B.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Consumer {
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A>? = aBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder, aBuilderAlias) } else { B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Consumer(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsBuilderInsideItsOwnFunction_whenItsTypeReceivesItBesideCycleClosingCallThatReceivesItThroughRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Consumer", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self, onlyIfAvailable: true) let aBuilderAlias: Instantiator<A>?"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Consumer+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Consumer {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init()
			        ) {
			            self.bBuilder = bBuilder
			        }

			        let bBuilder: B.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Consumer {
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder, aBuilder: aBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A>? = aBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder, aBuilderAlias) } else { B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Consumer(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsValueBeforeBuilderThatReceivesIt_whenValuesTreeCallsEnclosingFunctionOfTypeThatRenamesTheBuilder() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Consumer", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let c: C", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self) let aBuilderAlias: Instantiator<A>"),
			Self.type("C", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let c: C"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Consumer+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Consumer {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init()
			        ) {
			            self.bBuilder = bBuilder
			        }

			        let bBuilder: B.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Consumer {
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_c() -> C {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return if let safeDIBuilder = safeDIOverrides.bBuilder.c.safeDIBuilder { safeDIBuilder(bBuilder) } else { C(bBuilder: bBuilder) }
			            }
			            let c: C = __safeDI_c()
			            func __safeDI_aBuilder() -> A {
			                if let safeDIBuilder = safeDIOverrides.bBuilder.aBuilder { safeDIBuilder(c) } else { A(c: c) }
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 11)
			            let aBuilderAlias: Instantiator<A> = aBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.bBuilder.safeDIBuilder { safeDIBuilder(c, aBuilder, aBuilderAlias) } else { B(c: c, aBuilder: aBuilder, aBuilderAlias: aBuilderAlias) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Consumer(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root that declares an erased builder of each of `screenCount` screens, each of which receives the builders of the
	/// screens one, two and five after it, round the ring.
	private static func screensOpeningOneAnother(screenCount: Int) -> [String] {
		var files = ["public protocol Screen {}"]
		for index in 0..<screenCount {
			files.append(type("S\(index)", openedScreenIndices(from: index, screenCount: screenCount).map { "@Received let s\($0)Builder: ErasedInstantiator<(), any Screen>" }, conformances: ", Screen"))
		}
		files.append(type("Root", attributes: "(isRoot: true, generateMock: true)", (0..<screenCount).map { "@Instantiated(fulfilledByType: \"S\($0)\") let s\($0)Builder: ErasedInstantiator<(), any Screen>" }))
		return files
	}

	/// The screens the screen at `index` opens, among `screenCount` (see `screensOpeningOneAnother(screenCount:)`).
	private static func openedScreenIndices(from index: Int, screenCount: Int) -> [Int] {
		[1, 2, 5].map { (index + $0) % screenCount }
	}

	/// The mock of the root of `screensOpeningOneAnother(screenCount:)`, after the generated file's header: for each
	/// screen, an override, a builder function that wraps again the three builders the screen receives, and a binding.
	private static func expectedMockOfScreensOpeningOneAnother(screenCount: Int) -> String {
		let builderType = "ErasedInstantiator<(), any Screen>"
		let overrideType = "((\(builderType), \(builderType), \(builderType)) -> any Screen)?"
		let indices = 0..<screenCount
		var lines = ["#if DEBUG", "extension Root {", "    /// Overrides for the mock dependency tree.", "    struct SafeDIOverrides {", "        init("]
		for index in indices {
			lines.append("            s\(index)Builder: \(overrideType) = nil\(index == screenCount - 1 ? "" : ",")")
		}
		lines.append("        ) {")
		for index in indices {
			lines.append("            self.s\(index)Builder = s\(index)Builder")
		}
		lines.append("        }")
		lines.append("")
		for index in indices {
			lines.append("        let s\(index)Builder: \(overrideType)")
		}
		lines.append("    }")
		lines.append("")
		lines.append("    static func mock(")
		lines.append("        safeDIOverrides: SafeDIOverrides = .init()")
		lines.append("    ) -> Root {")
		for index in indices {
			let openedLabels = openedScreenIndices(from: index, screenCount: screenCount).map { "s\($0)Builder" }
			lines.append("        func __safeDI_s\(index)Builder() -> any Screen {")
			for label in openedLabels {
				lines.append("            let \(label) = \(builderType)(__safeDI_\(label))")
			}
			let arguments = openedLabels.joined(separator: ", ")
			let labeledArguments = openedLabels.map { "\($0): \($0)" }.joined(separator: ", ")
			lines.append("            return if let safeDIBuilder = safeDIOverrides.s\(index)Builder { safeDIBuilder(\(arguments)) } else { S\(index)(\(labeledArguments)) }")
			lines.append("        }")
		}
		for index in indices {
			lines.append("        let s\(index)Builder = \(builderType)(__safeDI_s\(index)Builder)")
		}
		lines.append("        return Root(\(indices.map { "s\($0)Builder: s\($0)Builder" }.joined(separator: ", ")))")
		lines.append("    }")
		lines.append("}")
		lines.append("#endif")
		return lines.joined(separator: "\n")
	}

	/// `Step` declares its own `session` and closes a cycle on `screenBuilder`, so `__safeDI_screenBuilder` takes
	/// `session`, and `Detail` receives `screenBuilder` inside its tree.
	private static let loopMemberTakingCycleParameterFixture = [
		type("Session"),
		type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
		type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
		type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
		type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
	]

	/// A mocked root that instantiates a builder of each of `count` children, each of which receives `peerBuilder`, whose
	/// `Peer` receives every child's builder as an optional: the mock promotes `peerBuilder` and each optional form, so
	/// `__safeDI_peerBuilder` is on a loop with both forms of every child's label.
	private static func labelsPromotedInTwoForms(count: Int) -> [String] {
		var files = [type("Root", attributes: "(generateMock: true)", (0..<count).map { "@Instantiated let c\($0)Builder: Instantiator<C\($0)>" })]
		for index in 0..<count {
			files.append(type("C\(index)", "@Received let peerBuilder: Instantiator<Peer>"))
		}
		files.append(type("Peer", (0..<count).map { "@Received let c\($0)Builder: Instantiator<C\($0)>?" }))
		return files
	}

	/// The mock of the root of `labelsPromotedInTwoForms(count:)`, after the generated file's header: an override for each
	/// child's builder in each form and for `peerBuilder`, whose function wraps again the optional form of every child's
	/// builder, the form `Peer` reads, and a binding of each non-optional form, which the root's construction reads.
	private static func expectedMockOfLabelsPromotedInTwoForms(count: Int) -> String {
		let indices = 0..<count
		let peerOverrideType = "((\(indices.map { "Instantiator<C\($0)>?" }.joined(separator: ", "))) -> Peer)?"
		var fields = [(name: String, type: String)]()
		for index in indices {
			fields.append(("c\(index)Builder_Instantiator__C\(index)", "((Instantiator<Peer>) -> C\(index))?"))
		}
		fields.append(("peerBuilder", peerOverrideType))
		for index in indices {
			fields.append(("c\(index)Builder_Instantiator__C\(index)_Optional", "((Instantiator<Peer>) -> C\(index))?"))
		}
		var lines = ["#if DEBUG", "extension Root {", "    /// Overrides for the mock dependency tree.", "    struct SafeDIOverrides {", "        init("]
		for (position, field) in fields.enumerated() {
			lines.append("            \(field.name): \(field.type) = nil\(position == fields.count - 1 ? "" : ",")")
		}
		lines.append("        ) {")
		for field in fields {
			lines.append("            self.\(field.name) = \(field.name)")
		}
		lines.append("        }")
		lines.append("")
		for field in fields {
			lines.append("        let \(field.name): \(field.type)")
		}
		lines.append("    }")
		lines.append("")
		lines.append("    static func mock(")
		lines.append("        safeDIOverrides: SafeDIOverrides = .init()")
		lines.append("    ) -> Root {")
		/// The builder function of a child's builder, in the form `suffix` names.
		func childFunction(_ index: Int, suffix: String) {
			let name = "c\(index)Builder_Instantiator__C\(index)\(suffix)"
			lines.append("        func __safeDI_\(name)() -> C\(index) {")
			lines.append("            let peerBuilder = Instantiator<Peer>(__safeDI_peerBuilder)")
			lines.append("            return if let safeDIBuilder = safeDIOverrides.\(name) { safeDIBuilder(peerBuilder) } else { C\(index)(peerBuilder: peerBuilder) }")
			lines.append("        }")
		}
		for index in indices {
			childFunction(index, suffix: "")
		}
		lines.append("        func __safeDI_peerBuilder() -> Peer {")
		for index in indices {
			lines.append("            let c\(index)Builder_Instantiator__C\(index)_Optional = Instantiator<C\(index)>(__safeDI_c\(index)Builder_Instantiator__C\(index)_Optional)")
		}
		for index in indices {
			lines.append("            let c\(index)Builder: Instantiator<C\(index)>? = c\(index)Builder_Instantiator__C\(index)_Optional")
		}
		let arguments = indices.map { "c\($0)Builder" }.joined(separator: ", ")
		let labeledArguments = indices.map { "c\($0)Builder: c\($0)Builder" }.joined(separator: ", ")
		lines.append("            return if let safeDIBuilder = safeDIOverrides.peerBuilder { safeDIBuilder(\(arguments)) } else { Peer(\(labeledArguments)) }")
		lines.append("        }")
		for index in indices {
			childFunction(index, suffix: "_Optional")
		}
		for index in indices {
			lines.append("        let c\(index)Builder_Instantiator__C\(index) = Instantiator<C\(index)>(__safeDI_c\(index)Builder_Instantiator__C\(index))")
		}
		lines.append("        return Root(\(indices.map { "c\($0)Builder: c\($0)Builder_Instantiator__C\($0)" }.joined(separator: ", ")))")
		lines.append("    }")
		lines.append("}")
		lines.append("#endif")
		return lines.joined(separator: "\n")
	}

	/// `fixture`'s files, named by their position.
	private static func fixtureFiles(_ fixture: [String]) -> [String: String] {
		var fixtureFiles = [String: String]()
		for (index, file) in fixture.enumerated() {
			fixtureFiles["File\(index).swift"] = file
		}
		return fixtureFiles
	}

	/// Expects `Root.mock()` to build the values `Root()` builds, with the code `output` generated for `fixture`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectMockBuildsWhatProductionBuilds(fixture: [String], output: TestOutput, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let fixtureFiles = Self.fixtureFiles(fixture)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(
				fixtureFiles: fixtureFiles,
				generatedFiles: output.dependencyTreeFiles.merging(["Root+ProductionMock.swift": "extension Root {\n    static func mock() -> Root {\n        Root()\n    }\n}\n"]) { first, _ in first },
			),
			probes: [DifferentialValueProbe("Root.mock()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private static func type(_ name: String, attributes: String = "", _ declarations: String..., conformances: String = "") -> String {
		type(name, attributes: attributes, declarations, conformances: conformances)
	}

	private static func type(_ name: String, attributes: String = "", _ declarations: [String], conformances: String = "") -> String {
		let type = seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: conformances)
		guard !attributes.isEmpty else { return type }
		return "@Instantiable\(attributes)" + type.dropFirst("@Instantiable".count)
	}
}
