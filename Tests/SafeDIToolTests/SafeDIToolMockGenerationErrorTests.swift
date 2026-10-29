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
				\(fixtures["CachedItem.swift"]):7:5: error: Dependency cycle: `Player` -> `Instantiator<CachedItem>` -> `Player`. SafeDI accepts a dependency cycle only if the dependency that closes it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change `player: Player` to an instantiator; SafeDI then reports any other dependency in the cycle that must change too.
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
				\(fixtures["C.swift"]):4:5: error: Dependency cycle: `A` -> `B` -> `C` -> `A`. SafeDI accepts a dependency cycle only if the dependency that closes it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change `a: A` to an instantiator; SafeDI then reports any other dependency in the cycle that must change too.
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
	mutating func mock_throwsError_whenRequiredReceivedPropertyIsHiddenByForwardedPropertyOfMockedTypeWithSameLabel() async {
		// The mocked type's own tree hides `user: Draft`, as it does under a root. A mock names a required
		// received parameter apart only from what its promotion of received dependencies binds beside it.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Editor.swift"]):4:5: error: @Received property `user: Draft` is hidden in chain: ProfileView -> Editor. `ProfileView` declares `user: User` with the same label, so the types below `ProfileView` receive `user: User` instead. Give `user: User` on `ProfileView` a different label to fix.
				\(fixtures["ProfileView.swift"]):4:5: note: `user: User` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public final class User {}
					public final class Draft {}
					""",
					"""
					@Instantiable(generateMock: true)
					public final class ProfileView: Instantiable {
					    public init(user: User, editor: Editor) { self.user = user; self.editor = editor }
					    @Forwarded let user: User
					    @Instantiated let editor: Editor
					}
					""",
					"""
					@Instantiable
					public final class Editor: Instantiable {
					    public init(user: Draft) { self.user = user }
					    @Received let user: Draft
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
	mutating func mock_throwsError_whenOnlyIfAvailableReceivedPropertyIsHiddenByForwardedPropertyOfMockedTypeWithSameLabel() async {
		// The mocked type's own tree hides `user: Draft?`: production builds `Editor` under `ProfileView`, beside
		// the forwarded `user: User`. A mock names its `onlyIfAvailable` overrides apart only from what its
		// promotion of received dependencies binds beside them.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Editor.swift"]):4:5: error: @Received property `user: Draft?` is hidden in chain: ProfileView -> Editor. `ProfileView` declares `user: User` with the same label, so the types below `ProfileView` receive `user: User` instead. Give `user: User` on `ProfileView` a different label to fix.
				\(fixtures["ProfileView.swift"]):4:5: note: `user: User` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public final class User {}
					public final class Draft {}
					""",
					"""
					@Instantiable(generateMock: true)
					public final class ProfileView: Instantiable {
					    public init(user: User, editorBuilder: Instantiator<Editor>) { self.user = user; self.editorBuilder = editorBuilder }
					    @Forwarded let user: User
					    @Instantiated let editorBuilder: Instantiator<Editor>
					}
					""",
					"""
					@Instantiable
					public final class Editor: Instantiable {
					    public init(user: Draft?) { self.user = user }
					    @Received(onlyIfAvailable: true) let user: Draft?
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
				\(fixtures["C.swift"]):4:5: error: Dependency cycle: `B` -> `Worker` -> `C` -> `B`. `C` receives `b: B`, which is still being built when `C` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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
	mutating func mock_throwsError_whenReceiverRequiresOnlyIfAvailableAliasOfOptionalFormOfSiblingThatReceivesTheReceiversAncestor() async {
		// Parent.mock() builds `b` and `x`. D requires C's `onlyIfAvailable` alias `y` of `x: X?`, which no sibling
		// declares exactly, so `x` must be built before `b`, but X requires `b`. Parent is not a root, so only the
		// mock tree is validated.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["X.swift"]):4:5: error: Dependency cycle: @Instantiated `b: B` -> @Received `x: X?` -> @Received `b: B`. `b: B` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Parent: Instantiable {
					    public init(b: B, x: X) { self.b = b; self.x = x }
					    @Instantiated let b: B
					    @Instantiated let x: X
					}
					""",
					"""
					@Instantiable
					public final class X: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(y: X?, d: D) { self.y = y; self.d = d }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let y: X?
					    @Instantiated let d: D
					}
					""",
					"""
					@Instantiable
					public final class D: Instantiable {
					    public init(y: X?) { self.y = y }
					    @Received let y: X?
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
	mutating func mock_throwsError_whenReceiverRequiresOnlyIfAvailableAliasOfOnlyIfAvailableAliasOfOptionalFormOfSiblingThatReceivesTheReceiversAncestor() async {
		// Parent.mock() builds `b` and `x`. D requires E's `onlyIfAvailable` alias `z` of C's `onlyIfAvailable` alias `y`
		// of `x: X?`, so `x` must be built before `b`, but X requires `b`. Parent is not a root, so only the mock tree is
		// validated.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["X.swift"]):4:5: error: Dependency cycle: @Instantiated `b: B` -> @Received `x: X?` -> @Received `b: B`. `b: B` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Parent: Instantiable {
					    public init(b: B, x: X) { self.b = b; self.x = x }
					    @Instantiated let b: B
					    @Instantiated let x: X
					}
					""",
					"""
					@Instantiable
					public final class X: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(y: X?, e: E) { self.y = y; self.e = e }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let y: X?
					    @Instantiated let e: E
					}
					""",
					"""
					@Instantiable
					public final class E: Instantiable {
					    public init(z: X?, d: D) { self.z = z; self.d = d }
					    @Received(fulfilledByDependencyNamed: "y", ofType: X?.self, onlyIfAvailable: true) let z: X?
					    @Instantiated let d: D
					}
					""",
					"""
					@Instantiable
					public final class D: Instantiable {
					    public init(z: X?) { self.z = z }
					    @Received let z: X?
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
	mutating func mock_throwsError_whenReceiverRequiresRequiredAliasOfOnlyIfAvailableAliasOfOptionalFormOfSiblingThatReceivesTheReceiversAncestor() async {
		// As above, with C declaring `z` as a required alias of its own `onlyIfAvailable` alias `y`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["X.swift"]):4:5: error: Dependency cycle: @Instantiated `b: B` -> @Received `x: X?` -> @Received `b: B`. `b: B` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Parent: Instantiable {
					    public init(b: B, x: X) { self.b = b; self.x = x }
					    @Instantiated let b: B
					    @Instantiated let x: X
					}
					""",
					"""
					@Instantiable
					public final class X: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(y: X?, z: X?, d: D) { self.y = y; self.z = z; self.d = d }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let y: X?
					    @Received(fulfilledByDependencyNamed: "y", ofType: X?.self) let z: X?
					    @Instantiated let d: D
					}
					""",
					"""
					@Instantiable
					public final class D: Instantiable {
					    public init(z: X?) { self.z = z }
					    @Received let z: X?
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
	mutating func mock_throwsError_whenReceiverRequiresOnlyIfAvailableAliasOfOnlyIfAvailableAliasOfOptionalFormOfSiblingDeclaredOnOneTypeThatReceivesTheReceiversAncestor() async {
		// As above, with C declaring `z` as an `onlyIfAvailable` alias of its own `onlyIfAvailable` alias `y`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["X.swift"]):4:5: error: Dependency cycle: @Instantiated `b: B` -> @Received `x: X?` -> @Received `b: B`. `b: B` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Parent: Instantiable {
					    public init(b: B, x: X) { self.b = b; self.x = x }
					    @Instantiated let b: B
					    @Instantiated let x: X
					}
					""",
					"""
					@Instantiable
					public final class X: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(y: X?, z: X?, d: D) { self.y = y; self.z = z; self.d = d }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let y: X?
					    @Received(fulfilledByDependencyNamed: "y", ofType: X?.self, onlyIfAvailable: true) let z: X?
					    @Instantiated let d: D
					}
					""",
					"""
					@Instantiable
					public final class D: Instantiable {
					    public init(z: X?) { self.z = z }
					    @Received let z: X?
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
				\(fixtures["X.swift"]):6:5: error: Dependency cycle: @Instantiated `child: Child` -> @Received `maybe: Greeter?` -> @Received `x: X` -> @Received `child: Child`. `child: Child` is received while it is still being instantiated. `maybe: Greeter?` renames `x: X` only if available, so a type that receives `maybe` without `onlyIfAvailable` must be built after `x: X`. Receive `maybe` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `x: X` cannot be built first.
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
	mutating func mock_throwsError_whenPromotedDependencyFulfillsOnlyIfAvailableAliasRequiredByItsOwnTree() async {
		// Mocked.mock() promotes `t`. T requires Mocked's `onlyIfAvailable` alias of `t`, so `t`
		// must be built before T is.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["T.swift"]):4:5: error: Dependency cycle: @Instantiated `t: T` -> @Received `tProtocol: TProtocol?` -> @Received `t: T`. `t: T` is received while it is still being instantiated. `tProtocol: TProtocol?` renames `t: T` only if available, so a type that receives `tProtocol` without `onlyIfAvailable` must be built after `t: T`. Receive `tProtocol` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `t: T` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol TProtocol: AnyObject {}

					@Instantiable(generateMock: true)
					public final class Mocked: Instantiable {
					    public init(tProtocol: TProtocol?, t: T) { self.tProtocol = tProtocol; self.t = t }
					    @Received(fulfilledByDependencyNamed: "t", ofType: T.self, onlyIfAvailable: true) let tProtocol: TProtocol?
					    @Received let t: T
					}
					""",
					"""
					@Instantiable
					public final class T: Instantiable, TProtocol {
					    public init(tProtocol: TProtocol?) { self.tProtocol = tProtocol }
					    @Received let tProtocol: TProtocol?
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
	mutating func mock_throwsError_whenInstantiatedDependencyFulfillsOnlyIfAvailableAliasRequiredByItsOwnTree() async {
		// T requires Mocked's `onlyIfAvailable` alias of `t`, so `t` must be built before T is.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["T.swift"]):4:5: error: Dependency cycle: @Instantiated `t: T` -> @Received `tProtocol: TProtocol?` -> @Received `t: T`. `t: T` is received while it is still being instantiated. `tProtocol: TProtocol?` renames `t: T` only if available, so a type that receives `tProtocol` without `onlyIfAvailable` must be built after `t: T`. Receive `tProtocol` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `t: T` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol TProtocol: AnyObject {}

					@Instantiable(generateMock: true)
					public final class Mocked: Instantiable {
					    public init(tProtocol: TProtocol?, t: T) { self.tProtocol = tProtocol; self.t = t }
					    @Received(fulfilledByDependencyNamed: "t", ofType: T.self, onlyIfAvailable: true) let tProtocol: TProtocol?
					    @Instantiated let t: T
					}
					""",
					"""
					@Instantiable
					public final class T: Instantiable, TProtocol {
					    public init(tProtocol: TProtocol?) { self.tProtocol = tProtocol }
					    @Received let tProtocol: TProtocol?
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
	mutating func mock_throwsError_whenRootGeneratingMockInstantiatesDependencyFulfillingOnlyIfAvailableAliasRequiredByItsOwnTree() async {
		// T requires Root's `onlyIfAvailable` alias of `t`, so `t` must be built before T is,
		// in Root's dependency tree and in its mock alike.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["T.swift"]):4:5: error: Dependency cycle: @Instantiated `t: T` -> @Received `tProtocol: TProtocol?` -> @Received `t: T`. `t: T` is received while it is still being instantiated. `tProtocol: TProtocol?` renames `t: T` only if available, so a type that receives `tProtocol` without `onlyIfAvailable` must be built after `t: T`. Receive `tProtocol` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `t: T` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol TProtocol: AnyObject {}

					@Instantiable(isRoot: true, generateMock: true)
					public final class Root: Instantiable {
					    public init(tProtocol: TProtocol?, t: T) { self.tProtocol = tProtocol; self.t = t }
					    @Received(fulfilledByDependencyNamed: "t", ofType: T.self, onlyIfAvailable: true) let tProtocol: TProtocol?
					    @Instantiated let t: T
					}
					""",
					"""
					@Instantiable
					public final class T: Instantiable, TProtocol {
					    public init(tProtocol: TProtocol?) { self.tProtocol = tProtocol }
					    @Received let tProtocol: TProtocol?
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
	mutating func mock_throwsError_whenPromotedDependencyFulfillsAliasRequiredByItsOwnTree() async {
		// Mocked.mock() promotes `t`. T requires Mocked's alias of `t`, which is built from the T being built.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["T.swift"]):4:5: error: Dependency cycle: @Instantiated `t: T` -> @Received `tProtocol: TProtocol?` -> @Received `t: T`. `t: T` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol TProtocol: AnyObject {}

					@Instantiable(generateMock: true)
					public final class Mocked: Instantiable {
					    public init(tProtocol: TProtocol?, t: T) { self.tProtocol = tProtocol; self.t = t }
					    @Received(fulfilledByDependencyNamed: "t", ofType: T.self) let tProtocol: TProtocol?
					    @Received let t: T
					}
					""",
					"""
					@Instantiable
					public final class T: Instantiable, TProtocol {
					    public init(tProtocol: TProtocol?) { self.tProtocol = tProtocol }
					    @Received let tProtocol: TProtocol?
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
				\(fixtures["Child.swift"]):4:5: error: Dependency cycle: `User` -> `Child` -> `User?`. `Child` receives `user: User?`, which is still being built when `Child` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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
				\(fixtures["Child.swift"]):4:5: error: Dependency cycle: `User` -> `Parent` -> `Child` -> `User?`. `Child` receives `user: User?`, which is still being built when `Child` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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
				\(fixtures["ZetaPeer.swift"]):4:5: error: Dependency cycle: `Zeta` -> `ZetaWorker` -> `ZetaPeer` -> `Zeta`. `ZetaPeer` receives `zeta: Zeta`, which is still being built when `ZetaPeer` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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
				\(fixtures["Pong.swift"]):7:5: error: Dependency cycle: @Instantiated `ping: Ping` -> @Received `pong: Pong` -> @Received `ping: Ping`. `ping: Ping` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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
				\(fixtures["Pong.swift"]):7:5: error: Dependency cycle: @Instantiated `pingBuilder: Instantiator<Ping>` -> @Received `pongBuilder: Instantiator<Pong>` -> @Received `pingBuilder: Instantiator<Ping>`. `pingBuilder: Instantiator<Ping>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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

	// The time limit only turns a hang into a failure; see
	// `mock_generatesWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsReceivedCycleErrorWithinTimeLimit_whenEveryReceivedAliasPathFromEarlierSiblingsEndsInReceivedCycleOfLazyCycles() async {
		// Each layer holds a Left and a Right service that instantiate Instantiators of each other and
		// receive aliases, assigned through two other aliases, of the Instantiators of the two services of
		// the next layer. The last layer's services receive the last of a long chain of aliases of Ping's
		// Instantiator, and Ping and Pong receive aliases of each other's. Feature declares every alias in
		// reverse order of assignment.
		let layerCount = 40
		let aliasChainLength = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["pingAlias\(aliasChainLength - 1): Instantiator<Ping>"]
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
			["Left\(layer)", "Right\(layer)"].flatMap { type in
				let label = type.prefix(1).lowercased() + type.dropFirst()
				return [
					alias("\(label)Alias", of: "\(label)Renamed", type: "Instantiator<\(type)>"),
					alias("\(label)Renamed", of: "\(label)Builder", type: "Instantiator<\(type)>"),
				]
			}
		}
			+ (1..<aliasChainLength).reversed().map { alias("pingAlias\($0)", of: "pingAlias\($0 - 1)", type: "Instantiator<Ping>") }
			+ [
				alias("pingAlias0", of: "pingBuilder", type: "Instantiator<Ping>"),
				alias("pongAlias", of: "pongBuilder", type: "Instantiator<Pong>"),
			]
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Pong.swift"]):7:5: error: Dependency cycle: @Instantiated `pingBuilder: Instantiator<Ping>` -> @Received `pongAlias: Instantiator<Pong>` -> @Received `pingAlias\(aliasChainLength - 1): Instantiator<Ping>` -> @Received `pingBuilder: Instantiator<Ping>`. `pingBuilder: Instantiator<Ping>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
					    public init(pingAlias\(aliasChainLength - 1): Instantiator<Ping>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let pingAlias\(aliasChainLength - 1): Instantiator<Ping>
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
				\(fixtures["Child.swift"]):4:5: error: No @Instantiable type or extension fulfills `Unknown`, which @Instantiated property `unknown: Unknown` instantiates. Decorate `Unknown`, or an extension of it, with @Instantiable; list `Unknown` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target.
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
				\(fixtures["SelfReferencing.swift"]):4:5: error: Dependency cycle: `SelfReferencing` -> `SelfReferencing`. SafeDI accepts a dependency cycle only if the dependency that closes it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change `selfReferencing: SelfReferencing` to an instantiator; SafeDI then reports any other dependency in the cycle that must change too.
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
				\(fixtures["Root.swift"]):4:5: error: `child: Child` on `Root` cannot build `Child`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<Child>`.
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
				\(fixtures["B.swift"]):4:5: error: Dependency cycle: `Instantiator<A>` -> `B` -> `Instantiator<A>`. `B` receives `aBuilder: Instantiator<A>` inside the tree that `aBuilder` builds. Declare `aBuilder: Instantiator<A>` on `B` as @Instantiated instead of @Received.
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
				\(fixtures["B.swift"]):4:5: error: Dependency cycle: `Instantiator<A>` -> `B` -> `Instantiator<A>`. `B` receives `aBuilder: Instantiator<A>` inside the tree that `aBuilder` builds. Declare `aBuilder: Instantiator<A>` on `B` as @Instantiated instead of @Received.
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
	mutating func mock_throwsError_whenMockRootAliasesInstantiatorThatBuildsIt() async {
		// The mock promotes `nodeBuilder` to build Node, and the Node it builds aliases `nodeBuilder`
		// itself. An alias receives the property it renames, so this is a received cycle.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Node.swift"]):4:5: error: Dependency cycle: `Instantiator<Node>` -> `Instantiator<Node>`. `Node` receives `nodeBuilder: Instantiator<Node>` as `childBuilder: Instantiator<Node>` inside the tree that `nodeBuilder` builds. Declare `childBuilder: Instantiator<Node>` on `Node` as @Instantiated instead of @Received(fulfilledByDependencyNamed:ofType:).
				\(fixtures["Node.swift"]):1:1: note: `Node` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenMockRootAliasesSendableInstantiatorThatBuildsIt() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Node.swift"]):4:5: error: Dependency cycle: `SendableInstantiator<Node>` -> `SendableInstantiator<Node>`. `Node` receives `nodeBuilder: SendableInstantiator<Node>` as `childBuilder: SendableInstantiator<Node>` inside the tree that `nodeBuilder` builds. Declare `childBuilder: SendableInstantiator<Node>` on `Node` as @Instantiated instead of @Received(fulfilledByDependencyNamed:ofType:).
				\(fixtures["Node.swift"]):1:1: note: `Node` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenMockRootAliasesErasedInstantiatorThatBuildsIt() async {
		// Holder's erasure lets the mock build `nodeBuilder: ErasedInstantiator<(), AnyNode>` from Node,
		// and the Node it builds aliases that instantiator, erased to another wrapper. AnyNode is not
		// `@Instantiable`, so no note marks it.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Node.swift"]):4:5: error: Dependency cycle: `ErasedInstantiator<(), AnyNode>` -> `ErasedInstantiator<(), AnyNode>`. `Node` receives `nodeBuilder: ErasedInstantiator<(), AnyNode>` as `childBuilder: AnyNodeFactory` inside the tree that `nodeBuilder` builds. Declare `childBuilder: AnyNodeFactory` on `Node` as @Instantiated instead of @Received(fulfilledByDependencyNamed:ofType:).
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenAliasOfAncestorsAliasReceivesInstantiatorThatBuildsIt() async {
		// Screen renames `nodeBuilder` to `middleBuilder`, and Node renames `middleBuilder` to
		// `childBuilder`. The mock promotes both instantiators, and the Node that `middleBuilder` builds
		// aliases `middleBuilder` itself.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Node.swift"]):4:5: error: Dependency cycle: `Instantiator<Node>` -> `Instantiator<Node>`. `Node` receives `middleBuilder: Instantiator<Node>` as `childBuilder: Instantiator<Node>` inside the tree that `middleBuilder` builds. Declare `childBuilder: Instantiator<Node>` on `Node` as @Instantiated instead of @Received(fulfilledByDependencyNamed:ofType:).
				\(fixtures["Node.swift"]):1:1: note: `Node` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(middleBuilder: Instantiator<Node>) { self.middleBuilder = middleBuilder }
					    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let middleBuilder: Instantiator<Node>
					}
					""",
					"""
					@Instantiable
					public final class Node: Instantiable {
					    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
					    @Received(fulfilledByDependencyNamed: "middleBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
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
	mutating func mock_throwsError_whenAliasThatChildRenamesAgainReceivesInstantiatorThatBuildsIt() async {
		// Node renames `nodeBuilder` to `middleBuilder`, and its child renames `middleBuilder` to
		// `childBuilder`. The Node that the promoted `nodeBuilder` builds is the first alias's receiver,
		// so the cycle is reported there.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Node.swift"]):4:5: error: Dependency cycle: `Instantiator<Node>` -> `Instantiator<Node>`. `Node` receives `nodeBuilder: Instantiator<Node>` as `middleBuilder: Instantiator<Node>` inside the tree that `nodeBuilder` builds. Declare `middleBuilder: Instantiator<Node>` on `Node` as @Instantiated instead of @Received(fulfilledByDependencyNamed:ofType:).
				\(fixtures["Node.swift"]):1:1: note: `Node` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenAliasInTreeOfPromotedInstantiatorReceivesThatInstantiator() async {
		// Screen receives `nodeBuilder`, which the mock promotes. Child, built inside the Node it builds,
		// aliases `nodeBuilder`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: Dependency cycle: `Instantiator<Node>` -> `Child` -> `Instantiator<Node>`. `Child` receives `nodeBuilder: Instantiator<Node>` as `childBuilder: Instantiator<Node>` inside the tree that `nodeBuilder` builds. Declare `childBuilder: Instantiator<Node>` on `Child` as @Instantiated instead of @Received(fulfilledByDependencyNamed:ofType:).
				\(fixtures["Node.swift"]):1:1: note: `Node` is part of the cycle
				\(fixtures["Child.swift"]):1:1: note: `Child` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeListedInAdditionalMocksToGenerateAliasesInstantiatorThatBuildsIt() async throws {
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
		)
		let dependentModuleFixtures = dependentModuleOutput.fixtures

		await assertThrowsError(
			diagnostics: { _ in
				"""
				\(dependentModuleFixtures["Node.swift"]):4:5: error: Dependency cycle: `Instantiator<Node>` -> `Instantiator<Node>`. `Node` receives `nodeBuilder: Instantiator<Node>` as `childBuilder: Instantiator<Node>` inside the tree that `nodeBuilder` builds. Declare `childBuilder: Instantiator<Node>` on `Node` as @Instantiated instead of @Received(fulfilledByDependencyNamed:ofType:).
				\(dependentModuleFixtures["Node.swift"]):1:1: note: `Node` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalMocksToGenerate: [
					        "Node",
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
	mutating func mock_throwsReceivedCycleError_whenSiblingInstantiatorsOfMockRootReceiveEachOther() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<A>` -> @Received `bBuilder: Instantiator<B>` -> @Received `aBuilder: Instantiator<A>`. `aBuilder: Instantiator<A>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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
	mutating func mock_throwsReceivedCycleError_whenSiblingInstantiatorOfMockRootReceivesAliasOfAliasOfSiblingThatReceivesIt() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<A>` -> @Received `renamedAgainBBuilder: Instantiator<B>` -> @Received `aBuilder: Instantiator<A>`. `aBuilder: Instantiator<A>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, renamedBBuilder: Instantiator<B>, renamedAgainBBuilder: Instantiator<B>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let aBuilder: Instantiator<A>
					    @Instantiated let bBuilder: Instantiator<B>
					    @Received(fulfilledByDependencyNamed: "bBuilder", ofType: Instantiator<B>.self) let renamedBBuilder: Instantiator<B>
					    @Received(fulfilledByDependencyNamed: "renamedBBuilder", ofType: Instantiator<B>.self) let renamedAgainBBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(renamedAgainBBuilder: Instantiator<B>) { self.renamedAgainBBuilder = renamedAgainBBuilder }
					    @Received let renamedAgainBBuilder: Instantiator<B>
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
	mutating func mock_throwsAliasCycleError_whenAliasesOfMockRootFulfillEachOther() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Parent.swift"]):8:5: error: Dependency cycle: each @Received(fulfilledByDependencyNamed:ofType:) dependency is fulfilled by the next: `y: X` -> `x: X` -> `y: X`. Change one of them to be fulfilled by a property outside this cycle.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(y: X, x: X) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received(fulfilledByDependencyNamed: "x", ofType: X.self) let y: X
					    @Received(fulfilledByDependencyNamed: "y", ofType: X.self) let x: X
					}

					public final class X {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsReceivedCycleError_whenChildOfMockRootReceivesAliasOfItself() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):4:5: error: Dependency cycle: @Instantiated `a: A` -> @Received `renamedA: A` -> @Received `a: A`. `a: A` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(a: A, renamedA: A) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let a: A
					    @Received(fulfilledByDependencyNamed: "a", ofType: A.self) let renamedA: A
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    public init(renamedA: A) { self.renamedA = renamedA }
					    @Received let renamedA: A
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
	mutating func mock_throwsReceivedCycleError_whenSiblingInstantiatorIsReceivedInsideLazyCycleOfEarlierSibling() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):8:5: error: Dependency cycle: @Instantiated `qBuilder: Instantiator<Q>` -> @Received `bBuilder: Instantiator<B>` -> @Received `qBuilder: Instantiator<Q>`. `qBuilder: Instantiator<Q>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsReceivedCycleError_whenOptionalReceiveOfSiblingIsRequiredBySiblingThatReceivesIt() async {
		// `user` is built with `x`, received as `X?` from the unwrapped `x: X`, which is built with `user`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["X.swift"]):4:5: error: Dependency cycle: @Instantiated `user: User` -> @Received `x: X?` -> @Received `user: User`. `user: User` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(user: User, x: X) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let user: User
					    @Instantiated let x: X
					}
					""",
					"""
					@Instantiable
					public final class User: Instantiable {
					    public init(x: X?) { self.x = x }
					    @Received let x: X?
					}
					""",
					"""
					@Instantiable
					public final class X: Instantiable {
					    public init(user: User) { self.user = user }
					    @Received let user: User
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
		// `A`'s mock promotes the `bBuilder` it receives, and then the `aBuilder` that `B` receives, so the chain starts
		// at `bBuilder`, which the mock's tree receives first.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):4:5: error: Dependency cycle: @Instantiated `bBuilder: Instantiator<B>` -> @Received `aBuilder: Instantiator<A>` -> @Received `bBuilder: Instantiator<B>`. `bBuilder: Instantiator<B>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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
				\(fixtures["B.swift"]):4:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<A>` -> @Received `bBuilder: Instantiator<B>` -> @Received `aBuilder: Instantiator<A>`. `aBuilder: Instantiator<A>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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
				\(fixtures["B.swift"]):4:5: error: Dependency cycle: @Instantiated `a: A` -> @Received `b: B` -> @Received `a: A`. `a: A` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
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
				\(fixtures["Parent.swift"]):4:5: error: `child: Child` on `Parent` cannot build `Child`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<Child>`.
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
	mutating func mock_throwsErrorOfEveryTypeInSourceOrder_whenManyTypesWithGeneratedMocksHaveCycles() async {
		// Every one of the 200 types whose mock is generated is in its own cycle. Their scopes
		// hash by object identity, so a set of them iterates in an order that changes from run
		// to run; every cycle is reported, in source order, whichever order validates them.
		let suffixes = (0..<200).map { index in
			String(repeating: "0", count: 3 - String(index).count) + String(index)
		}
		let swiftFileContent = suffixes.map { suffix in
			"""
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
				// Each type and its partner take ten lines.
				suffixes.enumerated().map { index, suffix in
					"""
					\(fixtures["Mock000.swift"]):\(10 * index + 4):5: error: Dependency cycle: `Partner\(suffix)` -> `Mock\(suffix)` -> `Partner\(suffix)`. SafeDI accepts a dependency cycle only if the dependency that closes it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change `partner: Partner\(suffix)` to an instantiator; SafeDI then reports any other dependency in the cycle that must change too.
					\(fixtures["Mock000.swift"]):\(10 * index + 6):1: note: `Partner\(suffix)` is part of the cycle
					\(fixtures["Mock000.swift"]):\(10 * index + 1):1: note: `Mock\(suffix)` is part of the cycle
					"""
				}.joined(separator: "\n")
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenSendableInstantiatorSubtreeReceivesInstantiatorMockCannotBuild() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>`, which the tree of `Screen` receives from outside it, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` as `SendableInstantiator<Child>` where it is declared and where it is received as `Instantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}

					public final class Child: Instantiable {}
					""",
					"""
					@Instantiable
					public final class Settings: Instantiable {
					    public init(childBuilder: Instantiator<Child>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let childBuilder: Instantiator<Child>
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
	mutating func mock_throwsError_whenSendableInstantiatorSubtreeReceivesInstantiatorPromotedToMockRoot() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Screen -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `Screen` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>`, which the tree of `Screen` receives from outside it, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` as `SendableInstantiator<Child>` where it is declared and where it is received as `Instantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let childBuilder: Instantiator<Child>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Settings: Instantiable {
					    public init(childBuilder: Instantiator<Child>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let childBuilder: Instantiator<Child>
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
	mutating func mock_throwsError_whenTypeInTreeOfPromotedOptionalInstantiatorRequiresOnlyIfAvailableAliasOfIt() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):7:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<A>?` -> @Received `aBuilderAlias: Instantiator<A>?` -> @Received `aBuilder: Instantiator<A>?`. `aBuilder: Instantiator<A>?` is received while it is still being instantiated. `aBuilderAlias: Instantiator<A>?` renames `aBuilder: Instantiator<A>` only if available, so a type that receives `aBuilderAlias` without `onlyIfAvailable` must be built after `aBuilder: Instantiator<A>`. Receive `aBuilderAlias` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `aBuilder: Instantiator<A>` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(aBuilder: Instantiator<A>?) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let aBuilder: Instantiator<A>?
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    public init(b: B) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(aBuilderAlias: Instantiator<A>?, c: C) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received(fulfilledByDependencyNamed: "aBuilder", ofType: Instantiator<A>.self, onlyIfAvailable: true) let aBuilderAlias: Instantiator<A>?
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(aBuilderAlias: Instantiator<A>?) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let aBuilderAlias: Instantiator<A>?
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
	mutating func mock_throwsError_whenTypeInTreeOfPromotedInstantiatorRequiresOnlyIfAvailableAliasOfIt() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):7:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<A>` -> @Received `aBuilderAlias: Instantiator<A>?` -> @Received `aBuilder: Instantiator<A>`. `aBuilder: Instantiator<A>` is received while it is still being instantiated. `aBuilderAlias: Instantiator<A>?` renames `aBuilder: Instantiator<A>` only if available, so a type that receives `aBuilderAlias` without `onlyIfAvailable` must be built after `aBuilder: Instantiator<A>`. Receive `aBuilderAlias` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `aBuilder: Instantiator<A>` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(aBuilder: Instantiator<A>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let aBuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    public init(b: B) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(aBuilderAlias: Instantiator<A>?, c: C) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received(fulfilledByDependencyNamed: "aBuilder", ofType: Instantiator<A>.self, onlyIfAvailable: true) let aBuilderAlias: Instantiator<A>?
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(aBuilderAlias: Instantiator<A>?) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let aBuilderAlias: Instantiator<A>?
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
	mutating func mock_throwsErrorAtDeclaration_whenGeneratedMockRootDeclaresErasedInstantiatorWithIncorrectFirstGeneric() async {
		// Parent is not a root, so only its generated mock builds `childBuilder`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Parent.swift"]):7:5: error: The first generic argument of `childBuilder: ErasedInstantiator<Int, AnyChild>` on `Parent` must be the @Forwarded properties of `Child`, which it builds. Declare it as `ErasedInstantiator<String, AnyChild>`.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Parent: Instantiable {
					    public init(childBuilder: ErasedInstantiator<Int, AnyChild>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<Int, AnyChild>
					}
					""",
					"""
					public final class AnyChild {
					    public init(_ child: Child) {}
					}

					@Instantiable
					public final class Child: Instantiable {
					    public init(name: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

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
	mutating func mock_throwsErrorAtDeclaration_whenTypeBelowAdditionalMockRootDeclaresErasedInstantiatorWithIncorrectFirstGeneric() async {
		// Screen's mock exists only because it is listed in additionalMocksToGenerate, and only that mock builds Header.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Header.swift"]):7:5: error: The first generic argument of `titleBuilder: SendableErasedInstantiator<String, AnyTitle>` on `Header` must be the @Forwarded properties of `Title`, which it builds. Declare it as `SendableErasedInstantiator<(subtitle: String, text: String), AnyTitle>`.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(additionalMocksToGenerate: ["Screen"])
					""",
					"""
					@Instantiable
					public final class Screen: Instantiable {
					    public init(header: Header) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let header: Header
					}
					""",
					"""
					@Instantiable
					public final class Header: Instantiable {
					    public init(titleBuilder: SendableErasedInstantiator<String, AnyTitle>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Title", erasedToConcreteExistential: true) let titleBuilder: SendableErasedInstantiator<String, AnyTitle>
					}
					""",
					"""
					public final class AnyTitle: Sendable {
					    public init(_ title: Title) {}
					}

					@Instantiable
					public final class Title: Instantiable, Sendable {
					    public init(text: String, subtitle: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let text: String
					    @Forwarded let subtitle: String
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
	mutating func mock_throwsError_whenTreeOfTypeReceivedByValueReceivesItsInstantiator_andTypeSortsBeforeInstantiator() async {
		// Consumer receives `x: Abc`, and the Inner that Abc instantiates receives `x: Instantiator<Abc>`. The mock
		// builds both forms, and the Abc that the Instantiator builds needs that Instantiator.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Inner.swift"]):4:5: error: Dependency cycle: `Instantiator<Abc>` -> `Inner` -> `Instantiator<Abc>`. `Inner` receives `x: Instantiator<Abc>` inside the tree that `x` builds. Declare `x: Instantiator<Abc>` on `Inner` as @Instantiated instead of @Received.
				\(fixtures["Abc.swift"]):1:1: note: `Abc` is part of the cycle
				\(fixtures["Inner.swift"]):1:1: note: `Inner` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTreeOfTypeReceivedByValueReceivesItsInstantiator_andTypeSortsAfterInstantiator() async {
		// The graph of the test above with `Abc` renamed to `Xyz`, which sorts after `Instantiator<Xyz>`. The
		// error is the same, with the type renamed.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Inner.swift"]):4:5: error: Dependency cycle: `Instantiator<Xyz>` -> `Inner` -> `Instantiator<Xyz>`. `Inner` receives `x: Instantiator<Xyz>` inside the tree that `x` builds. Declare `x: Instantiator<Xyz>` on `Inner` as @Instantiated instead of @Received.
				\(fixtures["Xyz.swift"]):1:1: note: `Xyz` is part of the cycle
				\(fixtures["Inner.swift"]):1:1: note: `Inner` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenReceiverRequiresOnlyIfAvailableAliasOfOptionalFormOfSiblingThatReceivesTheReceiversAncestorAndMockRootPromotesTheAliasProperty() async {
		// Parent.mock() builds `b`, `x`, and the promoted `y: X`. D requires C's `onlyIfAvailable` alias `y` of `x: X?`, so
		// where `x` cannot be built before `b` (X requires `b`), D is handed the promoted `y`, which must then be built
		// before `b`; but it requires `b`. Parent is not a root, so only the mock tree is validated.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["D.swift"]):4:5: error: Dependency cycle: @Instantiated `y: X` -> @Received `b: B` -> @Received `y: X?` -> @Received `y: X`. `y: X` is received while it is still being instantiated. `y: X?` renames `x: X?` only if available, and an enclosing type declares `y: X`, so a type that receives `y` without `onlyIfAvailable` is handed `y: X` where `x: X?` cannot be built first and must be built after it. Receive `y` with `@Received(onlyIfAvailable: true)` to be passed `nil` where neither can be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Parent: Instantiable {
					    public init(b: B, x: X, y: X) { self.b = b; self.x = x; self.y = y }
					    @Instantiated let b: B
					    @Instantiated let x: X
					    @Received let y: X
					}
					""",
					"""
					@Instantiable
					public final class X: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(y: X?, d: D) { self.y = y; self.d = d }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let y: X?
					    @Instantiated let d: D
					}
					""",
					"""
					@Instantiable
					public final class D: Instantiable {
					    public init(y: X?) { self.y = y }
					    @Received let y: X?
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
	mutating func mock_throwsError_whenReceiverRequiresOnlyIfAvailableAliasOfOnlyIfAvailableAliasOfOptionalFormOfSiblingThatReceivesTheReceiversAncestorAndMockRootPromotesTheSecondAliasProperty() async {
		// Parent.mock() builds `b`, `x`, and the promoted `z: X`. D requires E's `onlyIfAvailable` alias `z` of C's
		// `onlyIfAvailable` alias `y` of `x: X?`, so where `y` is not created, D is handed the promoted `z`, which must
		// then be built before `b`; but it requires `b`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["D.swift"]):4:5: error: Dependency cycle: @Instantiated `z: X` -> @Received `b: B` -> @Received `z: X?` -> @Received `z: X`. `z: X` is received while it is still being instantiated. `z: X?` renames `y: X?` only if available, and an enclosing type declares `z: X`, so a type that receives `z` without `onlyIfAvailable` is handed `z: X` where `y: X?` cannot be built first and must be built after it. Receive `z` with `@Received(onlyIfAvailable: true)` to be passed `nil` where neither can be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Parent: Instantiable {
					    public init(b: B, x: X, z: X) { self.b = b; self.x = x; self.z = z }
					    @Instantiated let b: B
					    @Instantiated let x: X
					    @Received let z: X
					}
					""",
					"""
					@Instantiable
					public final class X: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(y: X?, e: E) { self.y = y; self.e = e }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let y: X?
					    @Instantiated let e: E
					}
					""",
					"""
					@Instantiable
					public final class E: Instantiable {
					    public init(z: X?, d: D) { self.z = z; self.d = d }
					    @Received(fulfilledByDependencyNamed: "y", ofType: X?.self, onlyIfAvailable: true) let z: X?
					    @Instantiated let d: D
					}
					""",
					"""
					@Instantiable
					public final class D: Instantiable {
					    public init(z: X?) { self.z = z }
					    @Received let z: X?
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
	mutating func mock_throwsError_whenReceiverRequiresOnlyIfAvailableAliasOfOptionalFormOfSiblingThatReceivesTheReceiversAncestorAndMockRootDeclaresTheAliasPropertyAsRequiredAliasOfTheSibling() async {
		// Parent.mock() builds `b` and `x` and assigns `y: X` from `x`. D requires C's `onlyIfAvailable` alias `y` of
		// `x: X?`, so where `x` cannot be built before `b` (X requires `b`), D is handed Parent's `y`, which must then be
		// built before `b`; but it is assigned from `x`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["X.swift"]):4:5: error: Dependency cycle: @Instantiated `b: B` -> @Received `y: X?` -> @Received `b: B`. `b: B` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Parent: Instantiable {
					    public init(b: B, x: X, y: X) { self.b = b; self.x = x; self.y = y }
					    @Instantiated let b: B
					    @Instantiated let x: X
					    @Received(fulfilledByDependencyNamed: "x", ofType: X.self) let y: X
					}
					""",
					"""
					@Instantiable
					public final class X: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(y: X?, d: D) { self.y = y; self.d = d }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let y: X?
					    @Instantiated let d: D
					}
					""",
					"""
					@Instantiable
					public final class D: Instantiable {
					    public init(y: X?) { self.y = y }
					    @Received let y: X?
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete = [URL]()
}
