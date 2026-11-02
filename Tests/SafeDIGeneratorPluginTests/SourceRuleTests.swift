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
			"Sources/SafeDITool/GenerateCommand.swift",
		]))
		#expect(try findings(of: [.forceUnwrap, .forceTry, .forceCast, .trap, .uniqueKeysWithValues]) == [])
	}

	@Test
	func generators_discardNoErrorWithOptionalTry() throws {
		#expect(try findings(of: [.optionalTry]) == [])
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
			"Sources/SafeDICore/Models/Fixture.swift:1: waiver: a waiver reads `safedi-source-rule: allow <rule> — <reason>`, where the rule is one of `forceUnwrap`, `forceTry`, `forceCast`, `trap`, `uniqueKeysWithValues`, `optionalTry`, `builderFunctionNamePrefix`, `backtick`",
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

	private func findings(in source: String, at path: String = "Sources/SafeDICore/Models/Fixture.swift") -> [String] {
		SourceRuleCheck.findings(in: source, at: path).map(\.description)
	}

	/// The Swift files under `Sources` and `Plugins`, each with its findings, read and checked once for every test of
	/// SafeDI's sources.
	private static let checkedFiles = Result {
		try RepositorySwiftFile.files(under: ["Sources", "Plugins"]).map { file in
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
