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

/// What a public mock's root level holds: the values `mock()` binds itself before it builds its tree – a `@Forwarded`
/// property, a received dependency the mock cannot build, one received only if available, and the wrapper it binds around
/// one received lazily – as a seam's root level holds its parameters. `Detail`, in module `Feature`, is a seam with a public mock and an `internal` initializer, so module
/// `App`, in another package, calls `Detail.mock()`; `Detail` instantiates `api: any Api`, which only `App`'s `Live`
/// fulfills, and `Live` receives the value `Detail` binds before `api`.
struct SafeDIToolPublicMockRootLevelTests: ~Copyable {
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

	@Test(arguments: RootValue.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesValueMockBindsBeforeItsTreeInRootPayload_whenPublicMocksPlaceIsBuiltAtRoot(rootValue: RootValue) async throws {
		// The seam's `api_Values` holds the value; the public mock's must too, so a fill reads it there.
		let modules = Self.publicMockModules(rootValue)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let generated = output.modules["Feature"]?.generatedFiles["Feature.swift"]
		#expect(generated == generatedFileHeader + rootValue.expectedFeature)
		if let generated, generated != generatedFileHeader + rootValue.expectedFeature {
			Issue.record(Comment(rawValue: "=== Feature.swift\n" + generated.dropFirst(generatedFileHeader.count)))
		}
	}

	@Test(arguments: RootValue.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPublicMocksPlaceWithValueMockBindsBeforeItsTree_whenCallingMocksFulfillerReceivesIt(rootValue: RootValue) async throws {
		// `Root.mock()` fills `Detail`'s place with `Live`, handing it the value the public mock bound, as the same graph's
		// mock does when it builds `Detail` inline. On a mock root level that carries nothing, `App` passes the place up:
		// `Root.mock()` then takes a required `apiBuilder`, which the probe does not pass, and whose closure cannot read the
		// value either.
		let modules = Self.publicMockModules(rootValue)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.inlineModules(rootValue)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: [DifferentialValueProbe(rootValue.probe)],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBeneathChildWithForwardedValueOfRootLevel_whenFulfillerReceivesIt() async throws {
		// `api` is built in `Panel`, beneath the root: the root level is the first level on its route, and `Live` reads `id`
		// there.
		try await expectPublicMock(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Panel", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				Self.publicMockType(named: "Detail", declarations: ["@Forwarded public let id: Int", "@Instantiated public let panel: Panel"]),
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: ["@Received public let id: Int"]),
				Self.mockedRoot(declarations: ["@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			probes: [DifferentialValueProbe("Root.mock().detailBuilder.instantiate(7)")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case panel(panel_Values, SafeDIMockScope_Api.Panel_Scope)

			        public struct panel_Values {
			            public let id: Int
			        }

			        @frozen public enum Panel_Scope {
			            case api(api_Values)

			            public struct api_Values {}
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            panel: ((any Api) -> Panel)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel
			            )
			        }

			        public var panel: ((any Api) -> Panel)? { __safeDI_storage.panel }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: ((any Api) -> Panel)?
			            ) {
			                self.panel = panel
			            }

			            let panel: ((any Api) -> Panel)?
			        }
			    }

			    public static func mock(
			        id: Int,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let __safeDI_apiValues_panel = SafeDIMockScope_Api.panel_Values(id: id)
			        func __safeDI_panel() -> Panel {
			            let api: any Api = __safeDI_apiBuilder(.panel(__safeDI_apiValues_panel, .api(SafeDIMockScope_Api.Panel_Scope.api_Values())))
			            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(api) } else { Panel(api: api) }
			        }
			        let panel: Panel = __safeDI_panel()
			        return Detail(id: id, panel: panel)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_08ADD92D89E60DD1 {}
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesWrapperMockBindsInRootLevel_whenFulfillerReceivesInstanceOfLazilyInstantiatedValueMockCannotBuild() async throws {
		// `mock()` takes the instance under the label and binds the wrapper it hands `Detail` under a name apart. The root
		// level holds the wrapper, read from that name, as the seam's holds the wrapper it takes, and `Live`, which receives
		// the instance, is handed the wrapper's instance.
		// A stated divergence: `Live`'s fill reads the instance through `Detail.mock()`'s wrapper, which then reports its
		// instance read, where inline `Live` is handed `Root.mock()`'s instance and `Detail` the wrapper no one read. The
		// instance is the one inline shares, which the wrapper only holds.
		try await expectPublicMock(
			feature: [
				Self.featureTypes,
				Self.publicMockType(named: "Detail", declarations: ["@Received public let session: LazilyInstantiated<Session>", "@Instantiated public let api: any Api"]),
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: ["@Received public let session: Session"]),
				Self.mockedRoot(declarations: ["@Received public let session: LazilyInstantiated<Session>", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			probes: [DifferentialValueProbe("Root.mock(session: Session()).detailBuilder.instantiate()")],
			exempting: [DifferentialValueDifference(
				probe: "Root.mock(session: Session()).detailBuilder.instantiate()",
				path: ["<1> Detail", "session"],
				feature: "session: <2> LazilyInstantiated<Session> (already instantiated, instance read last)",
				knownRight: "session: <2> LazilyInstantiated<Session> (instance read last)",
			)],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case api(api_Values)

			        public struct api_Values {
			            public let session: LazilyInstantiated<Session>
			        }
			    }

			    public static func mock(
			        session: Session,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let session_lazilyInstantiated = LazilyInstantiated<Session> { session }
			        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(session: session_lazilyInstantiated)))
			        return Detail(session: session_lazilyInstantiated, api: api)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_33973195EAE76EEE {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: ((Session, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        var detailBuilder: ((Session, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: ((Session, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: ((Session, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			        }
			    }

			    static func mock(
			        session: Session,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session_lazilyInstantiated = LazilyInstantiated<Session> { session }
			        func __safeDI_detailBuilder() -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let session = scope.session
			                    let api: any Api = Live(session: session.instance)
			                    return api
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_33973195EAE76EEE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(session, __safeDI_apiBuilder_Detail) } else { Detail.mock(session: session, apiBuilder: __safeDI_apiBuilder_Detail) }
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        return Root(session: session_lazilyInstantiated, detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsForwardedFormInRootLevelAndBindsOtherFormAgain_whenTreeReceivesLabelInAnotherForm() async throws {
		try await expectPublicMock(
			feature: Self.labelInTwoFormsFeature(names: .canonical),
			app: Self.labelInTwoFormsApp(names: .canonical),
			// `Root.mock()` takes `Detail.mock()`'s parameter under its name; inline, it takes the receive under its label.
			probes: [DifferentialValueProbe(name: "detail", expression: "Root.mock(id_Token: Token()).detailBuilder.instantiate(7)", knownRightExpression: "Root.mock(id: Token()).detailBuilder.instantiate(7)")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case first(first_Values, SafeDIMockScope_Api.Child_Scope)

			        public struct first_Values {
			            public let id: Int
			        }

			        @frozen public enum Child_Scope {
			            case api(api_Values)

			            public struct api_Values {
			                public let id: Token
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            first: ((Token, any Api) -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first
			            )
			        }

			        public var first: ((Token, any Api) -> Child)? { __safeDI_storage.first }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: ((Token, any Api) -> Child)?
			            ) {
			                self.first = first
			            }

			            let first: ((Token, any Api) -> Child)?
			        }
			    }

			    public static func mock(
			        id: Int,
			        id_Token: Token,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api,
			        first: Child? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let __safeDI_apiValues_first = SafeDIMockScope_Api.first_Values(id: id)
			        func __safeDI_first() -> Child {
			            let id: Token = id_Token
			            let api: any Api = __safeDI_apiBuilder(.first(__safeDI_apiValues_first, .api(SafeDIMockScope_Api.Child_Scope.api_Values(id: id))))
			            return if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(id, api) } else { Child(id: id, api: api) }
			        }
			        let first: Child = if let first { first } else { __safeDI_first() }
			        return Detail(id: id, first: first)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_27F2000823ACB90E {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: Detail.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        var detailBuilder: Detail.SafeDIOverrides { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: Detail.SafeDIOverrides
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: Detail.SafeDIOverrides
			        }
			    }

			    static func mock(
			        id_Token: Token,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_detailBuilder(id: Int) -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .first(_, scope): return __safeDI_apiBuilder_Detail_Child_Scope(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Detail_Child_Scope(_ scope: Detail.SafeDIMockScope_Api.Child_Scope) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let id = scope.id
			                    let api: any Api = Live(id: id)
			                    return api
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_27F2000823ACB90E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Detail.mock(id: id, id_Token: id_Token, apiBuilder: __safeDI_apiBuilder_Detail, first: nil, safeDIOverrides: safeDIOverrides.detailBuilder)
			        }
			        let detailBuilder = Instantiator<Detail> {
			            __safeDI_detailBuilder(id: $0)
			        }
			        return Root(detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsNoRootFieldOfLabelAndBindsEachFormAgain_whenMockNamesBothFormsApart() async throws {
		try await expectPublicMock(
			feature: Self.labelNamedApartFeature(names: .canonical),
			app: Self.labelNamedApartApp(names: .canonical),
			probes: [DifferentialValueProbe("Root.mock(id_Badge: Badge(), id_Token: Token()).detailBuilder.instantiate()")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case first(first_Values, SafeDIMockScope_Api.Child_Scope)

			        public struct first_Values {}

			        @frozen public enum Child_Scope {
			            case api(api_Values)

			            public struct api_Values {
			                public let id: Token
			            }
			        }
			    }

			    @frozen public enum SafeDIMockScope_Gadget {
			        case second(second_Values, SafeDIMockScope_Gadget.Other_Scope)

			        public struct second_Values {
			            public let first: Child
			        }

			        @frozen public enum Other_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {
			                public let id: Badge
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            first: ((Token, any Api) -> Child)? = nil,
			            second: ((Badge, any Gadget) -> Other)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        public var first: ((Token, any Api) -> Child)? { __safeDI_storage.first }
			        public var second: ((Badge, any Gadget) -> Other)? { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: ((Token, any Api) -> Child)?,
			                second: ((Badge, any Gadget) -> Other)?
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: ((Token, any Api) -> Child)?
			            let second: ((Badge, any Gadget) -> Other)?
			        }
			    }

			    public static func mock(
			        id_Badge: Badge,
			        id_Token: Token,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api,
			        gadgetBuilder: @escaping (Detail.SafeDIMockScope_Gadget) -> any Gadget,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let __safeDI_gadgetBuilder = gadgetBuilder
			        let __safeDI_apiValues_first = SafeDIMockScope_Api.first_Values()
			        func __safeDI_first() -> Child {
			            let id: Token = id_Token
			            let api: any Api = __safeDI_apiBuilder(.first(__safeDI_apiValues_first, .api(SafeDIMockScope_Api.Child_Scope.api_Values(id: id))))
			            return if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(id, api) } else { Child(id: id, api: api) }
			        }
			        let first: Child = __safeDI_first()
			        let __safeDI_gadgetValues_second = SafeDIMockScope_Gadget.second_Values(first: first)
			        func __safeDI_second() -> Other {
			            let id: Badge = id_Badge
			            let gadget: any Gadget = __safeDI_gadgetBuilder(.second(__safeDI_gadgetValues_second, .gadget(SafeDIMockScope_Gadget.Other_Scope.gadget_Values(id: id))))
			            return if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(id, gadget) } else { Other(id: id, gadget: gadget) }
			        }
			        let second: Other = __safeDI_second()
			        return Detail(first: first, second: second)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_9AFB2582DEBF4A0B {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: Detail.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        var detailBuilder: Detail.SafeDIOverrides { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: Detail.SafeDIOverrides
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: Detail.SafeDIOverrides
			        }
			    }

			    static func mock(
			        id_Badge: Badge,
			        id_Token: Token,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_detailBuilder() -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .first(_, scope): return __safeDI_apiBuilder_Detail_Child_Scope(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Detail_Child_Scope(_ scope: Detail.SafeDIMockScope_Api.Child_Scope) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let id = scope.id
			                    let api: any Api = Live(id: id)
			                    return api
			                }
			            }
			            func __safeDI_gadgetBuilder_Detail(_ scope: Detail.SafeDIMockScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .second(_, scope): return __safeDI_gadgetBuilder_Detail_Other_Scope(scope)
			                }
			            }
			            func __safeDI_gadgetBuilder_Detail_Other_Scope(_ scope: Detail.SafeDIMockScope_Gadget.Other_Scope) -> any Gadget {
			                switch scope {
			                case let .gadget(scope):
			                    let id = scope.id
			                    let gadget: any Gadget = LiveGadget(id: id)
			                    return gadget
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_9AFB2582DEBF4A0B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Detail.mock(id_Badge: id_Badge, id_Token: id_Token, apiBuilder: __safeDI_apiBuilder_Detail, gadgetBuilder: __safeDI_gadgetBuilder_Detail, safeDIOverrides: safeDIOverrides.detailBuilder)
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        return Root(detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresPackageFieldAndPassesNilFromPublicTier_whenPublicMockReceivesPackageValueOnlyIfAvailable() async throws {
		// `App` is in `Feature`'s package, so it calls the `package` tier, which takes `token`; the `public` tier passes `nil`.
		try await expectPublicMock(
			feature: [
				"public protocol Api {}",
				"package final class Token {\n    package init() {}\n}",
				"""
				@Instantiable(generateMock: .public)
				public final class Detail: Instantiable {
				    init(token: Token?, api: any Api) {
				        self.token = token
				        self.api = api
				    }

				    @Received(onlyIfAvailable: true) package let token: Token?
				    @Instantiated public let api: any Api
				}
				""",
			],
			app: [
				"""
				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class Live: Instantiable, Api {
				    package init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) package let token: Token?
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    package init(token: Token?, detailBuilder: Instantiator<Detail>) {
				        self.token = token
				        self.detailBuilder = detailBuilder
				    }

				    @Received(onlyIfAvailable: true) package let token: Token?
				    @Instantiated public let detailBuilder: Instantiator<Detail>
				}
				""",
			],
			appPackageName: "Shop",
			inlineInitializerAccess: "package",
			probes: [DifferentialValueProbe("Root.mock(safeDIOverrides: .init(token: Token())).detailBuilder.instantiate()")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case api(api_Values)

			        public struct api_Values {
			            package let token: Token?
			        }
			    }

			    public static func mock(
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api
			    ) -> Detail {
			        Detail.mock(apiBuilder: apiBuilder, token: nil)
			    }

			    package static func mock(
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api,
			        token: Token? = nil
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(token: token)))
			        return Detail(token: token, api: api)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_AD347AC086E4FD02 {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: ((@escaping (Detail.SafeDIMockScope_Api) -> any Api, Token?) -> Detail)? = nil,
			            token: Token? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			            self.token = token
			        }

			        var detailBuilder: ((@escaping (Detail.SafeDIMockScope_Api) -> any Api, Token?) -> Detail)? { __safeDI_storage.detailBuilder }
			        let token: Token?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: ((@escaping (Detail.SafeDIMockScope_Api) -> any Api, Token?) -> Detail)?
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: ((@escaping (Detail.SafeDIMockScope_Api) -> any Api, Token?) -> Detail)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let token: Token? = safeDIOverrides.token
			        func __safeDI_detailBuilder() -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let token = scope.token
			                    let api: any Api = Live(token: token)
			                    return api
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_AD347AC086E4FD02.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(__safeDI_apiBuilder_Detail, token) } else { Detail.mock(apiBuilder: __safeDI_apiBuilder_Detail, token: token) }
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        return Root(token: token, detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsEachBuildsOwnValuesInRootLevel_whenMockedTypeIsBuiltAgainInItsTree() async throws {
		// `Detail` builds itself again through `nextBuilder`: each build's `api` is handed the `id` forwarded to that build and
		// the `session` it receives. `first`, which the mock promotes, receives `id: Token`, which `mock()` names apart beside
		// the forwarded `id`, and holds `gadget`.
		try await expectPublicMock(
			feature: [
				Self.featureTypes,
				"public protocol Gadget {}",
				seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received public let id: Token", "@Instantiated public let gadget: any Gadget"])
					.replacingOccurrences(of: "public init(", with: "init("),
				Self.publicMockType(named: "Detail", declarations: [
					"@Forwarded public let id: Int",
					"@Received public let session: Session",
					"@Received public let first: Child",
					"@Instantiated public let api: any Api",
					"@Instantiated public let nextBuilder: Instantiator<Detail>",
				]),
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: ["@Received public let id: Int", "@Received public let session: Session"]),
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let id: Token"]),
				Self.mockedRoot(declarations: ["@Received public let session: Session", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			probes: [DifferentialValueProbe(
				name: "detail",
				expression: "Root.mock(id_Token: Token(), session: Session()).detailBuilder.instantiate(1).nextBuilder.instantiate(2).nextBuilder.instantiate(3)",
				knownRightExpression: "Root.mock(id: Token(), session: Session()).detailBuilder.instantiate(1).nextBuilder.instantiate(2).nextBuilder.instantiate(3)",
			)],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case api(api_Values)
			        indirect case nextBuilder(nextBuilder_Values, SafeDIMockScope_Api)

			        public struct api_Values {
			            public let id: Int
			            public let session: Session
			        }

			        public struct nextBuilder_Values {
			            public let id: Int
			            public let session: Session
			            public let api: any Api
			            public let first: Child
			        }
			    }

			    @frozen public enum SafeDIMockScope_Gadget {
			        case first(first_Values, SafeDIMockScope_Gadget.Child_Scope)

			        public struct first_Values {
			            public let id: Int
			            public let session: Session
			            public let api: any Api
			        }

			        @frozen public enum Child_Scope {
			            case gadget(gadget_Values)

			            public struct gadget_Values {
			                public let id: Token
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            first: ((Token, any Gadget) -> Child)? = nil,
			            nextBuilder: __safeDI_Feature_Detail_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                nextBuilder: nextBuilder
			            )
			        }

			        public var first: ((Token, any Gadget) -> Child)? { __safeDI_storage.first }
			        public var nextBuilder: __safeDI_Feature_Detail_MockConfiguration { __safeDI_storage.nextBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: ((Token, any Gadget) -> Child)?,
			                nextBuilder: __safeDI_Feature_Detail_MockConfiguration
			            ) {
			                self.first = first
			                self.nextBuilder = nextBuilder
			            }

			            let first: ((Token, any Gadget) -> Child)?
			            let nextBuilder: __safeDI_Feature_Detail_MockConfiguration
			        }
			    }

			    public static func mock(
			        id: Int,
			        id_Token: Token,
			        session: Session,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api,
			        gadgetBuilder: @escaping (Detail.SafeDIMockScope_Gadget) -> any Gadget,
			        first: Child? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let __safeDI_gadgetBuilder = gadgetBuilder
			        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(id: id, session: session)))
			        let __safeDI_gadgetValues_first = SafeDIMockScope_Gadget.first_Values(id: id, session: session, api: api)
			        func __safeDI_first() -> Child {
			            let id: Token = id_Token
			            let gadget: any Gadget = __safeDI_gadgetBuilder(.first(__safeDI_gadgetValues_first, .gadget(SafeDIMockScope_Gadget.Child_Scope.gadget_Values(id: id))))
			            return if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(id, gadget) } else { Child(id: id, gadget: gadget) }
			        }
			        let first: Child = if let first { first } else { __safeDI_first() }
			        let __safeDI_apiValues_nextBuilder = SafeDIMockScope_Api.nextBuilder_Values(id: id, session: session, api: api, first: first)
			        func __safeDI_nextBuilder(id: Int) -> Detail {
			            let api: any Api = __safeDI_apiBuilder(.nextBuilder(__safeDI_apiValues_nextBuilder, .api(SafeDIMockScope_Api.api_Values(id: id, session: session))))
			            let nextBuilder = Instantiator<Detail> {
			                __safeDI_nextBuilder(id: $0)
			            }
			            return Detail.__safeDI_init(id: id, session: session, first: first, api: api, nextBuilder: nextBuilder, safeDIBuilder: safeDIOverrides.nextBuilder.safeDIBuilder)
			        }
			        let nextBuilder = Instantiator<Detail> {
			            __safeDI_nextBuilder(id: $0)
			        }
			        return Detail(id: id, session: session, first: first, api: api, nextBuilder: nextBuilder)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_D8B6ADD6EEC9E824 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Detail` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Detail_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((Int, Session, Child, any Api, Instantiator<Detail>) -> Detail)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// Overrides how `Detail` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Int, Session, Child, any Api, Instantiator<Detail>) -> Detail)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            safeDIBuilder: ((Int, Session, Child, any Api, Instantiator<Detail>) -> Detail)?
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let safeDIBuilder: ((Int, Session, Child, any Api, Instantiator<Detail>) -> Detail)?
			    }
			}

			extension Detail {
			    static func __safeDI_init(id: Int, session: Session, first: Child, api: any Api, nextBuilder: Instantiator<Detail>, safeDIBuilder: ((Int, Session, Child, any Api, Instantiator<Detail>) -> Detail)?) -> Detail {
			        if let safeDIBuilder { safeDIBuilder(id, session, first, api, nextBuilder) } else { Detail(id: id, session: session, first: first, api: api, nextBuilder: nextBuilder) }
			    }
			}
			#endif

			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: Detail.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        var detailBuilder: Detail.SafeDIOverrides { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: Detail.SafeDIOverrides
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: Detail.SafeDIOverrides
			        }
			    }

			    static func mock(
			        id_Token: Token,
			        session: Session,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_detailBuilder(id: Int) -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let id = scope.id
			                    let session = scope.session
			                    let api: any Api = Live(id: id, session: session)
			                    return api
			                case let .nextBuilder(_, scope): return __safeDI_apiBuilder_Detail(scope)
			                }
			            }
			            func __safeDI_gadgetBuilder_Detail(_ scope: Detail.SafeDIMockScope_Gadget) -> any Gadget {
			                switch scope {
			                case let .first(_, scope): return __safeDI_gadgetBuilder_Detail_Child_Scope(scope)
			                }
			            }
			            func __safeDI_gadgetBuilder_Detail_Child_Scope(_ scope: Detail.SafeDIMockScope_Gadget.Child_Scope) -> any Gadget {
			                switch scope {
			                case let .gadget(scope):
			                    let id = scope.id
			                    let gadget: any Gadget = LiveGadget(id: id)
			                    return gadget
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_D8B6ADD6EEC9E824.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Detail.mock(id: id, id_Token: id_Token, session: session, apiBuilder: __safeDI_apiBuilder_Detail, gadgetBuilder: __safeDI_gadgetBuilder_Detail, first: nil, safeDIOverrides: safeDIOverrides.detailBuilder)
			        }
			        let detailBuilder = Instantiator<Detail> {
			            __safeDI_detailBuilder(id: $0)
			        }
			        return Root(session: session, detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsEachBuildsWrapperInRootLevel_whenMockedTypeReceivingLazilyInstantiatedValueIsBuiltAgain() async throws {
		// `Detail` receives `session` lazily and builds itself again through `nextBuilder`: each build's root level holds the
		// wrapper that build is handed, which `mock()` binds apart from the instance it takes, and the `id` forwarded to it.
		try await expectPublicMock(
			feature: [
				Self.featureTypes,
				Self.publicMockType(named: "Detail", declarations: [
					"@Forwarded public let id: Int",
					"@Received public let session: LazilyInstantiated<Session>",
					"@Instantiated public let api: any Api",
					"@Instantiated public let nextBuilder: Instantiator<Detail>",
				]),
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: ["@Received public let id: Int", "@Received public let session: LazilyInstantiated<Session>"]),
				Self.mockedRoot(declarations: ["@Received public let session: LazilyInstantiated<Session>", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			probes: [DifferentialValueProbe("Root.mock(session: Session()).detailBuilder.instantiate(1).nextBuilder.instantiate(2).nextBuilder.instantiate(3)")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case api(api_Values)
			        indirect case nextBuilder(nextBuilder_Values, SafeDIMockScope_Api)

			        public struct api_Values {
			            public let id: Int
			            public let session: LazilyInstantiated<Session>
			        }

			        public struct nextBuilder_Values {
			            public let id: Int
			            public let session: LazilyInstantiated<Session>
			            public let api: any Api
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            nextBuilder: __safeDI_Feature_Detail_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nextBuilder: nextBuilder
			            )
			        }

			        public var nextBuilder: __safeDI_Feature_Detail_MockConfiguration { __safeDI_storage.nextBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                nextBuilder: __safeDI_Feature_Detail_MockConfiguration
			            ) {
			                self.nextBuilder = nextBuilder
			            }

			            let nextBuilder: __safeDI_Feature_Detail_MockConfiguration
			        }
			    }

			    public static func mock(
			        id: Int,
			        session: Session,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let session_lazilyInstantiated = LazilyInstantiated<Session> { session }
			        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(id: id, session: session_lazilyInstantiated)))
			        let __safeDI_apiValues_nextBuilder = SafeDIMockScope_Api.nextBuilder_Values(id: id, session: session_lazilyInstantiated, api: api)
			        func __safeDI_nextBuilder(id: Int) -> Detail {
			            let api: any Api = __safeDI_apiBuilder(.nextBuilder(__safeDI_apiValues_nextBuilder, .api(SafeDIMockScope_Api.api_Values(id: id, session: session_lazilyInstantiated))))
			            let nextBuilder = Instantiator<Detail> {
			                __safeDI_nextBuilder(id: $0)
			            }
			            return Detail.__safeDI_init(id: id, session: session_lazilyInstantiated, api: api, nextBuilder: nextBuilder, safeDIBuilder: safeDIOverrides.nextBuilder.safeDIBuilder)
			        }
			        let nextBuilder = Instantiator<Detail> {
			            __safeDI_nextBuilder(id: $0)
			        }
			        return Detail(id: id, session: session_lazilyInstantiated, api: api, nextBuilder: nextBuilder)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_8588E2907C8994A8 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Detail` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Detail_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((Int, LazilyInstantiated<Session>, any Api, Instantiator<Detail>) -> Detail)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// Overrides how `Detail` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Int, LazilyInstantiated<Session>, any Api, Instantiator<Detail>) -> Detail)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            safeDIBuilder: ((Int, LazilyInstantiated<Session>, any Api, Instantiator<Detail>) -> Detail)?
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let safeDIBuilder: ((Int, LazilyInstantiated<Session>, any Api, Instantiator<Detail>) -> Detail)?
			    }
			}

			extension Detail {
			    static func __safeDI_init(id: Int, session: LazilyInstantiated<Session>, api: any Api, nextBuilder: Instantiator<Detail>, safeDIBuilder: ((Int, LazilyInstantiated<Session>, any Api, Instantiator<Detail>) -> Detail)?) -> Detail {
			        if let safeDIBuilder { safeDIBuilder(id, session, api, nextBuilder) } else { Detail(id: id, session: session, api: api, nextBuilder: nextBuilder) }
			    }
			}
			#endif

			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: Detail.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        var detailBuilder: Detail.SafeDIOverrides { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: Detail.SafeDIOverrides
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: Detail.SafeDIOverrides
			        }
			    }

			    static func mock(
			        session: Session,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session_lazilyInstantiated = LazilyInstantiated<Session> { session }
			        func __safeDI_detailBuilder(id: Int) -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let id = scope.id
			                    let session = scope.session
			                    let api: any Api = Live(id: id, session: session)
			                    return api
			                case let .nextBuilder(_, scope): return __safeDI_apiBuilder_Detail(scope)
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_8588E2907C8994A8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Detail.mock(id: id, session: session, apiBuilder: __safeDI_apiBuilder_Detail, safeDIOverrides: safeDIOverrides.detailBuilder)
			        }
			        let detailBuilder = Instantiator<Detail> {
			            __safeDI_detailBuilder(id: $0)
			        }
			        return Root(session: session_lazilyInstantiated, detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithClosureMockedTypeInstantiates_whenFulfillerReceivesIt() async throws {
		// Nothing can build `format`, a closure, which `mock()` takes as a parameter; `Live` receives it.
		try await expectPublicMock(
			feature: [
				"public protocol Api {}",
				Self.publicMockType(named: "Detail", declarations: ["@Instantiated public let format: (Int) -> String", "@Instantiated public let api: any Api"]),
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: ["@Received public let format: (Int) -> String"]),
				Self.mockedRoot(declarations: ["@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			probes: [DifferentialValueProbe("Root.mock(format: { String($0) }).detailBuilder.instantiate()")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case api(api_Values)

			        public struct api_Values {
			            public let format: (Int) -> String
			        }
			    }

			    public static func mock(
			        format: @escaping (Int) -> String,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(format: format)))
			        return Detail(format: format, api: api)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_D75C03450093815F {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: ((@escaping (Int) -> String, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        var detailBuilder: ((@escaping (Int) -> String, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: ((@escaping (Int) -> String, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: ((@escaping (Int) -> String, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			        }
			    }

			    static func mock(
			        format: @escaping (Int) -> String,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_detailBuilder() -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let format = scope.format
			                    let api: any Api = Live(format: format)
			                    return api
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_D75C03450093815F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(format, __safeDI_apiBuilder_Detail) } else { Detail.mock(format: format, apiBuilder: __safeDI_apiBuilder_Detail) }
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        return Root(detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoBuilder_whenPublicCallingMocksFulfillerReadsValueOfRootLevel() async throws {
		// `Root`'s public mock fills `Detail`'s place itself, so it passes no builder up.
		try await expectPublicMock(
			feature: [
				"public protocol Api {}",
				Self.publicMockType(named: "Detail", declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api"]),
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: ["@Received public let id: Int"]),
				seamFixtureType(named: "Root", isFinalClass: true, declarations: ["@Instantiated public let detailBuilder: Instantiator<Detail>"])
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n"),
			],
			probes: [DifferentialValueProbe("Root.mock().detailBuilder.instantiate(7)")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case api(api_Values)

			        public struct api_Values {
			            public let id: Int
			        }
			    }

			    public static func mock(
			        id: Int,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(id: id)))
			        return Detail(id: id, api: api)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_31DA67991BB5767F {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            detailBuilder: ((Int, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        public var detailBuilder: ((Int, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: ((Int, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: ((Int, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_detailBuilder(id: Int) -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let id = scope.id
			                    let api: any Api = Live(id: id)
			                    return api
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_31DA67991BB5767F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(id, __safeDI_apiBuilder_Detail) } else { Detail.mock(id: id, apiBuilder: __safeDI_apiBuilder_Detail) }
			        }
			        let detailBuilder = Instantiator<Detail> {
			            __safeDI_detailBuilder(id: $0)
			        }
			        return Root(detailBuilder: detailBuilder)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUp_whenPlaceIsBuiltInsideSendableFunction() async throws {
		// `api` is built inside `panelBuilder`'s `@Sendable` function, whose case carries no value of the root level: `Root`
		// passes the place up, and a builder that captures the value fills it.
		try await expectPublicMock(
			feature: [
				"public protocol Api: Sendable {}",
				seamFixtureType(named: "Panel", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"], conformances: ", Sendable"),
				Self.publicMockType(named: "Detail", declarations: ["@Forwarded public let id: Int", "@Instantiated public let panelBuilder: SendableInstantiator<Panel>"]),
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: ["@Received public let id: Int"]),
				Self.mockedRoot(declarations: ["@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			probes: [DifferentialValueProbe(
				name: "panel",
				expression: "Root.mock(apiSendableBuilder: { _ in Live(id: 7) }).detailBuilder.instantiate(7).panelBuilder.instantiate()",
				knownRightExpression: "Root.mock().detailBuilder.instantiate(7).panelBuilder.instantiate()",
			)],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        @frozen public enum Panel_Scope {
			            case api(api_Values)

			            public struct api_Values {}
			        }
			    }

			    @frozen public enum SafeDISendableMockScope_Api {
			        case panelBuilder(SafeDIMockScope_Api.Panel_Scope)
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            panelBuilder: (@Sendable (any Api) -> Panel)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panelBuilder: panelBuilder
			            )
			        }

			        public var panelBuilder: (@Sendable (any Api) -> Panel)? { __safeDI_storage.panelBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panelBuilder: (@Sendable (any Api) -> Panel)?
			            ) {
			                self.panelBuilder = panelBuilder
			            }

			            let panelBuilder: (@Sendable (any Api) -> Panel)?
			        }
			    }

			    public static func mock(
			        id: Int,
			        apiSendableBuilder: @escaping @Sendable (Detail.SafeDISendableMockScope_Api) -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Detail {
			        let __safeDI_apiSendableBuilder = apiSendableBuilder
			        let __safeDI_panelBuilder__safeDIBuilder = safeDIOverrides.panelBuilder
			        @Sendable func __safeDI_panelBuilder() -> Panel {
			            let api: any Api = __safeDI_apiSendableBuilder(.panelBuilder(.api(SafeDIMockScope_Api.Panel_Scope.api_Values())))
			            return if let safeDIBuilder = __safeDI_panelBuilder__safeDIBuilder { safeDIBuilder(api) } else { Panel(api: api) }
			        }
			        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
			        return Detail(id: id, panelBuilder: panelBuilder)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_31E02770AFAFD8EE {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: Detail.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        var detailBuilder: Detail.SafeDIOverrides { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: Detail.SafeDIOverrides
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: Detail.SafeDIOverrides
			        }
			    }

			    static func mock(
			        apiSendableBuilder: @escaping @Sendable (Detail.SafeDISendableMockScope_Api) -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        _ = Detail.__safeDI_Detail_mock_31E02770AFAFD8EE.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_detailBuilder(id: Int) -> Detail {
			            Detail.mock(id: id, apiSendableBuilder: apiSendableBuilder, safeDIOverrides: safeDIOverrides.detailBuilder)
			        }
			        let detailBuilder = Instantiator<Detail> {
			            __safeDI_detailBuilder(id: $0)
			        }
			        return Root(detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test(arguments: LabelInTwoFormsShape.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesRootLevelOneShape_whenTypeAndFileNamesArePermuted(shape: LabelInTwoFormsShape) async throws {
		// Which form of `id` keeps the root level's field, and which levels bind a form again, follows `mock()`'s naming rule,
		// whatever the types and the files that declare them are named: each fixture file is named after its type, so the
		// names also order the files. The shape is `Feature`'s enums and its lines that bind a form of `id` again, never
		// `mock()`'s parameter list, which orders the two named-apart forms by `Property.precedesInMockOrder` (label, kind, then
		// type), so their order moves with the names by design.
		let canonicalShape = try await rootLevelShape(of: shape, names: .canonical)
		let names = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"]
		// Every fifth of the 120 orders, so each name takes each role.
		for (index, permutation) in Self.permutations(of: names).enumerated() where index.isMultiple(of: 5) {
			let permutedNames = LabelInTwoFormsNames(mocked: permutation[0], first: permutation[1], second: permutation[2], firstValue: permutation[3], secondValue: permutation[4])
			let permutedShape = try await rootLevelShape(of: shape, names: permutedNames)
			#expect(permutedShape == canonicalShape, "\(permutation)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceBeneathChild_whenFulfillerBeneathReadsWrapperRootLevelHolds() async throws {
		// The root level holds the wrapper `mock()` binds as `session_lazilyInstantiated` around the instance it takes, which it
		// hands `Panel` by that name, never binding it again under the label: `Live`, beneath `Panel`, reads the wrapper from the
		// root level, so `Root` fills the place, as inline.
		try await expectPublicMock(
			feature: [
				Self.featureTypes,
				seamFixtureType(named: "Panel", isFinalClass: true, declarations: ["@Received public let session: LazilyInstantiated<Session>", "@Instantiated public let api: any Api"]),
				Self.publicMockType(named: "Detail", declarations: ["@Received public let session: LazilyInstantiated<Session>", "@Instantiated public let panel: Panel"]),
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: ["@Received public let session: LazilyInstantiated<Session>"]),
				Self.mockedRoot(declarations: ["@Received public let session: LazilyInstantiated<Session>", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			probes: [DifferentialValueProbe("Root.mock(session: Session()).detailBuilder.instantiate()")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case panel(panel_Values, SafeDIMockScope_Api.Panel_Scope)

			        public struct panel_Values {
			            public let session: LazilyInstantiated<Session>
			        }

			        @frozen public enum Panel_Scope {
			            case api(api_Values)

			            public struct api_Values {}
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            panel: ((LazilyInstantiated<Session>, any Api) -> Panel)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel
			            )
			        }

			        public var panel: ((LazilyInstantiated<Session>, any Api) -> Panel)? { __safeDI_storage.panel }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: ((LazilyInstantiated<Session>, any Api) -> Panel)?
			            ) {
			                self.panel = panel
			            }

			            let panel: ((LazilyInstantiated<Session>, any Api) -> Panel)?
			        }
			    }

			    public static func mock(
			        session: Session,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        let session_lazilyInstantiated = LazilyInstantiated<Session> { session }
			        let __safeDI_apiValues_panel = SafeDIMockScope_Api.panel_Values(session: session_lazilyInstantiated)
			        func __safeDI_panel() -> Panel {
			            let api: any Api = __safeDI_apiBuilder(.panel(__safeDI_apiValues_panel, .api(SafeDIMockScope_Api.Panel_Scope.api_Values())))
			            return if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(session_lazilyInstantiated, api) } else { Panel(session: session_lazilyInstantiated, api: api) }
			        }
			        let panel: Panel = __safeDI_panel()
			        return Detail(session: session_lazilyInstantiated, panel: panel)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_91040B5780593FCA {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: Detail.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        var detailBuilder: Detail.SafeDIOverrides { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: Detail.SafeDIOverrides
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: Detail.SafeDIOverrides
			        }
			    }

			    static func mock(
			        session: Session,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session_lazilyInstantiated = LazilyInstantiated<Session> { session }
			        func __safeDI_detailBuilder() -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .panel(values, scope): return __safeDI_apiBuilder_Detail_Panel_Scope(scope, session: values.session)
			                }
			            }
			            func __safeDI_apiBuilder_Detail_Panel_Scope(_ scope: Detail.SafeDIMockScope_Api.Panel_Scope, session: LazilyInstantiated<Session>) -> any Api {
			                switch scope {
			                case .api:
			                    let api: any Api = Live(session: session)
			                    return api
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_91040B5780593FCA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Detail.mock(session: session, apiBuilder: __safeDI_apiBuilder_Detail, safeDIOverrides: safeDIOverrides.detailBuilder)
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        return Root(session: session_lazilyInstantiated, detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsFulfillingPropertyInRootLevel_whenMockedTypeReceivesValueUnderAlias() async throws {
		// `Detail` receives `session` as `renamed`: `mock()` takes `session`, which the root level holds, and binds `renamed`
		// from it, as a child of the root.
		try await expectPublicMock(
			feature: [
				Self.featureTypes,
				Self.publicMockType(named: "Detail", declarations: [#"@Received(fulfilledByDependencyNamed: "session", ofType: Session.self) public let renamed: Session"#, "@Instantiated public let api: any Api"]),
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: ["@Received public let session: Session", "@Received public let renamed: Session"]),
				Self.mockedRoot(declarations: ["@Received public let session: Session", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			probes: [DifferentialValueProbe("Root.mock(session: Session()).detailBuilder.instantiate()")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case api(api_Values)

			        public struct api_Values {
			            public let session: Session
			            public let renamed: Session
			        }
			    }

			    public static func mock(
			        session: Session,
			        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api
			    ) -> Detail {
			        let __safeDI_apiBuilder = apiBuilder
			        #sourceLocation(file: "{Detail.swift}", line: 8)
			        let renamed: Session = session
			        #sourceLocation()
			        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(session: session, renamed: renamed)))
			        return Detail(renamed: renamed, api: api)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_CF13E6EDEEC9603E {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detailBuilder: ((Session, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder
			            )
			        }

			        var detailBuilder: ((Session, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: ((Session, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			            ) {
			                self.detailBuilder = detailBuilder
			            }

			            let detailBuilder: ((Session, @escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			        }
			    }

			    static func mock(
			        session: Session,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_detailBuilder() -> Detail {
			            func __safeDI_apiBuilder_Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let session = scope.session
			                    let renamed = scope.renamed
			                    let api: any Api = Live(session: session, renamed: renamed)
			                    return api
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_CF13E6EDEEC9603E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(session, __safeDI_apiBuilder_Detail) } else { Detail.mock(session: session, apiBuilder: __safeDI_apiBuilder_Detail) }
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        return Root(session: session, detailBuilder: detailBuilder)
			    }
			}
			#endif
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appendsUnderscoreToHoleBuildersLabel_whenDefaultValuedParameterOfMockOutsideRootLevelTakesIt() async throws {
		// `Detail`'s initializer takes `apiBuilder: Int = 0`, which is not a dependency: `mock()` takes it as a flat parameter
		// that the root level does not hold, so the label of the builder of `api`'s place takes `_` and its enum keeps its name.
		try await expectPublicMock(
			feature: [
				"public protocol Api {}",
				"""
				@Instantiable(generateMock: .public)
				public final class Detail: Instantiable {
				    init(api: any Api, apiBuilder: Int = 0) {
				        self.api = api
				        self.apiBuilder = apiBuilder
				    }

				    @Instantiated public let api: any Api
				    public let apiBuilder: Int
				}
				""",
			],
			app: [
				Self.fulfillingType(named: "Live", declarations: []),
				Self.mockedRoot(declarations: ["@Instantiated public let detail: Detail"]),
			],
			probes: [DifferentialValueProbe("Root.mock().detail.apiBuilder")],
			expectedFeature: """
			#if DEBUG
			extension Detail {
			    @frozen public enum SafeDIMockScope_Api {
			        case api(api_Values)

			        public struct api_Values {}
			    }

			    public static func mock(
			        apiBuilder: Int? = nil,
			        apiBuilder_: @escaping (Detail.SafeDIMockScope_Api) -> any Api
			    ) -> Detail {
			        let __safeDI_apiBuilder_ = apiBuilder_
			        let apiBuilder = apiBuilder ?? (0)
			        let api: any Api = __safeDI_apiBuilder_(.api(SafeDIMockScope_Api.api_Values()))
			        return Detail(api: api, apiBuilder: apiBuilder)
			    }
			}

			extension Detail {
			    public enum __safeDI_Detail_mock_8913461BF3169573 {}
			}
			#endif
			""",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            detail: ((@escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detail: detail
			            )
			        }

			        var detail: ((@escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)? { __safeDI_storage.detail }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detail: ((@escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			            ) {
			                self.detail = detail
			            }

			            let detail: ((@escaping (Detail.SafeDIMockScope_Api) -> any Api) -> Detail)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_detail() -> Detail {
			            func __safeDI_apiBuilder__Detail(_ scope: Detail.SafeDIMockScope_Api) -> any Api {
			                switch scope {
			                case .api:
			                    let api: any Api = Live()
			                    return api
			                }
			            }
			            _ = Detail.__safeDI_Detail_mock_8913461BF3169573.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.detail { safeDIBuilder(__safeDI_apiBuilder__Detail) } else { Detail.mock(apiBuilder_: __safeDI_apiBuilder__Detail) }
			        }
			        let detail: Detail = __safeDI_detail()
			        return Root(detail: detail)
			    }
			}
			#endif
			""",
		)
	}

	// MARK: RootValue

	/// The two graphs whose root binds `id` in two forms.
	enum LabelInTwoFormsShape: CaseIterable, CustomTestStringConvertible {
		/// The mocked type forwards `id: Int`, and a type the mock promotes receives `id: <firstValue>`.
		case forwardedBesidePromotedReceive
		/// Two types of the mocked type's tree receive `id` in two forms, both of which `mock()` names apart.
		case twoFormsNamedApart

		var testDescription: String {
			switch self {
			case .forwardedBesidePromotedReceive:
				"forwarded beside a promoted type's receive"
			case .twoFormsNamedApart:
				"two forms named apart"
			}
		}
	}

	/// A value `Detail.mock()` binds before it builds its tree, which `Live` receives.
	enum RootValue: CaseIterable, CustomTestStringConvertible {
		/// `@Forwarded public let id: Int`, a parameter of `mock()` and of the instantiator that builds `Detail`.
		case forwarded
		/// `@Received public let session: Session`, of a type no `@Instantiable` declaration fulfills: a required
		/// parameter of `mock()`.
		case receivedThatMockCannotBuild
		/// `@Received(onlyIfAvailable: true) public let token: Token?`: an optional parameter of `mock()`.
		case receivedOnlyIfAvailable
		/// `@Received public let session: LazilyInstantiated<Session>`, of a type no `@Instantiable` declaration fulfills:
		/// `mock()` takes the instance and binds the wrapper under a name apart, and the root level holds the wrapper, as the
		/// seam's does.
		case receivedLazilyInstantiated
		/// `@Received(onlyIfAvailable: true) public let session: LazilyInstantiated<Session>?`: `mock()` takes an optional
		/// instance and binds the optional wrapper around it under a name apart, which the root level holds.
		case receivedLazilyInstantiatedOnlyIfAvailable

		var testDescription: String {
			switch self {
			case .forwarded:
				"forwarded"
			case .receivedThatMockCannotBuild:
				"received that the mock cannot build"
			case .receivedOnlyIfAvailable:
				"received only if available"
			case .receivedLazilyInstantiated:
				"received lazily instantiated"
			case .receivedLazilyInstantiatedOnlyIfAvailable:
				"received lazily instantiated only if available"
			}
		}

		/// `Detail`'s declaration of the value.
		var detailDeclaration: String {
			switch self {
			case .forwarded:
				"@Forwarded public let id: Int"
			case .receivedThatMockCannotBuild:
				"@Received public let session: Session"
			case .receivedOnlyIfAvailable:
				"@Received(onlyIfAvailable: true) public let token: Token?"
			case .receivedLazilyInstantiated:
				"@Received public let session: LazilyInstantiated<Session>"
			case .receivedLazilyInstantiatedOnlyIfAvailable:
				"@Received(onlyIfAvailable: true) public let session: LazilyInstantiated<Session>?"
			}
		}

		/// `Live`'s receive of the value.
		var liveDeclaration: String {
			switch self {
			case .forwarded:
				"@Received public let id: Int"
			case .receivedThatMockCannotBuild:
				"@Received public let session: Session"
			case .receivedOnlyIfAvailable:
				"@Received(onlyIfAvailable: true) public let token: Token?"
			case .receivedLazilyInstantiated:
				"@Received public let session: LazilyInstantiated<Session>"
			case .receivedLazilyInstantiatedOnlyIfAvailable:
				"@Received(onlyIfAvailable: true) public let session: LazilyInstantiated<Session>?"
			}
		}

		/// What `Root` declares beside `detailBuilder`: the value `Root.mock()` passes `Detail.mock()`.
		var rootDeclarations: [String] {
			switch self {
			case .forwarded:
				[]
			case .receivedThatMockCannotBuild:
				["@Received public let session: Session"]
			case .receivedOnlyIfAvailable:
				["@Received public let token: Token"]
			case .receivedLazilyInstantiated, .receivedLazilyInstantiatedOnlyIfAvailable:
				["@Received public let session: LazilyInstantiated<Session>"]
			}
		}

		/// What the test builds through `Root.mock()`: a `Detail`, whose `api` is a `Live`.
		var probe: String {
			switch self {
			case .forwarded:
				"Root.mock().detailBuilder.instantiate(7)"
			case .receivedThatMockCannotBuild:
				"Root.mock(session: Session()).detailBuilder.instantiate()"
			case .receivedOnlyIfAvailable:
				"Root.mock(token: Token()).detailBuilder.instantiate()"
			case .receivedLazilyInstantiated, .receivedLazilyInstantiatedOnlyIfAvailable:
				"Root.mock(session: Session()).detailBuilder.instantiate()"
			}
		}

		/// `Feature`'s generated file after its header. The public mock's `api_Values` holds what the seam's does, and the
		/// mock's guard hashes it.
		var expectedFeature: String {
			switch self {
			case .forwarded:
				"""
				extension Detail {
				    @frozen nonisolated public enum SafeDIScope_Api {
				        case api(api_Values)

				        nonisolated public struct api_Values {
				            public let id: Int
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built

				            public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                self.api = api
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.api = { _ in __safeDI_builder() }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_id id: Int, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values(id: id))
				        self.init(id: id, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_4FD7A6651375681C {}
				}

				#if DEBUG
				extension Detail {
				    @frozen public enum SafeDIMockScope_Api {
				        case api(api_Values)

				        public struct api_Values {
				            public let id: Int
				        }
				    }

				    public static func mock(
				        id: Int,
				        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api
				    ) -> Detail {
				        let __safeDI_apiBuilder = apiBuilder
				        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(id: id)))
				        return Detail(id: id, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_mock_31DA67991BB5767F {}
				}
				#endif
				"""
			case .receivedThatMockCannotBuild:
				"""
				extension Detail {
				    @frozen nonisolated public enum SafeDIScope_Api {
				        case api(api_Values)

				        nonisolated public struct api_Values {
				            public let session: Session
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built

				            public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                self.api = api
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.api = { _ in __safeDI_builder() }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_session session: Session, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values(session: session))
				        self.init(session: session, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_6813EB4016CA9038 {}
				}

				#if DEBUG
				extension Detail {
				    @frozen public enum SafeDIMockScope_Api {
				        case api(api_Values)

				        public struct api_Values {
				            public let session: Session
				        }
				    }

				    public static func mock(
				        session: Session,
				        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api
				    ) -> Detail {
				        let __safeDI_apiBuilder = apiBuilder
				        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(session: session)))
				        return Detail(session: session, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_mock_6037F8B4036DC8EF {}
				}
				#endif
				"""
			case .receivedOnlyIfAvailable:
				"""
				extension Detail {
				    @frozen nonisolated public enum SafeDIScope_Api {
				        case api(api_Values)

				        nonisolated public struct api_Values {
				            public let token: Token?
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built

				            public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                self.api = api
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.api = { _ in __safeDI_builder() }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_token token: Token?, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values(token: token))
				        self.init(token: token, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_9D054B4263DD2A80 {}
				}

				#if DEBUG
				extension Detail {
				    @frozen public enum SafeDIMockScope_Api {
				        case api(api_Values)

				        public struct api_Values {
				            public let token: Token?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api,
				        token: Token? = nil
				    ) -> Detail {
				        let __safeDI_apiBuilder = apiBuilder
				        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(token: token)))
				        return Detail(token: token, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_mock_C07D469C609A4C0A {}
				}
				#endif
				"""
			case .receivedLazilyInstantiated:
				"""
				extension Detail {
				    @frozen nonisolated public enum SafeDIScope_Api {
				        case api(api_Values)

				        nonisolated public struct api_Values {
				            public let session: LazilyInstantiated<Session>
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built

				            public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                self.api = api
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.api = { _ in __safeDI_builder() }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_session session: LazilyInstantiated<Session>, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values(session: session))
				        self.init(session: session, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_95C32B3D7625FDE8 {}
				}

				#if DEBUG
				extension Detail {
				    @frozen public enum SafeDIMockScope_Api {
				        case api(api_Values)

				        public struct api_Values {
				            public let session: LazilyInstantiated<Session>
				        }
				    }

				    public static func mock(
				        session: Session,
				        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api
				    ) -> Detail {
				        let __safeDI_apiBuilder = apiBuilder
				        let session_lazilyInstantiated = LazilyInstantiated<Session> { session }
				        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(session: session_lazilyInstantiated)))
				        return Detail(session: session_lazilyInstantiated, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_mock_33973195EAE76EEE {}
				}
				#endif
				"""
			case .receivedLazilyInstantiatedOnlyIfAvailable:
				"""
				extension Detail {
				    @frozen nonisolated public enum SafeDIScope_Api {
				        case api(api_Values)

				        nonisolated public struct api_Values {
				            public let session: LazilyInstantiated<Session>?
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let api: (api_Values) -> __safeDI_Built

				            public init(api: @escaping (api_Values) -> __safeDI_Built) {
				                self.api = api
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.api = { _ in __safeDI_builder() }
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public convenience init(__safeDI_session session: LazilyInstantiated<Session>?, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
				        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values(session: session))
				        self.init(session: session, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_A6723096D4089A26 {}
				}

				#if DEBUG
				extension Detail {
				    @frozen public enum SafeDIMockScope_Api {
				        case api(api_Values)

				        public struct api_Values {
				            public let session: LazilyInstantiated<Session>?
				        }
				    }

				    public static func mock(
				        apiBuilder: @escaping (Detail.SafeDIMockScope_Api) -> any Api,
				        session: Session? = nil
				    ) -> Detail {
				        let __safeDI_apiBuilder = apiBuilder
				        let session_lazilyInstantiated = session.map { instance in LazilyInstantiated<Session> { instance } }
				        let api: any Api = __safeDI_apiBuilder(.api(SafeDIMockScope_Api.api_Values(session: session_lazilyInstantiated)))
				        return Detail(session: session_lazilyInstantiated, api: api)
				    }
				}

				extension Detail {
				    public enum __safeDI_Detail_mock_BD7E909B7E325253 {}
				}
				#endif
				"""
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A public final class named `name` that generates a public mock and has an `internal` initializer, so another module
	/// calls its mock.
	private static func publicMockType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")
			.replacingOccurrences(of: "public init(", with: "init(")
	}

	/// `Root`, which generates a mock, with `declarations`.
	private static func mockedRoot(declarations: [String]) -> String {
		seamFixtureType(named: "Root", isFinalClass: true, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
	}

	/// A final class named `name` that fulfills `fulfilledType`.
	private static func fulfillingType(named name: String, fulfilling fulfilledType: String = "Api", declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// The names of the types of a graph whose root binds one label in two forms, which the test of rule 6 permutes.
	struct LabelInTwoFormsNames: Equatable {
		/// The public mock.
		var mocked = "Detail"
		/// The type in `Feature` that receives the first form and holds `api`.
		var first = "Child"
		/// The type in `Feature` that receives the second form and holds `gadget`.
		var second = "Other"
		/// The first form's type.
		var firstValue = "Token"
		/// The second form's type.
		var secondValue = "Badge"

		static let canonical = LabelInTwoFormsNames()

		var all: [String] {
			[mocked, first, second, firstValue, secondValue]
		}
	}

	/// `Feature`'s types where `mocked` forwards `id: Int` and receives `first`, which receives `id: <firstValue>` and holds
	/// the place `api`. Production builds `first` above `mocked`, where the forwarded `id` hides nothing; the mock promotes it
	/// to its root, beside the forwarded `id`, so `mock()` takes `id: Int` and names `id_<firstValue>` apart. `first` has an
	/// `internal` initializer, so a caller in another module cannot build it, and the mock builds it with its place.
	private static func labelInTwoFormsFeature(names: LabelInTwoFormsNames) -> [String] {
		[
			"public protocol Api {}",
			"public final class \(names.firstValue) {\n    public init() {}\n}",
			seamFixtureType(named: names.first, isFinalClass: true, declarations: ["@Received public let id: \(names.firstValue)", "@Instantiated public let api: any Api"])
				.replacingOccurrences(of: "public init(", with: "init("),
			publicMockType(named: names.mocked, declarations: ["@Forwarded public let id: Int", "@Received public let first: \(names.first)"]),
		]
	}

	/// `App`'s types for `labelInTwoFormsFeature(names:)`: `Live` reads the first form.
	private static func labelInTwoFormsApp(names: LabelInTwoFormsNames) -> [String] {
		[
			fulfillingType(named: "Live", declarations: ["@Received public let id: \(names.firstValue)"]),
			mockedRoot(declarations: ["@Instantiated public let detailBuilder: Instantiator<\(names.mocked)>"]),
		]
	}

	/// `Feature`'s types where `mocked` builds `first`, which receives `id: <firstValue>` and holds `api`, and `second`, which
	/// receives `id: <secondValue>` and holds `gadget`.
	private static func labelNamedApartFeature(names: LabelInTwoFormsNames) -> [String] {
		[
			"public protocol Api {}",
			"public protocol Gadget {}",
			"public final class \(names.firstValue) {\n    public init() {}\n}",
			"public final class \(names.secondValue) {\n    public init() {}\n}",
			seamFixtureType(named: names.first, isFinalClass: true, declarations: ["@Received public let id: \(names.firstValue)", "@Instantiated public let api: any Api"]),
			seamFixtureType(named: names.second, isFinalClass: true, declarations: ["@Received public let id: \(names.secondValue)", "@Instantiated public let gadget: any Gadget"]),
			publicMockType(named: names.mocked, declarations: ["@Instantiated public let first: \(names.first)", "@Instantiated public let second: \(names.second)"]),
		]
	}

	/// `App`'s types for `labelNamedApartFeature(names:)`: `Live` reads the first form and `LiveGadget` the second.
	private static func labelNamedApartApp(names: LabelInTwoFormsNames) -> [String] {
		[
			fulfillingType(named: "Live", declarations: ["@Received public let id: \(names.firstValue)"]),
			fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let id: \(names.secondValue)"]),
			mockedRoot(declarations: ["@Instantiated public let detailBuilder: Instantiator<\(names.mocked)>"]),
		]
	}

	/// The shape of the root level of `shape`'s graph with `names`, spelled with the canonical names: the enums of the public
	/// mock's file, and the lines of `mock()`'s body that bind a form of `id` again.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func rootLevelShape(of shape: LabelInTwoFormsShape, names: LabelInTwoFormsNames) async throws -> [String] {
		let feature = switch shape {
		case .forwardedBesidePromotedReceive:
			Self.labelInTwoFormsFeature(names: names)
		case .twoFormsNamedApart:
			Self.labelNamedApartFeature(names: names)
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature)],
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		var generated = try #require(output.modules["Feature"]?.generatedFiles["Feature.swift"])
		for (name, canonicalName) in zip(names.all, LabelInTwoFormsNames.canonical.all) where name != canonicalName {
			generated = generated.replacingOccurrences(of: "(?<![A-Za-z])\(name)(?![a-z])", with: canonicalName, options: .regularExpression)
		}
		let lines = generated.components(separatedBy: "\n")
		let enumLines = lines.drop { !$0.contains("@frozen public enum") }.prefix { !$0.contains("/// Overrides") && !$0.contains("public static func mock(") }
		return Array(enumLines) + lines.filter { $0.contains("let id: ") && $0.contains(" = id_") }.map { $0.trimmingCharacters(in: .whitespaces) }
	}

	private static func permutations(of elements: [String]) -> [[String]] {
		guard !elements.isEmpty else { return [[]] }
		return elements.indices.flatMap { index in
			var rest = elements
			let element = rest.remove(at: index)
			return permutations(of: rest).map { [element] + $0 }
		}
	}

	/// `Feature`, which declares the public mock, and `App`, which calls it: in another package unless `appPackageName` says.
	private static func modules(feature: [String], app: [String], appPackageName: String = "Other") -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: appPackageName, swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// Expects `Feature`'s generated file to be exactly `expectedFeature` after the file header, and `App`'s exactly
	/// `expectedApp` where given, both modules to compile, and `App`'s mock to build, for each of `probes`, the values the same
	/// graph's mock builds with no public mock, every `internal` initializer at `inlineInitializerAccess`, every fulfiller in
	/// `Feature` and the tree built inline, but for `exemptions`. The last of `app` is the mocked root; the others are
	/// fulfillers.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectPublicMock(
		feature: [String],
		app: [String],
		appPackageName: String = "Other",
		inlineInitializerAccess: String = "public",
		probes: [DifferentialValueProbe],
		exempting exemptions: [DifferentialValueDifference] = [],
		expectedFeature: String,
		expectedApp: String? = nil,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = Self.modules(feature: feature, app: app, appPackageName: appPackageName)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		for (moduleName, expectedWithFileNames) in [("Feature", Optional(expectedFeature)), ("App", expectedApp)] {
			guard let expectedWithFileNames, let moduleOutput = output.modules[moduleName] else { continue }
			// A `#sourceLocation` names a file of the fixture by its path, which `{<file name>}` stands for.
			let expected = expectedWithFileNames.contains("{Detail.swift}")
				? expectedWithFileNames.replacingOccurrences(of: "{Detail.swift}", with: moduleOutput.fixtures["Detail.swift"])
				: expectedWithFileNames
			let generated = moduleOutput.generatedFiles["\(moduleName).swift"]
			#expect(generated == generatedFileHeader + expected, sourceLocation: sourceLocation)
			if let generated, generated != generatedFileHeader + expected {
				Issue.record(Comment(rawValue: "=== \(moduleName).swift\n" + generated.dropFirst(generatedFileHeader.count)), sourceLocation: sourceLocation)
			}
		}
		guard compileVerificationIsEnabled, !probes.isEmpty else { return }
		let inlineModules = Self.modules(
			feature: (feature + app.dropLast()).map { file in
				file.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true").replacingOccurrences(of: "\n    init(", with: "\n    \(inlineInitializerAccess) init(")
			},
			app: app.suffix(1),
			appPackageName: appPackageName,
		)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: probes,
			exempting: exemptions,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// The plain types `Feature` declares: the hole's protocol and the types of the received values.
	private static let featureTypes = """
	public protocol Api {}

	public final class Session {
	    public init() {}
	}

	public final class Token {
	    public init() {}
	}
	"""

	/// `Feature`, where `Detail` is a seam with a public mock and an `internal` initializer, and `App`, another package,
	/// which calls `Detail.mock()`.
	private static func publicMockModules(_ rootValue: RootValue) -> [ModuleFixture] {
		let detail = seamFixtureType(named: "Detail", isFinalClass: true, declarations: [rootValue.detailDeclaration, "@Instantiated public let api: any Api"])
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateDependencyTree: true, generateMock: .public)\n")
			.replacingOccurrences(of: "public init(", with: "init(")
		return modules(feature: [featureTypes, detail], rootValue: rootValue)
	}

	/// The same graph with `Detail` a plain `@Instantiable` with a `public` initializer, so `Root.mock()` builds its tree
	/// inline.
	private static func inlineModules(_ rootValue: RootValue) -> [ModuleFixture] {
		modules(feature: [featureTypes, seamFixtureType(named: "Detail", isFinalClass: true, declarations: [rootValue.detailDeclaration, "@Instantiated public let api: any Api"])], rootValue: rootValue)
	}

	private static func modules(feature: [String], rootValue: RootValue) -> [ModuleFixture] {
		let live = seamFixtureType(named: "Live", isFinalClass: true, declarations: [rootValue.liveDeclaration], conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
		let root = seamFixtureType(named: "Root", isFinalClass: true, declarations: rootValue.rootDeclarations + ["@Instantiated public let detailBuilder: Instantiator<Detail>"])
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [live, root].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}
}
