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

/// A mock root's world finds a capture of a wrapper that is not `Sendable` by a `@Sendable` function wherever its tree
/// does (`DeclarationsAnsweringReads`), resolving each receive by label and type in the order the tree looks declarations
/// up. These tests pin what the world and the tree find for the shapes where a lookup by spelling, by label alone, or
/// before promotion is final would answer otherwise; the executors' oracle (`MockRootTreeChecksOracle`) holds every other
/// test to the world finding each capture the tree finds.
struct SafeDIToolMockSendableCaptureCheckTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	mutating func mock_findsNoCaptureOfForwardedValue_whenRootAlsoPromotesLazyWrapperOfItsLabelWhoseTypeSortsEitherSide() async {
		// Each root forwards `value` and promotes a `LazilyInstantiated` of the same label and type for the panel it
		// receives; the worker built in a `@Sendable` function reads the forwarded value, which the tree looks up first,
		// whichever way the type's name sorts against the wrapper's.
		let findings = await sendableCaptureFindingByRoot(of: ["Zeta", "Alpha"].flatMap(Self.forwardedValueBesideLazyWrapper(of:)))
		#expect(findings == [
			"ZetaRoot": SendableCaptureFinding(world: false, tree: false),
			"AlphaRoot": SendableCaptureFinding(world: false, tree: false),
		])
	}

	@Test
	mutating func mock_findsCaptureAsTreeDoes_whenRootPromotesTwoLazyWrapperKindsOfOneLabelAndSendableFunctionReadsTheInstance() async {
		// The root promotes the `LazilyInstantiated` its panel receives before the `SendableLazilyInstantiated` its gauge
		// receives, and the worker built in a `@Sendable` function reads the instance of the first, which it captures.
		let findings = await sendableCaptureFindingByRoot(of: [
			"""
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(panel: Panel, gauge: Gauge, workerBuilder: SendableInstantiator<Worker>) {
			        self.panel = panel
			        self.gauge = gauge
			        self.workerBuilder = workerBuilder
			    }

			    @Instantiated let panel: Panel
			    @Instantiated let gauge: Gauge
			    @Instantiated let workerBuilder: SendableInstantiator<Worker>
			}
			""",
			"""
			@Instantiable
			public final class Gauge: Instantiable {
			    public init(token: SendableLazilyInstantiated<Token>) {
			        self.token = token
			    }

			    @Received let token: SendableLazilyInstantiated<Token>
			}
			""",
			"""
			@Instantiable
			public final class Panel: Instantiable {
			    public init(token: LazilyInstantiated<Token>) {
			        self.token = token
			    }

			    @Received let token: LazilyInstantiated<Token>
			}
			""",
			"""
			@Instantiable
			public final class Worker: Instantiable, Sendable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}
			""",
			"""
			@Instantiable
			public final class Token: Instantiable, Sendable {
			    public init() {}
			}
			""",
		], expectsError: true)
		#expect(findings == ["Screen": SendableCaptureFinding(world: true, tree: true)])
	}

	@Test
	mutating func mock_passesNilToReceiveOfWrapper_whenSendableFunctionReceivesWrapperOnlyIfAvailableThatRequiredReceivePins() async throws {
		// `Leaf`'s required receive of `token` pins its declaration to the value, which `Worker`'s receive of an
		// `Instantiator` only if available cannot read: the tree passes it `nil`, and captures nothing. The world does not
		// judge pins (`DeclarationsAnsweringReads`), so it finds a capture here and keeps the tree, which the oracle counts.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			"""
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(workerBuilder: SendableInstantiator<Worker>) {
			        self.workerBuilder = workerBuilder
			    }

			    @Instantiated let workerBuilder: SendableInstantiator<Worker>
			}
			""",
			"""
			@Instantiable
			public final class Worker: Instantiable {
			    public init(token: Instantiator<Token>?, leaf: Leaf) {
			        self.token = token
			        self.leaf = leaf
			    }

			    @Received(onlyIfAvailable: true) let token: Instantiator<Token>?
			    @Instantiated let leaf: Leaf
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable, Sendable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}
			""",
			"""
			@Instantiable
			public final class Token: Instantiable, Sendable {
			    public init() {}
			}
			""",
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == ["Screen+SafeDIMock.swift": """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            workerBuilder: Worker.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                workerBuilder: workerBuilder
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var workerBuilder: Worker.SafeDIMockConfiguration { __safeDI_storage.workerBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                workerBuilder: Worker.SafeDIMockConfiguration
		            ) {
		                self.token = token
		                self.workerBuilder = workerBuilder
		            }

		            let token: (() -> Token)?
		            let workerBuilder: Worker.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        let __safeDI_workerBuilder__overrides = safeDIOverrides.workerBuilder
		        @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
		            let leaf = if let safeDIBuilder = __safeDI_workerBuilder__overrides.leaf { safeDIBuilder(token) } else { Leaf(token: token) }
		            return if let safeDIBuilder = __safeDI_workerBuilder__overrides.safeDIBuilder { safeDIBuilder(nil, leaf) } else { Worker(token: nil, leaf: leaf) }
		        }
		        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		        return Screen(workerBuilder: workerBuilder)
		    }
		}
		#endif
		"""])
	}

	@Test
	mutating func mock_findsNoCapture_whenAliasKeepingItsLabelInsideSendableFunctionAnswersChildBesideRootLazyWrapperOfAliasedType() async {
		// `Middle`'s alias keeps the label `token` and answers `Leaf`'s receive of the protocol; the wrapper of the protocol
		// the root promotes for the gauge it receives answers nothing beneath the call, since `Middle` reads the concrete
		// type from above.
		let findings = await sendableCaptureFindingByRoot(of: [
			"""
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(gauge: Gauge, middleBuilder: SendableInstantiator<Middle>) {
			        self.gauge = gauge
			        self.middleBuilder = middleBuilder
			    }

			    @Received let gauge: Gauge
			    @Instantiated let middleBuilder: SendableInstantiator<Middle>
			}
			""",
			"""
			@Instantiable
			public final class Gauge: Instantiable {
			    public init(token: LazilyInstantiated<TokenProtocol>) {
			        self.token = token
			    }

			    @Received let token: LazilyInstantiated<TokenProtocol>
			}
			""",
			"""
			@Instantiable
			public final class Middle: Instantiable, Sendable {
			    public init(token: TokenProtocol, leaf: Leaf) {
			        self.token = token
			        self.leaf = leaf
			    }

			    @Received(fulfilledByDependencyNamed: "token", ofType: Token.self) let token: TokenProtocol
			    @Instantiated let leaf: Leaf
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable, Sendable {
			    public init(token: TokenProtocol) {
			        self.token = token
			    }

			    @Received let token: TokenProtocol
			}
			""",
			"""
			public protocol TokenProtocol: Sendable {}

			@Instantiable(fulfillingAdditionalTypes: [TokenProtocol.self])
			public final class Token: Instantiable, TokenProtocol {
			    public init() {}
			}
			""",
		])
		#expect(findings == ["Screen": SendableCaptureFinding(world: false, tree: false)])
	}

	@Test
	mutating func mock_findsNoCapture_whenWrapperOnlyPublicMockCallReceivesInsideSendableFunctionIsLeftOutOfMock() async throws {
		// Only `Cache`'s public mock receives `filter`, inside the `@Sendable` builder of `Wrapper`: promotion leaves it out of
		// what the internal mock binds, so the call passes `nil` and nothing is captured.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Cache.swift": """
			import SafeDI

			@Instantiable
			public final class Filter: Instantiable {
			    public init() {}
			}

			@Instantiable
			package struct TokenCache: Instantiable {
			    package init(filter: Instantiator<Filter>?) {
			        self.filter = filter
			    }

			    @Received(onlyIfAvailable: true) let filter: Instantiator<Filter>?
			}

			@Instantiable(generateMock: .public)
			public struct Cache: Instantiable {
			    package init(tokenCache: TokenCache) {
			        self.tokenCache = tokenCache
			    }

			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable
			public struct Wrapper: Instantiable {
			    public init(cache: Cache) {
			        self.cache = cache
			    }

			    @Instantiated let cache: Cache
			}

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(wrapperBuilder: SendableInstantiator<Wrapper>) {
			        self.wrapperBuilder = wrapperBuilder
			    }

			    @Instantiated let wrapperBuilder: SendableInstantiator<Wrapper>
			}
			"""], dependencies: ["Core"]),
		]
		let (comparisons, continuation) = AsyncStream.makeStream(of: MockRootTreeChecksComparison.self)
		_ = try await MockRootTreeChecksObservation.$comparesTree.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var findings = [String: SendableCaptureFinding]()
		for await comparison in comparisons {
			findings[comparison.root] = SendableCaptureFinding(world: comparison.sendableCaptureFinding.world, tree: comparison.sendableCaptureFinding.tree)
		}
		#expect(findings == ["Screen": SendableCaptureFinding(world: false, tree: false), "Cache": SendableCaptureFinding(world: false, tree: false)])
	}

	// MARK: Private

	private struct SendableCaptureFinding: Equatable {
		let world: Bool?
		let tree: Bool
	}

	private var filesToDelete: [URL]

	/// What each mock root's world and tree find of a `Sendable` capture, by mocked type, of a run over `swiftFileContent`,
	/// which reports an error exactly where `expectsError`.
	private mutating func sendableCaptureFindingByRoot(of swiftFileContent: [String], expectsError: Bool = false) async -> [String: SendableCaptureFinding] {
		let (comparisons, continuation) = AsyncStream.makeStream(of: MockRootTreeChecksComparison.self)
		await MockRootTreeChecksObservation.$comparesTree.withValue({ continuation.yield($0) }) {
			do {
				_ = try await executeSafeDIToolTest(
					swiftFileContent: swiftFileContent,
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
				#expect(!expectsError)
			} catch {
				// The tree reports the capture it finds as the error.
				#expect(expectsError, "\(error)")
			}
		}
		continuation.finish()
		var findings = [String: SendableCaptureFinding]()
		for await comparison in comparisons {
			findings[comparison.root] = SendableCaptureFinding(world: comparison.sendableCaptureFinding.world, tree: comparison.sendableCaptureFinding.tree)
		}
		return findings
	}

	/// A mock root named for `type` that forwards a value of it and receives a panel, which production builds above it and
	/// whose `LazilyInstantiated` of the same label the mock promotes beside the value, and a worker built in a `@Sendable`
	/// function that reads the value.
	private static func forwardedValueBesideLazyWrapper(of type: String) -> [String] {
		[
			"""
			@Instantiable(generateMock: true)
			public final class \(type)Root: Instantiable {
			    public init(value: \(type), panel: \(type)Panel, workerBuilder: SendableInstantiator<\(type)Worker>) {
			        self.value = value
			        self.panel = panel
			        self.workerBuilder = workerBuilder
			    }

			    @Forwarded let value: \(type)
			    @Received let panel: \(type)Panel
			    @Instantiated let workerBuilder: SendableInstantiator<\(type)Worker>
			}
			""",
			"""
			@Instantiable
			public final class \(type)Panel: Instantiable {
			    public init(value: LazilyInstantiated<\(type)>) {
			        self.value = value
			    }

			    @Received let value: LazilyInstantiated<\(type)>
			}
			""",
			"""
			@Instantiable
			public final class \(type)Worker: Instantiable, Sendable {
			    public init(value: \(type)) {
			        self.value = value
			    }

			    @Received let value: \(type)
			}
			""",
			"""
			@Instantiable
			public final class \(type): Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
	}
}
