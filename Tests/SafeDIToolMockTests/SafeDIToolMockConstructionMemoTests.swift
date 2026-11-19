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
import Testing
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The mock roots of a module share one construction memo: a place a mock root built is reused by a later mock root
/// that reaches the same place. Every test here runs the module three ways, with the memo shared between mock roots,
/// with it shared and the mock roots built in reverse order, and with no memo, and expects the same diagnostics or
/// mocks each time; `executeSafeDIToolTest` also builds every tree with the memo and without it and compares them by
/// reflection, so a reused place that holds what another path would not fails each test.
struct SafeDIToolMockConstructionMemoTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: [
		// `P` fails first, in the middle and last of the mock roots, which are built in type order.
		["Q", "R"],
		["N", "Q"],
		["M", "N"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_reportsSameErrorWithMemoAsWithout_whenMockRootFailingAfterItsConstructionSharesSubtreesWithOtherMockRoots(otherMockRootNames: [String]) async {
		// `P`'s mock builds `A`, whose label `x` no one cycle parameter can carry (`unpassableCycleLabel`), which is
		// thrown after its tree is built, so the places of `G`'s subtree it built are kept and the other roots reuse them.
		let fixture = [
			Self.mockedType(named: "P", declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let g: G"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: LazilyInstantiated<X>.self, onlyIfAvailable: true) let lazyX: LazilyInstantiated<X>?"#]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "G", isFinalClass: true, declarations: ["@Instantiated let h: H", "@Instantiated let kBuilder: Instantiator<K>"]),
			seamFixtureType(named: "H", isFinalClass: true, declarations: ["@Instantiated let k: K"]),
			seamFixtureType(named: "K", isFinalClass: true, declarations: []),
		] + otherMockRootNames.map { Self.mockedType(named: $0, declarations: ["@Instantiated let g: G"]) }
		for setting in MemoSetting.allCases {
			await assertThrowsError(diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):7:5: error: @Received property `x: LazilyInstantiated<X>` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: LazilyInstantiated<X>` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: LazilyInstantiated<X>` and `x: X?`, which one value cannot carry together. Receive `x: LazilyInstantiated<X>` and `x: X?` under different labels to fix.
				\(fixtures["S.swift"]):8:5: note: `x: LazilyInstantiated<X>` is declared here
				"""
			}) {
				try await setting.run { [fixture] in
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
		}
	}

	@Test(arguments: [
		// `P` fails first, in the middle and last of the mock roots, which are built in type order.
		["Q", "R"],
		["N", "Q"],
		["M", "N"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_reportsSameErrorWithMemoAsWithout_whenMockRootThrowsDuringItsConstruction(otherMockRootNames: [String]) async {
		// `P`'s construction throws, which ends the mock pass, so no later mock root reads what the memo kept before it.
		let fixture = [
			Self.mockedType(named: "P", declarations: [#"@Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<Int, AnyChild>"#, "@Instantiated let g: G"]),
			"""
			public final class AnyChild {
			    public init(_ child: Child) {}
			}
			""",
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Forwarded let name: String"]),
			seamFixtureType(named: "G", isFinalClass: true, declarations: ["@Instantiated let h: H"]),
			seamFixtureType(named: "H", isFinalClass: true, declarations: []),
		] + otherMockRootNames.map { Self.mockedType(named: $0, declarations: ["@Instantiated let g: G"]) }
		for setting in MemoSetting.allCases {
			await assertThrowsError(diagnostics: { fixtures in
				"""
				\(fixtures["P.swift"]):8:5: error: The first generic argument of `childBuilder: ErasedInstantiator<Int, AnyChild>` on `P` must be the @Forwarded properties of `Child`, which it builds. Declare it as `ErasedInstantiator<String, AnyChild>`.
				"""
			}) {
				try await setting.run { [fixture] in
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
		}
	}

	@Test(arguments: [
		// `P1` reaches `S` directly and `P2` through `X`, each first in turn.
		["P1", "P2"],
		["P2", "P1"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesSameMocksWithMemoAsWithout_whenTwoPublicMocksReachTypeWithHoleByDifferentPaths(names: [String]) async throws {
		// `S` instantiates `api: any Api`, which nothing fulfills, so each public mock's tree holds a place there, whose
		// hole stack is the path from the mock's root. A place holding it is stored in no memo.
		let fixture = [
			"public protocol Api {}",
			seamFixtureType(named: "S", declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "X", declarations: ["@Instantiated public let s: S"]),
			Self.publicMockedType(named: names[0], declarations: ["@Instantiated public let s: S"]),
			Self.publicMockedType(named: names[1], declarations: ["@Instantiated public let x: X"]),
		]
		try await expectSameMocksInEverySetting(of: fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesSameMockWithMemoAsWithout_whenPublicMockReachesTypeWithHoleByTwoPaths() async throws {
		// `P` reaches `S`, whose `api` is a place, as its own child and beneath `X`: two places, two hole stacks.
		let fixture = [
			"public protocol Api {}",
			seamFixtureType(named: "S", declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "X", declarations: ["@Instantiated public let s: S"]),
			Self.publicMockedType(named: "P", declarations: ["@Instantiated public let s: S", "@Instantiated public let x: X"]),
		]
		try await expectSameMocksInEverySetting(of: fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesSameMockWithMemoAsWithout_whenPublicMockReachesTypeWithHoleByTwoPathsAndMockConditionIsOff() async throws {
		// As above, compiled without `DEBUG`, the module's mock condition, so the generated mocks are compiled out.
		let fixture = [
			"public protocol Api {}",
			seamFixtureType(named: "S", declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "X", declarations: ["@Instantiated public let s: S"]),
			Self.publicMockedType(named: "P", declarations: ["@Instantiated public let s: S", "@Instantiated public let x: X"]),
		]
		try await expectSameMocksInEverySetting(of: fixture, verificationCompilationConditions: [])
	}

	@Test(arguments: [
		// `B` pins a receive of its own, so both mock roots' declarations hold a receive passed `nil`, and only the read of
		// `Inner`'s receive tells their places of `Inner` apart.
		true,
		// `B` declares nothing of `token`, so `Inner`'s receive is merely unavailable there, and the mock roots' places of `Inner`
		// differ in whether any receive is passed `nil` too.
		false,
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsEachMockRootsOwnPlace_whenMockRootsDifferOnlyInReceivePassedNil(secondRootPinsReceiveOfItsOwn: Bool) async throws {
		// `A` and `B` both build `Inner`, which receives `token: Token?` only if available. `A` requires
		// `token: Instantiator<Token>` above it, which pins the one declaration both read, so `A`'s mock passes `Inner` `nil`
		// (`NearestDeclarations.binding(_:passingNilTo:)`), at both of its places; `B` requires `token: Token`, which its mock
		// binds and `Inner` reads. Built first, `A`'s place of `Inner` must not hand `B` a generator that passes `nil`, nor
		// `B`'s hand `A` one that reads `token`; `A`'s second place of `Inner`, beneath `Holder`, reuses its first.
		var fixture = [
			seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let token: Token?"]),
			seamFixtureType(named: "Holder", isFinalClass: true, declarations: ["@Instantiated let inner: Inner"]),
			Self.mockedType(named: "A", declarations: ["@Received let token: Instantiator<Token>", "@Instantiated let inner: Inner", "@Instantiated let holder: Holder"]),
		]
		if secondRootPinsReceiveOfItsOwn {
			fixture += [
				seamFixtureType(named: "Other", isFinalClass: true, declarations: []),
				seamFixtureType(named: "InnerOther", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let other: Other?"]),
				Self.mockedType(named: "B", declarations: ["@Received let token: Token", "@Received let other: Instantiator<Other>", "@Instantiated let inner: Inner", "@Instantiated let innerOther: InnerOther"]),
			]
		} else {
			fixture.append(Self.mockedType(named: "B", declarations: ["@Instantiated let inner: Inner"]))
		}
		var mocksBySetting = [[String: String]]()
		for setting in MemoSetting.allCases {
			let output = try await setting.run { [fixture] in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
			mocksBySetting.append(output.mockFiles)
		}
		for mocks in mocksBySetting {
			#expect(mocks["A+SafeDIMock.swift"] == """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            inner: ((Token?) -> Inner)? = nil,
			            holder: Holder.SafeDIMockConfiguration = .init(),
			            token: (() -> Token)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                inner: inner,
			                holder: holder,
			                token: token
			            )
			        }

			        var inner: ((Token?) -> Inner)? { __safeDI_storage.inner }
			        var holder: Holder.SafeDIMockConfiguration { __safeDI_storage.holder }
			        var token: (() -> Token)? { __safeDI_storage.token }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                inner: ((Token?) -> Inner)?,
			                holder: Holder.SafeDIMockConfiguration,
			                token: (() -> Token)?
			            ) {
			                self.inner = inner
			                self.holder = holder
			                self.token = token
			            }

			            let inner: ((Token?) -> Inner)?
			            let holder: Holder.SafeDIMockConfiguration
			            let token: (() -> Token)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let inner = if let safeDIBuilder = safeDIOverrides.inner { safeDIBuilder(nil) } else { Inner(token: nil) }
			        func __safeDI_holder() -> Holder {
			            let inner = if let safeDIBuilder = safeDIOverrides.holder.inner { safeDIBuilder(nil) } else { Inner(token: nil) }
			            return if let safeDIBuilder = safeDIOverrides.holder.safeDIBuilder { safeDIBuilder(inner) } else { Holder(inner: inner) }
			        }
			        let holder: Holder = __safeDI_holder()
			        func __safeDI_token() -> Token {
			            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
			        }
			        let token = Instantiator<Token>(__safeDI_token)
			        return A(token: token, inner: inner, holder: holder)
			    }
			}
			#endif
			""")
			if secondRootPinsReceiveOfItsOwn {
				#expect(mocks["B+SafeDIMock.swift"] == """
				// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
				// Any modifications made to this file will be overwritten on subsequent builds.
				// Please refrain from editing this file directly.

				#if DEBUG
				extension B {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            token: (() -> Token)? = nil,
				            inner: ((Token?) -> Inner)? = nil,
				            innerOther: ((Other?) -> InnerOther)? = nil,
				            other: (() -> Other)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                token: token,
				                inner: inner,
				                innerOther: innerOther,
				                other: other
				            )
				        }

				        var token: (() -> Token)? { __safeDI_storage.token }
				        var inner: ((Token?) -> Inner)? { __safeDI_storage.inner }
				        var innerOther: ((Other?) -> InnerOther)? { __safeDI_storage.innerOther }
				        var other: (() -> Other)? { __safeDI_storage.other }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                token: (() -> Token)?,
				                inner: ((Token?) -> Inner)?,
				                innerOther: ((Other?) -> InnerOther)?,
				                other: (() -> Other)?
				            ) {
				                self.token = token
				                self.inner = inner
				                self.innerOther = innerOther
				                self.other = other
				            }

				            let token: (() -> Token)?
				            let inner: ((Token?) -> Inner)?
				            let innerOther: ((Other?) -> InnerOther)?
				            let other: (() -> Other)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
				        let inner = if let safeDIBuilder = safeDIOverrides.inner { safeDIBuilder(token) } else { Inner(token: token) }
				        let innerOther = if let safeDIBuilder = safeDIOverrides.innerOther { safeDIBuilder(nil) } else { InnerOther(other: nil) }
				        func __safeDI_other() -> Other {
				            if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder() } else { Other() }
				        }
				        let other = Instantiator<Other>(__safeDI_other)
				        return B(token: token, other: other, inner: inner, innerOther: innerOther)
				    }
				}
				#endif
				""")
			} else {
				#expect(mocks["B+SafeDIMock.swift"] == """
				// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
				// Any modifications made to this file will be overwritten on subsequent builds.
				// Please refrain from editing this file directly.

				#if DEBUG
				extension B {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            inner: ((Token?) -> Inner)? = nil,
				            token: Token? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                inner: inner
				            )
				            self.token = token
				        }

				        var inner: ((Token?) -> Inner)? { __safeDI_storage.inner }
				        let token: Token?

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                inner: ((Token?) -> Inner)?
				            ) {
				                self.inner = inner
				            }

				            let inner: ((Token?) -> Inner)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> B {
				        let token: Token? = safeDIOverrides.token
				        let inner = if let safeDIBuilder = safeDIOverrides.inner { safeDIBuilder(token) } else { Inner(token: token) }
				        return B(inner: inner)
				    }
				}
				#endif
				""")
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsEachMockRootsOwnPlace_whenOnlyOneMockRootPassesNilToReceiveItAlsoBindsForAnotherReceiver() async throws {
		// `A`'s `Wrapper` requires `token: Instantiator<Token>` above `Inner`, which pins the one declaration `Inner` reads, so
		// `A`'s mock passes `Inner` `nil`; `U`, beside `Wrapper`, receives `token: Token?` unpinned, so `A`'s mock binds that
		// form too, as `B`'s binds it for its own `Inner`. Both places of `Inner` read the same binding of `token: Token?`;
		// only `A`'s declarations hold a receive passed `nil`, which the memo's key tells apart, so `B`'s place, built first
		// in reverse order, is not reused by `A`.
		let fixture = [
			seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let token: Token?"]),
			seamFixtureType(named: "U", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let token: Token?"]),
			seamFixtureType(named: "Wrapper", isFinalClass: true, declarations: ["@Received let token: Instantiator<Token>", "@Instantiated let inner: Inner"]),
			Self.mockedType(named: "A", declarations: ["@Instantiated let wrapper: Wrapper", "@Instantiated let u: U"]),
			Self.mockedType(named: "B", declarations: ["@Instantiated let inner: Inner"]),
		]
		var mocksBySetting = [[String: String]]()
		for setting in MemoSetting.allCases {
			let output = try await setting.run { [fixture] in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
			mocksBySetting.append(output.mockFiles)
		}
		for mocks in mocksBySetting {
			#expect(mocks["A+SafeDIMock.swift"] == """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            token: (() -> Token)? = nil,
			            wrapper: Wrapper.SafeDIMockConfiguration = .init(),
			            u: ((Token?) -> U)? = nil,
			            token_Token: Token? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                wrapper: wrapper,
			                u: u
			            )
			            self.token_Token = token_Token
			        }

			        var token: (() -> Token)? { __safeDI_storage.token }
			        var wrapper: Wrapper.SafeDIMockConfiguration { __safeDI_storage.wrapper }
			        var u: ((Token?) -> U)? { __safeDI_storage.u }
			        let token_Token: Token?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: (() -> Token)?,
			                wrapper: Wrapper.SafeDIMockConfiguration,
			                u: ((Token?) -> U)?
			            ) {
			                self.token = token
			                self.wrapper = wrapper
			                self.u = u
			            }

			            let token: (() -> Token)?
			            let wrapper: Wrapper.SafeDIMockConfiguration
			            let u: ((Token?) -> U)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let token_Token: Token? = safeDIOverrides.token_Token
			        func __safeDI_token() -> Token {
			            if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
			        }
			        let token = Instantiator<Token>(__safeDI_token)
			        func __safeDI_wrapper() -> Wrapper {
			            let inner = if let safeDIBuilder = safeDIOverrides.wrapper.inner { safeDIBuilder(nil) } else { Inner(token: nil) }
			            return if let safeDIBuilder = safeDIOverrides.wrapper.safeDIBuilder { safeDIBuilder(token, inner) } else { Wrapper(token: token, inner: inner) }
			        }
			        let wrapper: Wrapper = __safeDI_wrapper()
			        func __safeDI_u() -> U {
			            let token: Token? = token_Token
			            return if let safeDIBuilder = safeDIOverrides.u { safeDIBuilder(token) } else { U(token: token) }
			        }
			        let u: U = __safeDI_u()
			        return A(wrapper: wrapper, u: u)
			    }
			}
			#endif
			""")
			#expect(mocks["B+SafeDIMock.swift"] == """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            inner: ((Token?) -> Inner)? = nil,
			            token: Token? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                inner: inner
			            )
			            self.token = token
			        }

			        var inner: ((Token?) -> Inner)? { __safeDI_storage.inner }
			        let token: Token?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                inner: ((Token?) -> Inner)?
			            ) {
			                self.inner = inner
			            }

			            let inner: ((Token?) -> Inner)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        let token: Token? = safeDIOverrides.token
			        let inner = if let safeDIBuilder = safeDIOverrides.inner { safeDIBuilder(token) } else { Inner(token: token) }
			        return B(inner: inner)
			    }
			}
			#endif
			""")
		}
	}

	// MARK: Private

	/// How the module's mock roots share the construction memo.
	private enum MemoSetting: CaseIterable {
		case shared
		case sharedInReverseOrder
		/// Shared by a drawn schedule: each lookup builds again or asks its candidates in a drawn order.
		case sharedByDrawnSchedule
		/// Shared from a discarded build of each first pass, newest candidate first, and by a drawn schedule.
		case sharedWithLaterPlacesCandidates
		case off

		func run<T>(_ body: () async throws -> T) async throws -> T {
			switch self {
			case .shared:
				try await body()
			case .sharedInReverseOrder:
				try await ConstructionMemoOracle.$buildsMockRootsInReverseOrder.withValue(true) { try await body() }
			case .sharedByDrawnSchedule:
				try await ConstructionSharingSchedule.$current.withValue(ConstructionSharingSchedule(seed: 7, offersLaterPlacesCandidates: false)) { try await body() }
			case .sharedWithLaterPlacesCandidates:
				try await ConstructionSharingSchedule.$current.withValue(ConstructionSharingSchedule(seed: 11, offersLaterPlacesCandidates: true)) { try await body() }
			case .off:
				try await ConstructionMemo.$isEnabled.withValue(false) { try await body() }
			}
		}
	}

	private var filesToDelete: [URL]

	/// Expects `fixture`'s mocks to be the same in every `MemoSetting`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectSameMocksInEverySetting(of fixture: [String], verificationCompilationConditions: [String]? = nil) async throws {
		var mocksBySetting = [[String: String]]()
		for setting in MemoSetting.allCases {
			let output = try await setting.run { [fixture] in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, verificationCompilationConditions: verificationCompilationConditions)
			}
			mocksBySetting.append(output.mockFiles)
		}
		#expect(!mocksBySetting[0].isEmpty)
		for mocks in mocksBySetting.dropFirst() {
			#expect(mocks == mocksBySetting[0])
		}
	}

	/// A final class named `name` whose mock is generated.
	private static func mockedType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
	}

	/// A struct named `name` whose public mock is generated.
	private static func publicMockedType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")
	}
}
