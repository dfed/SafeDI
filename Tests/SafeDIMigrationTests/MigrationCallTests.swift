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
@testable import SafeDIMigration

struct MigrationCallTests {
	// MARK: Created dependencies the mock cannot build

	@Test
	func migrate_wrapsParameterInBuilderReadingIt_whenArgumentIsParameterOfEnclosingFunction() {
		#expect(migratedText("""
		func calls(service: UserService) {
			_ = Banner.mock(userService: service)
		}
		""") == """
		func calls(service: UserService) {
			_ = Banner.fake(userService: { service })
		}
		""")
	}

	@Test
	func migrate_capturesExpressionOnce_whenArgumentIsExpression() {
		#expect(migratedText("""
		func calls() {
			_ = Banner.mock(userService: Live())
		}
		""") == """
		func calls() {
			_ = Banner.fake(userService: { [userService = Live()] in userService })
		}
		""")
	}

	@Test
	func migrate_capturesPropertyRatherThanSelf_whenArgumentIsPropertyReadThroughSelfImplicitly() {
		#expect(migratedText("""
		final class BannerTests {
			let spy = Spy()
			func test() {
				_ = Banner.mock(userService: spy)
			}
		}
		""") == """
		final class BannerTests {
			let spy = Spy()
			func test() {
				_ = Banner.fake(userService: { [userService = spy] in userService })
			}
		}
		""")
	}

	@Test
	func migrate_capturesValue_whenArgumentIsLocalVariable() {
		#expect(migratedText("""
		func calls() {
			var service = Live()
			_ = Banner.mock(userService: service)
		}
		""") == """
		func calls() {
			var service = Live()
			_ = Banner.fake(userService: { [userService = service] in userService })
		}
		""")
	}

	@Test
	func migrate_readsConstant_whenArgumentIsLocalLet() {
		#expect(migratedText("""
		func calls() {
			let service = Live()
			_ = Banner.mock(userService: service)
		}
		""") == """
		func calls() {
			let service = Live()
			_ = Banner.fake(userService: { service })
		}
		""")
	}

	@Test
	func migrate_readsConstant_whenArgumentIsGuardLetBinding() {
		#expect(migratedText("""
		func calls(service: UserService?) {
			guard let live = service else { return }
			_ = Banner.mock(userService: live)
		}
		""") == """
		func calls(service: UserService?) {
			guard let live = service else { return }
			_ = Banner.fake(userService: { live })
		}
		""")
	}

	@Test
	func migrate_capturesValue_whenArgumentIsGuardVarBinding() {
		#expect(migratedText("""
		func calls(service: UserService?) {
			guard var live = service else { return }
			_ = Banner.mock(userService: live)
		}
		""") == """
		func calls(service: UserService?) {
			guard var live = service else { return }
			_ = Banner.fake(userService: { [userService = live] in userService })
		}
		""")
	}

	@Test
	func migrate_readsConstant_whenArgumentIsIfLetBinding() {
		#expect(migratedText("""
		func calls(service: UserService?) {
			if let service {
				_ = Banner.mock(userService: service)
			}
		}
		""") == """
		func calls(service: UserService?) {
			if let service {
				_ = Banner.fake(userService: { service })
			}
		}
		""")
	}

	@Test
	func migrate_readsConstant_whenArgumentIsForLoopElement() {
		#expect(migratedText("""
		func calls(services: [UserService]) {
			for service in services {
				_ = Banner.mock(userService: service)
			}
		}
		""") == """
		func calls(services: [UserService]) {
			for service in services {
				_ = Banner.fake(userService: { service })
			}
		}
		""")
	}

	@Test
	func migrate_readsConstant_whenArgumentIsInitializerParameter() {
		#expect(migratedText("""
		struct Holder {
			init(service: UserService) {
				_ = Banner.mock(userService: service)
			}
		}
		""") == """
		struct Holder {
			init(service: UserService) {
				_ = Banner.fake(userService: { service })
			}
		}
		""")
	}

	@Test
	func migrate_readsConstant_whenArgumentIsShorthandClosureParameter() {
		#expect(migratedText("""
		let banners = services.map { service in Banner.mock(userService: service) }
		""") == """
		let banners = services.map { service in Banner.fake(userService: { service }) }
		""")
	}

	@Test
	func migrate_readsConstant_whenArgumentIsClosureParameterWithType() {
		#expect(migratedText("""
		let banners = services.map { (service: UserService) in Banner.mock(userService: service) }
		""") == """
		let banners = services.map { (service: UserService) in Banner.fake(userService: { service }) }
		""")
	}

	@Test
	func migrate_capturesValue_whenEnclosingClosureDeclaresOtherParameter() {
		#expect(migratedText("""
		let banners = services.map { other in Banner.mock(userService: service) }
		""") == """
		let banners = services.map { other in Banner.fake(userService: { [userService = service] in userService }) }
		""")
	}

	@Test
	func migrate_capturesValue_whenEnclosingClosureDeclaresNoParameters() {
		#expect(migratedText("""
		let make = { Banner.mock(userService: service) }
		""") == """
		let make = { Banner.fake(userService: { [userService = service] in userService }) }
		""")
	}

	@Test
	func migrate_evaluatesExpressionInBuilder_whenParameterIsSendableAutoclosure() {
		#expect(migratedText("""
		func calls() {
			_ = Profile.mock(name: "n", clock: clock, logger: Logger())
		}
		""") == """
		func calls() {
			_ = Profile.fake(name: "n", clock: clock, logger: { Logger() })
		}
		""")
	}

	@Test
	func migrate_capturesClosureAndReportsSite_whenDependencyTypeIsClosure() {
		let result = migrate("""
		func calls() {
			_ = Profile.mock(name: "n", clock: clock, handler: { makeHandler() })
		}
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		func calls() {
			_ = Profile.fake(name: "n", clock: clock, handler: { [handler = { makeHandler() }] in handler })
		}
		""")])
		#expect(result.findings == [
			finding(.closureTypedDependencyWrapped, line: 2, column: 6, #"Profile.mock(name: "n", clock: clock, handler: { makeHandler() })"#),
		])
	}

	@Test
	func migrate_escapesCaptureName_whenLabelIsKeyword() {
		#expect(migratedText("""
		func calls() {
			_ = Profile.mock(name: "n", clock: clock, default: Live())
		}
		""") == """
		func calls() {
			_ = Profile.fake(name: "n", clock: clock, default: { [`default` = Live()] in `default` })
		}
		""")
	}

	// MARK: The mocked type's own defaults

	@Test
	func migrate_movesOwnDefaultsIntoNewOverrides_whenCallPassesNoOverrides() {
		#expect(migratedText("""
		let banner = Banner.mock(retries: 1, note: "x", userService: service)
		""") == """
		let banner = Banner.fake(userService: { [userService = service] in userService }, safeDIOverrides: .init(note: "x", retries: 1))
		""")
	}

	@Test
	func migrate_movesOnlyArgument_whenOwnDefaultIsTheOnlyArgument() {
		#expect(migratedText("""
		let inner = Outer.Inner.mock(count: 2)
		""") == """
		let inner = Outer.Inner.fake(safeDIOverrides: .init(count: 2))
		""")
	}

	@Test
	func migrate_appendsOwnDefaultsAfterTreeFields_whenCallWritesOverridesLiteral() {
		#expect(migratedText("""
		let banner = Banner.mock(note: "x", userService: service, safeDIOverrides: Banner.SafeDIOverrides(badge: .init(label: "y")))
		""") == """
		let banner = Banner.fake(userService: { [userService = service] in userService }, safeDIOverrides: Banner.SafeDIOverrides(badge: .init(label: "y"), note: "x"))
		""")
	}

	@Test
	func migrate_appendsOwnDefaultsOnLinesOfTheirOwn_whenOverridesLiteralSpansLines() {
		#expect(migratedText("""
		let banner = Banner.mock(
			note: "Ends Friday",
			retries: 1,
			userService: service,
			safeDIOverrides: .init(
				badge: .init(label: nil),
			),
		)
		""") == """
		let banner = Banner.fake(
			userService: { [userService = service] in userService },
			safeDIOverrides: .init(
				badge: .init(label: nil),
				note: "Ends Friday",
				retries: 1,
			),
		)
		""")
	}

	@Test
	func migrate_addsOverridesOnLineOfItsOwn_whenCallSpansLines() {
		#expect(migratedText("""
		let banner = Banner.mock(
			note: "x",
			userService: service
		)
		""") == """
		let banner = Banner.fake(
			userService: { [userService = service] in userService },
			safeDIOverrides: .init(note: "x")
		)
		""")
	}

	@Test
	func migrate_appendsOwnDefaultToEmptyLiteral_whenOverridesLiteralIsEmpty() {
		#expect(migratedText("""
		let banner = Banner.mock(retries: 1, userService: service, safeDIOverrides: .init())
		""") == """
		let banner = Banner.fake(userService: { [userService = service] in userService }, safeDIOverrides: .init(retries: 1))
		""")
	}

	@Test
	func migrate_keepsOverridesAsWritten_whenOverridesLiteralNeedsNoChange() {
		#expect(migratedText("""
		let banner = Banner.mock(userService: service, safeDIOverrides: .init(badge: .init()))
		""") == """
		let banner = Banner.fake(userService: { [userService = service] in userService }, safeDIOverrides: .init(badge: .init()))
		""")
	}

	@Test
	func migrate_renamesOwnDefaultToFieldLabel_whenRoleFileGivesFieldLabel() {
		#expect(migratedText("""
		let profile = Profile.mock(name: "n", clock: clock, tint: .red)
		""") == """
		let profile = Profile.fake(name: "n", clock: clock, safeDIOverrides: .init(tint_Color: .red))
		""")
	}

	@Test
	func migrate_keepsOwnDefaultAndReportsSite_whenOverridesIsNotLiteral() {
		let result = migrate("""
		let banner = Banner.mock(note: "x", userService: service, safeDIOverrides: overrides)
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		let banner = Banner.fake(note: "x", userService: { [userService = service] in userService }, safeDIOverrides: overrides)
		""")])
		#expect(result.findings == [
			finding(.ownDefaultBesideNonLiteralOverrides, line: 1, column: 14, #"Banner.mock(note: "x", userService: service, safeDIOverrides: overrides)"#),
		])
	}

	@Test
	func migrate_reportsNothing_whenNonLiteralOverridesStandsAlone() {
		let result = migrate("""
		let banner = Banner.mock(userService: service, safeDIOverrides: overrides)
		""")
		#expect(result.findings == [])
	}

	// MARK: Public mocks

	@Test
	func migrate_dropsNilOwnDefault_whenPublicMockTakesNonOptionalDefault() {
		#expect(migratedText("""
		let panel = Panel.mock(id: 1, theme: nil, title: nil)
		""") == """
		let panel = Panel.fake(id: 1, safeDIOverrides: .init(title: nil))
		""")
	}

	@Test
	func migrate_wrapsReceivedValueAsInstance_whenPublicMockTakesItFlat() {
		#expect(migratedText("""
		let panel = Panel.mock(id: 1, session: session)
		""") == """
		let panel = Panel.fake(id: 1, session: .instance(session))
		""")
	}

	@Test
	func migrate_dropsReceivedNil_whenPublicMockIsPassedNilToBuildIt() {
		#expect(migratedText("""
		let panel = Panel.mock(id: 1, session: nil, rowBuilder: { Row() })
		""") == """
		let panel = Panel.fake(id: 1, rowBuilder: { Row() })
		""")
	}

	@Test
	func migrate_keepsBuildersAsWritten_whenMockTakesBuilders() {
		#expect(migratedText("""
		let panel = Panel.mock(id: 1, rowBuilder: { Row() }, serviceBuilder: { Service() })
		""") == """
		let panel = Panel.fake(id: 1, rowBuilder: { Row() }, serviceBuilder: { Service() })
		""")
	}

	// MARK: Received dependencies the mock builds

	@Test
	func migrate_movesOverrideToBuiltArgument_whenOverridesConfigureReceivedDependency() {
		#expect(migratedText("""
		let profile = Profile.mock(name: "n", clock: clock, safeDIOverrides: .init(user_Draft: .init(title: "t"), avatar: .init()))
		""") == """
		let profile = Profile.fake(name: "n", clock: clock, user: .built(.init(title: "t")), safeDIOverrides: .init(avatar: .init()))
		""")
	}

	@Test
	func migrate_dropsOverrides_whenOnlyFieldMovesToBuiltArgument() {
		#expect(migratedText("""
		let profile = Profile.mock(name: "n", clock: clock, safeDIOverrides: .init(user_Draft: .init()))
		""") == """
		let profile = Profile.fake(name: "n", clock: clock, user: .built(.init()))
		""")
	}

	@Test
	func migrate_movesOverrideToBuiltArgument_whenFieldValueNamesConfigurationType() {
		#expect(migratedText("""
		let profile = Profile.mock(name: "n", clock: clock, safeDIOverrides: .init(user_Draft: Draft.SafeDIMockConfiguration(title: "t")))
		""") == """
		let profile = Profile.fake(name: "n", clock: clock, user: .built(Draft.SafeDIFakeConfiguration(title: "t")))
		""")
	}

	@Test
	func migrate_keepsOverrideAndReportsSite_whenReceivedDependencyOverrideIsNotLiteral() {
		let result = migrate("""
		let profile = Profile.mock(name: "n", clock: clock, safeDIOverrides: .init(user_Draft: configuration))
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		let profile = Profile.fake(name: "n", clock: clock, safeDIOverrides: .init(user_Draft: configuration))
		""")])
		#expect(result.findings == [
			finding(.receivedBuildableOverrideNotLiteral, line: 1, column: 15, #"Profile.mock(name: "n", clock: clock, safeDIOverrides: .init(user_Draft: configuration))"#),
		])
	}

	@Test
	func migrate_movesClosureIntoBuiltConfiguration_whenReceivedDependencyOverrideIsClosure() {
		let result = migrate("""
		let profile = Profile.mock(name: "n", clock: clock, safeDIOverrides: .init(user_Draft: { title in Draft(title: title) }))
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		let profile = Profile.fake(name: "n", clock: clock, user: .built(.init({ title in Draft(title: title) })))
		""")])
		#expect(result.findings == [])
	}

	@Test
	func migrate_relabelsBuilderToPropertyLabel_whenRoleFileNamesFakeLabel() {
		#expect(migratedText("""
		let panel = Panel.mock(id: 1, rowBuilder: { Row() }, imageLoadingBuilder: { ImageLoader() })
		""") == """
		let panel = Panel.fake(id: 1, rowBuilder: { Row() }, imageLoader: { ImageLoader() })
		""")
	}

	@Test
	func migrate_keepsPlainValue_whenReceivedDependencyHasNothingToConfigure() {
		#expect(migratedText("""
		let panel = Panel.mock(id: 1, cache: cache)
		""") == """
		let panel = Panel.fake(id: 1, cache: cache)
		""")
	}

	@Test
	func migrate_callsOverrideClosureInPlace_whenReceivedDependencyHasNothingToConfigure() {
		#expect(migratedText("""
		let panel = Panel.mock(id: 1, safeDIOverrides: .init(cache: { Cache() }))
		""") == """
		let panel = Panel.fake(id: 1, cache: { Cache() }())
		""")
	}

	@Test
	func migrate_keepsOverrideAndReportsSite_whenReceivedDependencyWithNothingToConfigureHasLiteralOverride() {
		let result = migrate("""
		let panel = Panel.mock(id: 1, safeDIOverrides: .init(cache: .init()))
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		let panel = Panel.fake(id: 1, safeDIOverrides: .init(cache: .init()))
		""")])
		#expect(result.findings == [
			finding(.receivedBuildableOverrideNotLiteral, line: 1, column: 13, "Panel.mock(id: 1, safeDIOverrides: .init(cache: .init()))"),
		])
	}

	@Test
	func migrate_renamesOnlyAndReportsSite_whenReceivedDependencyIsPassedTwice() {
		let result = migrate("""
		let panel = Panel.mock(id: 1, session: session, safeDIOverrides: .init(session: .init()))
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		let panel = Panel.fake(id: 1, session: session, safeDIOverrides: .init(session: .init()))
		""")])
		#expect(result.findings == [
			finding(.receivedBuildablePassedTwice, line: 1, column: 13, "Panel.mock(id: 1, session: session, safeDIOverrides: .init(session: .init()))"),
		])
	}

	@Test
	func migrate_insertsBuiltArgumentBeforeOverridesOnLineOfItsOwn_whenCallSpansLines() {
		#expect(migratedText("""
		let profile = Profile.mock(
			name: "n",
			clock: clock,
			safeDIOverrides: .init(
				user_Draft: .init(),
				avatar: .init(),
			)
		)
		""") == """
		let profile = Profile.fake(
			name: "n",
			clock: clock,
			user: .built(.init()),
			safeDIOverrides: .init(
				avatar: .init(),
			)
		)
		""")
	}

	// MARK: Renames

	@Test
	func migrate_renamesCall_whenMockTakesNoParameters() {
		let result = migrate("let empty = Empty.mock()")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: "let empty = Empty.fake()")])
		#expect(result.editCounts == [.generatedMockCallRenamed: 1])
	}

	@Test
	func migrate_resolvesType_whenCallQualifiesItWithModule() {
		#expect(migratedText("""
		let banner = App.Banner.mock(note: "x", userService: service)
		""") == """
		let banner = App.Banner.fake(userService: { [userService = service] in userService }, safeDIOverrides: .init(note: "x"))
		""")
	}

	@Test
	func migrate_resolvesNestedType_whenCallSpellsItInsideEnclosingType() {
		#expect(migratedText("""
		extension Outer {
			static func inner() -> Inner { Inner.mock(count: 2) }
		}
		""") == """
		extension Outer {
			static func inner() -> Inner { Inner.fake(safeDIOverrides: .init(count: 2)) }
		}
		""")
	}

	@Test
	func migrate_resolvesEnclosingType_whenCallSpellsSelf() {
		#expect(migratedText("""
		extension Banner {
			static func preview() -> Banner {
				Self.mock(userService: Live())
			}
		}
		""") == """
		extension Banner {
			static func preview() -> Banner {
				Self.fake(userService: { [userService = Live()] in userService })
			}
		}
		""")
	}

	@Test
	func migrate_resolvesEnclosingType_whenCallIsBare() {
		#expect(migratedText("""
		extension Empty {
			static func preview() -> Empty { mock() }
		}
		""") == """
		extension Empty {
			static func preview() -> Empty { fake() }
		}
		""")
	}

	@Test
	func migrate_leavesCall_whenBareCallIsOutsideEveryType() {
		let result = migrate("let value = mock()")
		#expect(result.rewrittenFiles == [])
		#expect(result.findings == [])
	}

	@Test
	func migrate_leavesCall_whenSelfCallIsOutsideMockedType() {
		#expect(migrate("""
		extension Data {
			static func preview() -> Data { Self.mock() }
		}
		""").rewrittenFiles == [])
	}

	@Test
	func migrate_leavesCall_whenSelfIsOutsideEveryType() {
		#expect(migrate("let value = Self.mock()").rewrittenFiles == [])
	}

	@Test
	func migrate_leavesCall_whenTypeIsNoMockedType() {
		let result = migrate("let data = Data.mock()")
		#expect(result.rewrittenFiles == [])
		#expect(result.findings == [])
	}

	@Test
	func migrate_leavesCall_whenCalledMethodIsNotMock() {
		#expect(migrate("let banner = Banner.preview(note: 1)").rewrittenFiles == [])
	}

	@Test
	func migrate_resolvesImplicitMember_whenBindingWritesType() {
		let result = migrate("let implicit: Banner = .mock(userService: service)")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: "let implicit: Banner = .fake(userService: { [userService = service] in userService })")])
		#expect(result.editCounts[.implicitMemberResolvedFromWrittenType] == 1)
	}

	@Test
	func migrate_resolvesImplicitMember_whenBindingWritesOptionalType() {
		#expect(migratedText("let implicit: Empty? = .mock()") == "let implicit: Empty? = .fake()")
	}

	@Test
	func migrate_resolvesImplicitMember_whenBindingWritesImplicitlyUnwrappedType() {
		#expect(migratedText("var implicit: Empty! = .mock()") == "var implicit: Empty! = .fake()")
	}

	@Test
	func migrate_resolvesImplicitMember_whenParameterDefaultWritesType() {
		#expect(migratedText("func show(empty: Empty = .mock()) {}") == "func show(empty: Empty = .fake()) {}")
	}

	@Test
	func migrate_resolvesImplicitMember_whenFunctionReturnsIt() {
		#expect(migratedText("func make() -> Empty { .mock() }") == "func make() -> Empty { .fake() }")
	}

	@Test
	func migrate_resolvesImplicitMember_whenReturnStatementReturnsIt() {
		#expect(migratedText("""
		func make() -> Empty {
			print("made")
			return .mock()
		}
		""") == """
		func make() -> Empty {
			print("made")
			return .fake()
		}
		""")
	}

	@Test
	func migrate_resolvesImplicitMember_whenComputedPropertyReturnsIt() {
		#expect(migratedText("var empty: Empty { .mock() }") == "var empty: Empty { .fake() }")
	}

	@Test
	func migrate_leavesImplicitMember_whenWrittenTypeIsNoMockedType() {
		let result = migrate("let data: Data = .mock()")
		#expect(result.rewrittenFiles == [])
		#expect(result.findings == [])
	}

	@Test
	func migrate_renamesCallAndReportsSite_whenTwoModulesMockTypeOfThatName() {
		let result = migrate("let shared = Shared.mock()")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: "let shared = Shared.fake()")])
		#expect(result.findings == [finding(.ambiguousType, line: 1, column: 14, "Shared.mock()")])
	}

	@Test
	func migrate_renamesCallWithoutReport_whenModuleQualifierSettlesTypeTwoModulesMock() {
		let result = migrate("let shared = Feature.Shared.mock()")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: "let shared = Feature.Shared.fake()")])
		#expect(result.findings == [])
	}

	@Test
	func migrate_renamesHandWrittenMockCall_whenTypeDeclaresMockFoundByName() {
		let result = migrate(
			"let fake = Store.mock(items: [])",
			otherSources: [SourceFile(path: "Store.swift", text: """
			@Instantiable(mockOnly: true)
			extension Store {
				static func mock(items: [Item]) -> Store { Store(items: items) }
			}
			""")],
		)
		#expect(result.rewrittenFiles == [
			SourceFile(path: "Calls.swift", text: "let fake = Store.fake(items: [])"),
			SourceFile(path: "Store.swift", text: """
			@Instantiable(fakeOnly: true)
			extension Store {
				static func fake(items: [Item]) -> Store { Store(items: items) }
			}
			"""),
		])
		#expect(result.editCounts == [.handWrittenMockCallRenamed: 1, .attributeLabelRenamed: 1, .handWrittenMockDeclarationRenamed: 1])
	}

	@Test
	func migrate_keepsCustomMockNameMethod_whenDeclarationNamesIt() {
		let result = migrate("""
		@Instantiable(customMockName: "preview")
		final class Store: Instantiable {
			static func mock() -> Store { Store() }
			static func preview() -> Store { Store() }
		}
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		@Instantiable(customFakeName: "preview")
		final class Store: Instantiable {
			static func mock() -> Store { Store() }
			static func preview() -> Store { Store() }
		}
		""")])
	}

	@Test
	func migrate_keepsMockMethod_whenTypeIsNotInstantiable() {
		#expect(migrate("""
		struct Helper {
			static func mock() -> Helper { Helper() }
		}
		""").rewrittenFiles == [])
	}

	@Test
	func migrate_keepsInstanceMockMethod_whenMethodIsNotStatic() {
		#expect(migrate("""
		@Instantiable
		final class Store: Instantiable {
			func mock() {}
		}
		""").rewrittenFiles == [])
	}

	@Test
	func migrate_renamesHandWrittenMockOfEveryKindOfType_whenEachDeclaresMock() {
		let declarations = ["class", "struct", "actor", "enum"].map { kind in
			"""
			@Instantiable
			\(kind) \(kind.capitalized)Fake {
				static func mock() -> Self { Self() }
			}
			"""
		}.joined(separator: "\n")
		#expect(migratedText(declarations) == declarations.replacingOccurrences(of: "func mock", with: "func fake"))
	}

	// MARK: Order of arguments (THREE-ZERO 2.1)

	@Test
	func migrate_ordersArgumentsAsRoleFileListsParameters_whenOptionOrdersByRoleFile() {
		let result = migrate(
			"let profile = Profile.mock(name: \"n\", logger: log, clock: clock)",
			options: MigrationOptions(ordersArgumentsByRoleFile: true),
		)
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: "let profile = Profile.fake(name: \"n\", clock: clock, logger: { log })")])
		#expect(result.editCounts[.argumentsReordered] == 1)
	}

	@Test
	func migrate_countsNoReorder_whenArgumentsAlreadyFollowRoleFile() {
		let result = migrate(
			"let profile = Profile.mock(name: \"n\", clock: clock)",
			options: MigrationOptions(ordersArgumentsByRoleFile: true),
		)
		#expect(result.editCounts[.argumentsReordered] == nil)
	}
}
