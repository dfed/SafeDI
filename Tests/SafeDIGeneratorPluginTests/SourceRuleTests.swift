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

import Testing

/// Rules SafeDI's own sources follow, checked so that they hold whether or not a change remembers them. See
/// `SourceRule` for the rules and the waiver of a site that is safe.
struct SourceRuleTests {
	// MARK: SafeDI's sources

	@Test
	func sources_trapNowhere_exceptWhereWaived() throws {
		let checkedFiles = try Self.checkedFiles.get()
		#expect(Set(checkedFiles.map(\.file.path)).isSuperset(of: [
			"Plugins/Shared.swift",
			"Sources/SafeDI/Decorators/Instantiable.swift",
			"Sources/SafeDICore/Generators/ScopeGenerator.swift",
			"Sources/SafeDIMacros/Macros/InstantiableMacro.swift",
			"Sources/SafeDIToolLibrary/GenerateCommand.swift",
			"TuistPlugins/SafeDITuist/ProjectDescriptionHelpers/SafeDI.swift",
		]))
		#expect(try findings(of: [.forceUnwrap, .forceTry, .forceCast, .trap, .uniqueKeysWithValues]) == [])
	}

	@Test
	func generators_discardNoErrorWithOptionalTry() throws {
		#expect(try findings(of: [.optionalTry]) == [])
	}

	@Test
	func generators_nameNoTrappingFunctionInALiteral() throws {
		#expect(try findings(of: [.generatedTrap]) == [])
	}

	@Test
	func sources_spellBuilderFunctionNamePrefix_onlyInReservedName() throws {
		#expect(try findings(of: [.builderFunctionNamePrefix]) == [])
	}

	@Test
	func sources_spellALoneBacktick_onlyInIdentifierSpellingExtensions() throws {
		#expect(try findings(of: [.backtick]) == [])
	}

	@Test
	func sources_spellEachApostropheInALiteralCurly() throws {
		#expect(try findings(of: [.apostrophe]) == [])
	}

	@Test
	func sources_declareNoUncheckedConcurrency_exceptWhereDanApproved() throws {
		#expect(try findings(of: [.uncheckedConcurrency]) == [])
	}

	@Test
	func typeKeyFilesAndPlaceRecords_nameNoFeature() throws {
		#expect(try findings(of: [.engineFeatureName]) == [])
	}

	@Test(arguments: [
		("let mockDefaults = 1", "mockDefaults", "mock"),
		("_ = record.seamRoot", "seamRoot", "seam"),
		("struct SafeDIOverrides {}", "SafeDIOverrides", "overrides"),
		("func read(configuration: Int) {}", "configuration", "configuration"),
		("_ = HoleFill.self", "HoleFill", "hole"),
		("_ = \"a fill\"", "a fill", "fill"),
	])
	func sourceRuleCheck_findsEngineFeatureName_whenATypeKeyFileNamesAFeature(source: String, name: String, word: String) {
		#expect(findings(in: source, at: "Sources/SafeDICore/Generators/Emission/TypeKeyBody+Fixture.swift") == [
			"Sources/SafeDICore/Generators/Emission/TypeKeyBody+Fixture.swift:1: engineFeatureName: the type key and its records name no feature, and `\(name)` names `\(word)`: record the fact in general terms on the place, and read that",
		])
	}

	@Test
	func sourceRuleCheck_findsNoEngineFeatureName_whenAWordOnlyContainsAFeaturesLettersOrAnotherFileNamesIt() {
		#expect(findings(in: """
		// A comment may say what a mock or a seam records.
		let fulfillingProperty = 1
		override func visit() {}
		""", at: "Sources/SafeDICore/Generators/Emission/TypeKeyBody.swift") == [])
		#expect(findings(in: "let mockDefaults = seamRoot", at: "Sources/SafeDICore/Generators/Emission/ArgumentSource.swift") == [])
	}

	@Test
	func sourceRuleCheck_findsEngineFeatureName_whenPlaceRecordNamesAFeature() {
		#expect(findings(in: "let isHole = true", at: "Sources/SafeDICore/Generators/Emission/PlaceRecord.swift") == [
			"Sources/SafeDICore/Generators/Emission/PlaceRecord.swift:1: engineFeatureName: the type key and its records name no feature, and `isHole` names `hole`: record the fact in general terms on the place, and read that",
		])
	}

	@Test
	func generators_scanNoStringsCharacters_exceptWhereWaived() throws {
		#expect(try findings(of: [.stringScan]) == [])
	}

	@Test(arguments: [
		("_ = code.split(separator: \"\\n\")", "split"),
		("_ = text.replacingOccurrences(of: \"a\", with: \"b\")", "replacingOccurrences"),
		("_ = text.components(separatedBy: separator)", "components"),
		("_ = code.contains(\"public \")", "contains"),
		("_ = line.split(whereSeparator: { $0 == \" \" })", "split"),
	])
	func sourceRuleCheck_findsStringScan_whenAGeneratorScansAString(source: String, name: String) {
		#expect(findings(in: source, at: "Sources/SafeDICore/Generators/Fixture.swift") == [
			"Sources/SafeDICore/Generators/Fixture.swift:1: stringScan: `\(name)` reads every character of its text, and a generator’s code runs per place or per node: go over UTF-8 bytes (`GeneratedCodeText`), or waive a site that runs a bounded number of times with why",
		])
	}

	@Test
	func sourceRuleCheck_findsNoStringScan_whenContainsTakesNoLiteralOrTheFileIsNoGenerator() {
		#expect(findings(in: """
		_ = names.contains(name)
		_ = names.contains { $0.isEmpty }
		// A comment may say code.split(separator: "x").
		""", at: "Sources/SafeDICore/Generators/Emission/Fixture.swift") == [])
		#expect(findings(in: "_ = code.split(separator: \"\\n\")", at: "Sources/SafeDICore/Models/Fixture.swift") == [])
	}

	@Test
	func sources_returnNoTupleFromATaskGroup() throws {
		#expect(try findings(of: [.taskGroupTupleElement]) == [])
	}

	@Test(arguments: [
		"let reads = await withTaskGroup(of: (Int, String).self) { _ in }",
		"let reads = await withTaskGroup(\n    of: (index: Int, read: Result<Head, any Error>).self,\n    returning: [Head].self,\n) { _ in }",
		"let reads = try await withThrowingTaskGroup(of: (path: String, read: Read)?.self) { _ in }",
		"let reads = await withTaskGroup(of: (only: Int).self) { _ in }",
	])
	func sourceRuleCheck_findsTaskGroupTupleElement_whenTaskGroupReturnsTuple(declaration: String) {
		let line = declaration.hasPrefix("let reads = await withTaskGroup(\n") ? 2 : 1
		#expect(findings(in: declaration) == [
			"Sources/SafeDICore/Models/Fixture.swift:\(line): taskGroupTupleElement: a task group whose element is a tuple miscompiles in release builds of Swift 6.3 and 6.4: return a struct",
		])
	}

	@Test
	func sourceRuleCheck_findsTaskGroupTupleElement_whenPluginsTaskGroupReturnsTuple() {
		#expect(findings(in: "let reads = await withTaskGroup(of: (Int, String).self) { _ in }", at: "Plugins/Shared.swift") == [
			"Plugins/Shared.swift:1: taskGroupTupleElement: a task group whose element is a tuple miscompiles in release builds of Swift 6.3 and 6.4: return a struct",
		])
	}

	@Test
	func sourceRuleCheck_findsNoTaskGroupTupleElement_whenTaskGroupReturnsStructOrParenthesizedType() {
		#expect(findings(in: """
		let reads = await withTaskGroup(of: HeadRead.self, returning: [(Int, String)].self) { _ in }
		let plans = try await withThrowingTaskGroup(of: PlannedRoot?.self) { _ in }
		let names = await withTaskGroup(of: (String).self) { _ in }
		let other = await otherFunction(of: (Int, String).self)
		_ = "withTaskGroup(of: (Int, String).self)"
		""") == [])
	}

	@Test
	func toolTestSupport_importsNoModuleTestably() throws {
		let checkedFiles = try Self.checkedFiles.get()
		#expect(Set(checkedFiles.map(\.file.path)).isSuperset(of: [
			"Tests/SafeDIToolTestSupport/GraphFuzzerCallingMocks.swift",
			"Tests/SafeDIToolTestSupport/SafeDIToolTestExecution.swift",
		]))
		#expect(try findings(of: [.testableImport]) == [])
	}

	@Test
	func waivers_eachNameARuleGiveAReasonAndWaiveASite() throws {
		let findings = try Self.checkedFiles.get().flatMap { checkedFile in
			checkedFile.findings.filter { $0.subject == .waiver }.map(\.description)
		}
		#expect(findings == [])
	}

	@Test
	func errorTypes_areEachListedWithTheSiteThatReportsThem() throws {
		let files = try Self.checkedFiles.get().map(\.file).filter { $0.path.hasPrefix("Sources/") }
		let errorTypes = ErrorTypeDeclarations.errorTypes(in: files.filter { $0.path.hasPrefix("Sources/SafeDICore/") })
		#expect(errorTypes.keys.contains("DependencyTreeGenerator.DependencyTreeGeneratorError"))
		#expect(ErrorReportingSite.problems(ofRegistry: ErrorReportingSite.byErrorType, errorTypes: errorTypes, files: files) == [])
	}

	// MARK: Actor state

	@Test
	func generatorActor_assignsNoStoredPropertyInAnAsyncFunction() throws {
		let files = try Self.checkedFiles.get().map(\.file)
		#expect(ActorStateRuleCheck.coveredActors(in: files).keys.sorted() == ["DependencyTreeGenerator"])
		#expect(ActorStateRuleCheck.findings(in: files) == [])
	}

	@Test(arguments: [
		"self.memo = value",
		"memo = value",
		"memo[key] = value",
		"self.memo[key] = value",
		"memo.field = value",
		"memo += value",
		"(memo, other) = (value, value)",
	])
	func actorStateRuleCheck_findsAssignment_whenAsyncFunctionAssignsStoredProperty(assignment: String) {
		#expect(actorStateFindings(in: [Self.actorFixture, "extension Generator {\n    func compute() async {\n        \(assignment)\n    }\n}"]) == [
			"Sources/SafeDICore/Fixture1.swift:3: an `async` function of actor `Generator` assigns its stored property `memo`",
		])
	}

	@Test
	func actorStateRuleCheck_findsAssignment_whenAsyncGetterAssignsStoredProperty() {
		#expect(actorStateFindings(in: [Self.actorFixture, "extension Generator {\n    var computed: Int {\n        get async {\n            memo = 1\n            return 1\n        }\n    }\n}"]) == [
			"Sources/SafeDICore/Fixture1.swift:4: an `async` function of actor `Generator` assigns its stored property `memo`",
		])
	}

	@Test
	func actorStateRuleCheck_findsAssignment_whenActorsOwnAsyncFunctionAssignsStoredProperty() {
		#expect(actorStateFindings(in: ["actor Generator {\n    var memo: Int?\n    func compute() async {\n        memo = 1\n    }\n}"]) == [
			"Sources/SafeDICore/Fixture0.swift:4: an `async` function of actor `Generator` assigns its stored property `memo`",
		])
	}

	@Test
	func actorStateRuleCheck_findsNothing_whenAsyncFunctionAssignsLocalOfPropertysName() {
		#expect(actorStateFindings(in: [Self.actorFixture, "extension Generator {\n    func compute(other: inout Int?) async {\n        var memo: Int?\n        memo = 1\n        other = memo\n        _ = memo\n    }\n}"]) == [])
	}

	@Test
	func actorStateRuleCheck_findsAssignment_whenOptionalBindingOfPropertysNameScopesOnlyTheOtherBranch() {
		#expect(actorStateFindings(in: [Self.actorFixture, "extension Generator {\n    func compute() async {\n        if let memo {\n            _ = memo\n        } else {\n            memo = 1\n        }\n    }\n}"]) == [
			"Sources/SafeDICore/Fixture1.swift:6: an `async` function of actor `Generator` assigns its stored property `memo`",
		])
	}

	@Test(arguments: [
		"guard var memo = Optional(1) else { return }\n        memo = 2",
		"for var memo in [1] {\n            memo = 2\n        }",
		"_ = { (memo: inout Int) in memo = 2 }",
		"if var memo = Optional(1) {\n            memo = 2\n        }",
	])
	func actorStateRuleCheck_findsNothing_whenAsyncFunctionAssignsBindingOfPropertysName(statements: String) {
		#expect(actorStateFindings(in: [Self.actorFixture, "extension Generator {\n    func compute() async {\n        \(statements)\n    }\n}"]) == [])
	}

	@Test
	func actorStateRuleCheck_findsNothing_whenSynchronousFunctionAssignsStoredProperty() {
		#expect(actorStateFindings(in: [Self.actorFixture, "extension Generator {\n    func compute() {\n        memo = 1\n    }\n}"]) == [])
	}

	@Test
	func actorStateRuleCheck_findsNothing_whenAsyncFunctionComparesStoredProperty() {
		#expect(actorStateFindings(in: [Self.actorFixture, "extension Generator {\n    func compute() async -> Bool {\n        memo == nil && computed <= 1\n    }\n}"]) == [])
	}

	@Test
	func actorStateRuleCheck_findsNothing_whenAsyncFunctionOfAnotherTypeAssignsPropertyOfActorsName() {
		#expect(actorStateFindings(in: [Self.actorFixture, "struct Other {\n    var memo: Int?\n    mutating func compute() async {\n        memo = 1\n    }\n}"]) == [])
	}

	@Test
	func actorStateRuleCheck_findsNothing_whenActorIsNotYetCovered() {
		#expect(actorStateFindings(in: ["actor ScopeGenerator {\n    var memo: Int?\n    func compute() async {\n        memo = 1\n    }\n}"]) == [])
	}

	// MARK: Traps

	@Test(arguments: [
		"value!",
		"value!.count",
		"valueByKey[key]!",
		"(value as Int?)!",
		"optionalClosure!()",
		"value?.optionalMember!",
		#"values.map(\.value!)"#,
		#"values.map(\Box.value!.count)"#,
		#"box[keyPath: \.value!]"#,
	])
	func sourceRuleCheck_findsForceUnwrap_whenCodeForceUnwrapsAValue(expression: String) {
		#expect(findings(in: "_ = \(expression)") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: forceUnwrap: a force unwrap traps on `nil`",
		])
	}

	@Test(arguments: [
		"Int!",
		"(() -> Void)!",
		"(@Sendable () -> Void)!",
		"(Int, String)!",
		"(any Error)!",
		"Outer.Inner!",
		"Array<Int>!",
		"Alias!",
		"Swift.Int!",
	])
	func sourceRuleCheck_findsForceUnwrap_whenCodeDeclaresAnImplicitlyUnwrappedOptional(type: String) {
		#expect(findings(in: "var value: \(type)") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: forceUnwrap: an implicitly unwrapped optional traps when it is read as `nil`",
		])
	}

	@Test
	func sourceRuleCheck_findsNoForceUnwrap_whenCodeNegatesComparesOrChainsOptionals() {
		#expect(findings(in: """
		_ = value != other
		_ = !flag
		_ = value?.count
		if let value { _ = value }
		_ = "value!" // value!
		_ = values.compactMap(\\.value?.count)
		""") == [])
	}

	@Test
	func sourceRuleCheck_findsForceUnwrap_whenCodeReadsUnsafelyUnwrapped() {
		#expect(findings(in: "_ = value.unsafelyUnwrapped") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: forceUnwrap: `unsafelyUnwrapped` traps on `nil` in a debug build and reads an undefined value in a release build",
		])
	}

	@Test
	func sourceRuleCheck_findsForceUnwrap_whenCodeDeclaresAnImplicitlyUnwrappedFailableInitializer() {
		#expect(findings(in: """
		struct Box {
		    init!(value: Int) { return nil }
		    init?(other: Int) { return nil }
		}
		""") == [
			"Sources/SafeDICore/Models/Fixture.swift:2: forceUnwrap: an implicitly unwrapped failable initializer traps when its `nil` result is read",
		])
	}

	@Test
	func sourceRuleCheck_findsForceTry_whenCodeForceTries() {
		#expect(findings(in: "_ = try! load()") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: forceTry: `try!` traps on an error",
		])
	}

	@Test
	func sourceRuleCheck_findsNothing_whenCodeTriesOrTriesOptionallyOutsideGenerators() {
		#expect(findings(in: """
		_ = try load()
		_ = try? load()
		""") == [])
	}

	@Test(arguments: [
		"Int",
		"() -> Void",
		"@Sendable () -> Void",
		"(() -> Void)?",
		"(Int, String)",
		"any Error",
		"Outer.Inner",
		"[String: Int]",
		"Alias",
		"Swift.Int",
	])
	func sourceRuleCheck_findsForceCast_whenCodeForceCasts(type: String) {
		#expect(findings(in: "_ = value as! \(type)") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: forceCast: `as!` traps on a failed cast",
		])
	}

	@Test
	func sourceRuleCheck_findsNoForceCast_whenCodeCastsConditionallyOrStatically() {
		#expect(findings(in: """
		_ = value as? Int
		_ = value as Int
		_ = value is Int
		""") == [])
	}

	@Test(arguments: [
		("fatalError(\"unreachable\")", "fatalError"),
		("precondition(flag)", "precondition"),
		("preconditionFailure()", "preconditionFailure"),
		("assert(flag)", "assert"),
		("assertionFailure()", "assertionFailure"),
		("Swift.fatalError()", "fatalError"),
		("let stop: () -> Never = fatalError", "fatalError"),
	])
	func sourceRuleCheck_findsTrap_whenCodeCallsATrappingFunction(code: String, function: String) {
		#expect(findings(in: code) == [
			"Sources/SafeDICore/Models/Fixture.swift:1: trap: `\(function)` traps",
		])
	}

	@Test
	func sourceRuleCheck_findsNoTrap_whenCodeNamesAMemberOrLabelLikeATrappingFunction() {
		#expect(findings(in: """
		checker.assert(flag)
		_ = Check.precondition
		let check: Check = .fatalError
		validate(precondition: flag)
		""") == [])
	}

	@Test(arguments: [
		"Dictionary(uniqueKeysWithValues: pairs)",
		"[String: Int](uniqueKeysWithValues: pairs)",
		"Dictionary<String, Int>(uniqueKeysWithValues: pairs)",
		"Swift.Dictionary(uniqueKeysWithValues: pairs)",
		"Alias(uniqueKeysWithValues: pairs)",
		"[String: Int].init(uniqueKeysWithValues: pairs)",
		"[pairs].map(Dictionary.init(uniqueKeysWithValues:))",
	])
	func sourceRuleCheck_findsUniqueKeysWithValues_whenCodeBuildsADictionaryThatTrapsOnADuplicateKey(expression: String) {
		#expect(findings(in: "_ = \(expression)") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: uniqueKeysWithValues: `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key",
		])
	}

	@Test(arguments: [
		"[first.label: 1, second.label: 2]",
		"[first: 1, second: 2]",
		#"["one": 1, "one": 2]"#,
		#"[1: "one", 1: "uno"]"#,
	])
	func sourceRuleCheck_findsUniqueKeysWithValues_whenADictionaryLiteralsKeysAreNotDistinctLiterals(literal: String) {
		#expect(findings(in: "_ = \(literal)") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: uniqueKeysWithValues: a dictionary literal traps on a duplicate key unless its keys are distinct literals",
		])
	}

	@Test
	func sourceRuleCheck_findsUniqueKeysWithValues_whenCodeBuildsADictionaryFromALiteralList() {
		#expect(findings(in: "_ = Dictionary(dictionaryLiteral: (first, 1), (second, 2))") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: uniqueKeysWithValues: `Dictionary(dictionaryLiteral:)` traps on a duplicate key",
		])
	}

	@Test
	func sourceRuleCheck_findsNoUniqueKeysWithValues_whenCodeBuildsADictionaryThatKeepsOneValuePerKey() {
		#expect(findings(in: """
		_ = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
		_ = Dictionary(grouping: values, by: \\.count)
		_ = (uniqueKeysWithValues: pairs)
		_ = ["one": 1, "two": 2]
		_ = [1: "one", 2: "two", 3: "three"]
		_ = [key: value]
		_ = [String: Int]()
		let empty: [String: Int] = [:]
		""") == [])
	}

	@Test
	func sourceRuleCheck_findsTrapsInPlugins_whenAPluginTraps() {
		#expect(findings(in: "_ = value!", at: "Plugins/SafeDIGenerator/Fixture.swift") == [
			"Plugins/SafeDIGenerator/Fixture.swift:1: forceUnwrap: a force unwrap traps on `nil`",
		])
	}

	// MARK: Optional try

	@Test
	func sourceRuleCheck_findsOptionalTry_whenAGeneratorTriesOptionally() {
		#expect(findings(in: "_ = try? load()", at: "Sources/SafeDICore/Generators/Fixture.swift") == [
			"Sources/SafeDICore/Generators/Fixture.swift:1: optionalTry: `try?` discards an error a generator must report",
		])
	}

	// MARK: Traps in generated code

	@Test(arguments: [
		(#""fatalError()""#, "fatalError"),
		(#""precondition(\(condition))""#, "precondition"),
		(#""preconditionFailure("unreachable")""#, "preconditionFailure"),
		(#""assert(flag)""#, "assert"),
		(#""\(indentation)assertionFailure()""#, "assertionFailure"),
		(##"#"Swift.fatalError()"#"##, "fatalError"),
		(#""calls fatalError when it is reached""#, "fatalError"),
		(#""let value = try! load()""#, "try!"),
		(#""(\(name) as! Service)""#, "as!"),
		(#""\(name).unsafelyUnwrapped""#, "unsafelyUnwrapped"),
	])
	func sourceRuleCheck_findsGeneratedTrap_whenAGeneratorsLiteralSpellsATrap(literal: String, trap: String) {
		#expect(findings(in: "_ = \(literal)", at: "Sources/SafeDICore/Generators/Fixture.swift") == [
			"Sources/SafeDICore/Generators/Fixture.swift:1: generatedTrap: a literal in `Sources` spells `\(trap)`, so the code it generates could trap",
		])
	}

	@Test(arguments: [
		"Sources/SafeDICore/Models/Fixture.swift",
		"Sources/SafeDIToolLibrary/Fixture.swift",
		"Sources/SafeDIMacros/Fixture.swift",
	])
	func sourceRuleCheck_findsGeneratedTrap_whenALiteralOutsideGeneratorsSpellsATrap(path: String) {
		#expect(findings(in: #"_ = "fatalError()""#, at: path) == [
			"\(path):1: generatedTrap: a literal in `Sources` spells `fatalError`, so the code it generates could trap",
		])
	}

	@Test
	func sourceRuleCheck_findsGeneratedTrap_whenAGeneratorsMultilineLiteralSpellsATrap() {
		#expect(findings(in: #"""
		_ = """
		    guard let value else {
		        fatalError()
		    }
		"""
		"""#, at: "Sources/SafeDICore/Generators/Fixture.swift") == [
			"Sources/SafeDICore/Generators/Fixture.swift:3: generatedTrap: a literal in `Sources` spells `fatalError`, so the code it generates could trap",
		])
	}

	@Test
	func sourceRuleCheck_findsNoGeneratedTrap_whenALiteralSpellsATrapOnlyInsideAWord() {
		#expect(findings(in: #"""
		_ = "the assertion holds"
		_ = "preconditions_met"
		_ = "assertFailure"
		_ = "my_fatalError()"
		_ = "it has! no trap"
		_ = "entry! as well"
		_ = "isUnsafelyUnwrapped"
		// fatalError()
		"""#, at: "Sources/SafeDICore/Generators/Fixture.swift") == [])
	}

	@Test
	func sourceRuleCheck_findsNoGeneratedTrap_whenALiteralOutsideSourcesSpellsATrap() {
		#expect(findings(in: #"_ = "fatalError()""#, at: "Plugins/SafeDIGenerator/Fixture.swift") == [])
	}

	@Test
	func sourceRuleCheck_findsNothing_whenAWaiverWithAReasonFollowsAGeneratedTrap() {
		#expect(findings(in: #"_ = "assert(flag)" // safedi-source-rule: allow generatedTrap — names the function in a diagnostic, never in generated code"#, at: "Sources/SafeDICore/Generators/Fixture.swift") == [])
	}

	// MARK: Spellings

	@Test(arguments: [
		#""__safeDI_""#,
		#""__safeDI_\(label)""#,
		#""\(label)__safeDI_""#,
		##"#"__safeDI_"#"##,
		"#/__safeDI_/#",
	])
	func sourceRuleCheck_findsBuilderFunctionNamePrefix_whenALiteralOutsideReservedNameSpellsIt(literal: String) {
		#expect(findings(in: "_ = \(literal)") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: builderFunctionNamePrefix: only `ReservedName.builderFunctionNamePrefix` spells `__safeDI_`",
		])
	}

	@Test
	func sourceRuleCheck_findsBuilderFunctionNamePrefix_whenAMultilineLiteralSpellsIt() {
		#expect(findings(in: #"""
		_ = """
		func __safeDI_value() {}
		"""
		"""#) == [
			"Sources/SafeDICore/Models/Fixture.swift:2: builderFunctionNamePrefix: only `ReservedName.builderFunctionNamePrefix` spells `__safeDI_`",
		])
	}

	@Test
	func sourceRuleCheck_findsNoBuilderFunctionNamePrefix_whenReservedNameSpellsItOrCodeJoinsIt() {
		#expect(findings(in: #"public static let builderFunctionNamePrefix = "__safeDI_""#, at: "Sources/SafeDICore/Models/ReservedName.swift") == [])
		#expect(findings(in: """
		// Generated code declares `__safeDI_<label>`.
		_ = ReservedName.builderFunctionNamePrefix + label
		""") == [])
	}

	@Test(arguments: [
		#""`""#,
		##"#"`"#"##,
	])
	func sourceRuleCheck_findsBacktick_whenALiteralOutsideIdentifierSpellingExtensionsIsALoneBacktick(literal: String) {
		#expect(findings(in: "_ = name.filter { $0 != \(literal) }") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: backtick: only the identifier-spelling extensions add or remove a backtick",
		])
	}

	@Test
	func sourceRuleCheck_findsNoBacktick_whenIdentifierSpellingExtensionsSpellItOrALiteralQuotesText() {
		#expect(findings(in: #"_ = name.filter { $0 != "`" }"#, at: "Sources/SafeDICore/Extensions/IdentifierSpellingExtensions.swift") == [])
		#expect(findings(in: """
		_ = "`\\(name)` is not fulfilled"
		_ = "`name`"
		""") == [])
	}

	@Test(arguments: [
		#""the type's value""#,
		#""it doesn't compile""#,
		#""`\(name)`'s initializer""#,
		#""\(name)'s initializer""#,
		#""module 2's files""#,
		##"#"the type's value"#"##,
	])
	func sourceRuleCheck_findsApostrophe_whenALiteralSpellsAStraightApostropheBetweenLetters(literal: String) {
		#expect(findings(in: "_ = \(literal)") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: apostrophe: the text SafeDI emits spells an apostrophe ’, never '",
		])
	}

	@Test
	func sourceRuleCheck_findsApostrophe_whenAMultilineLiteralSpellsAStraightApostrophe() {
		#expect(findings(in: #"""
		_ = """
		// The seam's tree.
		"""
		"""#, at: "Plugins/SafeDIGenerator/Fixture.swift") == [
			"Plugins/SafeDIGenerator/Fixture.swift:2: apostrophe: the text SafeDI emits spells an apostrophe ’, never '",
		])
	}

	@Test
	func sourceRuleCheck_findsNoApostrophe_whenNoStraightQuoteInALiteralIsBetweenLetters() {
		#expect(findings(in: #"""
		_ = "the type’s value"
		_ = "the module '\(name)' at '\(path)'"
		_ = "requires '--module-name'"
		_ = character == "'"
		_ = "the types' declarations"
		// the type's value
		"""#) == [])
	}

	@Test
	func sourceRuleCheck_findsNothing_whenAWaiverWithAReasonFollowsAnApostrophe() {
		#expect(findings(in: #"_ = "doesn't" // safedi-source-rule: allow apostrophe — matches the compiler's output verbatim"#) == [])
	}

	// MARK: Test support imports

	@Test(arguments: [
		"@testable import SafeDIToolLibrary",
		"@testable @preconcurrency import SafeDIToolLibrary",
		"@preconcurrency @testable import SafeDIToolLibrary",
		"@testable import struct SafeDIToolLibrary.SafeDIToolCommandLine",
	])
	func sourceRuleCheck_findsTestableImport_whenTestSupportImportsAModuleTestably(importDeclaration: String) {
		#expect(findings(in: """
		import Foundation
		\(importDeclaration)
		""", at: "Tests/SafeDIToolTestSupport/Fixture.swift") == [
			"Tests/SafeDIToolTestSupport/Fixture.swift:2: testableImport: a release build compiles `SafeDIToolTestSupport` without `-enable-testing`, which rejects `@testable import`",
		])
	}

	@Test
	func sourceRuleCheck_findsTestableImport_whenTestSupportImportsAModuleTestablyInAConditionalBlock() {
		#expect(findings(in: """
		#if canImport(SafeDIToolLibrary)
		@testable import SafeDIToolLibrary
		#endif
		""", at: "Tests/SafeDIToolTestSupport/Fixture.swift") == [
			"Tests/SafeDIToolTestSupport/Fixture.swift:2: testableImport: a release build compiles `SafeDIToolTestSupport` without `-enable-testing`, which rejects `@testable import`",
		])
	}

	@Test
	func sourceRuleCheck_findsTestableImport_whenAConditionalBlockInTheImportsAttributesAddsTestable() {
		#expect(findings(in: """
		#if canImport(SafeDIToolLibrary)
		@testable
		#endif
		import SafeDIToolLibrary
		""", at: "Tests/SafeDIToolTestSupport/Fixture.swift") == [
			"Tests/SafeDIToolTestSupport/Fixture.swift:4: testableImport: a release build compiles `SafeDIToolTestSupport` without `-enable-testing`, which rejects `@testable import`",
		])
	}

	@Test(arguments: [
		"@testable\nimport SafeDIToolLibrary",
		"@preconcurrency\n@testable import SafeDIToolLibrary",
	])
	func sourceRuleCheck_findsTestableImportOnTheImportKeywordsLine_whenTheAttributesSpanLines(importDeclaration: String) {
		#expect(findings(in: importDeclaration, at: "Tests/SafeDIToolTestSupport/Fixture.swift") == [
			"Tests/SafeDIToolTestSupport/Fixture.swift:2: testableImport: a release build compiles `SafeDIToolTestSupport` without `-enable-testing`, which rejects `@testable import`",
		])
	}

	@Test
	func sourceRuleCheck_findsNoTestableImport_whenTestSupportImportsPlainly() {
		#expect(findings(in: """
		import SafeDIToolLibrary
		@preconcurrency import SafeDICore
		import struct SafeDIToolLibrary.SafeDIToolCommandLine
		""", at: "Tests/SafeDIToolTestSupport/Fixture.swift") == [])
	}

	@Test
	func sourceRuleCheck_findsNoTestableImport_whenALiteralSpellsATestableImport() {
		#expect(findings(in: #"""
		let imports = moduleNames.map { "@testable import \($0)" }
		let main = """
		@testable import Fixture
		"""
		"""#, at: "Tests/SafeDIToolTestSupport/Fixture.swift") == [])
	}

	@Test(arguments: [
		"Tests/SafeDIToolTests/Fixture.swift",
		"Tests/SafeDIGeneratorPluginTests/Fixture.swift",
		"Sources/SafeDICore/Models/Fixture.swift",
	])
	func sourceRuleCheck_findsNoTestableImport_whenAFileOutsideTestSupportImportsTestably(path: String) {
		#expect(findings(in: "@testable import SafeDIToolLibrary", at: path) == [])
	}

	@Test(arguments: [
		"@testable import SafeDIToolLibrary",
		"@testable\nimport SafeDIToolLibrary",
		"@preconcurrency\n@testable import SafeDIToolLibrary",
	])
	func sourceRuleCheck_findsNothing_whenAWaiverWithAReasonFollowsATestableImport(importDeclaration: String) {
		#expect(findings(in: "\(importDeclaration) // safedi-source-rule: allow testableImport — this target builds only with testing enabled", at: "Tests/SafeDIToolTestSupport/Fixture.swift") == [])
	}

	// MARK: Waivers

	@Test
	func sourceRuleCheck_findsNothing_whenAWaiverWithAReasonFollowsTheSite() {
		#expect(findings(in: "_ = value! // safedi-source-rule: allow forceUnwrap — `value` is set before this line") == [])
	}

	@Test
	func sourceRuleCheck_findsNothing_whenAWaiverWithAReasonPrecedesTheSite() {
		#expect(findings(in: """
		// safedi-source-rule: allow uniqueKeysWithValues — the keys are indices,
		// which are distinct.
		_ = Dictionary(uniqueKeysWithValues: pairs)
		""") == [])
	}

	@Test
	func sourceRuleCheck_findsWaiver_whenAWaiverGivesNoReason() {
		#expect(findings(in: "_ = value! // safedi-source-rule: allow forceUnwrap") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: waiver: the waiver of `forceUnwrap` gives no reason",
		])
	}

	@Test
	func sourceRuleCheck_findsSiteAndWaiver_whenAWaiverNamesNoRule() {
		#expect(findings(in: "_ = value! // safedi-source-rule: allow forceUnwrapping — `value` is set before this line") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: forceUnwrap: a force unwrap traps on `nil`",
			"Sources/SafeDICore/Models/Fixture.swift:1: waiver: a waiver reads `safedi-source-rule: allow <rule> — <reason>`, where the rule is one of `forceUnwrap`, `forceTry`, `forceCast`, `trap`, `uniqueKeysWithValues`, `optionalTry`, `generatedTrap`, `builderFunctionNamePrefix`, `backtick`, `apostrophe`, `testableImport`, `uncheckedConcurrency`, `taskGroupTupleElement`, `engineFeatureName`, `stringScan`",
		])
	}

	@Test
	func sourceRuleCheck_findsSiteAndWaiver_whenAWaiverNamesAnotherRule() {
		#expect(findings(in: "_ = value! // safedi-source-rule: allow forceTry — `value` is set before this line") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: forceUnwrap: a force unwrap traps on `nil`",
			"Sources/SafeDICore/Models/Fixture.swift:1: waiver: the waiver of `forceTry` waives no site on line 1",
		])
	}

	@Test
	func sourceRuleCheck_findsSiteAndWaiver_whenCodeSeparatesAWaiverFromTheSite() {
		#expect(findings(in: """
		// safedi-source-rule: allow forceUnwrap — `value` is set before this line
		let other = value
		_ = value!
		""") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: waiver: the waiver of `forceUnwrap` waives no site on line 2",
			"Sources/SafeDICore/Models/Fixture.swift:3: forceUnwrap: a force unwrap traps on `nil`",
		])
	}

	@Test(arguments: [
		(declaration: "nonisolated(unsafe) var cache = [Int]()", line: 1),
		(declaration: "final class Owner: Sendable {\n    nonisolated(unsafe) private var children: [Owner] = []\n}", line: 2),
		(declaration: "enum Shared {\n    nonisolated(unsafe) static var count = 0\n}", line: 2),
		(declaration: "func run() {\n    nonisolated(unsafe) let box = Box()\n    _ = box\n}", line: 2),
	])
	func sourceRuleCheck_findsUncheckedConcurrency_whenCodeDeclaresNonisolatedUnsafe(declaration: String, line: Int) {
		#expect(findings(in: declaration) == [
			"Sources/SafeDICore/Models/Fixture.swift:\(line): uncheckedConcurrency: `nonisolated(unsafe)` opts out of the compiler’s proof of concurrency safety",
		])
	}

	@Test(arguments: [
		"final class Box: @unchecked Sendable {}",
		"struct Box: Hashable, @unchecked Sendable {}",
		"extension Box: @unchecked Sendable {}",
	])
	func sourceRuleCheck_findsUncheckedConcurrency_whenTypeConformsToUncheckedSendable(declaration: String) {
		#expect(findings(in: declaration) == [
			"Sources/SafeDICore/Models/Fixture.swift:1: uncheckedConcurrency: `@unchecked Sendable` opts out of the compiler’s proof of concurrency safety",
		])
	}

	@Test
	func sourceRuleCheck_findsUncheckedConcurrency_whenPluginDeclaresNonisolatedUnsafe() {
		#expect(findings(in: "nonisolated(unsafe) var cache = [Int]()", at: "Plugins/Shared.swift") == [
			"Plugins/Shared.swift:1: uncheckedConcurrency: `nonisolated(unsafe)` opts out of the compiler’s proof of concurrency safety",
		])
	}

	@Test
	func sourceRuleCheck_findsNoUncheckedConcurrency_whenCodeIsNonisolatedOrSendable() {
		#expect(findings(in: """
		nonisolated func run() {}
		final class Box: Sendable {
		    nonisolated var name: String { "" }
		}
		struct Value: @MainActor Equatable {}
		_ = "nonisolated(unsafe) @unchecked Sendable"
		""") == [])
	}

	@Test
	func sourceRuleCheck_findsNothing_whenWaiverOfUncheckedConcurrencyCitesDansOK() {
		#expect(findings(in: """
		// safedi-source-rule: allow uncheckedConcurrency — Dan’s OK: pull request 930, for this cache alone.
		nonisolated(unsafe) var cache = [Int]()
		""") == [])
	}

	@Test
	func sourceRuleCheck_findsWaiver_whenWaiverOfUncheckedConcurrencyCitesNoOKFromDan() {
		#expect(findings(in: """
		// safedi-source-rule: allow uncheckedConcurrency — only `deinit` mutates it.
		nonisolated(unsafe) var cache = [Int]()
		""") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: waiver: the waiver of `uncheckedConcurrency` must cite Dan’s explicit OK for this site: `— Dan’s OK: <where he gave it>`",
		])
	}

	@Test
	func sourceRuleCheck_findsWaiver_whenTheWaivedRuleDoesNotApplyToTheFile() {
		#expect(findings(in: "_ = try? load() // safedi-source-rule: allow optionalTry — the error is reported elsewhere") == [
			"Sources/SafeDICore/Models/Fixture.swift:1: waiver: the waiver of `optionalTry` waives no site on line 1",
		])
	}

	// MARK: Error types

	@Test(arguments: [
		("struct Failure: Error {}", "Failure"),
		("struct Failure: Swift.Error {}", "Failure"),
		("enum Failure: Error, Equatable {}", "Failure"),
		("final class Failure: Error {}", "Failure"),
		("actor Failure: Error {}", "Failure"),
		("struct Failure<Value>: Error {}", "Failure"),
		("struct Failure: Error & Sendable {}", "Failure"),
		("struct Failure: @unchecked Sendable, Error {}", "Failure"),
		("struct Failure: LocalizedError {}", "Failure"),
		("struct Failure {}\nextension Failure: Error {}", "Failure"),
		("protocol LocatedFailure: Error {}\nstruct Failure: LocatedFailure {}", "Failure"),
		("struct Failure: LocatedFailure {}\nprotocol LocatedFailure: Located {}\nprotocol Located: Error {}", "Failure"),
		("typealias Failing = Error\nstruct Failure: Failing {}", "Failure"),
		("struct Outer {\n\tstruct Failure: Error {}\n}", "Outer.Failure"),
		("extension Outer {\n\tenum Failure: Error {}\n}", "Outer.Failure"),
		("func validate() {\n\tstruct Failure: Error {}\n}", "Failure"),
		("protocol LocatedFailure: Error {}\nextension DecodingError: LocatedFailure {}", "DecodingError"),
	])
	func errorTypes_findsErrorType_whenATypeConformsToError(source: String, errorType: String) {
		#expect(ErrorTypeDeclarations.errorTypes(in: [RepositorySwiftFile(path: "Sources/SafeDICore/Fixture.swift", source: source)]) == [
			errorType: "Sources/SafeDICore/Fixture.swift",
		])
	}

	@Test
	func errorTypes_findsErrorType_whenAnotherFileDeclaresTheProtocolItConformsTo() {
		#expect(ErrorTypeDeclarations.errorTypes(in: [
			RepositorySwiftFile(path: "Sources/SafeDICore/A.swift", source: "struct Failure: LocatedFailure {}"),
			RepositorySwiftFile(path: "Sources/SafeDICore/B.swift", source: "protocol LocatedFailure: Error {}"),
		]) == ["Failure": "Sources/SafeDICore/A.swift"])
	}

	@Test(arguments: [
		"class Base: Error {}\nfinal class Failure: Base {}",
		"final class Failure: Base {}\nclass Base: LocatedFailure {}\nprotocol LocatedFailure: Error {}",
	])
	func errorTypes_findsSubclass_whenItsSuperclassConformsToError(source: String) {
		#expect(ErrorTypeDeclarations.errorTypes(in: [RepositorySwiftFile(path: "Sources/SafeDICore/Fixture.swift", source: source)]) == [
			"Base": "Sources/SafeDICore/Fixture.swift",
			"Failure": "Sources/SafeDICore/Fixture.swift",
		])
	}

	@Test
	func errorTypes_findsNothing_whenNoTypeConformsToError() {
		#expect(ErrorTypeDeclarations.errorTypes(in: [RepositorySwiftFile(path: "Sources/SafeDICore/Fixture.swift", source: """
		struct ErrorDescription: CustomStringConvertible {}
		protocol LocatedFailure: Error {}
		class Box: Container<Error> {}
		struct Failure: Equatable {}
		""")]) == [:])
	}

	@Test
	func errorReportingSites_findNoProblem_whenEachErrorTypeIsListedWithCodeInItsFile() {
		#expect(ErrorReportingSite.problems(
			ofRegistry: ["Failure": ErrorReportingSite(path: "Sources/SafeDITool/Run.swift", code: "catch let error as Failure")],
			errorTypes: ["Failure": "Sources/SafeDICore/Failure.swift"],
			files: [RepositorySwiftFile(path: "Sources/SafeDITool/Run.swift", source: "do { try run() } catch let error\n\tas Failure { report(error) }")],
		) == [])
	}

	@Test
	func errorReportingSites_findProblem_whenAnErrorTypeIsNotListed() {
		#expect(ErrorReportingSite.problems(
			ofRegistry: [:],
			errorTypes: ["Failure": "Sources/SafeDICore/Failure.swift"],
			files: [],
		) == [
			"Sources/SafeDICore/Failure.swift: `Failure` is an error type, so `ErrorReportingSite.byErrorType` lists it with the site that reports it",
		])
	}

	@Test
	func errorReportingSites_findProblem_whenAnEntryNamesNoErrorType() {
		#expect(ErrorReportingSite.problems(
			ofRegistry: ["Failure": ErrorReportingSite(path: "Sources/SafeDITool/Run.swift", code: "catch let error as Failure")],
			errorTypes: [:],
			files: [RepositorySwiftFile(path: "Sources/SafeDITool/Run.swift", source: "do { try run() } catch let error as Failure {}")],
		) == [
			"`ErrorReportingSite.byErrorType` lists `Failure`, which is not an error type",
		])
	}

	@Test
	func errorReportingSites_findProblem_whenTheSiteIsNotCodeInItsFile() {
		#expect(ErrorReportingSite.problems(
			ofRegistry: ["Failure": ErrorReportingSite(path: "Sources/SafeDITool/Run.swift", code: "catch let error as Failure")],
			errorTypes: ["Failure": "Sources/SafeDICore/Failure.swift"],
			files: [RepositorySwiftFile(path: "Sources/SafeDITool/Run.swift", source: "// catch let error as Failure")],
		) == [
			"`ErrorReportingSite.byErrorType` reports `Failure` with `catch let error as Failure`, which is not in Sources/SafeDITool/Run.swift",
		])
	}

	// MARK: Private

	/// An actor named `Generator`, with a stored property `memo` and a computed one, `computed`.
	private static let actorFixture = "actor Generator {\n    var memo: Int?\n    var computed: Int { 1 }\n}"

	/// What `ActorStateRuleCheck` finds in `sources`, the files `Sources/SafeDICore/Fixture<index>.swift`.
	private func actorStateFindings(in sources: [String]) -> [String] {
		ActorStateRuleCheck.findings(in: sources.enumerated().map { index, source in
			RepositorySwiftFile(path: "Sources/SafeDICore/Fixture\(index).swift", source: source)
		})
	}

	private func findings(in source: String, at path: String = "Sources/SafeDICore/Models/Fixture.swift") -> [String] {
		SourceRuleCheck.findings(in: source, at: path).map(\.description)
	}

	/// The Swift files under `Sources`, `Plugins`, `TuistPlugins` and `Tests/SafeDIToolTestSupport`, each with its
	/// findings, read and checked once for every test of SafeDI's sources.
	private static let checkedFiles = Result {
		try RepositorySwiftFile.files(under: ["Sources", "Plugins", "TuistPlugins", "Tests/SafeDIToolTestSupport"]).map { file in
			(file: file, findings: SourceRuleCheck.findings(in: file.source, at: file.path))
		}
	}

	/// The findings in SafeDI's sources that break one of `rules`.
	private func findings(of rules: Set<SourceRule>) throws -> [String] {
		try Self.checkedFiles.get().flatMap { checkedFile in
			checkedFile.findings.compactMap { finding in
				switch finding.subject {
				case let .rule(rule):
					rules.contains(rule) ? finding.description : nil
				case .waiver:
					nil
				}
			}
		}
	}
}
