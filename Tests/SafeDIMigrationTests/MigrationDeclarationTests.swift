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

struct MigrationDeclarationTests {
	@Test
	func migrate_renamesInstantiableLabels_whenAttributeSpellsMockLabels() {
		let result = migrate("""
		@Instantiable(generateMock: .public, mockAttributes: "@MainActor")
		public final class Screen: Instantiable {}
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		@Instantiable(generateFake: .public, fakeAttributes: "@MainActor")
		public final class Screen: Instantiable {}
		""")])
		#expect(result.editCounts == [.attributeLabelRenamed: 2])
	}

	@Test
	func migrate_leavesAttribute_whenAttributeIsNotInstantiable() {
		#expect(migrate("@available(iOS 17, *) func show() {}").rewrittenFiles == [])
	}

	@Test
	func migrate_leavesAttribute_whenInstantiableTakesNoArguments() {
		#expect(migrate("@Instantiable final class Screen: Instantiable {}").rewrittenFiles == [])
	}

	@Test
	func migrate_renamesMockGeneration_whenSpelledAsTypeAndAsValue() {
		let result = migrate("""
		let generation: MockGeneration = MockGeneration.public
		let qualified: SafeDI.MockGeneration = .internal
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		let generation: FakeGeneration = FakeGeneration.public
		let qualified: SafeDI.FakeGeneration = .internal
		""")])
		#expect(result.editCounts == [.mockGenerationRenamed: 3])
	}

	@Test
	func migrate_renamesMockConfigurationType_whenSpelledAsTypeAndAsValue() {
		let result = migrate("""
		let configuration: Badge.SafeDIMockConfiguration = Badge.SafeDIMockConfiguration(label: "z")
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		let configuration: Badge.SafeDIFakeConfiguration = Badge.SafeDIFakeConfiguration(label: "z")
		""")])
		#expect(result.editCounts == [.configurationTypeRenamed: 2])
	}

	@Test
	func migrate_renamesMockConfigurationType_whenExtensionSpellsItBare() {
		#expect(migratedText("""
		extension Badge {
			func configure(_ configuration: SafeDIMockConfiguration) {}
		}
		""") == """
		extension Badge {
			func configure(_ configuration: SafeDIFakeConfiguration) {}
		}
		""")
	}

	// MARK: #SafeDIConfiguration

	@Test
	func migrate_renamesLabelsAndAddsOptIn_whenConfigurationLacksOptIn() {
		let result = migrate("""
		#SafeDIConfiguration(additionalMocksToGenerate: [Store.self], mockConditionalCompilation: "DEBUG")
		""")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: """
		#SafeDIConfiguration(additionalFakesToGenerate: [Store.self], fakeConditionalCompilation: "DEBUG", apiVersion: .v3Unstable)
		""")])
		#expect(result.editCounts == [.configurationLabelRenamed: 2, .optInSettingAdded: 1])
	}

	@Test
	func migrate_addsOptInOnLineOfItsOwn_whenConfigurationSpansLines() {
		#expect(migratedText("""
		#SafeDIConfiguration(
			additionalImportedModules: ["Feature"],
			additionalDirectoriesToInclude: ["Generated"]
		)
		""") == """
		#SafeDIConfiguration(
			additionalImportedModules: ["Feature"],
			additionalDirectoriesToInclude: ["Generated"],
			apiVersion: .v3Unstable
		)
		""")
	}

	@Test
	func migrate_addsOptInWithParentheses_whenConfigurationTakesNoArguments() {
		#expect(migratedText("#SafeDIConfiguration") == "#SafeDIConfiguration(apiVersion: .v3Unstable)")
	}

	@Test
	func migrate_updatesOptIn_whenConfigurationSetsAnotherValue() {
		let result = migrate("#SafeDIConfiguration(apiVersion: .v2)")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: "#SafeDIConfiguration(apiVersion: .v3Unstable)")])
		#expect(result.editCounts == [.optInSettingUpdated: 1])
	}

	@Test
	func migrate_leavesConfiguration_whenConfigurationAlreadyOptsIn() {
		let result = migrate("#SafeDIConfiguration(apiVersion: .v3Unstable)")
		#expect(result.rewrittenFiles == [])
		#expect(result.editCounts == [:])
	}

	@Test
	func migrate_leavesOtherMacro_whenMacroIsNotConfiguration() {
		#expect(migrate("#warning(\"check\")").rewrittenFiles == [])
	}

	@Test
	func migrate_createsConfigurationFile_whenModuleDeclaresNone() {
		let result = Migration.migrate(
			sources: [],
			roles: .fixture,
			options: MigrationOptions(modulesWithoutConfiguration: ["Feature/SafeDIConfiguration.swift", "App/SafeDIConfiguration.swift"]),
		)
		#expect(result.rewrittenFiles == [
			SourceFile(path: "App/SafeDIConfiguration.swift", text: "import SafeDI\n\n#SafeDIConfiguration(apiVersion: .v3Unstable)\n"),
			SourceFile(path: "Feature/SafeDIConfiguration.swift", text: "import SafeDI\n\n#SafeDIConfiguration(apiVersion: .v3Unstable)\n"),
		])
		#expect(result.editCounts == [.configurationFileCreated: 2])
	}
}

struct MigrationReportTests {
	@Test
	func migrate_reportsImplicitMember_whenCallIsArgument() {
		let result = migrate("func argument(service: UserService) { show(.mock(userService: service)) }")
		#expect(result.rewrittenFiles == [])
		#expect(result.findings == [finding(.implicitMemberUnresolved, line: 1, column: 44, ".mock(userService: service)")])
	}

	@Test
	func migrate_reportsImplicitMember_whenClosureReturnsIt() {
		let result = migrate("let make: () -> Banner = { .mock(userService: service) }")
		#expect(result.findings == [finding(.implicitMemberUnresolved, line: 1, column: 28, ".mock(userService: service)")])
	}

	@Test
	func migrate_reportsImplicitMember_whenBindingWritesNoType() {
		let result = migrate("let banner = .mock()")
		#expect(result.findings == [finding(.implicitMemberUnresolved, line: 1, column: 14, ".mock()")])
	}

	@Test
	func migrate_reportsImplicitMember_whenFunctionReturnsNothing() {
		let result = migrate("func make() { .mock() }")
		#expect(result.findings == [finding(.implicitMemberUnresolved, line: 1, column: 15, ".mock()")])
	}

	@Test
	func migrate_reportsImplicitMember_whenStatementIsAtFileScope() {
		let result = migrate(".mock()")
		#expect(result.findings == [finding(.implicitMemberUnresolved, line: 1, column: 1, ".mock()")])
	}

	@Test
	func migrate_reportsImplicitMember_whenComputedPropertyWritesNoType() {
		let result = migrate("var banner = { .mock() }()")
		#expect(result.findings == [finding(.implicitMemberUnresolved, line: 1, column: 16, ".mock()")])
	}

	@Test
	func migrate_reportsBase_whenTypealiasStandsForMockedType() {
		let result = migrate("""
		typealias B = Banner
		let viaAlias = B.mock(userService: service)
		""")
		#expect(result.rewrittenFiles == [])
		#expect(result.findings == [finding(.typealiasOrGenericBase, line: 2, column: 16, "B.mock(userService: service)")])
	}

	@Test
	func migrate_reportsNothing_whenTypealiasStandsForOtherType() {
		let result = migrate("""
		typealias D = Data
		let data = D.mock()
		""")
		#expect(result.findings == [])
	}

	@Test
	func migrate_reportsBase_whenGenericParameterCallsMock() {
		let result = migrate("func generic<T: MockMaking>(_: T.Type) -> T { T.mock() }")
		#expect(result.findings == [finding(.typealiasOrGenericBase, line: 1, column: 47, "T.mock()")])
	}

	@Test
	func migrate_reportsReference_whenMockIsReferencedAsValue() {
		let result = migrate("let reference = Banner.mock")
		#expect(result.rewrittenFiles == [])
		#expect(result.findings == [finding(.mockReferencedAsValue, line: 1, column: 17, "Banner.mock")])
	}

	@Test
	func migrate_reportsNothing_whenReferencedMockIsNoMockedType() {
		#expect(migrate("let reference = Data.mock").findings == [])
	}

	@Test
	func migrate_reportsNothing_whenImplicitMockIsReferenced() {
		#expect(migrate("let reference: () -> Banner = .mock").findings == [])
	}

	@Test
	func migrate_renamesOnlyAndReportsSite_whenCallHasTrailingClosure() {
		let result = migrate("let panel = Panel.mock(id: 1) { Row() }")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: "let panel = Panel.fake(id: 1) { Row() }")])
		#expect(result.findings == [finding(.trailingClosure, line: 1, column: 13, "Panel.mock(id: 1) { Row() }")])
	}

	@Test
	func migrate_renamesOnlyAndReportsSite_whenCallPassesLabelMockDoesNotTake() {
		let result = migrate("let banner = Banner.mock(note: \"x\", stale: 1)")
		#expect(result.rewrittenFiles == [SourceFile(path: "Calls.swift", text: "let banner = Banner.fake(note: \"x\", stale: 1)")])
		#expect(result.findings == [finding(.unknownLabel, line: 1, column: 14, "Banner.mock(note: \"x\", stale: 1)")])
	}

	@Test
	func migrate_renamesOnlyAndReportsSite_whenCallPassesUnlabeledArgument() {
		let result = migrate("let banner = Banner.mock(service)")
		#expect(result.findings == [finding(.unknownLabel, line: 1, column: 14, "Banner.mock(service)")])
	}

	@Test
	func migrate_reportsUnknownLabel_whenCallPassesOverridesFieldAsFlatArgument() {
		let result = migrate("let profile = Profile.mock(name: \"n\", user: draft, clock: clock)")
		#expect(result.findings == [finding(.unknownLabel, line: 1, column: 15, "Profile.mock(name: \"n\", user: draft, clock: clock)")])
	}

	@Test
	func migrate_reportsFieldRead_whenValueIsTypedAsOverrides() {
		let result = migrate("""
		func check(overrides: Banner.SafeDIOverrides) {
			print(overrides.badge.label)
		}
		""")
		#expect(result.findings == [finding(.configurationFieldRead, line: 2, column: 8, "overrides.badge")])
	}

	@Test
	func migrate_reportsFieldRead_whenBindingWritesConfigurationType() {
		let result = migrate("""
		let configuration: Badge.SafeDIMockConfiguration? = nil
		let label = configuration.label
		""")
		#expect(result.findings == [finding(.configurationFieldRead, line: 2, column: 13, "configuration.label")])
	}

	@Test
	func migrate_reportsFieldRead_whenBindingIsInitializedWithConfiguration() {
		let result = migrate("""
		let overrides = Banner.SafeDIOverrides.init()
		let badge = overrides.badge
		""")
		#expect(result.findings == [finding(.configurationFieldRead, line: 2, column: 13, "overrides.badge")])
	}

	@Test
	func migrate_reportsNothing_whenBindingIsOtherType() {
		let result = migrate("""
		let value = Banner.preview()
		let other: Int = 1
		let (a, b) = (overrides, 2)
		let badge = value.badge
		""")
		#expect(result.findings == [])
	}

	@Test
	func migrate_reportsForwardedWrapper_whenForwardedPropertyIsSafeDIWrapper() {
		let result = migrate("""
		@Instantiable
		public final class Screen: Instantiable {
			@Forwarded let detailBuilder: Instantiator<Detail>
			@Forwarded let lazyLog: LazilyInstantiated<Log>?
			@Forwarded let id: Int
			@Forwarded var a, b: Int
			@Instantiated let other: Instantiator<Other>
		}
		""")
		#expect(result.findings == [
			finding(.forwardedWrapper, line: 3, column: 32, "@Forwarded let detailBuilder: Instantiator<Detail>"),
			finding(.forwardedWrapper, line: 4, column: 26, "@Forwarded let lazyLog: LazilyInstantiated<Log>?"),
		])
	}

	@Test
	func migrate_reportsLabelRedeclarations_whenRoleFileListsThem() {
		let roles = MigrationRoles(mockedTypes: [], labelRedeclarations: [
			SourceSite(path: "B.swift", line: 2, column: 3),
			SourceSite(path: "A.swift", line: 9, column: 1),
		])
		let result = Migration.migrate(sources: [], roles: roles)
		#expect(result.findings == [
			MigrationFinding(kind: .labelRedeclaredBeneathItself, site: SourceSite(path: "A.swift", line: 9, column: 1), text: ""),
			MigrationFinding(kind: .labelRedeclaredBeneathItself, site: SourceSite(path: "B.swift", line: 2, column: 3), text: ""),
		])
	}

	@Test
	func migrate_ordersFindingsBySiteThenKind_whenOneSiteHasTwoFindings() {
		let result = migrate("""
		func check(overrides: Banner.SafeDIOverrides) { _ = overrides.mock }
		""", roles: MigrationRoles(mockedTypes: [], labelRedeclarations: [SourceSite(path: "Calls.swift", line: 1, column: 1)]))
		#expect(result.findings.map(\.kind) == [.labelRedeclaredBeneathItself, .configurationFieldRead])
	}
}

struct MigrationRolesTests {
	@Test
	func init_decodesDefaults_whenOptionalKeysAreMissing() throws {
		let json = """
		{"formatVersion": 0, "mockedTypes": [{"type": "Banner", "takesOverrides": true, "parameters": [{"label": "note", "role": "rootDefault"}]}]}
		"""
		let roles = try MigrationRoles(contentsOf: Data(json.utf8))
		#expect(roles == MigrationRoles(mockedTypes: [
			.init(type: "Banner", takesOverrides: true, parameters: [.init(label: "note", role: .rootDefault)]),
		]))
	}

	@Test
	func init_decodesEveryKey_whenFileWritesThem() throws {
		let roles = MigrationRoles(
			mockedTypes: [MigrationRoles.fixture.mockedTypes[3], MigrationRoles.fixture.mockedTypes[4]],
			labelRedeclarations: [SourceSite(path: "A.swift", line: 1, column: 2)],
		)
		let data = try JSONEncoder().encode(roles)
		#expect(try MigrationRoles(contentsOf: data) == roles)
	}

	@Test
	func sourceSite_ordersByPathThenLineThenColumn_whenSitesDiffer() {
		let sites = [
			SourceSite(path: "B.swift", line: 1, column: 1),
			SourceSite(path: "A.swift", line: 2, column: 1),
			SourceSite(path: "A.swift", line: 1, column: 5),
			SourceSite(path: "A.swift", line: 1, column: 2),
		]
		#expect(sites.sorted() == [sites[3], sites[2], sites[1], sites[0]])
	}
}

struct MigrationConfigurationPositionTests {
	@Test
	func migrate_addsOptIn_whenConfigurationIsDeclaredInsideType() {
		#expect(migratedText("""
		enum Configuration {
			#SafeDIConfiguration(additionalImportedModules: [])
		}
		""") == """
		enum Configuration {
			#SafeDIConfiguration(additionalImportedModules: [], apiVersion: .v3Unstable)
		}
		""")
	}

	@Test
	func migrate_addsOptInBeforeFollowingLine_whenConfigurationTakesNoArgumentsAndLineContinues() {
		#expect(migratedText("#SafeDIConfiguration\nlet x = 1") == "#SafeDIConfiguration(apiVersion: .v3Unstable)\nlet x = 1")
	}
}
