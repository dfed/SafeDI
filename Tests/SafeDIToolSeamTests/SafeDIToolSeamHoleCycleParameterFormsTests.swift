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

/// A hole inside the builder function a lazy cycle closes on, whose fill receives a label the function takes as a cycle
/// parameter. `Hub`, a seam in `Feature`, instantiates `tag: LazilyInstantiated<Tag>` and `aBuilder: Instantiator<A>`; `A`
/// builds `Reader`, `api: any Api` (a hole) and `bBuilder: Instantiator<B>`; `B` instantiates `tag` again and builds `A`
/// again, so the function that builds `A` takes `tag`. `App` fills the hole with `LiveApi`. Inline, the function's body
/// receives `tag` in the forms both `Reader` and `LiveApi` receive, and one parameter must carry them together; the fill's
/// receives count as receives of the label the same way, so a seam rejects what its inline build rejects.
struct SafeDIToolSeamHoleCycleParameterFormsTests: ~Copyable {
	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Rejected

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableCycleLabel_whenFillReceivesOnlyIfAvailableFormTheOnlyIfAvailableParameterCannotCarry() async {
		// `Reader` receives `tag: LazilyInstantiated<Tag>?` and `LiveApi` `tag: Tag?`, both only if available: the parameter,
		// made optional, offers no instance, as inline reports.
		await expectRejectedAsInline(
			readerReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
			liveApiReceive: "@Received(onlyIfAvailable: true) public let tag: Tag?",
		) { fixtures in
			"""
			\(fixtures["Feature"]!["Reader.swift"]):7:5: error: @Received property `tag: LazilyInstantiated<Tag>?` is received in chain: A -> Reader. A dependency cycle builds `A` again beneath `B`, which declares `tag: LazilyInstantiated<Tag>` with the same label, and SafeDI hands each `A` one value of `tag`. `A` and the types it builds receive `tag` as `tag: LazilyInstantiated<Tag>?` and `tag: Tag?`, which one value cannot carry together. Receive `tag: LazilyInstantiated<Tag>?` and `tag: Tag?` under different labels to fix.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `tag: LazilyInstantiated<Tag>` is declared here
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableCycleLabel_whenFillReceivesOnlyIfAvailableFormTheRequiredParameterCannotCarry() async {
		// `Reader` requires `tag: Tag`, so the parameter is `tag: Tag`; `LiveApi` receives `tag: LazilyInstantiated<Tag>?` only
		// if available, which `B`'s declaration provides and the parameter cannot carry, as inline reports.
		await expectRejectedAsInline(
			readerReceive: "@Received public let tag: Tag",
			liveApiReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
		) { fixtures in
			"""
			\(fixtures["Feature"]!["Reader.swift"]):7:5: error: @Received property `tag: Tag` is received in chain: A -> Reader. A dependency cycle builds `A` again beneath `B`, which declares `tag: LazilyInstantiated<Tag>` with the same label, and SafeDI hands each `A` one value of `tag`. `A` and the types it builds receive `tag` as `tag: LazilyInstantiated<Tag>?` and `tag: Tag`, which one value cannot carry together. Receive `tag: LazilyInstantiated<Tag>?` and `tag: Tag` under different labels to fix.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `tag: LazilyInstantiated<Tag>` is declared here
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableCycleLabel_whenFillRequiresFormBesideOnlyIfAvailableFormTheParameterCannotCarry() async {
		// `LiveApi` requires `tag: Tag`, so inline's parameter is `tag: Tag`, which cannot carry the
		// `tag: LazilyInstantiated<Tag>?` `Reader` receives only if available, as inline reports.
		await expectRejectedAsInline(
			readerReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
			liveApiReceive: "@Received public let tag: Tag",
		) { fixtures in
			"""
			\(fixtures["Feature"]!["Reader.swift"]):7:5: error: @Received property `tag: LazilyInstantiated<Tag>?` is received in chain: A -> Reader. A dependency cycle builds `A` again beneath `B`, which declares `tag: LazilyInstantiated<Tag>` with the same label, and SafeDI hands each `A` one value of `tag`. `A` and the types it builds receive `tag` as `tag: LazilyInstantiated<Tag>?` and `tag: Tag`, which one value cannot carry together. Receive `tag: LazilyInstantiated<Tag>?` and `tag: Tag` under different labels to fix.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `tag: LazilyInstantiated<Tag>` is declared here
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableCycleLabel_whenFillReceivesThroughRenameFormTheRequiredParameterCannotCarry() async {
		// `Reader` requires `tag: Tag`, so the parameter is `tag: Tag`; `LiveApi` renames `tag: LazilyInstantiated<Tag>` only
		// if available, a receive of that form, which `B`'s declaration provides and the parameter cannot carry.
		await expectRejectedAsInline(
			readerReceive: "@Received public let tag: Tag",
			liveApiReceive: "@Received(fulfilledByDependencyNamed: \"tag\", ofType: LazilyInstantiated<Tag>.self, onlyIfAvailable: true) public let lazyTag: LazilyInstantiated<Tag>?",
		) { fixtures in
			"""
			\(fixtures["Feature"]!["Reader.swift"]):7:5: error: @Received property `tag: Tag` is received in chain: A -> Reader. A dependency cycle builds `A` again beneath `B`, which declares `tag: LazilyInstantiated<Tag>` with the same label, and SafeDI hands each `A` one value of `tag`. `A` and the types it builds receive `tag` as `tag: LazilyInstantiated<Tag>` and `tag: Tag`, which one value cannot carry together. Receive `tag: LazilyInstantiated<Tag>` and `tag: Tag` under different labels to fix.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `tag: LazilyInstantiated<Tag>` is declared here
			"""
		}
	}

	// MARK: Inline tree

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsNoInlineTreeOfSeam_whenSeamsTreeReceivesEachLabelItDeclaresInOneForm() async throws {
		// `Reader` and `LiveApi` receive `tag` in one form, which one parameter always carries, so `App` learns from the
		// scopes alone that `Hub`'s tree holds no label to report, and builds no generator of it.
		let inlineTrees = try await inlineTreesOfForeignSeams(
			readerReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
			liveApiReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
		)
		#expect(inlineTrees == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsNoInlineTreeOfSeam_whenFactsFindOneParameterPassesLabelSeamsTreeReceivesInTwoForms() async throws {
		// `Reader` requires `tag: LazilyInstantiated<Tag>` and `LiveApi` receives `tag: Tag?`: two forms of a label `B`
		// declares, which the facts of `Hub`'s inline world find one parameter passes, so `App` builds no tree of it.
		let inlineTrees = try await inlineTreesOfForeignSeams(
			readerReceive: "@Received public let tag: LazilyInstantiated<Tag>",
			liveApiReceive: "@Received(onlyIfAvailable: true) public let tag: Tag?",
		)
		#expect(inlineTrees == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInlineTreeOfSeam_whenFactsFindLabelNoOneParameterPassesInSeamsInlineWorld() async throws {
		// `Reader` requires `tag: Tag` and `LiveApi` receives `tag: LazilyInstantiated<Tag>?`, which no one parameter passes
		// together, so each run of `App` builds `Hub`'s tree to report the label from. A rejected build is run again (as
		// a run that reads stored seam signatures and fails reruns computing them), so `App` runs more than once.
		let inlineTrees = try await inlineTreesOfForeignSeams(
			readerReceive: "@Received public let tag: Tag",
			liveApiReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
			rejected: true,
		)
		#expect(Set(inlineTrees) == ["App: Hub"])
	}

	// MARK: Accepted

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenFillReceivesOnlyTheFormTheParameterCarries() async throws {
		// `Reader` and `LiveApi` both receive `tag: LazilyInstantiated<Tag>?` only if available, which the parameter carries.
		try await expectValuesEqualInlineBuild(
			readerReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
			liveApiReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
			featureFile: [
				"Feature.swift": generatedFileHeader + """
				extension Hub {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let aBuilder: (LazilyInstantiated<Tag>) -> __safeDI_ApiCarrier_A<__safeDI_Built>

				        public init(aBuilder: @escaping (LazilyInstantiated<Tag>) -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
				            self.aBuilder = aBuilder
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(aBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				        }
				    }

				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
				        public let api: (LazilyInstantiated<Tag>?, Reader, Instantiator<B>) -> __safeDI_Built

				        public init(api: @escaping (LazilyInstantiated<Tag>?, Reader, Instantiator<B>) -> __safeDI_Built) {
				            self.api = api
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(api: { _, _, _ in __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        @inline(never) func __safeDI_tag() -> Tag {
				            Tag()
				        }
				        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
				        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(tag)
				        @inline(never) func __safeDI_aBuilder(tag: LazilyInstantiated<Tag>?) -> A {
				            let reader = Reader(tag: tag)
				            @inline(never) func __safeDI_bBuilder() -> B {
				                @inline(never) func __safeDI_tag() -> Tag {
				                    Tag()
				                }
				                let tag = LazilyInstantiated<Tag>(__safeDI_tag)
				                let aBuilder = Instantiator<A> {
				                    __safeDI_aBuilder(tag: tag)
				                }
				                return B(tag: tag, aBuilder: aBuilder)
				            }
				            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
				            let api: any Api = __safeDI_apiBuilder_aBuilder.api(tag, reader, bBuilder)
				            return A(reader: reader, api: api, bBuilder: bBuilder)
				        }
				        let aBuilder = Instantiator<A> {
				            __safeDI_aBuilder(tag: tag)
				        }
				        self.init(tag: tag, aBuilder: aBuilder)
				    }
				}

				extension Hub {
				    public enum __safeDI_Hub_193F7642B27B2ED9 {}
				}
				""",
			],
			appFile: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
				            .init(aBuilder: { values_tag in __safeDI_apiBuilder_Hub_A_Scope() })
				        }
				        func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
				            .init(api: { scope_tag, scope_reader, scope_bBuilder in
				                let tag = scope_tag
				                let api: any Api = LiveApi(tag: tag)
				                return api
				            })
				        }
				        func __safeDI_hub() -> Hub {
				            _ = Hub.__safeDI_Hub_193F7642B27B2ED9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Hub(__safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
				        }
				        let hub: Hub = __safeDI_hub()
				        self.init(hub: hub)
				    }
				}
				""",
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenOneParameterProvidesEveryFormTheFillReceives() async throws {
		// `Reader` requires `tag: LazilyInstantiated<Tag>`, which provides the `tag: Tag?` `LiveApi` receives only if
		// available: the parameter carries both.
		try await expectValuesEqualInlineBuild(
			readerReceive: "@Received public let tag: LazilyInstantiated<Tag>",
			liveApiReceive: "@Received(onlyIfAvailable: true) public let tag: Tag?",
			featureFile: [
				"Feature.swift": generatedFileHeader + """
				extension Hub {
				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
				        public let aBuilder: (LazilyInstantiated<Tag>) -> __safeDI_ApiCarrier_A<__safeDI_Built>

				        public init(aBuilder: @escaping (LazilyInstantiated<Tag>) -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
				            self.aBuilder = aBuilder
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(aBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				        }
				    }

				    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
				        public let api: (LazilyInstantiated<Tag>, Reader, Instantiator<B>) -> __safeDI_Built

				        public init(api: @escaping (LazilyInstantiated<Tag>, Reader, Instantiator<B>) -> __safeDI_Built) {
				            self.api = api
				        }

				        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				            self.init(api: { _, _, _ in __safeDI_builder() })
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
				        @inline(never) func __safeDI_tag() -> Tag {
				            Tag()
				        }
				        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
				        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(tag)
				        @inline(never) func __safeDI_aBuilder(tag: LazilyInstantiated<Tag>) -> A {
				            let reader = Reader(tag: tag)
				            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
				            let api: any Api = __safeDI_apiBuilder_aBuilder.api(tag, reader, bBuilder)
				            return A(reader: reader, api: api, bBuilder: bBuilder)
				        }
				        @inline(never) func __safeDI_bBuilder() -> B {
				            let tag = LazilyInstantiated<Tag>(__safeDI_tag)
				            let aBuilder = Instantiator<A> {
				                __safeDI_aBuilder(tag: tag)
				            }
				            return B(tag: tag, aBuilder: aBuilder)
				        }
				        let aBuilder = Instantiator<A> {
				            __safeDI_aBuilder(tag: tag)
				        }
				        self.init(tag: tag, aBuilder: aBuilder)
				    }
				}

				extension Hub {
				    public enum __safeDI_Hub_2176C1B85F5362C0 {}
				}
				""",
			],
			appFile: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
				            .init(aBuilder: { values_tag in __safeDI_apiBuilder_Hub_A_Scope() })
				        }
				        func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
				            .init(api: { scope_tag, scope_reader, scope_bBuilder in
				                let tag = scope_tag
				                let api: any Api = LiveApi(tag: tag.instance)
				                return api
				            })
				        }
				        func __safeDI_hub() -> Hub {
				            _ = Hub.__safeDI_Hub_2176C1B85F5362C0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Hub(__safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
				        }
				        let hub: Hub = __safeDI_hub()
				        self.init(hub: hub)
				    }
				}
				""",
			],
		)
	}

	// MARK: Fixtures

	/// The declaration of `LiveApi`, which fulfills `Api` and receives `tag` as `liveApiReceive` declares it.
	private static func liveApi(_ liveApiReceive: String) -> String {
		seamFixtureType(named: "LiveApi", isFinalClass: true, declarations: [liveApiReceive], conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
			.replacingOccurrences(of: "public init(", with: "\(stamp)\n\n    public init(")
	}

	/// `Feature`, in package `Shop`, whose `Reader` receives `tag` as `readerReceive` declares it, and `App`, in package
	/// `Other`, which declares `LiveApi`, receiving `tag` as `liveApiReceive` declares it, and `Root`. With
	/// `fulfillerInFeature`, `Feature` declares `LiveApi` instead, so no hole is left and `Hub`'s tree is built inline.
	private static func modules(readerReceive: String, liveApiReceive: String, fulfillerInFeature: Bool = false) -> [ModuleFixture] {
		let tag = """
		@Instantiable
		public final class Tag: Instantiable {
		    public init() {}

		    \(Self.stamp)
		}
		"""
		var feature = [
			DifferentialValueCreationStamp.counterDeclaration(named: "Counter"),
			"public protocol Api {}",
			tag,
			seamFixtureType(named: "Reader", declarations: [readerReceive]),
			seamFixtureType(named: "A", declarations: ["@Instantiated public let reader: Reader", "@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Instantiated public let tag: LazilyInstantiated<Tag>", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let tag: LazilyInstantiated<Tag>", "@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		var app = [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let hub: Hub"])]
		if fulfillerInFeature {
			feature.append(liveApi(liveApiReceive))
		} else {
			app.insert(liveApi(liveApiReceive), at: 0)
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	private static let stamp = DifferentialValueCreationStamp.property(counterNamed: "Counter")

	/// Expects the build with `LiveApi` in `App` to generate `featureFile` and `appFile`, to compile, and to construct the
	/// values the same graph builds with `LiveApi` in `Feature`, where no hole is left: the `A` `Hub` builds, and the one its
	/// `B` builds again.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualInlineBuild(
		readerReceive: String,
		liveApiReceive: String,
		featureFile: [String: String],
		appFile: [String: String],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = Self.modules(readerReceive: readerReceive, liveApiReceive: liveApiReceive)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == featureFile, sourceLocation: sourceLocation)
		#expect(output.modules["App"]?.generatedFiles == appFile, sourceLocation: sourceLocation)
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.modules(readerReceive: readerReceive, liveApiReceive: liveApiReceive, fulfillerInFeature: true)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: [
				DifferentialValueProbe("Root().hub.aBuilder.instantiate()"),
				DifferentialValueProbe("Root().hub.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
			],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// The inline trees of other modules' seams that the runs of the build with `LiveApi` in `App` build, each as the
	/// run's module and the seam's type, in order. Expects the build to throw where `rejected` is set, and to succeed
	/// otherwise.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func inlineTreesOfForeignSeams(readerReceive: String, liveApiReceive: String, rejected: Bool = false) async throws -> [String] {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		let modules = Self.modules(readerReceive: readerReceive, liveApiReceive: liveApiReceive)
		var filesToDelete = filesToDelete
		try await GenerationLayerObservation.$observer.withValue({ runModuleName, layer in
			switch layer {
			case let .inlineTreeOfForeignSeam(type):
				continuation.yield("\(runModuleName ?? "nil"): \(type.asSource)")
			case .seamSignatures, .accessProof, .dependencyTree, .mockScopes:
				break
			}
		}) {
			let threw: Bool
			do {
				_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
				threw = false
			} catch {
				threw = true
			}
			#expect(threw == rejected)
		}
		self.filesToDelete = filesToDelete
		continuation.finish()
		var inlineTrees = [String]()
		for await inlineTree in stream {
			inlineTrees.append(inlineTree)
		}
		return inlineTrees
	}

	/// Expects the build with `LiveApi` in `App` to throw `diagnostics` in `App`, and the same graph with `LiveApi` in
	/// `Feature`, where no hole is left and `Hub`'s tree is built inline, to throw them in `Feature`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectRejectedAsInline(
		readerReceive: String,
		liveApiReceive: String,
		sourceLocation: SourceLocation = #_sourceLocation,
		diagnostics: (_ fixtures: [String: FixturePaths]) -> String,
	) async {
		for fulfillerInFeature in [false, true] {
			await assertThrowsMultiModuleError(inModule: fulfillerInFeature ? "Feature" : "App", diagnostics: diagnostics, sourceLocation: sourceLocation) {
				try await executeSafeDIToolMultiModuleTest(
					modules: Self.modules(readerReceive: readerReceive, liveApiReceive: liveApiReceive, fulfillerInFeature: fulfillerInFeature),
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	private var filesToDelete: [URL]
}
