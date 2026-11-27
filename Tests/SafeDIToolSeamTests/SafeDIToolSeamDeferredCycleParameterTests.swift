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

/// A hole's site inside the builder function a lazy cycle closes on, in the tree of a seam that defers a pass-through
/// of a label that function takes as a cycle parameter: the level of the site's type, which every build of the type
/// builds in that function, carries the function's parameter, by value, as inline's site reads it, never the seam's memo
/// of the pass-through, which the parameter hides, nor the value of the chain the first build reports.
struct SafeDIToolSeamDeferredCycleParameterTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Fixtures

	/// How the cycle in `Hub`'s tree closes on the function that builds `A`.
	private enum Cycle {
		/// `Hub` and `B` each instantiate `aBuilder: Instantiator<A>`.
		case instantiator
		/// `Hub` and `B` each instantiate `a: LazilyInstantiated<A>`.
		case lazilyInstantiated
		/// `Hub` and `B` each instantiate `aBuilder: SendableInstantiator<A>`, and `A` instantiates
		/// `bBuilder: SendableInstantiator<B>`, so the function that builds `A`, and the site inside it, are `@Sendable`.
		case sendableInstantiator

		var openerAndCloser: String {
			switch self {
			case .instantiator: "@Instantiated let aBuilder: Instantiator<A>"
			case .lazilyInstantiated: "@Instantiated let a: LazilyInstantiated<A>"
			case .sendableInstantiator: "@Instantiated let aBuilder: SendableInstantiator<A>"
			}
		}

		var bBuilder: String {
			switch self {
			case .instantiator, .lazilyInstantiated: "@Instantiated let bBuilder: Instantiator<B>"
			case .sendableInstantiator: "@Instantiated let bBuilder: SendableInstantiator<B>"
			}
		}

		/// A probe that builds `B` with a `Tag` of its own, and so the `A` that `B` builds again.
		var probe: DifferentialValueProbe {
			switch self {
			case .instantiator, .sendableInstantiator: DifferentialValueProbe("Root().hub.aBuilder.instantiate().bBuilder.instantiate(Tag())")
			case .lazilyInstantiated: DifferentialValueProbe("Root().hub.a.instance.bBuilder.instantiate(Tag())")
			}
		}
	}

	/// `Feature`, where the seam `Hub` builds `A` behind `cycle`'s opener; `A` builds `TagReader`, which receives `tag` as
	/// `readerReceive` declares it, `api: any Api`, a hole only `App` can fill, and `B`, which forwards `tag` and builds `A`
	/// again behind `cycle`'s closer. `App`, in another package unless `appPackageName` says otherwise, declares `LiveApi`,
	/// which fulfills `Api` with `liveApiDeclarations`, and `Root`, which instantiates `tag` as `rootTag` and `hub`. Every
	/// type is spelled at `access`; `Tag` and `Root` are classes with creation stamps.
	private static func modules(
		cycle: Cycle = .instantiator,
		readerReceive: String = "@Received let tag: Tag",
		liveApiDeclarations: [String] = [],
		rootTag: String = "Tag",
		hubArguments: String = "generateDependencyTree: true",
		access: String = "public",
		appPackageName: String = "Other",
	) -> [ModuleFixture] {
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "Counter")
		let tagConformances = cycle == .sendableInstantiator ? ", Sendable" : ""
		let tag = """
		@Instantiable
		public final class Tag: Instantiable\(tagConformances) {
		    public init() {}

		    \(stamp)
		}
		"""
		let feature = [
			DifferentialValueCreationStamp.counterDeclaration(named: "Counter"),
			"public protocol Api {}",
			tag,
			seamFixtureType(named: "TagReader", declarations: [readerReceive]),
			seamFixtureType(named: "A", declarations: ["@Instantiated let reader: TagReader", "@Instantiated let api: any Api", cycle.bBuilder]),
			seamFixtureType(named: "B", declarations: ["@Forwarded let tag: Tag", cycle.openerAndCloser]),
			seamFixtureType(named: "Hub", declarations: [cycle.openerAndCloser])
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(\(hubArguments))\n"),
		]
		let liveApi = seamFixtureType(named: "LiveApi", declarations: liveApiDeclarations, conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
		let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let tag: \(rootTag)", "@Instantiated let hub: Hub"])
			.replacingOccurrences(of: "public final class Root: Instantiable {\n", with: "public final class Root: Instantiable {\n    \(stamp)\n\n")
		func spelled(_ files: [String]) -> [String] {
			files.map { $0.replacingOccurrences(of: "public ", with: "\(access) ") }
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: spelled(feature)),
			ModuleFixture(name: "App", packageName: appPackageName, swiftFileContent: spelled([liveApi, root]).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `modules` with `Hub` built inline, as a type that is not a seam.
	private static func inlineModules(_ modules: [ModuleFixture]) -> [ModuleFixture] {
		modules.map { module in
			ModuleFixture(
				name: module.name,
				packageName: module.packageName,
				swiftFileContent: module.swiftFileContent.map { $0.replacingOccurrences(of: "generateDependencyTree: true", with: "generateDependencyTree: false") },
				dependencies: module.dependencies,
			)
		}
	}

	/// The comment on the line of `App`'s guard of the call of `Hub`.
	private static let callComment = MultiModuleIntegration.moduleInfo.seamCallComment(type: "Hub", declaringModule: "Feature")

	// MARK: The site's struct

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCycleParameterInScope_whenSiteIsInsideFunctionInstantiatorCycleClosesOn() async throws {
		// `Hub` defers `tag`, which `TagReader` receives, as a memo; `B` builds `A` again with the `tag` it forwards, so the
		// function that builds `A` takes `tag`, which hides the memo inside it. The site of `api` there carries the
		// function's `tag`, by value, as inline's site reads it: `Root`'s where `Hub` builds `A`, `B`'s where `B` does.
		let modules = Self.modules()
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
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
			        public let api: (Tag, TagReader, Instantiator<B>) -> __safeDI_Built

			        public init(api: @escaping (Tag, TagReader, Instantiator<B>) -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(tag)
			        @inline(never) func __safeDI_aBuilder(tag: Tag) -> A {
			            let reader = TagReader(tag: tag)
			            @inline(never) func __safeDI_bBuilder(tag: Tag) -> B {
			                let aBuilder = Instantiator<A> {
			                    __safeDI_aBuilder(tag: tag)
			                }
			                return B(tag: tag, aBuilder: aBuilder)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(tag: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_aBuilder.api(tag, reader, bBuilder)
			            return A(reader: reader, api: api, bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(tag: tag.instance)
			        }
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_F0045AB682C97BD1 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
			            .init(aBuilder: { values_tag in __safeDI_apiBuilder_Hub_A_Scope() })
			        }
			        func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
			            .init(api: { scope_tag, scope_reader, scope_bBuilder in
			                let api: any Api = LiveApi()
			                return api
			            })
			        }
			        let tag = Tag()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_F0045AB682C97BD1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(tag: tag, hub: hub)
			    }
			}
			""",
		])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesOptionalCycleParameterInScope_whenTreeReceivesLabelOnlyIfAvailable() async throws {
		// Every receive of `tag` in the function's body is only if available, so the function takes it optionally, and the
		// site carries it as the function takes it.
		let modules = Self.modules(readerReceive: "@Received(onlyIfAvailable: true) let tag: Tag?")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let aBuilder: (LazilyInstantiated<Tag?>) -> __safeDI_ApiCarrier_A<__safeDI_Built>

			        public init(aBuilder: @escaping (LazilyInstantiated<Tag?>) -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(aBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
			        public let api: (Tag?, TagReader, Instantiator<B>) -> __safeDI_Built

			        public init(api: @escaping (Tag?, TagReader, Instantiator<B>) -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_tag: @autoclosure @escaping () -> Tag?, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let tag = LazilyInstantiated<Tag?>(__safeDI_tag)
			        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(tag)
			        @inline(never) func __safeDI_aBuilder(tag: Tag?) -> A {
			            let reader = TagReader(tag: tag)
			            @inline(never) func __safeDI_bBuilder(tag: Tag) -> B {
			                let aBuilder = Instantiator<A> {
			                    __safeDI_aBuilder(tag: tag)
			                }
			                return B(tag: tag, aBuilder: aBuilder)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(tag: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_aBuilder.api(tag, reader, bBuilder)
			            return A(reader: reader, api: api, bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(tag: tag.instance)
			        }
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_DEB194DE58CBB6E2 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
			            .init(aBuilder: { values_tag in __safeDI_apiBuilder_Hub_A_Scope() })
			        }
			        func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
			            .init(api: { scope_tag, scope_reader, scope_bBuilder in
			                let api: any Api = LiveApi()
			                return api
			            })
			        }
			        let tag = Tag()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_DEB194DE58CBB6E2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(tag: tag, hub: hub)
			    }
			}
			""",
		])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCycleParameterInScope_whenLazilyInstantiatedCycleClosesOnFunction() async throws {
		// `Hub` and `B` each build `A` lazily, and `Root` holds `tag` lazily too: the memo reads `Root`'s wrapper only when
		// `Hub`'s `a` is first read, as inline reads it there.
		let modules = Self.modules(cycle: .lazilyInstantiated, rootTag: "LazilyInstantiated<Tag>")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Hub {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let a: (LazilyInstantiated<Tag>) -> __safeDI_ApiCarrier_A<__safeDI_Built>

		        public init(a: @escaping (LazilyInstantiated<Tag>) -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
		            self.a = a
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(a: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
		        public let api: (Tag, TagReader, Instantiator<B>) -> __safeDI_Built

		        public init(api: @escaping (Tag, TagReader, Instantiator<B>) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _, _, _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
		        let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(tag)
		        @inline(never) func __safeDI_a(tag: Tag) -> A {
		            let reader = TagReader(tag: tag)
		            @inline(never) func __safeDI_bBuilder(tag: Tag) -> B {
		                let a = LazilyInstantiated<A> {
		                    __safeDI_a(tag: tag)
		                }
		                return B(tag: tag, a: a)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(tag: $0)
		            }
		            let api: any Api = __safeDI_apiBuilder_a.api(tag, reader, bBuilder)
		            return A(reader: reader, api: api, bBuilder: bBuilder)
		        }
		        let a = LazilyInstantiated<A> {
		            __safeDI_a(tag: tag.instance)
		        }
		        self.init(a: a)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_6A71D1DD032F785B {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
			            .init(a: { values_tag in __safeDI_apiBuilder_Hub_A_Scope() })
			        }
			        func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
			            .init(api: { scope_tag, scope_reader, scope_bBuilder in
			                let api: any Api = LiveApi()
			                return api
			            })
			        }
			        func __safeDI_tag() -> Tag {
			            Tag()
			        }
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_6A71D1DD032F785B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_tag: tag.instance, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(tag: tag, hub: hub)
			    }
			}
			""",
		])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.lazilyInstantiated.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCycleParameterInLevel_whenSendableInstantiatorCycleClosesOnSendableFunction() async throws {
		// The function that builds `A` is `@Sendable`, so the place is a case of the `@Sendable` enum, and `A`'s level carries
		// the function's `tag`; the memo, read inside a `@Sendable` function, is a `SendableLazilyInstantiated`.
		let modules = Self.modules(cycle: .sendableInstantiator)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
			        public let api: (Tag, TagReader, SendableInstantiator<B>) -> __safeDI_Built

			        public init(api: @escaping (Tag, TagReader, SendableInstantiator<B>) -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
			        public let aBuilder: @Sendable () -> __safeDI_ApiCarrier_A<__safeDI_Built>

			        public init(aBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(aBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_tag: @autoclosure @escaping @Sendable () -> Tag, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
			        let tag = SendableLazilyInstantiated<Tag>(__safeDI_tag)
			        @inline(never) @Sendable nonisolated func __safeDI_aBuilder(tag: Tag) -> A {
			            let __safeDI_apiSendableBuilder_aBuilder = __safeDI_apiSendableBuilder.aBuilder()
			            let reader = TagReader(tag: tag)
			            @inline(never) @Sendable nonisolated func __safeDI_bBuilder(tag: Tag) -> B {
			                let aBuilder = SendableInstantiator<A> {
			                    __safeDI_aBuilder(tag: tag)
			                }
			                return B(tag: tag, aBuilder: aBuilder)
			            }
			            let bBuilder = SendableInstantiator<B> {
			                __safeDI_bBuilder(tag: $0)
			            }
			            let api: any Api = __safeDI_apiSendableBuilder_aBuilder.api(tag, reader, bBuilder)
			            return A(reader: reader, api: api, bBuilder: bBuilder)
			        }
			        let aBuilder = SendableInstantiator<A> {
			            __safeDI_aBuilder(tag: tag.instance)
			        }
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_EE786E17B6B93847 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.__safeDI_ApiSendableCarrier<any Api> {
			            .init(aBuilder: { __safeDI_apiBuilder_Hub_A_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
			            .init(api: { scope_tag, scope_reader, scope_bBuilder in
			                let api: any Api = LiveApi()
			                return api
			            })
			        }
			        let tag = Tag()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_EE786E17B6B93847.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_tag: tag, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(tag: tag, hub: hub)
			    }
			}
			""",
		])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.sendableInstantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCycleParameterFromScope_whenFillReceivesLabel() async throws {
		// `LiveApi` receives `tag`, which the fill binds from the struct, never from `Root`: where `B` builds `A` again, the
		// `tag` inline's `LiveApi` receives is `B`'s.
		let modules = Self.modules(liveApiDeclarations: ["@Received let tag: Tag"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
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
			        public let api: (Tag, TagReader, Instantiator<B>) -> __safeDI_Built

			        public init(api: @escaping (Tag, TagReader, Instantiator<B>) -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(tag)
			        @inline(never) func __safeDI_aBuilder(tag: Tag) -> A {
			            let reader = TagReader(tag: tag)
			            @inline(never) func __safeDI_bBuilder(tag: Tag) -> B {
			                let aBuilder = Instantiator<A> {
			                    __safeDI_aBuilder(tag: tag)
			                }
			                return B(tag: tag, aBuilder: aBuilder)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(tag: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_aBuilder.api(tag, reader, bBuilder)
			            return A(reader: reader, api: api, bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(tag: tag.instance)
			        }
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_F0045AB682C97BD1 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
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
			        let tag = Tag()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_F0045AB682C97BD1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(tag: tag, hub: hub)
			    }
			}
			""",
		])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCycleParameterFromLevel_whenSendableFillReceivesLabel() async throws {
		// The `@Sendable` function's `tag` is in `A`'s level, which the `@Sendable` fill binds `tag` from: where `B` builds `A`
		// again, `LiveApi` receives `B`'s `tag`, as inline's does, never `Root`'s.
		let modules = Self.modules(cycle: .sendableInstantiator, liveApiDeclarations: ["@Received let tag: Tag"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
			        public let api: (Tag, TagReader, SendableInstantiator<B>) -> __safeDI_Built

			        public init(api: @escaping (Tag, TagReader, SendableInstantiator<B>) -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
			        public let aBuilder: @Sendable () -> __safeDI_ApiCarrier_A<__safeDI_Built>

			        public init(aBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(aBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_tag: @autoclosure @escaping @Sendable () -> Tag, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
			        let tag = SendableLazilyInstantiated<Tag>(__safeDI_tag)
			        @inline(never) @Sendable nonisolated func __safeDI_aBuilder(tag: Tag) -> A {
			            let __safeDI_apiSendableBuilder_aBuilder = __safeDI_apiSendableBuilder.aBuilder()
			            let reader = TagReader(tag: tag)
			            @inline(never) @Sendable nonisolated func __safeDI_bBuilder(tag: Tag) -> B {
			                let aBuilder = SendableInstantiator<A> {
			                    __safeDI_aBuilder(tag: tag)
			                }
			                return B(tag: tag, aBuilder: aBuilder)
			            }
			            let bBuilder = SendableInstantiator<B> {
			                __safeDI_bBuilder(tag: $0)
			            }
			            let api: any Api = __safeDI_apiSendableBuilder_aBuilder.api(tag, reader, bBuilder)
			            return A(reader: reader, api: api, bBuilder: bBuilder)
			        }
			        let aBuilder = SendableInstantiator<A> {
			            __safeDI_aBuilder(tag: tag.instance)
			        }
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_EE786E17B6B93847 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_apiSendableBuilder_Hub() -> Hub.__safeDI_ApiSendableCarrier<any Api> {
			            .init(aBuilder: { __safeDI_apiBuilder_Hub_A_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
			            .init(api: { scope_tag, scope_reader, scope_bBuilder in
			                let tag = scope_tag
			                let api: any Api = LiveApi(tag: tag)
			                return api
			            })
			        }
			        let tag = Tag()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_EE786E17B6B93847.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_tag: tag, __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(tag: tag, hub: hub)
			    }
			}
			""",
		])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.sendableInstantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillRequiresCycleParameterFunctionTakesOptionally() async {
		// `TagReader` receives `tag` only if available, so the function that builds `A` takes `tag: Tag?`, which hides
		// `Hub`'s pass-through, and the struct carries it as the function takes it, while `LiveApi` requires `tag: Tag`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag`, which SafeDI hands the builder for `A`’s `api: any Api` (`api` of `apiBuilder`) only as `tag: Tag?`, since `A`’s builder function takes it as a parameter, because a cycle inside `A`’s tree passes it, and no type `Hub`’s tree builds in that function requires `tag: Tag`. Receive it on `LiveApi` with `@Received(onlyIfAvailable: true) let tag: Tag?`, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["TagReader.swift"]):7:5: note: `TagReader` receives `tag: Tag?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(readerReceive: "@Received(onlyIfAvailable: true) let tag: Tag?", liveApiDeclarations: ["@Received let tag: Tag"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_mocksSeamInline_whenSeamWithSiteInsideCycleFunctionGeneratesMock() async throws {
		// A mock builds `Hub`'s tree inline, as mocks build every seam, taking `api`, which it cannot build.
		let modules = Self.modules(hubArguments: "generateDependencyTree: true, generateMock: true")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
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
			        public let api: (Tag, TagReader, Instantiator<B>) -> __safeDI_Built

			        public init(api: @escaping (Tag, TagReader, Instantiator<B>) -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(tag)
			        @inline(never) func __safeDI_aBuilder(tag: Tag) -> A {
			            let reader = TagReader(tag: tag)
			            @inline(never) func __safeDI_bBuilder(tag: Tag) -> B {
			                let aBuilder = Instantiator<A> {
			                    __safeDI_aBuilder(tag: tag)
			                }
			                return B(tag: tag, aBuilder: aBuilder)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(tag: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_aBuilder.api(tag, reader, bBuilder)
			            return A(reader: reader, api: api, bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(tag: tag.instance)
			        }
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_F0045AB682C97BD1 {}
			}

			#if DEBUG
			extension Hub {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            tag: (() -> Tag)? = nil,
			            aBuilder: A.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                tag: tag,
			                aBuilder: aBuilder
			            )
			        }

			        var tag: (() -> Tag)? { __safeDI_storage.tag }
			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                tag: (() -> Tag)?,
			                aBuilder: A.SafeDIMockConfiguration
			            ) {
			                self.tag = tag
			                self.aBuilder = aBuilder
			            }

			            let tag: (() -> Tag)?
			            let aBuilder: A.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        apiBuilder: @escaping () -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Hub {
			        let tag = if let safeDIBuilder = safeDIOverrides.tag { safeDIBuilder() } else { Tag() }
			        func __safeDI_aBuilder(tag: Tag, __safeDI_A_configuration: A.SafeDIMockConfiguration) -> A {
			            let api: any Api = apiBuilder()
			            let reader = if let safeDIBuilder = __safeDI_A_configuration.reader { safeDIBuilder(tag) } else { TagReader(tag: tag) }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(tag: $0, __safeDI_B_configuration: __safeDI_A_configuration.bBuilder, __safeDI_A_configuration_nearest: __safeDI_A_configuration)
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(reader, api, bBuilder) } else { A(reader: reader, api: api, bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder(tag: Tag, __safeDI_B_configuration: B.SafeDIMockConfiguration, __safeDI_A_configuration_nearest: A.SafeDIMockConfiguration?) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(tag: tag, __safeDI_A_configuration: __safeDI_A_configuration_nearest ?? A.SafeDIMockConfiguration())
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration.safeDIBuilder { safeDIBuilder(tag, aBuilder) } else { B(tag: tag, aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(tag: tag, __safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        return Hub(aBuilder: aBuilder)
			    }
			}
			#endif

			#if DEBUG
			extension B {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            _ safeDIBuilder: ((Tag, Instantiator<A>) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Tag, Instantiator<A>) -> B)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                safeDIBuilder: ((Tag, Instantiator<A>) -> B)?
			            ) {
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let safeDIBuilder: ((Tag, Instantiator<A>) -> B)?
			        }
			    }
			}

			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            reader: ((Tag) -> TagReader)? = nil,
			            bBuilder: B.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((TagReader, any Api, Instantiator<B>) -> A)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                reader: reader,
			                bBuilder: bBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var reader: ((Tag) -> TagReader)? { __safeDI_storage.reader }
			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((TagReader, any Api, Instantiator<B>) -> A)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                reader: ((Tag) -> TagReader)?,
			                bBuilder: B.SafeDIMockConfiguration,
			                safeDIBuilder: ((TagReader, any Api, Instantiator<B>) -> A)?
			            ) {
			                self.reader = reader
			                self.bBuilder = bBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let reader: ((Tag) -> TagReader)?
			            let bBuilder: B.SafeDIMockConfiguration
			            let safeDIBuilder: ((TagReader, any Api, Instantiator<B>) -> A)?
			        }
			    }
			}
			#endif

			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
			            .init(aBuilder: { values_tag in __safeDI_apiBuilder_Hub_A_Scope() })
			        }
			        func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
			            .init(api: { scope_tag, scope_reader, scope_bBuilder in
			                let api: any Api = LiveApi()
			                return api
			            })
			        }
			        let tag = Tag()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_F0045AB682C97BD1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(tag: tag, hub: hub)
			    }
			}
			""",
		])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [
			DifferentialValueProbe("Root()"),
			Cycle.instantiator.probe,
			// The inline build has no seam, so its `Hub.mock()` takes the value; the reference is the seam's production tree,
			// which builds an `Api` per place as the mock's builder does.
			DifferentialValueProbe(name: "Hub.mock(apiBuilder: { LiveApi() })", expression: "Hub.mock(apiBuilder: { LiveApi() })", knownRightExpression: "Root().hub"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCycleParameterAtPackageAccess_whenSeamsTierIsPackage() async throws {
		// Every type is `package`, and `App` is in `Feature`'s package: `Hub`'s one tier is `package`, and so is each field.
		let modules = Self.modules(access: "package", appPackageName: "Shop")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
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
			        public let api: (Tag, TagReader, Instantiator<B>) -> __safeDI_Built

			        public init(api: @escaping (Tag, TagReader, Instantiator<B>) -> __safeDI_Built) {
			            self.api = api
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(api: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    package init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(tag)
			        @inline(never) func __safeDI_aBuilder(tag: Tag) -> A {
			            let reader = TagReader(tag: tag)
			            @inline(never) func __safeDI_bBuilder(tag: Tag) -> B {
			                let aBuilder = Instantiator<A> {
			                    __safeDI_aBuilder(tag: tag)
			                }
			                return B(tag: tag, aBuilder: aBuilder)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(tag: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_aBuilder.api(tag, reader, bBuilder)
			            return A(reader: reader, api: api, bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(tag: tag.instance)
			        }
			        self.init(aBuilder: aBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_57FE31E06C311ED5 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
			            .init(aBuilder: { values_tag in __safeDI_apiBuilder_Hub_A_Scope() })
			        }
			        func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
			            .init(api: { scope_tag, scope_reader, scope_bBuilder in
			                let api: any Api = LiveApi()
			                return api
			            })
			        }
			        let tag = Tag()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_57FE31E06C311ED5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Hub(__safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(tag: tag, hub: hub)
			    }
			}
			""",
		])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	// MARK: A site passed up from inside the function

	/// `Core`, where the seam `Inner` builds `api: any Api`, a hole only `App` can fill, beside `innerDeclarations`;
	/// `Feature`, where the seam `Hub` builds `A` behind `aBuilder: Instantiator<A>`, and `A` builds `TagReader`, which
	/// receives `tag`, `Inner`, whose builder `Hub` passes up, and `B`, which forwards `tag` and builds `A` again, so the
	/// function that builds `A` takes `tag`; and `App`, which declares `LiveApi`, which fulfills `Api` with
	/// `liveApiDeclarations`, and `Root`, which instantiates `tag` and `hub`. `Tag` and `Root` are classes with creation
	/// stamps.
	private static func passedUpModules(innerDeclarations: [String] = [], liveApiDeclarations: [String] = []) -> [ModuleFixture] {
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "Counter")
		let tag = """
		@Instantiable
		public final class Tag: Instantiable {
		    public init() {}

		    \(stamp)
		}
		"""
		let core = [
			DifferentialValueCreationStamp.counterDeclaration(named: "Counter"),
			"public protocol Api {}",
			tag,
			seamFixtureType(named: "Inner", isSeam: true, declarations: innerDeclarations + ["@Instantiated let api: any Api"]),
		]
		let feature = [
			seamFixtureType(named: "TagReader", declarations: ["@Received let tag: Tag"]),
			seamFixtureType(named: "A", declarations: ["@Instantiated let reader: TagReader", "@Instantiated let inner: Inner", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded let tag: Tag", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
		]
		let liveApi = seamFixtureType(named: "LiveApi", declarations: liveApiDeclarations, conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
		let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let tag: Tag", "@Instantiated let hub: Hub"])
			.replacingOccurrences(of: "public final class Root: Instantiable {\n", with: "public final class Root: Instantiable {\n    \(stamp)\n\n")
		return [
			ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: core),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature.map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [liveApi, root].map { "import Core\nimport Feature\n\n" + $0 }, dependencies: ["Core", "Feature"]),
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenSeamPassesUpSiteInsideFunctionThatTakesCycleParameter() async {
		// `Hub` passes up the builder `Inner` takes for `api`, and calls `Inner` inside the function that builds `A`, which
		// takes `tag`. Inline, the `LiveApi` that `Inner` builds where `B` builds `A` again receives `B`'s `tag`; `Root`, which
		// fills the builder, holds only its own.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):10:5: error: `LiveApi` receives `tag: Tag`, which `A`’s builder function takes as a parameter on the path where `Hub` calls `Inner`, because a cycle inside `A`’s tree passes it, but `Hub` passes the builder for `Inner`’s `api: any Api` (`api` of `apiBuilder`) on from its own caller, which cannot hand it that value. Declare `@Received let tag: Tag` on `Inner`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies, so `Hub` fills the builder itself.
			\(fixtures["Feature"]!["TagReader.swift"]):9:5: note: `TagReader` receives `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.passedUpModules(liveApiDeclarations: ["@Received let tag: Tag"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCycleParameterFromInnerSeamsScope_whenInnerSeamReceivesLabel() async throws {
		// `Inner` receives `tag`, so `Hub` passes it the function's `tag` and `Inner`'s struct carries it: where `B` builds `A`
		// again, the `LiveApi` that `Inner` builds receives `B`'s `tag`, as inline's does.
		let modules = Self.passedUpModules(innerDeclarations: ["@Received let tag: Tag"], liveApiDeclarations: ["@Received let tag: Tag"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let innerCallComment = MultiModuleIntegration.moduleInfo.seamCallComment(type: "Inner", declaringModule: "Core")
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

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
		        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.inner = inner
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
		        let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(tag)
		        @inline(never) func __safeDI_aBuilder(tag: Tag) -> A {
		            let reader = TagReader(tag: tag)
		            @inline(never) func __safeDI_inner() -> Inner {
		                _ = Inner.__safeDI_Inner_5483833909C8FF8D.self\(innerCallComment)
		                return Inner(__safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder_aBuilder.inner)
		            }
		            let inner: Inner = __safeDI_inner()
		            @inline(never) func __safeDI_bBuilder(tag: Tag) -> B {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(tag: tag)
		                }
		                return B(tag: tag, aBuilder: aBuilder)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(tag: $0)
		            }
		            return A(reader: reader, inner: inner, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(tag: tag.instance)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_D079BEC3A0471EAD {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Hub() -> Hub.__safeDI_ApiCarrier<any Api> {
		            .init(aBuilder: { values_tag in __safeDI_apiBuilder_Hub_A_Scope() })
		        }
		        func __safeDI_apiBuilder_Hub_A_Scope() -> Hub.__safeDI_ApiCarrier_A<any Api> {
		            .init(inner: __safeDI_apiBuilder_Inner())
		        }
		        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_tag in
		                let tag = scope_tag
		                let api: any Api = LiveApi(tag: tag)
		                return api
		            })
		        }
		        let tag = Tag()
		        func __safeDI_hub() -> Hub {
		            _ = Hub.__safeDI_Hub_D079BEC3A0471EAD.self\(Self.callComment)
		            return Hub(__safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub())
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(tag: tag, hub: hub)
		    }
		}
		"""])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	// MARK: Values

	/// Expects the values `output`, the run of `modules`, builds for `probes` to equal those the run of `modules` with `Hub`
	/// built inline builds.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualInlineBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.inlineModules(modules)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private var filesToDelete: [URL]
}
