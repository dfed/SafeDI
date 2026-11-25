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

/// A calling mock whose fill of a called public mock’s place requires a value the called type’s tree receives only if
/// available, as a `LazilyInstantiated` or `SendableLazilyInstantiated`. The called mock hands the fill only that
/// optional wrapper, which gives no value, and the production twin rejects the tree, which receives the label in two
/// forms, so the calling mock reports at the twin’s sites rather than generating a fill that does not compile.
struct SafeDIToolCallingMockOptionalWrapperFillTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the twin’s error

	@Test(arguments: GraphFuzzerCallingMockCell.Caller.allCases, Wrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsErrorAtTwinsSites_whenFillRequiresValueCalledTypeReceivesInOptionalWrapper(caller: GraphFuzzerCallingMockCell.Caller, wrapper: Wrapper) async {
		// `Screen`, a public mock of `Feed`, receives `session` only if available in a wrapper, and `Fill`, which fills its
		// place, requires the instance and holds an `Instantiator<Screen>`, so the call inside the fill re-enters `Screen`’s
		// mock.
		let graph = Self.graph(caller: caller, wrapper: wrapper, fill: .requiresValue(buildsCalledTypeAgain: true))
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot fill the builder for `Screen`’s `holeBuilder: ErasedInstantiator<Int, AnyHole>` (`holeBuilder` of `fill_AnyHoleBuilder`) in a call of `Screen`’s mock: its tree receives `session` as `session: \(wrapper.name)<Session>?` on `Screen` and `session: Session` on `Fill`, so the mock hands the builder only `session: \(wrapper.name)<Session>?`, which holds no value where its caller passes none. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: \(wrapper.name)<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):21:5: note: `Screen` receives `session: \(wrapper.name)<Session>?` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `session` as `session: \(wrapper.name)<Session>?` on `Screen` and `session: Session` on `Fill`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: \(wrapper.name)<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):21:5: note: `Screen` receives `session: \(wrapper.name)<Session>?` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.twin), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: GraphFuzzerCallingMockCell.Caller.allCases, Wrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsErrorAtTwinsSites_whenFillThatHoldsNoBuilderOfCalledTypeRequiresValueItReceivesInOptionalWrapper(caller: GraphFuzzerCallingMockCell.Caller, wrapper: Wrapper) async {
		// The same, where `Fill` holds no `Instantiator<Screen>`: the fill reads the caller’s own declaration, so the mock
		// compiled before, but its twin reports the error all the same.
		let graph = Self.graph(caller: caller, wrapper: wrapper, fill: .requiresValue(buildsCalledTypeAgain: false))
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot fill the builder for `Screen`’s `holeBuilder: ErasedInstantiator<Int, AnyHole>` (`holeBuilder` of `fill_AnyHoleBuilder`) in a call of `Screen`’s mock: its tree receives `session` as `session: \(wrapper.name)<Session>?` on `Screen` and `session: Session` on `Fill`, so the mock hands the builder only `session: \(wrapper.name)<Session>?`, which holds no value where its caller passes none. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: \(wrapper.name)<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):21:5: note: `Screen` receives `session: \(wrapper.name)<Session>?` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `session` as `session: \(wrapper.name)<Session>?` on `Screen` and `session: Session` on `Fill`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: \(wrapper.name)<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):21:5: note: `Screen` receives `session: \(wrapper.name)<Session>?` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.twin), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsErrorAtTwinsSites_whenFillRequiresValueCalledTypeReceivesInOptionalWrapperUnderSwiftPackagePlugin() async {
		// The SwiftPM plugin scans every module before generating, which changes how the tool finds the files, not which
		// declarations it reports.
		let graph = Self.graph(caller: .internal, wrapper: .lazilyInstantiated, fill: .requiresValue(buildsCalledTypeAgain: true))
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(NormalizedFilePath(fixtures["Feed"]!.compilerPath(of: "FeedTypes.swift")).path):14:1: error: SafeDI cannot fill the builder for `Screen`’s `holeBuilder: ErasedInstantiator<Int, AnyHole>` (`holeBuilder` of `fill_AnyHoleBuilder`) in a call of `Screen`’s mock: its tree receives `session` as `session: LazilyInstantiated<Session>?` on `Screen` and `session: Session` on `Fill`, so the mock hands the builder only `session: LazilyInstantiated<Session>?`, which holds no value where its caller passes none. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: LazilyInstantiated<Session>`.
			\(NormalizedFilePath(fixtures["Feed"]!.compilerPath(of: "FeedTypes.swift")).path):21:5: note: `Screen` receives `session: LazilyInstantiated<Session>?` here.
			\(NormalizedFilePath(fixtures["App"]!.compilerPath(of: "AppTypes.swift")).path):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .swiftPackagePlugin, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsErrorAtTwinsSites_whenTypeBeneathCalledTypeReceivesValueInOptionalWrapper(receivesThroughAlias: Bool) async {
		// `Reader`, which `Screen` instantiates, receives `session` only if available in a wrapper, under its label or through
		// an alias, and `Screen` declares none of it: the twin’s seam takes it as a pass-through, and both name `Reader`.
		let graph = Self.graph(caller: .internal, wrapper: .lazilyInstantiated, fill: .requiresValue(buildsCalledTypeAgain: true), receiver: receivesThroughAlias ? .readerThroughAlias : .reader)
		let readerReceive = receivesThroughAlias ? "session: LazilyInstantiated<Session>" : "session: LazilyInstantiated<Session>?"
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot fill the builder for `Screen`’s `holeBuilder: ErasedInstantiator<Int, AnyHole>` (`holeBuilder` of `fill_AnyHoleBuilder`) in a call of `Screen`’s mock: its tree receives `session` as `\(readerReceive)` on `Reader` and `session: Session` on `Fill`, so the mock hands the builder only `session: LazilyInstantiated<Session>?`, which holds no value where its caller passes none. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: LazilyInstantiated<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):28:5: note: `Reader` receives `\(readerReceive)` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `session` as `\(readerReceive)` on `Reader` and `session: Session` on `Fill`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: LazilyInstantiated<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):28:5: note: `Reader` receives `\(readerReceive)` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.twin), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsErrorWithTwinsNotes_whenCalledTypeAndTypeBeneathItReceiveValueInOptionalWrapper() async {
		// `Screen` and `Reader`, which `Screen` instantiates, both receive `session` only if available. The twin’s seam takes
		// `Screen`’s own property as its parameter, which `Reader` receives from `Screen`, so the notes name `Screen` and the
		// fill, in the twin’s order, and not `Reader`.
		let graph = Self.graph(caller: .internal, wrapper: .lazilyInstantiated, fill: .requiresValue(buildsCalledTypeAgain: true), receiver: .screenAndReader)
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot fill the builder for `Screen`’s `holeBuilder: ErasedInstantiator<Int, AnyHole>` (`holeBuilder` of `fill_AnyHoleBuilder`) in a call of `Screen`’s mock: its tree receives `session` as `session: LazilyInstantiated<Session>?` on `Screen` and `session: Session` on `Fill`, so the mock hands the builder only `session: LazilyInstantiated<Session>?`, which holds no value where its caller passes none. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: LazilyInstantiated<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):22:5: note: `Screen` receives `session: LazilyInstantiated<Session>?` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `session` as `session: LazilyInstantiated<Session>?` on `Screen` and `session: Session` on `Fill`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: LazilyInstantiated<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):22:5: note: `Screen` receives `session: LazilyInstantiated<Session>?` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.twin), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsErrorAtTwinsSites_whenTypesAreMainActor() async {
		let graph = Self.graph(caller: .internal, wrapper: .lazilyInstantiated, fill: .requiresValue(buildsCalledTypeAgain: true), isolation: "@MainActor ")
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot fill the builder for `Screen`’s `holeBuilder: ErasedInstantiator<Int, AnyHole>` (`holeBuilder` of `fill_AnyHoleBuilder`) in a call of `Screen`’s mock: its tree receives `session` as `session: LazilyInstantiated<Session>?` on `Screen` and `session: Session` on `Fill`, so the mock hands the builder only `session: LazilyInstantiated<Session>?`, which holds no value where its caller passes none. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: LazilyInstantiated<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):21:5: note: `Screen` receives `session: LazilyInstantiated<Session>?` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["FeedTypes.swift"]):14:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `session` as `session: LazilyInstantiated<Session>?` on `Screen` and `session: Session` on `Fill`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: LazilyInstantiated<Session>`.
			\(fixtures["Feed"]!["FeedTypes.swift"]):21:5: note: `Screen` receives `session: LazilyInstantiated<Session>?` here.
			\(fixtures["App"]!["AppTypes.swift"]):13:5: note: `Fill` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.twin), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: Wrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesMockOutsideMockCondition_whenBuildLeavesMockConditionInactive(wrapper: Wrapper) async throws {
		// A release build compiles no generated mock, so the error, which is about the mock’s code alone, is not reported.
		let graph = Self.graph(caller: .internal, wrapper: wrapper, fill: .requiresValue(buildsCalledTypeAgain: true), mockBuild: .release)
		let output = try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles.keys.sorted() == ["App.swift"])
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			if let failure = compilation.failure {
				failure.recordIssues(skippingVerificationBy: "pass `compileVerification: .skipped`", sourceLocation: #_sourceLocation)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesFillThatHoldsOptionalWrapper_whenBuildLeavesMockConditionInactive() async throws {
		// In a release build, the fill is generated as it is: it passes the called mock’s optional wrapper where `Fill` requires
		// `Session`, inside the mock condition the build leaves inactive.
		let graph = Self.graph(caller: .internal, wrapper: .lazilyInstantiated, fill: .requiresValue(buildsCalledTypeAgain: true), mockBuild: .release)
		let output = try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session,
		                screen: screen
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }
		        var screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                session: (() -> Session)?,
		                screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)?
		            ) {
		                self.session = session
		                self.screen = screen
		            }

		            let session: (() -> Session)?
		            let screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)?
		        }
		    }

		    static func mock(
		        fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: LazilyInstantiated<Session>?) -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    func __safeDI_screenBuilder() -> Screen {
		                        Screen.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
		                    }
		                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                    return Fill(ticket: ticket, session: session, screenBuilder: screenBuilder)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
		            }
		            _ = Screen.__safeDI_Screen_mock_8C12403263F5CE07.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(fill_AnyHoleBuilder ?? __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: session), session) } else { Screen.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
	}

	// MARK: Tests – the remedies

	@Test(arguments: GraphFuzzerCallingMockCell.Caller.allCases, Wrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenCalledTypeRequiresWrapperTheErrorNames(caller: GraphFuzzerCallingMockCell.Caller, wrapper: Wrapper) async throws {
		// The remedy that declares the providing form on `Screen`: the called mock’s copy is a required wrapper, whose instance
		// the fill reads, and the call inside the fill hands `Screen` built again the same instance.
		let graph = Self.graph(caller: caller, wrapper: wrapper, fill: .requiresValue(buildsCalledTypeAgain: true), screenReceivesRequiredWrapper: true)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles.keys.sorted() == ["App.swift"])
		if compileVerificationIsEnabled {
			try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.requiredWrapperProbe(of: wrapper)])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFillInstanceOfCalledMocksWrapper_whenCalledTypeRequiresWrapperTheErrorNames() async throws {
		let graph = Self.graph(caller: .internal, wrapper: .lazilyInstantiated, fill: .requiresValue(buildsCalledTypeAgain: true), screenReceivesRequiredWrapper: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct holeBuilder_Values {
		            public let session: LazilyInstantiated<Session>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.init(holeBuilder: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        session: LazilyInstantiated<Session>,
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder
		    ) -> Screen {
		        Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session: LazilyInstantiated<Session>,
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Screen {
		        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session)))
		        return Screen(session: session, holeBuilder: holeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_83809BBB9344E886 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            screen: ((LazilyInstantiated<Session>, @escaping ErasedInstantiator<Int, AnyHole>.Builder) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session,
		                screen: screen
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }
		        var screen: ((LazilyInstantiated<Session>, @escaping ErasedInstantiator<Int, AnyHole>.Builder) -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                session: (() -> Session)?,
		                screen: ((LazilyInstantiated<Session>, @escaping ErasedInstantiator<Int, AnyHole>.Builder) -> Screen)?
		            ) {
		                self.session = session
		                self.screen = screen
		            }

		            let session: (() -> Session)?
		            let screen: ((LazilyInstantiated<Session>, @escaping ErasedInstantiator<Int, AnyHole>.Builder) -> Screen)?
		        }
		    }

		    static func mock(
		        fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: LazilyInstantiated<Session>) -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    func __safeDI_screenBuilder() -> Screen {
		                        Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen())
		                    }
		                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                    return Fill(ticket: ticket, session: session.instance, screenBuilder: screenBuilder)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
		            }
		            _ = Screen.__safeDI_Screen_mock_83809BBB9344E886.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(session, fill_AnyHoleBuilder ?? __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: session)) } else { Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen()) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
	}

	@Test(arguments: GraphFuzzerCallingMockCell.Caller.allCases, Wrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenFillReceivesWrapperAsCalledTypeDoes(caller: GraphFuzzerCallingMockCell.Caller, wrapper: Wrapper) async throws {
		// The remedy that receives `session` the same way in every type of the tree: `Fill` receives the wrapper only if
		// available, as `Screen` does, and reads the caller’s.
		let graph = Self.graph(caller: caller, wrapper: wrapper, fill: .receivesWrapperOnlyIfAvailable(buildsCalledTypeAgain: false))
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles.keys.sorted() == ["App.swift"])
		if compileVerificationIsEnabled {
			try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.sameWayProbe(of: wrapper)])
		}
	}

	@Test(arguments: GraphFuzzerCallingMockCell.Caller.allCases, Wrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineValues_whenFillThatReceivesWrapperAsCalledTypeDoesBuildsCalledTypeAgain(caller: GraphFuzzerCallingMockCell.Caller, wrapper: Wrapper) async throws {
		// The same remedy where `Fill` also holds an `Instantiator<Screen>`, the shape the error is reported for: the call
		// inside the fill hands `Screen` built again the caller’s instance, as inline hands it the caller’s wrapper.
		let graph = Self.graph(caller: caller, wrapper: wrapper, fill: .receivesWrapperOnlyIfAvailable(buildsCalledTypeAgain: true))
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles.keys.sorted() == ["App.swift"])
		if compileVerificationIsEnabled {
			try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.sameWayBuiltAgainProbe(of: wrapper)])
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The wrapper `Root` holds `session` in, which `Screen`’s tree receives optionally.
	enum Wrapper: CaseIterable, CustomTestStringConvertible {
		case lazilyInstantiated
		case sendableLazilyInstantiated

		var name: String {
			switch self {
			case .lazilyInstantiated:
				"LazilyInstantiated"
			case .sendableLazilyInstantiated:
				"SendableLazilyInstantiated"
			}
		}

		var testDescription: String {
			name
		}
	}

	/// How `Fill` receives `session`.
	enum FillReceive {
		/// `@Received let session: Session`, with an `Instantiator<Screen>` where `buildsCalledTypeAgain`.
		case requiresValue(buildsCalledTypeAgain: Bool)
		/// `@Received(onlyIfAvailable: true) let session: <Wrapper><Session>?`, as `Screen` receives it, with an
		/// `Instantiator<Screen>` where `buildsCalledTypeAgain`.
		case receivesWrapperOnlyIfAvailable(buildsCalledTypeAgain: Bool)
	}

	/// Which type of `Screen`’s tree receives `session` only if available.
	enum Receiver {
		/// `Screen` itself, under the label.
		case screen
		/// `Reader`, which `Screen` instantiates, under the label.
		case reader
		/// `Reader`, through an alias of the label.
		case readerThroughAlias
		/// `Screen` under the label, and `Reader`, which `Screen` instantiates, under it too.
		case screenAndReader
	}

	/// The graph: module `Feed` declares `Session`, which `App` declares instantiable, and `Screen`, a public mock whose tree
	/// receives `session` only if available in `wrapper` and whose place of `AnyHole` no type `Feed` sees fulfills; module
	/// `App` declares `Fill`, which fills it, and the caller `Root`, which holds `session` in `wrapper` and builds `Screen`.
	private static func graph(
		caller: GraphFuzzerCallingMockCell.Caller,
		wrapper: Wrapper,
		fill: FillReceive,
		receiver: Receiver = .screen,
		screenReceivesRequiredWrapper: Bool = false,
		isolation: String = "",
		mockBuild: GraphFuzzerCallingMockGraph.MockBuild = .compilesGeneratedMocks,
	) -> GraphFuzzerCallingMockGraph {
		let wrapped = "\(wrapper.name)<Session>"
		func feed(attribute: String) -> String {
			let screenBody = switch receiver {
			case .screen:
				// The remedy declares the wrapper required, on the same lines.
				screenReceivesRequiredWrapper
					? """
					    init(session: \(wrapped), holeBuilder: ErasedInstantiator<Int, AnyHole>) {
					        self.session = session
					        self.holeBuilder = holeBuilder
					    }

					    @Received public let session: \(wrapped)
					"""
					: """
					    init(session: \(wrapped)?, holeBuilder: ErasedInstantiator<Int, AnyHole>) {
					        self.session = session
					        self.holeBuilder = holeBuilder
					    }

					    @Received(onlyIfAvailable: true) public let session: \(wrapped)?
					"""
			case .screenAndReader:
				"""
				    init(session: \(wrapped)?, reader: Reader, holeBuilder: ErasedInstantiator<Int, AnyHole>) {
				        self.session = session
				        self.reader = reader
				        self.holeBuilder = holeBuilder
				    }

				    @Received(onlyIfAvailable: true) public let session: \(wrapped)?
				    @Instantiated public let reader: Reader
				"""
			case .reader, .readerThroughAlias:
				"""
				    init(reader: Reader, holeBuilder: ErasedInstantiator<Int, AnyHole>) {
				        self.reader = reader
				        self.holeBuilder = holeBuilder
				    }

				    @Instantiated public let reader: Reader
				"""
			}
			let reader = switch receiver {
			case .screen:
				""
			case .reader, .screenAndReader:
				"""


				@Instantiable
				public final class Reader: Instantiable {
				    init(session: \(wrapped)?) { self.session = session }
				    @Received(onlyIfAvailable: true) public let session: \(wrapped)?
				}
				"""
			case .readerThroughAlias:
				"""


				@Instantiable
				public final class Reader: Instantiable {
				    init(readerSession: \(wrapped)?) { self.readerSession = readerSession }
				    @Received(fulfilledByDependencyNamed: "session", ofType: \(wrapped).self, onlyIfAvailable: true) public let readerSession: \(wrapped)?
				}
				"""
			}
			return """
			import SafeDI

			public protocol HoleProtocol {}

			public struct AnyHole: HoleProtocol {
			    public init(_ value: any HoleProtocol) { self.value = value }
			    public let value: any HoleProtocol
			}

			public final class Session: Instantiable, Sendable {
			    public init() {}
			}

			\(attribute)
			\(isolation)public final class Screen: Instantiable {
			\(screenBody)
			    @Instantiated(fulfilledByType: "Fill", erasedToConcreteExistential: true) public let holeBuilder: ErasedInstantiator<Int, AnyHole>
			}\(reader)

			"""
		}
		func app(attribute: String) -> String {
			let fillProperties: [(attribute: String, label: String, type: String)] = switch fill {
			case let .requiresValue(buildsCalledTypeAgain):
				[("@Received", "session", "Session")] + (buildsCalledTypeAgain ? [("@Instantiated", "screenBuilder", "Instantiator<Screen>")] : [])
			case let .receivesWrapperOnlyIfAvailable(buildsCalledTypeAgain):
				[("@Received(onlyIfAvailable: true)", "session", "\(wrapped)?")] + (buildsCalledTypeAgain ? [("@Instantiated", "screenBuilder", "Instantiator<Screen>")] : [])
			}
			let parameters = (["ticket: Int"] + fillProperties.map { "\($0.label): \($0.type)" }).joined(separator: ", ")
			let assignments = (["self.ticket = ticket"] + fillProperties.map { "self.\($0.label) = \($0.label)" }).joined(separator: "; ")
			let declarations = fillProperties.map { "    \($0.attribute) public let \($0.label): \($0.type)" }.joined(separator: "\n")
			return """
			import Feed
			import SafeDI

			@Instantiable(conformsElsewhere: true)
			extension Session {
			    public static func instantiate() -> Session { Session() }
			}

			@Instantiable
			\(isolation)public final class Fill: Instantiable, HoleProtocol {
			    public init(\(parameters)) { \(assignments) }
			    @Forwarded public let ticket: Int
			\(declarations)
			}

			\(attribute)
			\(isolation)public final class Root: Instantiable {
			    public init(screen: Screen, session: \(wrapped)) {
			        self.screen = screen
			        self.session = session
			    }

			    @Instantiated public let screen: Screen
			    @Instantiated public let session: \(wrapped)
			}

			"""
		}
		return GraphFuzzerCallingMockGraph(
			name: "a fill that requires the value a called type receives only if available in a wrapper",
			mockFiles: [
				GraphFuzzerCallingMockGraph.File(module: "Feed", dependencies: [], content: feed(attribute: "@Instantiable(generateMock: .public)")),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Feed"], content: app(attribute: callerAttribute(of: caller))),
			],
			twinFiles: [
				GraphFuzzerCallingMockGraph.File(module: "Feed", dependencies: [], content: feed(attribute: "@Instantiable(generateDependencyTree: true, generateMock: .public)")),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Feed"], content: app(attribute: "@Instantiable(generateDependencyTree: true)")),
			],
			callerTypeName: "Root",
			callerIsPublic: caller == .public,
			mockConfiguration: caller == .listed ? "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n" : nil,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: nil,
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: nil,
			mockBuild: mockBuild,
		)
	}

	private static func callerAttribute(of caller: GraphFuzzerCallingMockCell.Caller) -> String {
		switch caller {
		case .internal:
			"@Instantiable(generateMock: true)"
		case .public:
			"@Instantiable(generateMock: .public)"
		case .listed:
			"@Instantiable"
		}
	}

	/// What the remedy that declares the required wrapper on `Screen` compares: whether `Fill` holds the caller’s
	/// instance, and whether the `Screen` it builds again holds a wrapper of that instance. The mock’s `Screen` holds the
	/// caller’s instance in a wrapper of its own, so the probe compares instances, not wrappers.
	private static func requiredWrapperProbe(of wrapper: Wrapper) -> DifferentialValueProbe {
		let read = { (root: String) in
			"{ let root = \(root); let fill = root.screen.holeBuilder.instantiate(7).value as! App.Fill; let again = fill.screenBuilder.instantiate(); return (fill.session === root.session.instance, again.session.instance === root.session.instance) }()"
		}
		return DifferentialValueProbe(name: "(Fill holds the caller’s \(wrapper.name) instance, the Screen it builds again holds it)", expression: read("App.Root.mock()"), knownRightExpression: read("App.Root()"))
	}

	/// What the remedy that receives `session` the same way compares: whether `Screen` and `Fill` hold the caller’s instance.
	private static func sameWayProbe(of wrapper: Wrapper) -> DifferentialValueProbe {
		let read = { (root: String) in
			"{ let root = \(root); let fill = root.screen.holeBuilder.instantiate(7).value as! App.Fill; return (root.screen.session?.instance === root.session.instance, fill.session?.instance === root.session.instance) }()"
		}
		return DifferentialValueProbe(name: "(Screen holds the caller’s \(wrapper.name) instance, Fill holds it)", expression: read("App.Root.mock()"), knownRightExpression: read("App.Root()"))
	}

	/// What the remedy that receives `session` the same way compares where `Fill` builds `Screen` again: whether `Fill` and the
	/// `Screen` it builds again hold the caller’s instance.
	private static func sameWayBuiltAgainProbe(of wrapper: Wrapper) -> DifferentialValueProbe {
		let read = { (root: String) in
			"{ let root = \(root); let fill = root.screen.holeBuilder.instantiate(7).value as! App.Fill; let again = fill.screenBuilder.instantiate(); return (fill.session?.instance === root.session.instance, again.session?.instance === root.session.instance) }()"
		}
		return DifferentialValueProbe(name: "(Fill holds the caller’s \(wrapper.name) instance, the Screen it builds again holds it)", expression: read("App.Root.mock()"), knownRightExpression: read("App.Root()"))
	}

	private mutating func expectCompilesAndBuildsInlineValues(of graph: GraphFuzzerCallingMockGraph, output: MultiModuleTestOutput, modules: [ModuleFixture], probes: [DifferentialValueProbe], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		if let failure = compilation.failure {
			failure.recordIssues(skippingVerificationBy: "pass `compileVerification: .skipped`", sourceLocation: sourceLocation)
		} else {
			let inlineModules = graph.inlineModules
			let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			let comparison = try #require(try await DifferentialValueOracle.compare(
				feature: DifferentialValuePath(output: output, modules: modules),
				knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
				probes: probes,
				filesToDelete: &filesToDelete,
			), sourceLocation: sourceLocation)
			for difference in comparison.differences {
				Issue.record("The calling mock builds other values than inline for \(difference)\n\(comparison.report)", sourceLocation: sourceLocation)
			}
		}
	}
}
