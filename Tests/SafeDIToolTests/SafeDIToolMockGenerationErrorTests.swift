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

struct SafeDIToolMockGenerationErrorTests: ~Copyable {
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
	mutating func mock_throwsError_whenPartiallyLazyCycleThroughInstantiatorBoundary() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["CachedItem.swift"]):7:5: error: Dependency cycle detected. Cycles with a mix of constant and lazy (Instantiator) dependencies cannot be resolved. Make all dependencies in the cycle lazy by using Instantiator: Player -> Instantiator<CachedItem> -> Player
				\(fixtures["Player.swift"]):1:1: note: `Player` is part of the cycle
				\(fixtures["CachedItem.swift"]):1:1: note: `CachedItem` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Player: Instantiable {
					    public init(cachedItemBuilder: Instantiator<CachedItem>) {
					        self.cachedItemBuilder = cachedItemBuilder
					    }
					    @Instantiated let cachedItemBuilder: Instantiator<CachedItem>
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct CachedItem: Instantiable {
					    public init(player: Player, name: String) {
					        self.player = player
					        self.name = name
					    }
					    @Instantiated let player: Player
					    @Forwarded let name: String
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
	mutating func mock_throwsError_whenConstantDependencyCycleExists() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):4:5: error: Dependency cycle detected: A -> B -> C -> A
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(a: A) { self.a = a }
					    @Instantiated let a: A
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
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct C: Instantiable {
					    public init(a: A) { self.a = a }
					    @Instantiated let a: A
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
	mutating func mock_throwsError_whenReceivedPropertyIsHiddenByAliasReusingItsLabel() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `analytics: Analytics` is hidden in chain: Root -> Mid -> Child. `Mid` declares `analytics: EventTracker` with the same label, so the types below `Mid` receive `analytics: EventTracker` instead. Give `analytics: EventTracker` on `Mid` a different label to fix.
				\(fixtures["Mid.swift"]):4:5: note: `analytics: EventTracker` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Root: Instantiable {
					    public init(analytics: Analytics, mid: Mid) { self.analytics = analytics; self.mid = mid }
					    @Instantiated let analytics: Analytics
					    @Instantiated let mid: Mid
					}
					""",
					"""
					public protocol EventTracker {}
					@Instantiable
					public final class Analytics: Instantiable, EventTracker {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Mid: Instantiable {
					    public init(analytics: EventTracker, child: Child) { self.analytics = analytics; self.child = child }
					    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) let analytics: EventTracker
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(analytics: Analytics) { self.analytics = analytics }
					    @Received let analytics: Analytics
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
	mutating func mock_throwsError_whenReceivedPropertyIsHiddenByAliasReusingItsLabelInTreeOfTypeListedInAdditionalMocksToGenerate() async throws {
		// Top is defined in a dependent module without generateMock: true.
		let dependentModuleOutput = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public struct Top: Instantiable {
				    public init(analytics: Analytics, mid: Mid) { self.analytics = analytics; self.mid = mid }
				    @Instantiated let analytics: Analytics
				    @Instantiated let mid: Mid
				}
				""",
				"""
				public protocol EventTracker {}
				@Instantiable
				public final class Analytics: Instantiable, EventTracker {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public struct Mid: Instantiable {
				    public init(analytics: EventTracker, child: Child) { self.analytics = analytics; self.child = child }
				    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) let analytics: EventTracker
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public init(analytics: Analytics) { self.analytics = analytics }
				    @Received let analytics: Analytics
				}
				""",
			],
			filesToDelete: &filesToDelete,
		)
		let dependentModuleFixtures = dependentModuleOutput.fixtures

		await assertThrowsError(
			diagnostics: { _ in
				"""
				\(dependentModuleFixtures["Child.swift"]):4:5: error: @Received property `analytics: Analytics` is hidden in chain: Top -> Mid -> Child. `Mid` declares `analytics: EventTracker` with the same label, so the types below `Mid` receive `analytics: EventTracker` instead. Give `analytics: EventTracker` on `Mid` a different label to fix.
				\(dependentModuleFixtures["Mid.swift"]):4:5: note: `analytics: EventTracker` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalMocksToGenerate: [
					        "Top",
					    ]
					)
					""",
				],
				dependentModuleInfoPaths: [dependentModuleOutput.moduleInfoOutputPath],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenRequiredOptionalReceivedPropertyIsHiddenByPropertyOfAnotherTypeWithSameLabel() async {
		// A required `analytics: Analytics?` resolves to a closer `analytics: Analytics`, but not to `Mid`'s
		// `analytics: OtherAnalytics`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `analytics: Analytics?` is hidden in chain: Root -> Mid -> Child. `Mid` declares `analytics: OtherAnalytics` with the same label, so the types below `Mid` receive `analytics: OtherAnalytics` instead. Give `analytics: OtherAnalytics` on `Mid` a different label to fix.
				\(fixtures["Mid.swift"]):4:5: note: `analytics: OtherAnalytics` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Root: Instantiable {
					    public init(analytics: Analytics, mid: Mid) { self.analytics = analytics; self.mid = mid }
					    @Instantiated let analytics: Analytics
					    @Instantiated let mid: Mid
					}
					""",
					"""
					@Instantiable
					public final class Analytics: Instantiable {
					    public init() {}
					}
					@Instantiable
					public final class OtherAnalytics: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Mid: Instantiable {
					    public init(analytics: OtherAnalytics, child: Child) { self.analytics = analytics; self.child = child }
					    @Instantiated let analytics: OtherAnalytics
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(analytics: Analytics?) { self.analytics = analytics }
					    @Received let analytics: Analytics?
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
	mutating func mock_throwsError_whenOnlyIfAvailableReceivedPropertyNoAncestorProvidesIsHiddenByPropertyWithSameLabel() async {
		// Production passes `nil`, because no ancestor provides `analytics: Analytics`, but the mock
		// declares `analytics: Analytics?` at its root, where `Mid`’s `analytics` hides it from `Child`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `analytics: Analytics?` is hidden in chain: Root -> Mid -> Child. `Mid` declares `analytics: OtherAnalytics` with the same label, so the types below `Mid` receive `analytics: OtherAnalytics` instead. Give `analytics: OtherAnalytics` on `Mid` a different label to fix.
				\(fixtures["Mid.swift"]):4:5: note: `analytics: OtherAnalytics` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(mid: Mid) { self.mid = mid }
					    @Instantiated let mid: Mid
					}
					""",
					"""
					@Instantiable
					public final class Analytics: Instantiable {
					    public init() {}
					}
					@Instantiable
					public final class OtherAnalytics: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Mid: Instantiable {
					    public init(analytics: OtherAnalytics, child: Child) { self.analytics = analytics; self.child = child }
					    @Instantiated let analytics: OtherAnalytics
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(analytics: Analytics?) { self.analytics = analytics }
					    @Received(onlyIfAvailable: true) let analytics: Analytics?
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
	mutating func mock_throwsError_whenPromotedDependenciesReceiveEachOther() async {
		// Child.mock() promotes `c` (Child receives it) and `b` (C receives it).
		// Worker, built inside `b`, requires `c`, so each promoted dependency must be
		// built before the other. Production rejects the same graph when one root
		// instantiates both `b` and `c`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):4:5: error: Dependency cycle detected: B -> Worker -> C -> B
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				\(fixtures["Worker.swift"]):1:1: note: `Worker` is part of the cycle
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(worker: Worker) { self.worker = worker }
					    @Instantiated let worker: Worker
					}
					""",
					"""
					@Instantiable
					public final class Worker: Instantiable {
					    public init(c: C) { self.c = c }
					    @Received let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public final class Child: Instantiable {
					    public init(c: C) { self.c = c }
					    @Received let c: C
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
	mutating func mock_throwsError_whenPromotedDependencyFulfillsOnlyIfAvailableAliasRequiredByReceiverAndReceivesTheReceiversAncestor() async {
		// Parent.mock() promotes `x` (Other receives it). Grand requires Child's
		// `onlyIfAvailable` alias of `x`, so `x` must be built before `child`, but X requires `child`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["X.swift"]):6:5: error: Dependency received in same chain it is instantiated: @Instantiated child: Child -> @Received maybe: Greeter? -> @Received x: X -> @Received child: Child
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Parent: Instantiable {
					    public init(child: Child, other: Other) { self.child = child; self.other = other }
					    @Instantiated let child: Child
					    @Instantiated let other: Other
					}
					""",
					"""
					@Instantiable
					public final class Other: Instantiable {
					    public init(x: X) { self.x = x }
					    @Received let x: X
					}
					""",
					"""
					public protocol Greeter {}

					@Instantiable
					public final class X: Instantiable, Greeter {
					    public init(child: Child) { self.child = child }
					    @Received let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(maybe: Greeter?, grand: Grand) { self.maybe = maybe; self.grand = grand }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let maybe: Greeter?
					    @Instantiated let grand: Grand
					}
					""",
					"""
					@Instantiable
					public final class Grand: Instantiable {
					    public init(maybe: Greeter?) { self.maybe = maybe }
					    @Received let maybe: Greeter?
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
	mutating func mock_throwsError_whenRequiredOptionalReceiveIsBuiltInsideItsOnlyProvider() async {
		// Child, built inside `user`, requires `user: User?`. Root.mock() builds `user`
		// itself, so it binds no `user` parameter, and `user` is still being built: the
		// receive closes a cycle, as a receive of `user: User` would.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: Dependency cycle detected: User -> Child -> User?
				\(fixtures["User.swift"]):1:1: note: `User` is part of the cycle
				\(fixtures["Child.swift"]):1:1: note: `Child` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Root: Instantiable {
					    public init(user: User) { self.user = user }
					    @Instantiated let user: User
					}
					""",
					"""
					@Instantiable
					public final class User: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(user: User?) { self.user = user }
					    @Received let user: User?
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
	mutating func mock_throwsError_whenRequiredOptionalReceiveUnderAncestorThatReceivesItOnlyIfAvailableIsBuiltInsideItsOnlyProvider() async {
		// Parent, built inside `user`, receives `user` only if available and gets `nil`,
		// because `user` is still being built. Child, which requires `user`, is built
		// inside it too, so its receive closes a cycle, as a receive of `user: User` would.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: Dependency cycle detected: User -> Parent -> Child -> User?
				\(fixtures["User.swift"]):1:1: note: `User` is part of the cycle
				\(fixtures["Parent.swift"]):1:1: note: `Parent` is part of the cycle
				\(fixtures["Child.swift"]):1:1: note: `Child` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Root: Instantiable {
					    public init(user: User) { self.user = user }
					    @Instantiated let user: User
					}
					""",
					"""
					@Instantiable
					public final class User: Instantiable {
					    public init(parent: Parent) { self.parent = parent }
					    @Instantiated let parent: Parent
					}
					""",
					"""
					@Instantiable
					public final class Parent: Instantiable {
					    public init(user: User?, child: Child) { self.user = user; self.child = child }
					    @Received(onlyIfAvailable: true) let user: User?
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(user: User?) { self.user = user }
					    @Received let user: User?
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// The time limit only turns a hang into a failure; see
	// `mock_generatesWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsErrorWithinTimeLimit_whenPromotedDependenciesReceiveEachOtherAfterDeepChainOfDiamonds() async {
		// Feature's promoted children require one another (Zeta -> ZetaWorker -> ZetaPeer
		// -> Zeta), so the mock root is walked like a production root. Its other promoted
		// children, which sort first, form a deep chain of diamonds whose received-dependency
		// paths grow exponentially: the walk must stay memoized to reach the cycle.
		let serviceCount = 80
		let serviceFiles = (0..<serviceCount).map { index in
			let receivedIndices = Set([index - 1, index - 2, index / 2])
				.filter { $0 >= 0 && $0 < index }
				.sorted()
			let initializerParameters = receivedIndices.map { "service\($0): Service\($0)" }.joined(separator: ", ")
			let receivedProperties = receivedIndices.map { "    @Received let service\($0): Service\($0)" }.joined(separator: "\n")
			return """
			@Instantiable
			public struct Service\(index): Instantiable {
			    public init(\(initializerParameters)) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			\(receivedProperties)
			}
			"""
		}
		let lastService = serviceCount - 1
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["ZetaPeer.swift"]):4:5: error: Dependency cycle detected: Zeta -> ZetaWorker -> ZetaPeer -> Zeta
				\(fixtures["Zeta.swift"]):1:1: note: `Zeta` is part of the cycle
				\(fixtures["ZetaWorker.swift"]):1:1: note: `ZetaWorker` is part of the cycle
				\(fixtures["ZetaPeer.swift"]):1:1: note: `ZetaPeer` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Feature: Instantiable {
					    public init(service\(lastService): Service\(lastService), zeta: Zeta) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let service\(lastService): Service\(lastService)
					    @Received let zeta: Zeta
					}
					""",
					"""
					@Instantiable
					public struct Zeta: Instantiable {
					    public init(zetaWorker: ZetaWorker) { self.zetaWorker = zetaWorker }
					    @Instantiated let zetaWorker: ZetaWorker
					}
					""",
					"""
					@Instantiable
					public struct ZetaWorker: Instantiable {
					    public init(zetaPeer: ZetaPeer) { self.zetaPeer = zetaPeer }
					    @Received let zetaPeer: ZetaPeer
					}
					""",
					"""
					@Instantiable
					public struct ZetaPeer: Instantiable {
					    public init(zeta: Zeta) { self.zeta = zeta }
					    @Received let zeta: Zeta
					}
					""",
				] + serviceFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
			)
		}
	}

	// The time limit only turns a hang into a failure; see
	// `mock_generatesWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsReceivedCycleErrorWithinTimeLimit_whenEveryReceivedPathFromEarlierSiblingsEndsInReceivedCycle() async {
		// Each layer holds a Left and a Right service that both receive the two services of the
		// next layer, and the last layer's services receive Ping, which receives Pong, which receives
		// Ping. Validating Feature's `left0` and `right0`, and every promoted service, walks down to
		// that cycle along every path, and the number of paths doubles with each layer. The promoted
		// `ping` sorts after every promoted Left service, so the walk must remember what lies past the
		// cycle to reach the error Ping reports.
		let layerCount = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["ping: Ping"]
				: ["left\(layer + 1): Left\(layer + 1)", "right\(layer + 1): Right\(layer + 1)"]
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
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Pong.swift"]):7:5: error: Dependency received in same chain it is instantiated: @Instantiated ping: Ping -> @Received pong: Pong -> @Received ping: Ping
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Feature: Instantiable {
					    public init(left0: Left0, right0: Right0) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let left0: Left0
					    @Instantiated let right0: Right0
					}
					""",
					"""
					@Instantiable
					public struct Ping: Instantiable {
					    public init(pong: Pong) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let pong: Pong
					}
					""",
					"""
					@Instantiable
					public struct Pong: Instantiable {
					    public init(ping: Ping) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let ping: Ping
					}
					""",
				] + layerFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
			)
		}
	}

	// The time limit only turns a hang into a failure; see
	// `mock_generatesWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsReceivedCycleErrorWithinTimeLimit_whenEveryReceivedInstantiatorPathFromEarlierSiblingsEndsInReceivedCycle() async {
		// Each layer holds a Left and a Right service that both receive Instantiators of the two
		// services of the next layer, and the last layer's services receive an Instantiator of Ping,
		// which receives one of Pong, which receives one of Ping. Feature's mock promotes every one of
		// those Instantiators, so the number of received paths from any layer to that cycle doubles
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
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Pong.swift"]):7:5: error: Dependency received in same chain it is instantiated: @Instantiated pingBuilder: Instantiator<Ping> -> @Received pongBuilder: Instantiator<Pong> -> @Received pingBuilder: Instantiator<Ping>
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenUnfulfillableInstantiatedPropertyExists() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `Unknown`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Child: Instantiable {
					    public init(unknown: Unknown) { self.unknown = unknown }
					    @Instantiated let unknown: Unknown
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
	mutating func mock_throwsError_whenReceivedPropertyIsUnfulfillable() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `service: Service` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let service: Service` on `Root` or on another type in the chain to fix.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(child: Child, other: Other) {
					        self.child = child
					        self.other = other
					    }
					    @Instantiated let child: Child
					    @Instantiated let other: Other
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Child: Instantiable {
					    public init(service: Service) { self.service = service }
					    @Received let service: Service
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Other: Instantiable {
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
	mutating func mock_throwsError_whenInstantiatedPropertyRefersToSelf() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["SelfReferencing.swift"]):4:5: error: Dependency cycle detected: SelfReferencing -> SelfReferencing
				\(fixtures["SelfReferencing.swift"]):1:1: note: `SelfReferencing` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(selfReferencing: SelfReferencing) { self.selfReferencing = selfReferencing }
					    @Instantiated let selfReferencing: SelfReferencing
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct SelfReferencing: Instantiable {
					    public init(selfReferencing: SelfReferencing) { self.selfReferencing = selfReferencing }
					    @Instantiated let selfReferencing: SelfReferencing
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
	mutating func mock_throwsError_whenInstantiatedPropertyHasForwardedArgument() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):4:5: error: Property `child: Child` on Root has at least one @Forwarded property. Property should instead be of type `Instantiator<Child>`.
				\(fixtures["Child.swift"]):4:5: note: @Forwarded property `name: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Child: Instantiable {
					    public init(name: String) { self.name = name }
					    @Forwarded let name: String
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
	mutating func mock_throwsError_whenReceivedInstantiatorDependencyCycleExists_withRoot() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>`. Declare @Received `aBuilder: Instantiator<A>` on `B` as @Instantiated to fix. Full cycle: Instantiator<A> -> B -> Instantiator<A>
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenReceivedInstantiatorDependencyCycleExists_withoutRoot() async {
		// Same cycle as the _withRoot test but no root — the cycle is only visible
		// after mock generation promotes @Received dependencies.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>`. Declare @Received `aBuilder: Instantiator<A>` on `B` as @Instantiated to fix. Full cycle: Instantiator<A> -> B -> Instantiator<A>
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsReceivedCycleError_whenSiblingInstantiatorsOfMockRootReceiveEachOther() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsReceivedCycleError_whenPromotedInstantiatorsReceiveEachOther() async {
		// `A`'s mock promotes the `bBuilder` it receives, and then the `aBuilder` that `B` receives.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsReceivedCycleError_whenSiblingInstantiatorsOfPromotedScopeReceiveEachOther() async {
		// Only `Top`'s mock reaches `Holder`, by promoting the `holder` that `Top` receives.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsReceivedCycleError_whenConstantSiblingsOfPromotedScopeReceiveEachOther() async {
		// No validation walks the trees of promoted scopes, so the received cycle in `Holder`, which
		// only `Top`'s mock reaches, is reported by the check for children that require one another.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated a: A -> @Received b: B -> @Received a: A
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
					    public init(a: A, b: B) {
					        self.a = a
					        self.b = b
					    }

					    @Instantiated let a: A
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(a: A) { self.a = a }
					    @Received let a: A
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
	mutating func mock_parseErrorWritesErrorStubToMockOutputs() async throws {
		// When source has parse errors, mock outputs should get the error stub too
		// (not be left stale or missing).
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public struct Root: Instantiable {
				    public init() {}

				    :::brokenSyntax
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// Fixture intentionally contains `:::brokenSyntax` to exercise the parse-error stub path
			skipCompileVerification: true,
		)

		// Both dependency tree AND mock outputs should have the error.
		// Path is dynamic so we check for the #error directive presence.
		let rootDependencyTree = try #require(output.dependencyTreeFiles["Root+SafeDI.swift"])
		#expect(rootDependencyTree.contains("#error"), "Dependency tree output should have #error. Output:\n\(rootDependencyTree)")
		let rootMock = try #require(output.mockFiles["Root+SafeDIMock.swift"])
		#expect(rootMock.contains("#error"), "Mock output should have #error. Output:\n\(rootMock)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenNonRootInstantiatedPropertyHasForwardedArgument() async {
		// Parent is NOT a root — only generateMock: true. Child has @Forwarded.
		// Production validation never sees this graph (no root entry point),
		// but mock generation must still catch the forwarded-property error.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Parent.swift"]):4:5: error: Property `child: Child` on Parent has at least one @Forwarded property. Property should instead be of type `Instantiator<Child>`.
				\(fixtures["Child.swift"]):4:5: note: @Forwarded property `name: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Child: Instantiable {
					    public init(name: String) { self.name = name }
					    @Forwarded let name: String
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
	mutating func mock_emitsIncorrectlyConfiguredComment_whenNoInitCoversDependenciesAndNoMockMethodExists() async throws {
		// The `@Instantiable` macro rejects this shape at compile time — the
		// init doesn't satisfy the @Instantiated dep and there's no mock
		// method. But the fixture still reaches SafeDITool's generator, which
		// must emit a stub return value (rather than crashing) so the
		// generated file is shaped enough to report the compile error
		// meaningfully alongside the macro diagnostic.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public struct Root: Instantiable {
				    public init() {}
				    @Instantiated let bar: Bar
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct Bar: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// Fixture is macro-invalid (init doesn't match deps). The mock
			// generator produces an incorrectly-configured stub for the
			// return statement.
			skipCompileVerification: true,
		)

		let rootMock = try #require(output.mockFiles["Root+SafeDIMock.swift"])
		#expect(rootMock == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            bar: (() -> Bar)? = nil
		        ) {
		            self.bar = bar
		        }

		        let bar: (() -> Bar)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let bar = if let safeDIBuilder = safeDIOverrides.bar { safeDIBuilder() } else { Bar() }
		        return Root(/* @Instantiable type is incorrectly configured. Fix errors from @Instantiable macro to fix this error. */)
		    }
		}
		#endif
		""", "Unexpected output \(rootMock)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsErrorOfFirstTypeInTypeOrder_whenManyTypesWithGeneratedMocksHaveCycles() async {
		// Every one of the 200 types whose mock is generated is in its own cycle. Their scopes
		// hash by object identity, so a set of them iterates in an order that changes from run
		// to run, and validating in that order reports `Mock000`'s cycle about once in 200 runs.
		let swiftFileContent = (0..<200).map { index in
			let suffix = String(repeating: "0", count: 3 - String(index).count) + String(index)
			return """
			@Instantiable(generateMock: true)
			public struct Mock\(suffix): Instantiable {
			    public init(partner: Partner\(suffix)) { self.partner = partner }
			    @Instantiated let partner: Partner\(suffix)
			}
			@Instantiable
			public struct Partner\(suffix): Instantiable {
			    public init(mock: Mock\(suffix)) { self.mock = mock }
			    @Instantiated let mock: Mock\(suffix)
			}
			"""
		}.joined(separator: "\n")
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Mock000.swift"]):4:5: error: Dependency cycle detected: Partner000 -> Mock000 -> Partner000
				\(fixtures["Mock000.swift"]):6:1: note: `Partner000` is part of the cycle
				\(fixtures["Mock000.swift"]):1:1: note: `Mock000` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete = [URL]()
}
