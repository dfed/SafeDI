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

	// MARK: Accepted

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenFillReceivesOnlyTheFormTheParameterCarries() async throws {
		// `Reader` and `LiveApi` both receive `tag: LazilyInstantiated<Tag>?` only if available, which the parameter carries.
		try await expectValuesEqualInlineBuild(
			readerReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
			liveApiReceive: "@Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?",
			featureFile: Self.featureFile(tagType: "LazilyInstantiated<Tag>?", guardName: "__safeDI_Hub_D708AD692F4FA289"),
			appFile: Self.appFile(guardName: "__safeDI_Hub_D708AD692F4FA289", liveApiTagArgument: "tag"),
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
			featureFile: Self.featureFile(tagType: "LazilyInstantiated<Tag>", guardName: "__safeDI_Hub_7480356911040170"),
			appFile: Self.appFile(guardName: "__safeDI_Hub_7480356911040170", liveApiTagArgument: "tag.instance"),
		)
	}

	// MARK: Fixtures

	/// `Feature`'s generated file, in which the function that builds `A` takes `tag` as `tagType` and hands the struct of
	/// `A`'s `api` that parameter, under the guard `guardName`.
	private static func featureFile(tagType: String, guardName: String) -> [String: String] {
		["Feature.swift": generatedFileHeader + """
		extension Hub {
		    @frozen public enum SafeDIScope_Api {
		        case aBuilder(aBuilder_Values, SafeDIScope_Api.A_Scope)

		        public struct aBuilder_Values {
		            public let tag: LazilyInstantiated<Tag>
		        }

		        @frozen public enum A_Scope {
		            case api(api_Values)

		            public struct api_Values {
		                public let tag: \(tagType)
		                public let reader: Reader
		                public let bBuilder: Instantiator<B>
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
		        func __safeDI_tag() -> Tag {
		            Tag()
		        }
		        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
		        let __safeDI_apiValues_aBuilder = SafeDIScope_Api.aBuilder_Values(tag: tag)
		        func __safeDI_aBuilder(tag: \(tagType)) -> A {
		            let reader = Reader(tag: tag)
		            func __safeDI_bBuilder() -> B {
		                func __safeDI_tag() -> Tag {
		                    Tag()
		                }
		                let tag = LazilyInstantiated<Tag>(__safeDI_tag)
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(tag: tag)
		                }
		                return B(tag: tag, aBuilder: aBuilder)
		            }
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let api: any Api = __safeDI_apiBuilder(.aBuilder(__safeDI_apiValues_aBuilder, .api(SafeDIScope_Api.A_Scope.api_Values(tag: tag, reader: reader, bBuilder: bBuilder))))
		            return A(reader: reader, api: api, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(tag: tag)
		        }
		        self.init(tag: tag, aBuilder: aBuilder)
		    }
		}

		extension Hub {
		    public enum \(guardName) {}
		}
		"""]
	}

	/// `App`'s generated file, whose `Root` calls `Hub`'s initializer under the guard `guardName` with a fill that hands
	/// `LiveApi` `liveApiTagArgument`, read from the struct's `tag`.
	private static func appFile(guardName: String, liveApiTagArgument: String) -> [String: String] {
		["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_hub() -> Hub {
		            _ = Hub.\(guardName).self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Hub", declaringModule: "Feature"))
		            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIScope_Api) -> any Api {
		                switch scope {
		                case let .aBuilder(_, scope): return __safeDI_apiBuilder_Hub_A_Scope(scope)
		                }
		            }
		            func __safeDI_apiBuilder_Hub_A_Scope(_ scope: Hub.SafeDIScope_Api.A_Scope) -> any Api {
		                switch scope {
		                case let .api(scope):
		                    let tag = scope.tag
		                    let api: any Api = LiveApi(tag: \(liveApiTagArgument))
		                    return api
		                }
		            }
		            return Hub(__safeDI_apiBuilder: __safeDI_apiBuilder_Hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(hub: hub)
		    }
		}
		"""]
	}

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
