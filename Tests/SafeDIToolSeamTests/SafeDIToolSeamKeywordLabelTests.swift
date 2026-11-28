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

/// A seam's builder struct declares one member per case of its level, named as the case, which is the label of the
/// property on the way to a hole: `Type` and `Protocol`, which Swift rejects as a member's name written bare, a keyword,
/// or a raw identifier. No such label is `self`: the `@Instantiable` macro requires an initializer parameter named as each
/// dependency, and a parameter named `self` hides the instance the initializer assigns to.
struct SafeDIToolSeamKeywordLabelTests: ~Copyable {
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
	mutating func generate_declaresBuilderStructMemberInBackticks_whenPlaceHeldInSendableWrapperIsLabeledTypeOrProtocol() async throws {
		// A place held in a `Sendable` wrapper is a member of the `@Sendable` enum's builder struct, which Swift rejects named
		// `Type` or `Protocol` bare.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(
			feature: [
				"public protocol Gadget: Sendable {}",
				seamFixtureType(named: "Host", isSeam: true, declarations: [
					"@Instantiated public let `Type`: SendableLazilyInstantiated<any Gadget>",
					"@Instantiated public let `Protocol`: SendableLazilyInstantiated<any Gadget>",
				]),
			],
			app: [
				seamFixtureType(named: "LiveGadget", isFinalClass: true, declarations: [], conformances: ", Gadget")
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Gadget.self])\n"),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
			],
		), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_GadgetSendableCarrier<__safeDI_Built>: Sendable {
		        public let `Type`: @Sendable () -> __safeDI_Built
		        public let `Protocol`: @Sendable () -> __safeDI_Built

		        public init(Type: @escaping @Sendable () -> __safeDI_Built, Protocol: @escaping @Sendable () -> __safeDI_Built) {
		            self.Type = Type
		            self.Protocol = Protocol
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(gadgetSendableBuilder: @escaping @Sendable () -> any Gadget) {
		        @Sendable nonisolated func __safeDI_noScope_Host_SafeDISendableCarrierScope_Gadget<__safeDI_Built>(_ __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) -> Host.__safeDI_GadgetSendableCarrier<__safeDI_Built> {
		            .init(Type: { __safeDI_builder() }, Protocol: { __safeDI_builder() })
		        }
		        self.init(__safeDI_gadgetSendableBuilder: __safeDI_noScope_Host_SafeDISendableCarrierScope_Gadget(gadgetSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_gadgetSendableBuilder: __safeDI_GadgetSendableCarrier<any Gadget>) {
		        @inline(never) @Sendable nonisolated func __safeDI_Type() -> any Gadget {
		            __safeDI_gadgetSendableBuilder.Type()
		        }
		        let Type = SendableLazilyInstantiated<any Gadget>(__safeDI_Type)
		        @inline(never) @Sendable nonisolated func __safeDI_Protocol() -> any Gadget {
		            __safeDI_gadgetSendableBuilder.Protocol()
		        }
		        let Protocol = SendableLazilyInstantiated<any Gadget>(__safeDI_Protocol)
		        self.init(Type: Type, Protocol: Protocol)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_0B387B46EEF2D9C4 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_Type() -> any Gadget {
		            return __safeDI_fillBody_9A592AE130AF0FC8()
		        }
		        @Sendable nonisolated func __safeDI_fillBody_9A592AE130AF0FC8() -> any Gadget {
		            @Sendable nonisolated func __safeDI_Type() -> LiveGadget {
		                LiveGadget()
		            }
		            return __safeDI_Type()
		        }
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_Protocol() -> any Gadget {
		            return __safeDI_fillBody_0FBEC6A0C3EC7A7C()
		        }
		        @Sendable nonisolated func __safeDI_fillBody_0FBEC6A0C3EC7A7C() -> any Gadget {
		            @Sendable nonisolated func __safeDI_Protocol() -> LiveGadget {
		                LiveGadget()
		            }
		            return __safeDI_Protocol()
		        }
		        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.__safeDI_GadgetSendableCarrier<any Gadget> {
		            .init(Type: { __safeDI_gadgetSendableBuilder_Host_Type() }, Protocol: { __safeDI_gadgetSendableBuilder_Host_Protocol() })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_0B387B46EEF2D9C4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresBuilderStructMemberInBackticks_whenSeamsPlaceIsLabeledType() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(
			feature: ["public protocol Api {}", seamFixtureType(named: "F", isSeam: true, declarations: ["@Instantiated public let `Type`: any Api"])],
			app: [Self.liveApi(declarations: []), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let f: F"])],
		), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension F {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let `Type`: () -> __safeDI_Built

		        public init(Type: @escaping () -> __safeDI_Built) {
		            self.Type = Type
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        @Sendable nonisolated func __safeDI_noScope_F_SafeDICarrierScope_Api<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> F.__safeDI_ApiCarrier<__safeDI_Built> {
		            .init(Type: { __safeDI_builder() })
		        }
		        self.init(__safeDI_apiBuilder: __safeDI_noScope_F_SafeDICarrierScope_Api(apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let Type: any Api = __safeDI_apiBuilder.Type()
		        self.init(Type: Type)
		    }
		}

		extension F {
		    public enum __safeDI_F_85E735945FC24B03 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_F() -> F.__safeDI_ApiCarrier<any Api> {
		            .init(Type: {
		                let Type: any Api = LiveApi()
		                return Type
		            })
		        }
		        func __safeDI_f() -> F {
		            _ = F.__safeDI_F_85E735945FC24B03.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F(__safeDI_apiBuilder: __safeDI_apiBuilder_F())
		        }
		        let f: F = __safeDI_f()
		        self.init(f: f)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsBuilderStructMembersCompilably_whenLevelsAndPlacesHaveKeywordLabels() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.keywordLevelsAndPlaces, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let `Type`: (Name) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(Type: @escaping (Name) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.Type = Type
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let `Self`: () -> __safeDI_Built
		        public let `init`: (any Api) -> __safeDI_Built
		        public let `my leaf`: (any Api, any Api) -> __safeDI_Built

		        public init(`Self`: @escaping () -> __safeDI_Built, `init`: @escaping (any Api) -> __safeDI_Built, `my leaf`: @escaping (any Api, any Api) -> __safeDI_Built) {
		            self.`Self` = `Self`
		            self.`init` = `init`
		            self.`my leaf` = `my leaf`
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_GizmoCarrier_Gadget<__safeDI_Built> {
		        public let `Protocol`: () -> __safeDI_Built

		        public init(Protocol: @escaping () -> __safeDI_Built) {
		            self.Protocol = Protocol
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_GizmoSendableCarrier<__safeDI_Built>: Sendable {
		        public let `Protocol`: @Sendable () -> __safeDI_GizmoCarrier_Gadget<__safeDI_Built>

		        public init(Protocol: @escaping @Sendable () -> __safeDI_GizmoCarrier_Gadget<__safeDI_Built>) {
		            self.Protocol = Protocol
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api, gizmoSendableBuilder: @escaping @Sendable () -> any Gizmo) {
		        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier<__safeDI_Built> {
		            .init(Type: { _ in __safeDI_noScope_Home_SafeDICarrierScope_Api_Detail_Scope(__safeDI_builder) })
		        }
		        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api_Detail_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier_Detail<__safeDI_Built> {
		            .init(Self: { __safeDI_builder() }, init: { _ in __safeDI_builder() }, `my leaf`: { _, _ in __safeDI_builder() })
		        }
		        @Sendable nonisolated func __safeDI_noScope_Home_SafeDISendableCarrierScope_Gizmo<__safeDI_Built>(_ __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) -> Home.__safeDI_GizmoSendableCarrier<__safeDI_Built> {
		            .init(Protocol: { __safeDI_noScope_Home_SafeDICarrierScope_Gizmo_Gadget_Scope(__safeDI_builder) })
		        }
		        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Gizmo_Gadget_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_GizmoCarrier_Gadget<__safeDI_Built> {
		            .init(Protocol: { __safeDI_builder() })
		        }
		        self.init(__safeDI_apiBuilder: __safeDI_noScope_Home_SafeDICarrierScope_Api(apiBuilder), __safeDI_gizmoSendableBuilder: __safeDI_noScope_Home_SafeDISendableCarrierScope_Gizmo(gizmoSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_gizmoSendableBuilder: __safeDI_GizmoSendableCarrier<any Gizmo>) {
		        let `default` = Name()
		        let __safeDI_apiBuilder_Type = __safeDI_apiBuilder.Type(`default`)
		        @inline(never) func __safeDI_Type() -> Detail {
		            let `Self`: any Api = __safeDI_apiBuilder_Type.`Self`()
		            let `init`: any Api = __safeDI_apiBuilder_Type.`init`(`Self`)
		            let `my leaf`: any Api = __safeDI_apiBuilder_Type.`my leaf`(`Self`, `init`)
		            return Detail(Self: `Self`, init: `init`, `my leaf`: `my leaf`)
		        }
		        let Type = Instantiator<Detail>(__safeDI_Type)
		        @inline(never) @Sendable nonisolated func __safeDI_Protocol() -> Gadget {
		            let __safeDI_gizmoSendableBuilder_Protocol = __safeDI_gizmoSendableBuilder.Protocol()
		            let Protocol: any Gizmo = __safeDI_gizmoSendableBuilder_Protocol.Protocol()
		            return Gadget(Protocol: Protocol)
		        }
		        let Protocol = SendableInstantiator<Gadget>(__safeDI_Protocol)
		        self.init(default: `default`, Type: Type, Protocol: Protocol)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_A5FBB8B80D68C88B {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(Type: { values_default in __safeDI_apiBuilder_Home_Detail_Scope(default: values_default) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(default: Name) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(
		                Self: {
		                    let `Self`: any Api = LiveApi(default: `default`)
		                    return `Self`
		                },
		                init: { scope_Self in
		                    let `init`: any Api = LiveApi(default: `default`)
		                    return `init`
		                },
		                `my leaf`: { scope_Self, scope_init in
		                    let `my leaf`: any Api = LiveApi(default: `default`)
		                    return `my leaf`
		                }
		            )
		        }
		        @Sendable nonisolated func __safeDI_gizmoSendableBuilder_Home() -> Home.__safeDI_GizmoSendableCarrier<any Gizmo> {
		            .init(Protocol: { __safeDI_gizmoBuilder_Home_Gadget_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_gizmoBuilder_Home_Gadget_Scope() -> Home.__safeDI_GizmoCarrier_Gadget<any Gizmo> {
		            .init(Protocol: {
		                let Protocol: any Gizmo = LiveGizmo()
		                return Protocol
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_A5FBB8B80D68C88B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_gizmoSendableBuilder: __safeDI_gizmoSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsBuilderStructMembersCompilably_whenSeamOfAnotherModulePassesUpKeywordLabeledPlace() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let `Type`: any Api", "@Instantiated public let `default`: any Api"]),
			]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let `Protocol`: Inner"]),
			].map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				Self.liveApi(declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
			].map { "import Core\nimport Feature\n\n" + $0 }, dependencies: ["Core", "Feature"]),
		], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let `Type`: () -> __safeDI_Built
		        public let `default`: (any Api) -> __safeDI_Built

		        public init(Type: @escaping () -> __safeDI_Built, `default`: @escaping (any Api) -> __safeDI_Built) {
		            self.Type = Type
		            self.`default` = `default`
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let Type: any Api = __safeDI_apiBuilder.Type()
		        let `default`: any Api = __safeDI_apiBuilder.`default`(Type)
		        self.init(Type: Type, default: `default`)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_A528D5381761650B {}
		}
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		extension Outer {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let `Protocol`: Inner.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(Protocol: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.Protocol = Protocol
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        @inline(never) func __safeDI_Protocol() -> Inner {
		            _ = Inner.__safeDI_Inner_A528D5381761650B.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_apiBuilder: __safeDI_apiBuilder.Protocol)
		        }
		        let Protocol: Inner = __safeDI_Protocol()
		        self.init(Protocol: Protocol)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_450510F51ADD6E2D {}
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
		    public init() {
		        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
		            .init(Protocol: __safeDI_apiBuilder_Inner())
		        }
		        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		            .init(
		                Type: {
		                    let Type: any Api = LiveApi()
		                    return Type
		                },
		                default: { scope_Type in
		                    let `default`: any Api = LiveApi()
		                    return `default`
		                }
		            )
		        }
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_450510F51ADD6E2D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	// MARK: Fixtures

	/// `Home`, a seam, binds `default`, then builds `Detail` through `Type` and `Gadget` through `Protocol`, whose places of
	/// `Api` and `Gizmo`, which only `App` fulfills, are labeled as keywords and a raw identifier; `LiveApi` reads `default`.
	private static let keywordLevelsAndPlaces = featureAndApp(
		feature: [
			"public protocol Api {}\npublic protocol Gizmo: Sendable {}",
			seamFixtureType(named: "Name", declarations: []),
			seamFixtureType(named: "Detail", declarations: [
				"@Instantiated public let `Self`: any Api",
				"@Instantiated public let `init`: any Api",
				"@Instantiated public let `my leaf`: any Api",
			]),
			seamFixtureType(named: "Gadget", declarations: ["@Instantiated public let `Protocol`: any Gizmo"], conformances: ", Sendable"),
			seamFixtureType(named: "Home", isSeam: true, declarations: [
				"@Instantiated public let `default`: Name",
				"@Instantiated public let `Type`: Instantiator<Detail>",
				"@Instantiated public let `Protocol`: SendableInstantiator<Gadget>",
			]),
		],
		app: [
			Self.liveApi(declarations: ["@Received public let `default`: Name"]),
			seamFixtureType(named: "LiveGizmo", isFinalClass: true, declarations: [], conformances: ", Gizmo")
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Gizmo.self])\n"),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
		],
	)

	// MARK: Private

	private var filesToDelete: [URL]

	/// Expects every module of `output` to have compiled, and its generated code to have drawn no warning, where compile
	/// verification is enabled.
	private static func expectCompiles(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		for module in compilation.modules {
			#expect(module.result.exitCode == 0, "\(module.moduleName): \(module.result.stderr)", sourceLocation: sourceLocation)
			#expect(module.generatedCodeWarnings.isEmpty, "\(module.moduleName): \(module.generatedCodeWarnings)", sourceLocation: sourceLocation)
		}
	}

	/// `Feature`, which declares `feature`'s types and generates readable initializers, and `App`, which declares `app`'s.
	private static func featureAndApp(feature: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `LiveApi`, a final class that fulfills `Api` and declares `declarations`.
	private static func liveApi(declarations: [String]) -> String {
		seamFixtureType(named: "LiveApi", isFinalClass: true, declarations: declarations, conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
	}
}
