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

/// A fill that receives a seam's parameter in a form the parameter does not provide: the tree the seam builds with the
/// fill receives the label in two forms, which the seam's generated initializer cannot take as one parameter. Built with
/// the fulfiller in the seam's module, the seam reports it; with the fulfiller in a caller's module, the caller reports the
/// same error, rather than handing the fill `nil` or another form than inline hands it.
struct SafeDIToolSeamFillReceivesParameterInAnotherFormTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabel_whenFillReceivesValueOfOptionalWrapperPassThrough() async {
		// `Reader` receives `tag` as an optional `LazilyInstantiated`, which provides only itself, so `Home` takes it as
		// `tag: LazilyInstantiated<Tag>?`, and `Impl`, which fills `service`, receives `tag: Tag?`. Inline, `Impl` gets the
		// instance of `Root`'s `tag`; the fill would get `nil`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Home.swift"]): error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `tag` as `tag: LazilyInstantiated<Tag>?` on `Reader` and `tag: Tag?` on `Impl`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `tag` the same way in every type of the tree, or declare it on `Home` as the form that provides the others: `@Received let tag: LazilyInstantiated<Tag>`.
			\(fixtures["Feature"]!["Reader.swift"]): note: `Reader` receives `tag: LazilyInstantiated<Tag>?` here.
			\(fixtures["App"]!["Impl.swift"]):9:5: note: `Impl` receives `tag: Tag?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(readerDeclarations: ["@Received(onlyIfAvailable: true) let tag: LazilyInstantiated<Tag>?"]),
					app: [
						Self.fulfillingType(named: "Impl", declarations: ["@Received(onlyIfAvailable: true) let tag: Tag?"]),
						Self.root,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabel_whenFillReceivesValueOfOptionalWrapperPassThroughUnderSwiftPackagePlugin() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: "Home.swift")).path):1:1: error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `tag` as `tag: LazilyInstantiated<Tag>?` on `Reader` and `tag: Tag?` on `Impl`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `tag` the same way in every type of the tree, or declare it on `Home` as the form that provides the others: `@Received let tag: LazilyInstantiated<Tag>`.
			\(NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: "Reader.swift")).path):7:5: note: `Reader` receives `tag: LazilyInstantiated<Tag>?` here.
			\(NormalizedFilePath(fixtures["App"]!.compilerPath(of: "Impl.swift")).path):9:5: note: `Impl` receives `tag: Tag?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(readerDeclarations: ["@Received(onlyIfAvailable: true) let tag: LazilyInstantiated<Tag>?"]),
					app: [
						Self.fulfillingType(named: "Impl", declarations: ["@Received(onlyIfAvailable: true) let tag: Tag?"]),
						Self.root,
					],
				),
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelAtSeam_whenFulfillerOfSameGraphIsInSeamsModule() async {
		// The same graph built with `Impl` in `Feature`: the seam's own tree receives both forms, which is the error the fill
		// above reports.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Home.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `tag` as `tag: LazilyInstantiated<Tag>?` on `Reader` and `tag: Tag?` on `Impl`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `tag` the same way in every type of the tree, or declare it on `Home` as the form that provides the others: `@Received let tag: LazilyInstantiated<Tag>`.
			\(fixtures["Feature"]!["Reader.swift"]):7:5: note: `Reader` receives `tag: LazilyInstantiated<Tag>?` here.
			\(fixtures["Feature"]!["Impl.swift"]):7:5: note: `Impl` receives `tag: Tag?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(readerDeclarations: ["@Received(onlyIfAvailable: true) let tag: LazilyInstantiated<Tag>?"]) + [
						Self.fulfillingType(named: "Impl", declarations: ["@Received(onlyIfAvailable: true) let tag: Tag?"]),
					],
					app: [Self.root],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabel_whenFillRequiresValueOfOptionalWrapperPassThrough() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Home.swift"]): error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `tag` as `tag: LazilyInstantiated<Tag>?` on `Reader` and `tag: Tag` on `Impl`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `tag` the same way in every type of the tree, or declare it on `Home` as the form that provides the others: `@Received let tag: LazilyInstantiated<Tag>`.
			\(fixtures["Feature"]!["Reader.swift"]): note: `Reader` receives `tag: LazilyInstantiated<Tag>?` here.
			\(fixtures["App"]!["Impl.swift"]):9:5: note: `Impl` receives `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(readerDeclarations: ["@Received(onlyIfAvailable: true) let tag: LazilyInstantiated<Tag>?"]),
					app: [
						Self.fulfillingType(named: "Impl", declarations: ["@Received let tag: Tag"]),
						Self.root,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelToReceiveTheSameWay_whenFillReceivesWrapperBesideRequiredOptionalPassThrough() async {
		// `Reader` requires `tag: Tag?`, which `Host`'s forwarded optional gives it, so `Home` takes a required optional
		// value, which no wrapper form provides: the remedy is to receive `tag` the same way, as the seam's own tree is told.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Home.swift"]): error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `tag` as `tag: Tag?` on `Reader` and `tag: LazilyInstantiated<Tag>?` on `Impl`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `tag` the same way in every type of the tree.
			\(fixtures["Feature"]!["Reader.swift"]): note: `Reader` receives `tag: Tag?` here.
			\(fixtures["App"]!["Impl.swift"]):9:5: note: `Impl` receives `tag: LazilyInstantiated<Tag>?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(readerDeclarations: ["@Received let tag: Tag?"]),
					app: [
						Self.fulfillingType(named: "Impl", declarations: ["@Received(onlyIfAvailable: true) let tag: LazilyInstantiated<Tag>?"]),
						seamFixtureType(named: "Host", declarations: ["@Forwarded let tag: Tag?", "@Instantiated let home: Home"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabel_whenTypeBeneathFillReceivesValueOfOptionalWrapperPassThrough() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Home.swift"]): error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `tag` as `tag: LazilyInstantiated<Tag>?` on `Reader` and `tag: Tag?` on `ImplDetail`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `tag` the same way in every type of the tree, or declare it on `Home` as the form that provides the others: `@Received let tag: LazilyInstantiated<Tag>`.
			\(fixtures["Feature"]!["Reader.swift"]): note: `Reader` receives `tag: LazilyInstantiated<Tag>?` here.
			\(fixtures["App"]!["ImplDetail.swift"]):9:5: note: `ImplDetail` receives `tag: Tag?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(readerDeclarations: ["@Received(onlyIfAvailable: true) let tag: LazilyInstantiated<Tag>?"]),
					app: [
						seamFixtureType(named: "ImplDetail", declarations: ["@Received(onlyIfAvailable: true) let tag: Tag?"]),
						Self.fulfillingType(named: "Impl", declarations: ["@Instantiated let detail: ImplDetail"]),
						Self.root,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabel_whenFillReceivesValueOfSeamsOwnOptionalWrapper() async {
		// `Home` itself receives `tag` as an optional `LazilyInstantiated`: its own receive is a parameter as declared, and
		// provides only itself.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Home.swift"]): error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `tag` as `tag: LazilyInstantiated<Tag>?` on `Home` and `tag: Tag?` on `Impl`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `tag` the same way in every type of the tree, or declare it on `Home` as the form that provides the others: `@Received let tag: LazilyInstantiated<Tag>`.
			\(fixtures["Feature"]!["Home.swift"]): note: `Home` receives `tag: LazilyInstantiated<Tag>?` here.
			\(fixtures["App"]!["Impl.swift"]):9:5: note: `Impl` receives `tag: Tag?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Service {}",
						seamFixtureType(named: "Tag", declarations: []),
						seamFixtureType(named: "Home", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let tag: LazilyInstantiated<Tag>?", "@Instantiated let service: any Service"]),
					],
					app: [
						Self.fulfillingType(named: "Impl", declarations: ["@Received(onlyIfAvailable: true) let tag: Tag?"]),
						Self.root,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabel_whenFillReceivesOtherTypeUnderPassThroughsLabel() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Home.swift"]): error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `tag` as `tag: Tag?` on `Reader` and `tag: Label?` on `Impl`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Feature"]!["Reader.swift"]): note: `Reader` receives `tag: Tag?` here.
			\(fixtures["App"]!["Impl.swift"]):9:5: note: `Impl` receives `tag: Label?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(readerDeclarations: ["@Received(onlyIfAvailable: true) let tag: Tag?"]) + [
						seamFixtureType(named: "Label", declarations: []),
					],
					app: [
						Self.fulfillingType(named: "Impl", declarations: ["@Received(onlyIfAvailable: true) let tag: Label?"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsWrapperFromCallersDeclaration_whenFillRequiresWrapperOfValuePassThrough() async throws {
		// The seam takes `tag: Tag`, which `Reader` requires, deferred; `Impl` requires the wrapper. Built in one module, the
		// seam would take the wrapper, which provides both forms, so this is no second form: the fill reads `tag` from the
		// caller's scope, as it reads every label a deferred parameter binds, and gets `Root`'s wrapper, as inline.
		let modules = Self.modules(
			feature: Self.feature(readerDeclarations: ["@Received let tag: Tag"]),
			app: [
				Self.fulfillingType(named: "Impl", declarations: ["@Received let tag: LazilyInstantiated<Tag>"]),
				Self.root,
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: (LazilyInstantiated<Tag>, Reader) -> __safeDI_Built

			        public init(service: @escaping (LazilyInstantiated<Tag>, Reader) -> __safeDI_Built) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(service: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			        let reader = Reader(tag: tag.instance)
			        let service: any Service = __safeDI_serviceBuilder.service(tag, reader)
			        self.init(reader: reader, service: service)
			    }
			}

			extension Home {
			    public enum __safeDI_Home_3246A33D3BB184B5 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_tag() -> Tag {
			            Tag()
			        }
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_3246A33D3BB184B5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_serviceBuilder_Home() -> Home.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { scope_tag, scope_reader in
			                    let service: any Service = Impl(tag: tag)
			                    return service
			                })
			            }
			            return Home(__safeDI_tag: tag.instance, __safeDI_serviceBuilder: __safeDI_serviceBuilder_Home())
			        }
			        let home: Home = __safeDI_home()
			        self.init(tag: tag, home: home)
			    }
			}
			""",
		])
		guard compileVerificationIsEnabled else { return }
		let visibleModules = Self.modules(
			feature: Self.feature(readerDeclarations: ["@Received let tag: Tag"]) + [
				Self.fulfillingType(named: "Impl", declarations: ["@Received let tag: LazilyInstantiated<Tag>"]),
			],
			app: [Self.root],
		)
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsParametersShareLabelForEachLabel_whenFillReceivesTwoPassThroughsInOtherForms() async {
		// Both errors are at `Home`, ordered by their notes: `Reader` receives `tag` first.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Home.swift"]): error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `tag` as `tag: LazilyInstantiated<Tag>?` on `Reader` and `tag: Tag?` on `Impl`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `tag` the same way in every type of the tree, or declare it on `Home` as the form that provides the others: `@Received let tag: LazilyInstantiated<Tag>`.
			\(fixtures["Feature"]!["Reader.swift"]): note: `Reader` receives `tag: LazilyInstantiated<Tag>?` here.
			\(fixtures["App"]!["Impl.swift"]):10:5: note: `Impl` receives `tag: Tag?` here.
			\(fixtures["Feature"]!["Home.swift"]): error: SafeDI cannot generate the dependency tree of `Home`: its tree receives `mark` as `mark: LazilyInstantiated<Mark>?` on `Reader` and `mark: Mark?` on `Impl`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `mark` the same way in every type of the tree, or declare it on `Home` as the form that provides the others: `@Received let mark: LazilyInstantiated<Mark>`.
			\(fixtures["Feature"]!["Reader.swift"]): note: `Reader` receives `mark: LazilyInstantiated<Mark>?` here.
			\(fixtures["App"]!["Impl.swift"]):11:5: note: `Impl` receives `mark: Mark?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(readerDeclarations: [
						"@Received(onlyIfAvailable: true) let tag: LazilyInstantiated<Tag>?",
						"@Received(onlyIfAvailable: true) let mark: LazilyInstantiated<Mark>?",
					]) + [
						seamFixtureType(named: "Mark", declarations: []),
					],
					app: [
						Self.fulfillingType(named: "Impl", declarations: ["@Received(onlyIfAvailable: true) let tag: Tag?", "@Received(onlyIfAvailable: true) let mark: Mark?"]),
						Self.root,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Home`, a seam that instantiates `reader` and then `service`, a hole; `Reader`, with `readerDeclarations`; and `Tag`.
	private static func feature(readerDeclarations: [String]) -> [String] {
		[
			"public protocol Service {}",
			seamFixtureType(named: "Tag", declarations: []),
			seamFixtureType(named: "Reader", declarations: readerDeclarations),
			seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let reader: Reader", "@Instantiated let service: any Service"]),
		]
	}

	/// `Root`, which instantiates `tag` lazily, then `home`.
	private static let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let tag: LazilyInstantiated<Tag>", "@Instantiated let home: Home"])

	private static func fulfillingType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", Service")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Service.self])\n")
	}

	private static func modules(feature: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}
}
