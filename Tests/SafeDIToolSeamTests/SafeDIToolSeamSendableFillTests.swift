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

/// The comment a call of `seam`, a seam of `module`, carries under `.moduleInfo`.
private func seamCallComment(seam: String, module: String) -> String {
	MultiModuleIntegration.moduleInfo.seamCallComment(type: seam, declaringModule: module)
}

/// A seam that fills another seam's hole, with a place, or a call of a further seam, inside the fill. When the fill is a
/// `@Sendable` function, what it holds is inside a `@Sendable` function as it is inside a `@Sendable` builder function:
/// a place there is a case of the `@Sendable` enum, and a builder a call inside it passes up is `@Sendable`.
struct SafeDIToolSeamSendableFillTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A place and an inner call inside a fill

	/// How `Feature` presents the hole `Middle` fills, which decides which functions of the fill are `@Sendable`.
	enum FillRoute: CaseIterable, CustomTestStringConvertible {
		/// `Host` calls `Inner`, which builds `widget` in plain code: the fill is plain.
		case plain
		/// `Host` calls `Shell`, which builds `Inner` in a `SendableInstantiator`: `Shell` takes the builder `@Sendable`.
		case sendableByRoute
		/// `Host` calls `Inner`, which builds `widget` in a `SendableInstantiator`: the fill is `@Sendable`.
		case placeInsideSendableFunction
		/// Both: the fill is `@Sendable`.
		case placeInsideSendableFunctionTakenSendable

		var testDescription: String {
			switch self {
			case .plain:
				"plain"
			case .sendableByRoute:
				"sendableByRoute"
			case .placeInsideSendableFunction:
				"placeInsideSendableFunction"
			case .placeInsideSendableFunctionTakenSendable:
				"placeInsideSendableFunctionTakenSendable"
			}
		}

		var isInsideSendableFunction: Bool {
			switch self {
			case .plain, .sendableByRoute:
				false
			case .placeInsideSendableFunction, .placeInsideSendableFunctionTakenSendable:
				true
			}
		}

		var isThroughShell: Bool {
			switch self {
			case .plain, .placeInsideSendableFunction:
				false
			case .sendableByRoute, .placeInsideSendableFunctionTakenSendable:
				true
			}
		}

		var featureTypes: [String] {
			let leaves = [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Clock", declarations: [], conformances: ", Sendable"),
			]
			let inner = isInsideSendableFunction
				? [
					seamFixtureType(named: "Panel", declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let clock: Clock", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
					seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let panelBuilder: SendableInstantiator<Panel>"], conformances: ", Sendable"),
				]
				: [seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let widget: any Widget"], conformances: ", Sendable")]
			let shell = isThroughShell ? [seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>"], conformances: ", Sendable")] : []
			return leaves + inner + shell
		}

		var hostDeclaration: String {
			isThroughShell ? "@Instantiated let shell: Shell" : "@Instantiated let inner: Inner"
		}
	}

	/// The types of a fixture, in the modules that declare them.
	private struct ThreeModules {
		let feature: [String]
		let middle: [String]
		let app: [String]
		let root: String

		/// `Feature` (package `Shop`), `Middle` (package `Mid`), which depends on it, and `App` (package `Other`), which
		/// depends on both.
		var modules: [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (app + [root]).map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			]
		}

		/// The same graph with every declaration but the root in one module, so no seam has a hole.
		var visibleModules: [ModuleFixture] {
			SafeDIToolSeamBuilderParameterTests.modules(feature: feature + middle + app, app: [root])
		}
	}

	private static let gadget = "public protocol Gadget: Sendable {}"
	private static let session = seamFixtureType(named: "Session", declarations: [], conformances: ", Sendable")
	private static let gear = [
		"public protocol Gear: Sendable {}",
		seamFixtureType(named: "Part", isSeam: true, declarations: ["@Instantiated let gear: any Gear"], conformances: ", Sendable"),
	]
	private static let defaultGadget = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let session: Session", "@Received let analytics: Analytics"])
	private static let defaultGear = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGear", fulfilling: "Gear", declarations: [])
	/// A `DefaultGadget` that reads only the `session` its seam receives, which a place held in a `Sendable` wrapper reads from
	/// the caller's scope.
	private static let defaultGadgetReadingSession = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let session: Session"])
	private static let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"])
	/// A root that instantiates the `session` its `Host` receives, which a fill inside a `@Sendable` function reads from the
	/// root's own scope.
	private static let rootWithSession = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let session: Session", "@Instantiated let host: Host"])

	/// `Feature` declares `route`'s types; `Middle`'s `Host` fills `Widget`'s hole with `DefaultWidget`, whose declarations
	/// are `widgetDeclarations`; and `App` fills what `Host` passes up.
	private static func fixture(
		route: FillRoute,
		featureTypes: [String] = [],
		middleTypes: [String] = [],
		widgetDeclarations: [String] = ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget", "@Instantiated let part: Part"],
		appTypes: [String] = [defaultGadget, defaultGear],
		root: String = rootWithSession,
		widgetConformances: String = "Instantiable, Widget",
	) -> ThreeModules {
		ThreeModules(
			feature: route.featureTypes + gear + featureTypes,
			middle: [gadget, session] + middleTypes + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: widgetDeclarations)
					.replacingOccurrences(of: "Instantiable, Widget", with: widgetConformances),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Received let session: Session", route.hostDeclaration]),
			],
			app: appTypes,
			root: root,
		)
	}

	@Test(arguments: FillRoute.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_treatsFillAsTheFunctionItIs_whenFillHoldsPlaceAndInnerCall(route: FillRoute) async throws {
		// `DefaultWidget` fills `Widget`'s hole in `Host`'s tree, and builds `gadget`, a place of `Host`, and calls `Part`,
		// whose builder `Host` passes up. Each `@Sendable` function of the fill starts a stage of `gadgetBuilder`, called
		// just before it, and `gearBuilder` is `@Sendable` when the call is in one.
		let fixture = Self.fixture(route: route)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		switch route {
		case .plain:
			expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
				"Middle.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Host {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public struct inner_widgetBuilder_Values {
				            public let session: Session
				        }

				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct gadget_Values {
				                public let part: Part
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner_widgetBuilder: (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_widgetBuilder: @escaping (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_widgetBuilder = inner_widgetBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(inner_widgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    nonisolated public enum SafeDIScope_Gear {
				        nonisolated public struct inner_widgetBuilder_Values {
				            public let session: Session
				        }

				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct part_Values: Sendable {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let part: (part_Values) -> Part.__safeDI_GearCarrier<__safeDI_Built>

				                public init(part: @escaping (part_Values) -> Part.__safeDI_GearCarrier<__safeDI_Built>) {
				                    self.part = part
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(part: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner_widgetBuilder: (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_widgetBuilder: @escaping (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_widgetBuilder = inner_widgetBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(inner_widgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_gearBuilder: SafeDIScope_Gear.__safeDI_Builder<any Gear>) {
				        let __safeDI_gadgetBuilder_inner_widgetBuilder = __safeDI_gadgetBuilder.inner_widgetBuilder(SafeDIScope_Gadget.inner_widgetBuilder_Values(session: session))
				        let __safeDI_gearBuilder_inner_widgetBuilder = __safeDI_gearBuilder.inner_widgetBuilder(SafeDIScope_Gear.inner_widgetBuilder_Values(session: session))
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_EA4DE2878D50CCB8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_inner_widgetBuilder_gadgetBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>, __safeDI_inner_widgetBuilder_gearBuilder: SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>) -> any Widget {
				                let analytics = scope_analytics
				                func __safeDI_widget() -> DefaultWidget {
				                    func __safeDI_part() -> Part {
				                        _ = Part.__safeDI_Part_6EBD3668CBE30F42.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				                        return Part(__safeDI_gearBuilder: __safeDI_inner_widgetBuilder_gearBuilder.part(SafeDIScope_Gear.DefaultWidget_Scope.part_Values()))
				                    }
				                    let part: Part = __safeDI_part()
				                    let gadget: any Gadget = __safeDI_inner_widgetBuilder_gadgetBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(part: part))
				                    return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            func __safeDI_widgetBuilder_Inner(up_inner_widgetBuilder_gadgetBuilder: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>, up_inner_widgetBuilder_gearBuilder: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
				                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_inner_widgetBuilder_gadgetBuilder: up_inner_widgetBuilder_gadgetBuilder.widget(scope_analytics), __safeDI_inner_widgetBuilder_gearBuilder: up_inner_widgetBuilder_gearBuilder.widget(scope_analytics)) })
				            }
				            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner(up_inner_widgetBuilder_gadgetBuilder: __safeDI_gadgetBuilder_inner_widgetBuilder, up_inner_widgetBuilder_gearBuilder: __safeDI_gearBuilder_inner_widgetBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_D9CDB96C08F7A067 {}
				}
				""",
			])
		case .sendableByRoute:
			expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
				"Middle.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Host {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct gadget_Values {
				                public let part: Part
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    nonisolated public enum SafeDIScope_Gear {
				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct part_Values: Sendable {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let part: (part_Values) -> Part.__safeDI_GearCarrier<__safeDI_Built>

				                public init(part: @escaping (part_Values) -> Part.__safeDI_GearCarrier<__safeDI_Built>) {
				                    self.part = part
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(part: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableScope_Gear {
				        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_gearSendableBuilder: SafeDISendableScope_Gear.__safeDI_Builder<any Gear>) {
				        func __safeDI_shell() -> Shell {
				            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
				            let __safeDI_gearSendableBuilder_shell_widgetSendableBuilder = __safeDI_gearSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gear.shell_widgetSendableBuilder_Values())
				            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder_gadgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>, __safeDI_shell_widgetSendableBuilder_gearSendableBuilder: SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>) -> any Widget {
				                let analytics = scope_analytics
				                func __safeDI_widget() -> DefaultWidget {
				                    func __safeDI_part() -> Part {
				                        _ = Part.__safeDI_Part_6EBD3668CBE30F42.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				                        return Part(__safeDI_gearBuilder: __safeDI_shell_widgetSendableBuilder_gearSendableBuilder.part(SafeDIScope_Gear.DefaultWidget_Scope.part_Values()))
				                    }
				                    let part: Part = __safeDI_part()
				                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder_gadgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(part: part))
				                    return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up_shell_widgetSendableBuilder_gadgetSendableBuilder: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>, up_shell_widgetSendableBuilder_gearSendableBuilder: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
				                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up_shell_widgetSendableBuilder_gadgetSendableBuilder: up_shell_widgetSendableBuilder_gadgetSendableBuilder.innerBuilder(), up_shell_widgetSendableBuilder_gearSendableBuilder: up_shell_widgetSendableBuilder_gearSendableBuilder.innerBuilder()) })
				            }
				            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up_shell_widgetSendableBuilder_gadgetSendableBuilder: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>, up_shell_widgetSendableBuilder_gearSendableBuilder: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
				                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder_gadgetSendableBuilder: up_shell_widgetSendableBuilder_gadgetSendableBuilder.widget(scope_analytics), __safeDI_shell_widgetSendableBuilder_gearSendableBuilder: up_shell_widgetSendableBuilder_gearSendableBuilder.widget(scope_analytics)) })
				            }
				            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up_shell_widgetSendableBuilder_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder, up_shell_widgetSendableBuilder_gearSendableBuilder: __safeDI_gearSendableBuilder_shell_widgetSendableBuilder))
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_168FE7DA17F54398 {}
				}
				""",
			])
		case .placeInsideSendableFunction:
			expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
				"Middle.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Host {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct gadget_Values {
				                public let part: Part
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct inner_widgetSendableBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let inner_widgetSendableBuilder: @Sendable (inner_widgetSendableBuilder_Values) -> Inner.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_widgetSendableBuilder: @escaping @Sendable (inner_widgetSendableBuilder_Values) -> Inner.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_widgetSendableBuilder = inner_widgetSendableBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(inner_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    nonisolated public enum SafeDIScope_Gear {
				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct part_Values: Sendable {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let part: (part_Values) -> Part.__safeDI_GearCarrier<__safeDI_Built>

				                public init(part: @escaping (part_Values) -> Part.__safeDI_GearCarrier<__safeDI_Built>) {
				                    self.part = part
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(part: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableScope_Gear {
				        nonisolated public struct inner_widgetSendableBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let inner_widgetSendableBuilder: @Sendable (inner_widgetSendableBuilder_Values) -> Inner.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_widgetSendableBuilder: @escaping @Sendable (inner_widgetSendableBuilder_Values) -> Inner.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_widgetSendableBuilder = inner_widgetSendableBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(inner_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_gearSendableBuilder: SafeDISendableScope_Gear.__safeDI_Builder<any Gear>) {
				        func __safeDI_inner() -> Inner {
				            let __safeDI_gadgetSendableBuilder_inner_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.inner_widgetSendableBuilder(SafeDISendableScope_Gadget.inner_widgetSendableBuilder_Values())
				            let __safeDI_gearSendableBuilder_inner_widgetSendableBuilder = __safeDI_gearSendableBuilder.inner_widgetSendableBuilder(SafeDISendableScope_Gear.inner_widgetSendableBuilder_Values())
				            _ = Inner.__safeDI_Inner_1A9C10F553C3A46C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Inner_Panel_Scope_widget(_ scope_analytics: Analytics, _ scope_clock: Clock, __safeDI_inner_widgetSendableBuilder_gadgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>, __safeDI_inner_widgetSendableBuilder_gearSendableBuilder: SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>) -> any Widget {
				                let analytics = scope_analytics
				                func __safeDI_widget() -> DefaultWidget {
				                    func __safeDI_part() -> Part {
				                        _ = Part.__safeDI_Part_6EBD3668CBE30F42.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				                        return Part(__safeDI_gearBuilder: __safeDI_inner_widgetSendableBuilder_gearSendableBuilder.part(SafeDIScope_Gear.DefaultWidget_Scope.part_Values()))
				                    }
				                    let part: Part = __safeDI_part()
				                    let gadget: any Gadget = __safeDI_inner_widgetSendableBuilder_gadgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(part: part))
				                    return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Inner(up_inner_widgetSendableBuilder_gadgetSendableBuilder: Inner.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>, up_inner_widgetSendableBuilder_gearSendableBuilder: Inner.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>>) -> Inner.__safeDI_WidgetSendableCarrier<any Widget> {
				                .init(panelBuilder: { __safeDI_widgetBuilder_Inner_Panel_Scope(up_inner_widgetSendableBuilder_gadgetSendableBuilder: up_inner_widgetSendableBuilder_gadgetSendableBuilder.panelBuilder(), up_inner_widgetSendableBuilder_gearSendableBuilder: up_inner_widgetSendableBuilder_gearSendableBuilder.panelBuilder()) })
				            }
				            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_Panel_Scope(up_inner_widgetSendableBuilder_gadgetSendableBuilder: Inner.__safeDI_WidgetCarrier_Panel<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>, up_inner_widgetSendableBuilder_gearSendableBuilder: Inner.__safeDI_WidgetCarrier_Panel<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>>) -> Inner.__safeDI_WidgetCarrier_Panel<any Widget> {
				                .init(widget: { scope_analytics, scope_clock in __safeDI_widgetSendableBuilder_Inner_Panel_Scope_widget(scope_analytics, scope_clock, __safeDI_inner_widgetSendableBuilder_gadgetSendableBuilder: up_inner_widgetSendableBuilder_gadgetSendableBuilder.widget(scope_analytics, scope_clock), __safeDI_inner_widgetSendableBuilder_gearSendableBuilder: up_inner_widgetSendableBuilder_gearSendableBuilder.widget(scope_analytics, scope_clock)) })
				            }
				            return Inner(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Inner(up_inner_widgetSendableBuilder_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_inner_widgetSendableBuilder, up_inner_widgetSendableBuilder_gearSendableBuilder: __safeDI_gearSendableBuilder_inner_widgetSendableBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_E77340B7874B2ED7 {}
				}
				""",
			])
		case .placeInsideSendableFunctionTakenSendable:
			expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
				"Middle.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Host {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct gadget_Values {
				                public let part: Part
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    nonisolated public enum SafeDIScope_Gear {
				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct part_Values: Sendable {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let part: (part_Values) -> Part.__safeDI_GearCarrier<__safeDI_Built>

				                public init(part: @escaping (part_Values) -> Part.__safeDI_GearCarrier<__safeDI_Built>) {
				                    self.part = part
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(part: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableScope_Gear {
				        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_gearSendableBuilder: SafeDISendableScope_Gear.__safeDI_Builder<any Gear>) {
				        func __safeDI_shell() -> Shell {
				            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
				            let __safeDI_gearSendableBuilder_shell_widgetSendableBuilder = __safeDI_gearSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gear.shell_widgetSendableBuilder_Values())
				            _ = Shell.__safeDI_Shell_C22D2AA049360CFC.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Inner_Panel_Scope_widget(_ scope_analytics: Analytics, _ scope_clock: Clock, __safeDI_shell_widgetSendableBuilder_gadgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>, __safeDI_shell_widgetSendableBuilder_gearSendableBuilder: SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>) -> any Widget {
				                let analytics = scope_analytics
				                func __safeDI_widget() -> DefaultWidget {
				                    func __safeDI_part() -> Part {
				                        _ = Part.__safeDI_Part_6EBD3668CBE30F42.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				                        return Part(__safeDI_gearBuilder: __safeDI_shell_widgetSendableBuilder_gearSendableBuilder.part(SafeDIScope_Gear.DefaultWidget_Scope.part_Values()))
				                    }
				                    let part: Part = __safeDI_part()
				                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder_gadgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(part: part))
				                    return DefaultWidget(analytics: analytics, gadget: gadget, part: part)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up_shell_widgetSendableBuilder_gadgetSendableBuilder: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>, up_shell_widgetSendableBuilder_gearSendableBuilder: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
				                .init(innerBuilder_Sendable: __safeDI_widgetSendableBuilder_Inner(up_shell_widgetSendableBuilder_gadgetSendableBuilder: up_shell_widgetSendableBuilder_gadgetSendableBuilder.innerBuilder_Sendable, up_shell_widgetSendableBuilder_gearSendableBuilder: up_shell_widgetSendableBuilder_gearSendableBuilder.innerBuilder_Sendable))
				            }
				            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Inner(up_shell_widgetSendableBuilder_gadgetSendableBuilder: Inner.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>, up_shell_widgetSendableBuilder_gearSendableBuilder: Inner.__safeDI_WidgetSendableCarrier<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>>) -> Inner.__safeDI_WidgetSendableCarrier<any Widget> {
				                .init(panelBuilder: { __safeDI_widgetBuilder_Inner_Panel_Scope(up_shell_widgetSendableBuilder_gadgetSendableBuilder: up_shell_widgetSendableBuilder_gadgetSendableBuilder.panelBuilder(), up_shell_widgetSendableBuilder_gearSendableBuilder: up_shell_widgetSendableBuilder_gearSendableBuilder.panelBuilder()) })
				            }
				            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_Panel_Scope(up_shell_widgetSendableBuilder_gadgetSendableBuilder: Inner.__safeDI_WidgetCarrier_Panel<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>, up_shell_widgetSendableBuilder_gearSendableBuilder: Inner.__safeDI_WidgetCarrier_Panel<SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>>) -> Inner.__safeDI_WidgetCarrier_Panel<any Widget> {
				                .init(widget: { scope_analytics, scope_clock in __safeDI_widgetSendableBuilder_Inner_Panel_Scope_widget(scope_analytics, scope_clock, __safeDI_shell_widgetSendableBuilder_gadgetSendableBuilder: up_shell_widgetSendableBuilder_gadgetSendableBuilder.widget(scope_analytics, scope_clock), __safeDI_shell_widgetSendableBuilder_gearSendableBuilder: up_shell_widgetSendableBuilder_gearSendableBuilder.widget(scope_analytics, scope_clock)) })
				            }
				            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up_shell_widgetSendableBuilder_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder, up_shell_widgetSendableBuilder_gearSendableBuilder: __safeDI_gearSendableBuilder_shell_widgetSendableBuilder))
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_A6D9AB9C1D4AEA00 {}
				}
				""",
			])
		}
		switch route {
		case .plain:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public init() {
				        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
				            .init(inner_widgetBuilder: { values in __safeDI_gadgetBuilder_Host_Inner(session: values.session) })
				        }
				        func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: Analytics, session: Session) -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
				            .init(gadget: { _ in
				                let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                return gadget
				            })
				        }
				        func __safeDI_gearBuilder_Host() -> Host.SafeDIScope_Gear.__safeDI_Builder<any Gear> {
				            .init(inner_widgetBuilder: { _ in __safeDI_gearBuilder_Host_Inner() })
				        }
				        func __safeDI_gearBuilder_Host_DefaultWidget_Scope() -> Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear> {
				            .init(part: { _ in __safeDI_gearBuilder_Part() })
				        }
				        func __safeDI_gearBuilder_Part() -> Part.__safeDI_GearCarrier<any Gear> {
				            .init(gear: {
				                let gear: any Gear = DefaultGear()
				                return gear
				            })
				        }
				        func __safeDI_gadgetBuilder_Host_Inner(session: Session) -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				            .init(widget: { values_analytics in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: values_analytics, session: session) })
				        }
				        func __safeDI_gearBuilder_Host_Inner() -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>> {
				            .init(widget: { values_analytics in __safeDI_gearBuilder_Host_DefaultWidget_Scope() })
				        }
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_D9CDB96C08F7A067.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Host(__safeDI_session: session, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host(), __safeDI_gearBuilder: __safeDI_gearBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				""",
			])
		case .sendableByRoute:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public init() {
				        @Sendable nonisolated func __safeDI_gearSendableBuilder_Host() -> Host.SafeDISendableScope_Gear.__safeDI_Builder<any Gear> {
				            .init(shell_widgetSendableBuilder: { _ in __safeDI_gearBuilder_Host_Shell() })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_DefaultWidget_Scope() -> Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear> {
				            .init(part: { _ in __safeDI_gearBuilder_Part() })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Part() -> Part.__safeDI_GearCarrier<any Gear> {
				            .init(gear: {
				                let gear: any Gear = DefaultGear()
				                return gear
				            })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_Shell() -> Shell.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>> {
				            .init(innerBuilder: { __safeDI_gearBuilder_Host_Inner() })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_Inner() -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>> {
				            .init(widget: { values_analytics in __safeDI_gearBuilder_Host_DefaultWidget_Scope() })
				        }
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_168FE7DA17F54398.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(shell_widgetSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_Shell() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: Analytics) -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
				                .init(gadget: { _ in
				                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                    return gadget
				                })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Shell() -> Shell.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				                .init(innerBuilder: { __safeDI_gadgetBuilder_Host_Inner() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner() -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				                .init(widget: { values_analytics in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: values_analytics) })
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host(), __safeDI_gearSendableBuilder: __safeDI_gearSendableBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				""",
			])
		case .placeInsideSendableFunction:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public init() {
				        @Sendable nonisolated func __safeDI_gearSendableBuilder_Host() -> Host.SafeDISendableScope_Gear.__safeDI_Builder<any Gear> {
				            .init(inner_widgetSendableBuilder: { _ in __safeDI_gearBuilder_Host_Inner() })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_DefaultWidget_Scope() -> Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear> {
				            .init(part: { _ in __safeDI_gearBuilder_Part() })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Part() -> Part.__safeDI_GearCarrier<any Gear> {
				            .init(gear: {
				                let gear: any Gear = DefaultGear()
				                return gear
				            })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_Inner() -> Inner.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>> {
				            .init(panelBuilder: { __safeDI_gearBuilder_Host_Inner_Panel_Scope() })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_Inner_Panel_Scope() -> Inner.__safeDI_WidgetCarrier_Panel<Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>> {
				            .init(widget: { values_analytics, values_clock in __safeDI_gearBuilder_Host_DefaultWidget_Scope() })
				        }
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_E77340B7874B2ED7.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(inner_widgetSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_Inner() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: Analytics) -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
				                .init(gadget: { _ in
				                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                    return gadget
				                })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner() -> Inner.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				                .init(panelBuilder: { __safeDI_gadgetBuilder_Host_Inner_Panel_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner_Panel_Scope() -> Inner.__safeDI_WidgetCarrier_Panel<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				                .init(widget: { values_analytics, values_clock in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: values_analytics) })
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host(), __safeDI_gearSendableBuilder: __safeDI_gearSendableBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				""",
			])
		case .placeInsideSendableFunctionTakenSendable:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public init() {
				        @Sendable nonisolated func __safeDI_gearSendableBuilder_Host() -> Host.SafeDISendableScope_Gear.__safeDI_Builder<any Gear> {
				            .init(shell_widgetSendableBuilder: { _ in __safeDI_gearBuilder_Host_Shell() })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_DefaultWidget_Scope() -> Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear> {
				            .init(part: { _ in __safeDI_gearBuilder_Part() })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Part() -> Part.__safeDI_GearCarrier<any Gear> {
				            .init(gear: {
				                let gear: any Gear = DefaultGear()
				                return gear
				            })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_Shell() -> Shell.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>> {
				            .init(innerBuilder_Sendable: __safeDI_gearBuilder_Host_Inner())
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_Inner() -> Inner.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>> {
				            .init(panelBuilder: { __safeDI_gearBuilder_Host_Inner_Panel_Scope() })
				        }
				        @Sendable nonisolated func __safeDI_gearBuilder_Host_Inner_Panel_Scope() -> Inner.__safeDI_WidgetCarrier_Panel<Host.SafeDIScope_Gear.DefaultWidget_Scope.__safeDI_Builder<any Gear>> {
				            .init(widget: { values_analytics, values_clock in __safeDI_gearBuilder_Host_DefaultWidget_Scope() })
				        }
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_A6D9AB9C1D4AEA00.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(shell_widgetSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_Shell() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: Analytics) -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
				                .init(gadget: { _ in
				                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
				                    return gadget
				                })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Shell() -> Shell.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				                .init(innerBuilder_Sendable: __safeDI_gadgetBuilder_Host_Inner())
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner() -> Inner.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				                .init(panelBuilder: { __safeDI_gadgetBuilder_Host_Inner_Panel_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner_Panel_Scope() -> Inner.__safeDI_WidgetCarrier_Panel<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				                .init(widget: { values_analytics, values_clock in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: values_analytics) })
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host(), __safeDI_gearSendableBuilder: __safeDI_gearSendableBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				""",
			])
		}
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: A place in a fill, beneath further `@Sendable` functions

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenPlaceIsBeneathSendableBuilderFunctionInsideSendableFill() async throws {
		// The fill is `@Sendable` by route, and `Holder` is built inside it in a `@Sendable` builder function.
		let fixture = Self.fixture(
			route: .sendableByRoute,
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let gadget: any Gadget"], conformances: ", Sendable")],
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let holderBuilder: SendableInstantiator<Holder>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum Holder_Scope {
			            nonisolated public struct gadget_Values {
			                public let analytics: Analytics
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct holderBuilder_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let holderBuilder: @Sendable (holderBuilder_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(holderBuilder: @escaping @Sendable (holderBuilder_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.holderBuilder = holderBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(holderBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder_Sendable: @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(shell_widgetSendableBuilder_Sendable: @escaping @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.shell_widgetSendableBuilder_Sendable = shell_widgetSendableBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder_Sendable(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Sendable_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics) -> any Widget {
			                let analytics = scope_analytics
			                func __safeDI_widget() -> DefaultWidget {
			                    @Sendable nonisolated func __safeDI_holderBuilder() -> Holder {
			                        let __safeDI_gadgetSendableBuilder_holderBuilder = __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable.holderBuilder(SafeDISendableScope_Gadget.DefaultWidget_Scope.holderBuilder_Values())
			                        let analytics = Analytics()
			                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder_holderBuilder.gadget(SafeDIScope_Gadget.Holder_Scope.gadget_Values(analytics: analytics))
			                        return Holder(analytics: analytics, gadget: gadget)
			                    }
			                    let holderBuilder = SendableInstantiator<Holder>(__safeDI_holderBuilder)
			                    return DefaultWidget(analytics: analytics, holderBuilder: holderBuilder)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell() -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner() })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner() -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell())
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_7F66076971233E21 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_7F66076971233E21.self\(seamCallComment(seam: "Host", module: "Middle"))
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(shell_widgetSendableBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() -> Host.SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
			                .init(holderBuilder: { _ in __safeDI_gadgetBuilder_Host_Holder_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Holder_Scope() -> Host.SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in
			                    let analytics = scope.analytics
			                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
			                    return gadget
			                })
			            }
			            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(session: session, host: host)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenPlaceIsInsideFillOfCallInsideAnotherSendableFill() async throws {
		// `DefaultWidget`'s fill calls `DeepShell`, which `Middle` also fills, with `DefaultYarn`, inside whose fill `gadget`
		// is built: the path to the place crosses two `@Sendable` fills.
		let fixture = Self.fixture(
			route: .sendableByRoute,
			featureTypes: [
				"public protocol Yarn: Sendable {}",
				seamFixtureType(named: "Deep", isSeam: true, declarations: ["@Instantiated let yarn: any Yarn"], conformances: ", Sendable"),
				seamFixtureType(named: "DeepShell", isSeam: true, declarations: ["@Instantiated let deepBuilder: SendableInstantiator<Deep>"], conformances: ", Sendable"),
			],
			middleTypes: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultYarn", fulfilling: "Yarn", declarations: ["@Instantiated let gadget: any Gadget"])],
			widgetDeclarations: ["@Instantiated let deepShell: DeepShell"],
			appTypes: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let session: Session"])],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultYarn_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct deepShell_yarnSendableBuilder_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let deepShell_yarnSendableBuilder: @Sendable (deepShell_yarnSendableBuilder_Values) -> DeepShell.__safeDI_YarnSendableCarrier<SafeDIScope_Gadget.DefaultYarn_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(deepShell_yarnSendableBuilder: @escaping @Sendable (deepShell_yarnSendableBuilder_Values) -> DeepShell.__safeDI_YarnSendableCarrier<SafeDIScope_Gadget.DefaultYarn_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.deepShell_yarnSendableBuilder = deepShell_yarnSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(deepShell_yarnSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder_Sendable: @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(shell_widgetSendableBuilder_Sendable: @escaping @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.shell_widgetSendableBuilder_Sendable = shell_widgetSendableBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder_Sendable(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Sendable_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    func __safeDI_deepShell() -> DeepShell {
			                        let __safeDI_gadgetSendableBuilder_deepShell_yarnSendableBuilder = __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable.deepShell_yarnSendableBuilder(SafeDISendableScope_Gadget.DefaultWidget_Scope.deepShell_yarnSendableBuilder_Values())
			                        _ = DeepShell.__safeDI_DeepShell_2F81867793363127.self\(seamCallComment(seam: "Shell", module: "Feature"))
			                        @Sendable nonisolated func __safeDI_yarnBuilder_Deep_yarn(__safeDI_deepShell_yarnSendableBuilder: SafeDIScope_Gadget.DefaultYarn_Scope.__safeDI_Builder<any Gadget>) -> any Yarn {
			                            func __safeDI_yarn() -> DefaultYarn {
			                                let gadget: any Gadget = __safeDI_deepShell_yarnSendableBuilder.gadget(SafeDIScope_Gadget.DefaultYarn_Scope.gadget_Values())
			                                return DefaultYarn(gadget: gadget)
			                            }
			                            let yarn: any Yarn = __safeDI_yarn()
			                            return yarn
			                        }
			                        @Sendable nonisolated func __safeDI_yarnSendableBuilder_DeepShell(up: DeepShell.__safeDI_YarnSendableCarrier<SafeDIScope_Gadget.DefaultYarn_Scope.__safeDI_Builder<any Gadget>>) -> DeepShell.__safeDI_YarnSendableCarrier<any Yarn> {
			                            .init(deepBuilder: { __safeDI_yarnBuilder_Deep(up: up.deepBuilder()) })
			                        }
			                        @Sendable nonisolated func __safeDI_yarnBuilder_Deep(up: Deep.__safeDI_YarnCarrier<SafeDIScope_Gadget.DefaultYarn_Scope.__safeDI_Builder<any Gadget>>) -> Deep.__safeDI_YarnCarrier<any Yarn> {
			                            .init(yarn: { __safeDI_yarnBuilder_Deep_yarn(__safeDI_deepShell_yarnSendableBuilder: up.yarn()) })
			                        }
			                        return DeepShell(__safeDI_yarnSendableBuilder: __safeDI_yarnSendableBuilder_DeepShell(up: __safeDI_gadgetSendableBuilder_deepShell_yarnSendableBuilder))
			                    }
			                    let deepShell: DeepShell = __safeDI_deepShell()
			                    return DefaultWidget(deepShell: deepShell)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell() -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner() })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner() -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell())
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_602FF9605B7F192C {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_602FF9605B7F192C.self\(seamCallComment(seam: "Host", module: "Middle"))
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(shell_widgetSendableBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() -> Host.SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
			                .init(deepShell_yarnSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_DeepShell() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultYarn_Scope() -> Host.SafeDIScope_Gadget.DefaultYarn_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { _ in
			                    let gadget: any Gadget = DefaultGadget(session: session)
			                    return gadget
			                })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DeepShell() -> DeepShell.__safeDI_YarnSendableCarrier<Host.SafeDIScope_Gadget.DefaultYarn_Scope.__safeDI_Builder<any Gadget>> {
			                .init(deepBuilder: { __safeDI_gadgetBuilder_Host_Deep() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Deep() -> Deep.__safeDI_YarnCarrier<Host.SafeDIScope_Gadget.DefaultYarn_Scope.__safeDI_Builder<any Gadget>> {
			                .init(yarn: { __safeDI_gadgetBuilder_Host_DefaultYarn_Scope() })
			            }
			            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(session: session, host: host)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	/// A wrapper of a place inside a `@Sendable` fill, which the seam builds around the place's builder.
	enum PlaceWrapper: CaseIterable, CustomTestStringConvertible {
		case lazilyInstantiated
		case sendableLazilyInstantiated

		var testDescription: String {
			switch self {
			case .lazilyInstantiated:
				"lazilyInstantiated"
			case .sendableLazilyInstantiated:
				"sendableLazilyInstantiated"
			}
		}

		var declaration: String {
			switch self {
			case .lazilyInstantiated:
				"@Instantiated let gadget: LazilyInstantiated<any Gadget>"
			case .sendableLazilyInstantiated:
				"@Instantiated let gadget: SendableLazilyInstantiated<any Gadget>"
			}
		}
	}

	@Test(arguments: PlaceWrapper.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCaseOfWrapper_whenPlaceInsideSendableFillIsWrapper(wrapper: PlaceWrapper) async throws {
		let fixture = Self.fixture(route: .sendableByRoute, widgetDeclarations: ["@Received let analytics: Analytics", wrapper.declaration], appTypes: [Self.defaultGadgetReadingSession, Self.defaultGear])
		// `@unchecked`, as the fuzzer's mixed-wrapper graphs mark their types: `DefaultWidget` holds a `LazilyInstantiated`.
		let adjusted = ThreeModules(feature: fixture.feature, middle: fixture.middle.map { $0.replacingOccurrences(of: "Instantiable, Widget", with: "Instantiable, Widget, @unchecked Sendable") }, app: fixture.app, root: fixture.root)
		let output = try await executeSafeDIToolMultiModuleTest(modules: adjusted.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		switch wrapper {
		case .lazilyInstantiated:
			expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
				"Middle.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Host {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct gadget_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }
				    }

				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
				        func __safeDI_shell() -> Shell {
				            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
				            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
				                let analytics = scope_analytics
				                func __safeDI_widget() -> DefaultWidget {
				                    func __safeDI_gadget() -> any Gadget {
				                        __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
				                    }
				                    let gadget = LazilyInstantiated<any Gadget>(__safeDI_gadget)
				                    return DefaultWidget(analytics: analytics, gadget: gadget)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
				                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
				            }
				            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
				                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
				            }
				            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_1383AA669B32C876 {}
				}
				""",
			])
		case .sendableLazilyInstantiated:
			expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
				"Middle.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Host {
				    nonisolated public enum SafeDISendableScope_Gadget {
				        nonisolated public struct shell_widgetSendableBuilder_Sendable_Values: Sendable {}

				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct gadget_Values: Sendable {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				                public let gadget: @Sendable (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping @Sendable (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
				            public let shell_widgetSendableBuilder_Sendable: @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

				            public init(shell_widgetSendableBuilder_Sendable: @escaping @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
				                self.shell_widgetSendableBuilder_Sendable = shell_widgetSendableBuilder_Sendable
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
				                self.init(shell_widgetSendableBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
				        func __safeDI_shell() -> Shell {
				            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder_Sendable(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Sendable_Values())
				            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics) -> any Widget {
				                let analytics = scope_analytics
				                func __safeDI_widget() -> DefaultWidget {
				                    @Sendable nonisolated func __safeDI_gadget() -> any Gadget {
				                        __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable.gadget(SafeDISendableScope_Gadget.DefaultWidget_Scope.gadget_Values())
				                    }
				                    let gadget = SendableLazilyInstantiated<any Gadget>(__safeDI_gadget)
				                    return DefaultWidget(analytics: analytics, gadget: gadget)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell() -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
				                .init(innerBuilder: { __safeDI_widgetBuilder_Inner() })
				            }
				            @Sendable nonisolated func __safeDI_widgetBuilder_Inner() -> Inner.__safeDI_WidgetCarrier<any Widget> {
				                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics) })
				            }
				            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell())
				        }
				        let shell: Shell = __safeDI_shell()
				        self.init(session: session, shell: shell)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_838240534F00DEC4 {}
				}
				""",
			])
		}
		switch wrapper {
		case .lazilyInstantiated:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public init() {
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_1383AA669B32C876.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope_gadget(_ scope: Host.SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values) -> any Gadget {
				                func __safeDI_gadget() -> DefaultGadget {
				                    DefaultGadget(session: session)
				                }
				                return __safeDI_gadget()
				            }
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(shell_widgetSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_Shell() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope() -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
				                .init(gadget: { scope in __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope_gadget(scope) })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Shell() -> Shell.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				                .init(innerBuilder: { __safeDI_gadgetBuilder_Host_Inner() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner() -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
				                .init(widget: { values_analytics in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope() })
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				""",
			])
		case .sendableLazilyInstantiated:
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif
				#if canImport(Middle)
				import Middle
				#endif

				extension Root {
				    public init() {
				        let session = Session()
				        func __safeDI_host() -> Host {
				            _ = Host.__safeDI_Host_838240534F00DEC4.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope_gadget() -> any Gadget {
				                @Sendable nonisolated func __safeDI_gadget() -> DefaultGadget {
				                    DefaultGadget(session: session)
				                }
				                return __safeDI_gadget()
				            }
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
				                .init(shell_widgetSendableBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() })
				            }
				            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() -> Host.SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
				                .init(gadget: { _ in __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope_gadget() })
				            }
				            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
				        }
				        let host: Host = __safeDI_host()
				        self.init(session: session, host: host)
				    }
				}
				""",
			])
		}
	}

	// MARK: Which fills are `@Sendable`

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillsSendable_whenSendableFillRefersToThemInChain() async throws {
		// `Top` takes `firstBuilder` `@Sendable`. The fill of `first` calls `SubB`, passing the fill of `second`, which calls
		// `SubC`, passing the fill of `third`: each is referred to from a `@Sendable` function that does not enclose it.
		let feature = [
			"public protocol First: Sendable {}",
			"public protocol Second: Sendable {}",
			"public protocol Third: Sendable {}",
			seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
			seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
			seamFixtureType(named: "SubC", isSeam: true, declarations: ["@Instantiated let third: any Third"], conformances: ", Sendable"),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subABuilder: SendableInstantiator<SubA>", "@Instantiated let subB: SubB", "@Instantiated let subC: SubC"]),
		]
		let fulfillers = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let subB: SubB"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: ["@Instantiated let subC: SubC"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultThird", fulfilling: "Third", declarations: []),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_thirdBuilder_Top() -> Top.__safeDI_ThirdCarrier<any Third> {
			            .init(subC: __safeDI_thirdBuilder_SubC())
			        }
			        @Sendable nonisolated func __safeDI_thirdBuilder_SubC() -> SubC.__safeDI_ThirdCarrier<any Third> {
			            .init(third: {
			                let third: any Third = DefaultThird()
			                return third
			            })
			        }
			        func __safeDI_top() -> Top {
			            _ = Top.__safeDI_Top_2C9038B6F47B5DFF.self\(seamCallComment(seam: "Top", module: "Feature"))
			            @Sendable nonisolated func __safeDI_firstBuilder_SubA_first() -> any First {
			                func __safeDI_first() -> DefaultFirst {
			                    func __safeDI_subB() -> SubB {
			                        _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "Top", module: "Feature"))
			                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB())
			                    }
			                    let subB: SubB = __safeDI_subB()
			                    return DefaultFirst(subB: subB)
			                }
			                let first: any First = __safeDI_first()
			                return first
			            }
			            @Sendable nonisolated func __safeDI_secondBuilder_SubB_second() -> any Second {
			                func __safeDI_second() -> DefaultSecond {
			                    func __safeDI_subC() -> SubC {
			                        _ = SubC.__safeDI_SubC_F882055416364258.self\(seamCallComment(seam: "Top", module: "Feature"))
			                        return SubC(__safeDI_thirdBuilder: __safeDI_thirdBuilder_SubC())
			                    }
			                    let subC: SubC = __safeDI_subC()
			                    return DefaultSecond(subC: subC)
			                }
			                let second: any Second = __safeDI_second()
			                return second
			            }
			            @Sendable nonisolated func __safeDI_firstSendableBuilder_Top() -> Top.__safeDI_FirstSendableCarrier<any First> {
			                .init(subABuilder: { __safeDI_firstBuilder_SubA() })
			            }
			            @Sendable nonisolated func __safeDI_firstBuilder_SubA() -> SubA.__safeDI_FirstCarrier<any First> {
			                .init(first: { __safeDI_firstBuilder_SubA_first() })
			            }
			            func __safeDI_secondBuilder_Top() -> Top.__safeDI_SecondCarrier<any Second> {
			                .init(subB: __safeDI_secondBuilder_SubB())
			            }
			            @Sendable nonisolated func __safeDI_secondBuilder_SubB() -> SubB.__safeDI_SecondCarrier<any Second> {
			                .init(second: { __safeDI_secondBuilder_SubB_second() })
			            }
			            return Top(__safeDI_firstSendableBuilder: __safeDI_firstSendableBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(), __safeDI_thirdBuilder: __safeDI_thirdBuilder_Top())
			        }
			        let top: Top = __safeDI_top()
			        self.init(top: top)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresEnclosingCallsFillSendable_whenSendableFillOfCallInsideAnotherFillRefersToIt() async throws {
		// `App`'s fill of `third`, declared for the call of `ThirdShell` inside the fill of `first`, is `@Sendable` because
		// `ThirdShell` takes it so. It calls `SubB`, passing the fill of `second`, of the enclosing call of `Top`, which it does
		// not enclose: `second`'s fill is `@Sendable` while `first`'s, which encloses the reference, stays plain.
		let feature = [
			"public protocol First: Sendable {}",
			"public protocol Second: Sendable {}",
			"public protocol Third: Sendable {}",
			seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
			seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
			seamFixtureType(named: "SubC", isSeam: true, declarations: ["@Instantiated let third: any Third"], conformances: ", Sendable"),
			seamFixtureType(named: "ThirdShell", isSeam: true, declarations: ["@Instantiated let subCBuilder: SendableInstantiator<SubC>"], conformances: ", Sendable"),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"]),
		]
		let fulfillers = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let thirdShell: ThirdShell"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: []),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultThird", fulfilling: "Third", declarations: ["@Instantiated let subB: SubB"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"])
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_secondBuilder_Top() -> Top.__safeDI_SecondCarrier<any Second> {
			            .init(subB: __safeDI_secondBuilder_SubB())
			        }
			        @Sendable nonisolated func __safeDI_secondBuilder_SubB() -> SubB.__safeDI_SecondCarrier<any Second> {
			            .init(second: {
			                let second: any Second = DefaultSecond()
			                return second
			            })
			        }
			        func __safeDI_top() -> Top {
			            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
			            func __safeDI_firstBuilder_SubA_first() -> any First {
			                func __safeDI_first() -> DefaultFirst {
			                    func __safeDI_thirdShell() -> ThirdShell {
			                        _ = ThirdShell.__safeDI_ThirdShell_574B3FB75FC44198.self\(seamCallComment(seam: "Top", module: "Feature"))
			                        @Sendable nonisolated func __safeDI_thirdBuilder_SubC_third() -> any Third {
			                            func __safeDI_third() -> DefaultThird {
			                                func __safeDI_subB() -> SubB {
			                                    _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "Top", module: "Feature"))
			                                    return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB())
			                                }
			                                let subB: SubB = __safeDI_subB()
			                                return DefaultThird(subB: subB)
			                            }
			                            let third: any Third = __safeDI_third()
			                            return third
			                        }
			                        @Sendable nonisolated func __safeDI_thirdSendableBuilder_ThirdShell() -> ThirdShell.__safeDI_ThirdSendableCarrier<any Third> {
			                            .init(subCBuilder: { __safeDI_thirdBuilder_SubC() })
			                        }
			                        @Sendable nonisolated func __safeDI_thirdBuilder_SubC() -> SubC.__safeDI_ThirdCarrier<any Third> {
			                            .init(third: { __safeDI_thirdBuilder_SubC_third() })
			                        }
			                        return ThirdShell(__safeDI_thirdSendableBuilder: __safeDI_thirdSendableBuilder_ThirdShell())
			                    }
			                    let thirdShell: ThirdShell = __safeDI_thirdShell()
			                    return DefaultFirst(thirdShell: thirdShell)
			                }
			                let first: any First = __safeDI_first()
			                return first
			            }
			            func __safeDI_firstBuilder_Top() -> Top.__safeDI_FirstCarrier<any First> {
			                .init(subA: __safeDI_firstBuilder_SubA())
			            }
			            func __safeDI_firstBuilder_SubA() -> SubA.__safeDI_FirstCarrier<any First> {
			                .init(first: { __safeDI_firstBuilder_SubA_first() })
			            }
			            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top())
			        }
			        let top: Top = __safeDI_top()
			        self.init(top: top)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root]))
	}

	// MARK: What a seam reads beside a `@Sendable` fill

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsDeferredParameterPlain_whenOnlyPlaceInsideSendableFillReadsIt() async throws {
		// `gadget`'s first stage carries `user`, `Host`'s deferred parameter, and is called before the `@Sendable` fill, so
		// `Host` takes it as a plain autoclosure. `DefaultGadget` is built in a later stage, so `App`'s fill reads `Root`'s
		// declaration inside a `@Sendable` function, as inline, which is why it is the `Sendable` wrapper.
		let fixture = ThreeModules(
			feature: FillRoute.sendableByRoute.featureTypes,
			middle: [Self.gadget, seamFixtureType(named: "User", declarations: [], conformances: ", Sendable"), seamFixtureType(named: "Session", declarations: ["@Received let user: User"], conformances: ", Sendable")] + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Received let session: Session", FillRoute.sendableByRoute.hostDeclaration]),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let user: User"])],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let session: Session", "@Instantiated let user: SendableLazilyInstantiated<User>", "@Instantiated let host: Host"]),
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                    return DefaultWidget(gadget: gadget)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_1383AA669B32C876 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_user() -> User {
			            User()
			        }
			        let user = SendableLazilyInstantiated<User>(__safeDI_user)
			        let session = Session(user: user.instance)
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_1383AA669B32C876.self\(seamCallComment(seam: "Host", module: "Middle"))
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(shell_widgetSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_Shell() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope() -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { _ in
			                    let gadget: any Gadget = DefaultGadget(user: user.instance)
			                    return gadget
			                })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Shell() -> Shell.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
			                .init(innerBuilder: { __safeDI_gadgetBuilder_Host_Inner() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner() -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
			                .init(widget: { values_analytics in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope() })
			            }
			            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(session: session, user: user, host: host)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOwnBuilderSendable_whenCallInsideSendableFillReentersSeam() async throws {
		// A call of `Host` inside the `@Sendable` fill, in a plain `Instantiator`, passes the builder `Host` takes for its own
		// `gadget`, which the fill captures.
		let fixture = ThreeModules(
			feature: FillRoute.sendableByRoute.featureTypes,
			middle: [
				Self.gadget,
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"])
					.replacingOccurrences(of: "Instantiable, Widget", with: "Instantiable, Widget, @unchecked Sendable"),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let gadget: any Gadget", FillRoute.sendableByRoute.hostDeclaration], conformances: ", @unchecked Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct gadget_Values {
			            public let shell: Shell
			        }

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct hostBuilder_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let hostBuilder: (hostBuilder_Values) -> Host.SafeDIScope_Gadget.__safeDI_Builder<__safeDI_Built>

			                public init(hostBuilder: @escaping (hostBuilder_Values) -> Host.SafeDIScope_Gadget.__safeDI_Builder<__safeDI_Built>) {
			                    self.hostBuilder = hostBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(hostBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let gadget: (gadget_Values) -> __safeDI_Built

			            public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                self.gadget = gadget
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(gadget: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			        nonisolated public struct shell_widgetSendableBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct hostBuilder_Sendable_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let hostBuilder_Sendable: @Sendable (hostBuilder_Sendable_Values) -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>

			                public init(hostBuilder_Sendable: @escaping @Sendable (hostBuilder_Sendable_Values) -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>) {
			                    self.hostBuilder_Sendable = hostBuilder_Sendable
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(hostBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let shell_widgetSendableBuilder_Sendable: @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>, shell_widgetSendableBuilder_Sendable: @escaping @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			                self.shell_widgetSendableBuilder_Sendable = shell_widgetSendableBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, shell_widgetSendableBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder_Sendable(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Sendable_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    func __safeDI_hostBuilder() -> Host {
			                        _ = Host.__safeDI_Host_4123A8AD31012EAA.self
			                        return Host(__safeDI_gadgetBuilder: __safeDI_shell_widgetSendableBuilder.hostBuilder(SafeDIScope_Gadget.DefaultWidget_Scope.hostBuilder_Values()), __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable.hostBuilder_Sendable(SafeDISendableScope_Gadget.DefaultWidget_Scope.hostBuilder_Sendable_Values()))
			                    }
			                    let hostBuilder = Instantiator<Host>(__safeDI_hostBuilder)
			                    return DefaultWidget(hostBuilder: hostBuilder)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			        }
			        let shell: Shell = __safeDI_shell()
			        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(SafeDIScope_Gadget.gadget_Values(shell: shell))
			        self.init(gadget: gadget, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_4123A8AD31012EAA {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = DefaultGadget()
			                return gadget
			            })
			        }
			        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(shell_widgetSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_Shell() }, shell_widgetSendableBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope() -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
			            .init(hostBuilder: { _ in __safeDI_gadgetBuilder_Host() })
			        }
			        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() -> Host.SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
			            .init(hostBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_Host() })
			        }
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Shell() -> Shell.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
			            .init(innerBuilder: { __safeDI_gadgetBuilder_Host_Inner() })
			        }
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner() -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
			            .init(widget: { values_analytics in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope() })
			        }
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_4123A8AD31012EAA.self\(seamCallComment(seam: "Host", module: "Middle"))
			            return Host(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host(), __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		])
	}

	// MARK: Shapes beside these, which compiled before a fill counted as a `@Sendable` function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPlaceInPlainEnum_whenPlaceIsBeneathPlainInstantiatorInsidePlainFill() async throws {
		let fixture = Self.fixture(
			route: .plain,
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget"])],
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let holderBuilder: Instantiator<Holder>"],
		)
		let adjusted = ThreeModules(feature: fixture.feature, middle: fixture.middle.map { $0.replacingOccurrences(of: "Instantiable, Widget", with: "Instantiable, Widget, @unchecked Sendable") }, app: fixture.app, root: fixture.root)
		let output = try await executeSafeDIToolMultiModuleTest(modules: adjusted.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_widgetBuilder_Values {
			            public let session: Session
			        }

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct holderBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let holderBuilder: (holderBuilder_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(holderBuilder: @escaping (holderBuilder_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.holderBuilder = holderBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(holderBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        nonisolated public enum Holder_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let inner_widgetBuilder: (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_widgetBuilder: @escaping (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_widgetBuilder = inner_widgetBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_widgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_widgetBuilder = __safeDI_gadgetBuilder.inner_widgetBuilder(SafeDIScope_Gadget.inner_widgetBuilder_Values(session: session))
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_EA4DE2878D50CCB8.self\(seamCallComment(seam: "Inner", module: "Feature"))
			            func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_inner_widgetBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                let analytics = scope_analytics
			                func __safeDI_widget() -> DefaultWidget {
			                    let __safeDI_gadgetBuilder_holderBuilder = __safeDI_inner_widgetBuilder.holderBuilder(SafeDIScope_Gadget.DefaultWidget_Scope.holderBuilder_Values())
			                    func __safeDI_holderBuilder() -> Holder {
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_holderBuilder.gadget(SafeDIScope_Gadget.Holder_Scope.gadget_Values())
			                        return Holder(analytics: analytics, gadget: gadget)
			                    }
			                    let holderBuilder = Instantiator<Holder>(__safeDI_holderBuilder)
			                    return DefaultWidget(analytics: analytics, holderBuilder: holderBuilder)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_inner_widgetBuilder: up.widget(scope_analytics)) })
			            }
			            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner(up: __safeDI_gadgetBuilder_inner_widgetBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(session: session, inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_9400DDE5A7A957AF {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        func __safeDI_gadgetBuilder_Host() -> Host.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(inner_widgetBuilder: { values in __safeDI_gadgetBuilder_Host_Inner(session: values.session) })
			        }
			        func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: Analytics, session: Session) -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
			            .init(holderBuilder: { _ in __safeDI_gadgetBuilder_Host_Holder_Scope(analytics: analytics, session: session) })
			        }
			        func __safeDI_gadgetBuilder_Host_Holder_Scope(analytics: Analytics, session: Session) -> Host.SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Host_Inner(session: Session) -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
			            .init(widget: { values_analytics in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: values_analytics, session: session) })
			        }
			        let session = Session()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_9400DDE5A7A957AF.self\(seamCallComment(seam: "Host", module: "Middle"))
			            return Host(__safeDI_session: session, __safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(session: session, host: host)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenPlaceIsBeneathSendableBuilderFunctionInsidePlainFill() async throws {
		let fixture = Self.fixture(
			route: .plain,
			middleTypes: [seamFixtureType(named: "Holder", declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let gadget: any Gadget"], conformances: ", Sendable")],
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let holderBuilder: SendableInstantiator<Holder>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum Holder_Scope {
			            nonisolated public struct gadget_Values {
			                public let analytics: Analytics
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct inner_widgetBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct holderBuilder_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let holderBuilder: @Sendable (holderBuilder_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(holderBuilder: @escaping @Sendable (holderBuilder_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.holderBuilder = holderBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(holderBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let inner_widgetBuilder_Sendable: @Sendable (inner_widgetBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(inner_widgetBuilder_Sendable: @escaping @Sendable (inner_widgetBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.inner_widgetBuilder_Sendable = inner_widgetBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(inner_widgetBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetSendableBuilder_inner_widgetBuilder_Sendable = __safeDI_gadgetSendableBuilder.inner_widgetBuilder_Sendable(SafeDISendableScope_Gadget.inner_widgetBuilder_Sendable_Values())
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_EA4DE2878D50CCB8.self\(seamCallComment(seam: "Inner", module: "Feature"))
			            func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics) -> any Widget {
			                let analytics = scope_analytics
			                func __safeDI_widget() -> DefaultWidget {
			                    @Sendable nonisolated func __safeDI_holderBuilder() -> Holder {
			                        let __safeDI_gadgetSendableBuilder_holderBuilder = __safeDI_gadgetSendableBuilder_inner_widgetBuilder_Sendable.holderBuilder(SafeDISendableScope_Gadget.DefaultWidget_Scope.holderBuilder_Values())
			                        let analytics = Analytics()
			                        let gadget: any Gadget = __safeDI_gadgetSendableBuilder_holderBuilder.gadget(SafeDIScope_Gadget.Holder_Scope.gadget_Values(analytics: analytics))
			                        return Holder(analytics: analytics, gadget: gadget)
			                    }
			                    let holderBuilder = SendableInstantiator<Holder>(__safeDI_holderBuilder)
			                    return DefaultWidget(analytics: analytics, holderBuilder: holderBuilder)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            func __safeDI_widgetBuilder_Inner() -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics) })
			            }
			            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner())
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(session: session, inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_08EAA5F2040DC06D {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_08EAA5F2040DC06D.self\(seamCallComment(seam: "Host", module: "Middle"))
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(inner_widgetBuilder_Sendable: { _ in __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host_DefaultWidget_Scope() -> Host.SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
			                .init(holderBuilder: { _ in __safeDI_gadgetBuilder_Host_Holder_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Holder_Scope() -> Host.SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { scope in
			                    let analytics = scope.analytics
			                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
			                    return gadget
			                })
			            }
			            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(session: session, host: host)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsNestedFillPlain_whenSendableFillCallsSeamItFillsItself() async throws {
		// `Middle` also sees `DefaultGear`, so the fill calls `Part` with a fill of its own, which nothing refers to from a
		// `@Sendable` function it does not enclose.
		let fixture = Self.fixture(
			route: .sendableByRoute,
			middleTypes: [Self.defaultGear],
			widgetDeclarations: ["@Instantiated let part: Part"],
			appTypes: [],
			root: Self.rootWithSession,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session) {
			        func __safeDI_shell() -> Shell {
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    func __safeDI_part() -> Part {
			                        _ = Part.__safeDI_Part_6EBD3668CBE30F42.self\(seamCallComment(seam: "Shell", module: "Feature"))
			                        func __safeDI_gearBuilder_Part() -> Part.__safeDI_GearCarrier<any Gear> {
			                            .init(gear: {
			                                let gear: any Gear = DefaultGear()
			                                return gear
			                            })
			                        }
			                        return Part(__safeDI_gearBuilder: __safeDI_gearBuilder_Part())
			                    }
			                    let part: Part = __safeDI_part()
			                    return DefaultWidget(part: part)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell() -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner() })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner() -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell())
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_13A4BC800B514232 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_13A4BC800B514232.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host(__safeDI_session: session)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsSendablePlaceWithPlainBody_whenFillHoldsNoPlaceOrCall() async throws {
		let fixture = Self.fixture(route: .placeInsideSendableFunction, widgetDeclarations: ["@Received let analytics: Analytics", "@Received let clock: Clock"], appTypes: [])
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session) {
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Inner() -> Inner.__safeDI_WidgetSendableCarrier<any Widget> {
			            .init(panelBuilder: { __safeDI_widgetBuilder_Inner_Panel_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_widgetBuilder_Inner_Panel_Scope() -> Inner.__safeDI_WidgetCarrier_Panel<any Widget> {
			            .init(widget: { scope_analytics, scope_clock in
			                let analytics = scope_analytics
			                let clock = scope_clock
			                let widget: any Widget = DefaultWidget(analytics: analytics, clock: clock)
			                return widget
			            })
			        }
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_1A9C10F553C3A46C.self\(seamCallComment(seam: "Inner", module: "Feature"))
			            return Inner(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Inner())
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(session: session, inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_13A4BC800B514232 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_13A4BC800B514232.self\(seamCallComment(seam: "Host", module: "Middle"))
		            return Host(__safeDI_session: session)
		        }
		        let host: Host = __safeDI_host()
		        self.init(session: session, host: host)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: A fill no `@Sendable` function outside it refers to

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsFillPlain_whenPlainFillInsideSendableBuilderFunctionIsAllThatRefersToIt() async throws {
		// `Host` calls `Top` in a `SendableInstantiator`, whose builder function declares both fills. The plain fill of
		// `first` passes the fill of `second` to `SubB`, and that builder function encloses both, so neither is `@Sendable`
		// and `gadget`, a place inside the fill of `second`, takes no stage for it.
		let fixture = ThreeModules(
			feature: [
				"public protocol First: Sendable {}",
				"public protocol Second: Sendable {}",
				seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
				seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
				seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"], conformances: ", Sendable"),
			],
			middle: [
				Self.gadget,
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let subB: SubB"]),
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: ["@Instantiated let gadget: any Gadget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let topBuilder: SendableInstantiator<Top>"]),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultFirst_Scope {
			            nonisolated public struct subB_secondBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let subB_secondBuilder: (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(subB_secondBuilder: @escaping (subB_secondBuilder_Values) -> SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.subB_secondBuilder = subB_secondBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(subB_secondBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        nonisolated public enum DefaultSecond_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct topBuilder_firstBuilder_Values: Sendable {}

			        nonisolated public struct topBuilder_secondBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let topBuilder_firstBuilder: @Sendable (topBuilder_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let topBuilder_secondBuilder: @Sendable (topBuilder_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(topBuilder_firstBuilder: @escaping @Sendable (topBuilder_firstBuilder_Values) -> Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<__safeDI_Built>>, topBuilder_secondBuilder: @escaping @Sendable (topBuilder_secondBuilder_Values) -> Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.topBuilder_firstBuilder = topBuilder_firstBuilder
			                self.topBuilder_secondBuilder = topBuilder_secondBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(topBuilder_firstBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, topBuilder_secondBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        @Sendable nonisolated func __safeDI_topBuilder() -> Top {
			            let __safeDI_gadgetSendableBuilder_topBuilder_firstBuilder = __safeDI_gadgetSendableBuilder.topBuilder_firstBuilder(SafeDISendableScope_Gadget.topBuilder_firstBuilder_Values())
			            let __safeDI_gadgetSendableBuilder_topBuilder_secondBuilder = __safeDI_gadgetSendableBuilder.topBuilder_secondBuilder(SafeDISendableScope_Gadget.topBuilder_secondBuilder_Values())
			            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
			            func __safeDI_firstBuilder_SubA_first(__safeDI_topBuilder_firstBuilder: SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>) -> any First {
			                func __safeDI_first() -> DefaultFirst {
			                    let __safeDI_gadgetSendableBuilder_subB_secondBuilder = __safeDI_topBuilder_firstBuilder.subB_secondBuilder(SafeDIScope_Gadget.DefaultFirst_Scope.subB_secondBuilder_Values())
			                    func __safeDI_subB() -> SubB {
			                        _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "SubB", module: "Feature"))
			                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB(up: __safeDI_gadgetSendableBuilder_subB_secondBuilder))
			                    }
			                    let subB: SubB = __safeDI_subB()
			                    return DefaultFirst(subB: subB)
			                }
			                let first: any First = __safeDI_first()
			                return first
			            }
			            func __safeDI_secondBuilder_SubB_second(__safeDI_topBuilder_secondBuilder: SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>) -> any Second {
			                func __safeDI_second() -> DefaultSecond {
			                    let gadget: any Gadget = __safeDI_topBuilder_secondBuilder.gadget(SafeDIScope_Gadget.DefaultSecond_Scope.gadget_Values())
			                    return DefaultSecond(gadget: gadget)
			                }
			                let second: any Second = __safeDI_second()
			                return second
			            }
			            func __safeDI_firstBuilder_Top(up: Top.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_FirstCarrier<any First> {
			                .init(subA: __safeDI_firstBuilder_SubA(up: up.subA))
			            }
			            func __safeDI_firstBuilder_SubA(up: SubA.__safeDI_FirstCarrier<SafeDIScope_Gadget.DefaultFirst_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_FirstCarrier<any First> {
			                .init(first: { __safeDI_firstBuilder_SubA_first(__safeDI_topBuilder_firstBuilder: up.first()) })
			            }
			            func __safeDI_secondBuilder_Top(up: Top.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_SecondCarrier<any Second> {
			                .init(subB: __safeDI_secondBuilder_SubB(up: up.subB))
			            }
			            func __safeDI_secondBuilder_SubB(up: SubB.__safeDI_SecondCarrier<SafeDIScope_Gadget.DefaultSecond_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_SecondCarrier<any Second> {
			                .init(second: { __safeDI_secondBuilder_SubB_second(__safeDI_topBuilder_secondBuilder: up.second()) })
			            }
			            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(up: __safeDI_gadgetSendableBuilder_topBuilder_firstBuilder), __safeDI_secondBuilder: __safeDI_secondBuilder_Top(up: __safeDI_gadgetSendableBuilder_topBuilder_secondBuilder))
			        }
			        let topBuilder = SendableInstantiator<Top>(__safeDI_topBuilder)
			        self.init(topBuilder: topBuilder)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_3D5FC152C2F625B9 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresEnclosingCallsFillSendable_whenCallInSendableBuilderFunctionInsidePlainFillPassesIt() async throws {
		// The fill of `first` is plain, but it calls `SubB` in a `SendableInstantiator`: that builder function does not
		// enclose the fill of `second`, which it passes.
		let feature = [
			"public protocol First: Sendable {}",
			"public protocol Second: Sendable {}",
			seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
			seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"]),
		]
		let fulfillers = [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let subBBuilder: SendableInstantiator<SubB>"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: []),
		]
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_secondBuilder_Top() -> Top.__safeDI_SecondCarrier<any Second> {
			            .init(subB: __safeDI_secondBuilder_SubB())
			        }
			        @Sendable nonisolated func __safeDI_secondBuilder_SubB() -> SubB.__safeDI_SecondCarrier<any Second> {
			            .init(second: {
			                let second: any Second = DefaultSecond()
			                return second
			            })
			        }
			        func __safeDI_top() -> Top {
			            _ = Top.__safeDI_Top_9F42E50147BFAB2E.self\(seamCallComment(seam: "Top", module: "Feature"))
			            func __safeDI_firstBuilder_SubA_first() -> any First {
			                func __safeDI_first() -> DefaultFirst {
			                    @Sendable nonisolated func __safeDI_subBBuilder() -> SubB {
			                        _ = SubB.__safeDI_SubB_3200C917631BE20F.self\(seamCallComment(seam: "Top", module: "Feature"))
			                        return SubB(__safeDI_secondBuilder: __safeDI_secondBuilder_SubB())
			                    }
			                    let subBBuilder = SendableInstantiator<SubB>(__safeDI_subBBuilder)
			                    return DefaultFirst(subBBuilder: subBBuilder)
			                }
			                let first: any First = __safeDI_first()
			                return first
			            }
			            func __safeDI_firstBuilder_Top() -> Top.__safeDI_FirstCarrier<any First> {
			                .init(subA: __safeDI_firstBuilder_SubA())
			            }
			            func __safeDI_firstBuilder_SubA() -> SubA.__safeDI_FirstCarrier<any First> {
			                .init(first: { __safeDI_firstBuilder_SubA_first() })
			            }
			            return Top(__safeDI_firstBuilder: __safeDI_firstBuilder_Top(), __safeDI_secondBuilder: __safeDI_secondBuilder_Top())
			        }
			        let top: Top = __safeDI_top()
			        self.init(top: top)
			    }
			}
			""",
		])
	}

	// MARK: A place in a `@Sendable` fill whose builder is `@Sendable` for another reason

	/// `Host`, which holds `hostDeclarations`, calls `Shell` with a fill by `DefaultWidget`, which holds `widgetDeclarations`
	/// and builds `gadget`, a place of `Host`, inside a `@Sendable` function.
	private static func fixtureOfSendableFillWithPlace(
		widgetConformances: String = "Instantiable, Widget",
		widgetDeclarations: [String] = ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget"],
		middleTypes: [String] = [],
		hostDeclarations: [String] = ["@Received let session: Session", FillRoute.sendableByRoute.hostDeclaration],
		session sessionType: String = session,
		hostConformances: String = ", Sendable",
		gadgetDeclarations: [String] = ["@Received let session: Session", "@Received let analytics: Analytics"],
		root: String = rootWithSession,
	) -> ThreeModules {
		ThreeModules(
			feature: FillRoute.sendableByRoute.featureTypes,
			middle: [gadget, sessionType] + middleTypes + [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: widgetDeclarations)
					.replacingOccurrences(of: "Instantiable, Widget", with: widgetConformances),
				seamFixtureType(named: "Host", isSeam: true, declarations: hostDeclarations, conformances: hostConformances),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: gadgetDeclarations)],
			root: root,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenBuilderIsSendableBecauseSeamCalledInFillPassesItBackSendable() async throws {
		// `Other`, called in the fill, re-enters `Host` in a `SendableInstantiator`, so it takes `gadgetBuilder` `@Sendable`.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetConformances: "Instantiable, Widget, @unchecked Sendable",
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget", "@Instantiated let otherBuilder: Instantiator<Other>"],
			middleTypes: [seamFixtureType(named: "Other", isSeam: true, declarations: ["@Instantiated let hostBuilder: SendableInstantiator<Host>"], conformances: ", Sendable")],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {
			                public let otherBuilder: Instantiator<Other>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			        nonisolated public struct shell_widgetSendableBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct otherBuilder_Sendable_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let otherBuilder_Sendable: @Sendable (otherBuilder_Sendable_Values) -> Other.__safeDI_GadgetSendableCarrier<__safeDI_Built>

			                public init(otherBuilder_Sendable: @escaping @Sendable (otherBuilder_Sendable_Values) -> Other.__safeDI_GadgetSendableCarrier<__safeDI_Built>) {
			                    self.otherBuilder_Sendable = otherBuilder_Sendable
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(otherBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let shell_widgetSendableBuilder_Sendable: @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>, shell_widgetSendableBuilder_Sendable: @escaping @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			                self.shell_widgetSendableBuilder_Sendable = shell_widgetSendableBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, shell_widgetSendableBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder_Sendable(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Sendable_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                let analytics = scope_analytics
			                func __safeDI_widget() -> DefaultWidget {
			                    func __safeDI_otherBuilder() -> Other {
			                        _ = Other.__safeDI_Other_18A1B77BC02A5E93.self
			                        return Other(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable.otherBuilder_Sendable(SafeDISendableScope_Gadget.DefaultWidget_Scope.otherBuilder_Sendable_Values()))
			                    }
			                    let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(otherBuilder: otherBuilder))
			                    return DefaultWidget(analytics: analytics, gadget: gadget, otherBuilder: otherBuilder)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_4291DD537A0A5962 {}
			}

			extension Other {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let hostBuilder_Sendable: @Sendable () -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>

			        public init(hostBuilder_Sendable: @escaping @Sendable () -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>) {
			            self.hostBuilder_Sendable = hostBuilder_Sendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(hostBuilder_Sendable: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session: @autoclosure @escaping @Sendable () -> Session, __safeDI_gadgetSendableBuilder: __safeDI_GadgetSendableCarrier<any Gadget>) {
			        let session = SendableLazilyInstantiated<Session>(__safeDI_session)
			        @Sendable nonisolated func __safeDI_hostBuilder() -> Host {
			            _ = Host.__safeDI_Host_4291DD537A0A5962.self
			            return Host(__safeDI_session: session.instance, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder.hostBuilder_Sendable())
			        }
			        let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
			        self.init(hostBuilder: hostBuilder)
			    }
			}

			extension Other {
			    public enum __safeDI_Other_18A1B77BC02A5E93 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenOnlyThatFillMakesBuilderSendable() async throws {
		// The call of `Host` inside the fill is in a plain `Instantiator`, so only the fill's own `@Sendable` function makes
		// the builder `@Sendable`, and `gadget` is staged there.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetConformances: "Instantiable, Widget, @unchecked Sendable",
			widgetDeclarations: ["@Received let analytics: Analytics", "@Instantiated let gadget: any Gadget", "@Instantiated let hostBuilder: Instantiator<Host>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {
			                public let hostBuilder: Instantiator<Host>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			        nonisolated public struct shell_widgetSendableBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct hostBuilder_Sendable_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let hostBuilder_Sendable: @Sendable (hostBuilder_Sendable_Values) -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>

			                public init(hostBuilder_Sendable: @escaping @Sendable (hostBuilder_Sendable_Values) -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>) {
			                    self.hostBuilder_Sendable = hostBuilder_Sendable
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(hostBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let shell_widgetSendableBuilder_Sendable: @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>, shell_widgetSendableBuilder_Sendable: @escaping @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			                self.shell_widgetSendableBuilder_Sendable = shell_widgetSendableBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, shell_widgetSendableBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder_Sendable(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Sendable_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                let analytics = scope_analytics
			                func __safeDI_widget() -> DefaultWidget {
			                    func __safeDI_hostBuilder() -> Host {
			                        _ = Host.__safeDI_Host_2A6BC3CCAE6E5EE1.self
			                        return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable.hostBuilder_Sendable(SafeDISendableScope_Gadget.DefaultWidget_Scope.hostBuilder_Sendable_Values()))
			                    }
			                    let hostBuilder = Instantiator<Host>(__safeDI_hostBuilder)
			                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(hostBuilder: hostBuilder))
			                    return DefaultWidget(analytics: analytics, gadget: gadget, hostBuilder: hostBuilder)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_2A6BC3CCAE6E5EE1 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesDeferredParameterSendable_whenCallInSendableBuilderFunctionInsideFillReentersSeam() async throws {
		// `gadget`'s first stage reads `user`, `Host`'s deferred parameter, before the fill, but the call of `Host` in the
		// `SendableInstantiator` inside the fill reads it inside a `@Sendable` function, which needs a `@Sendable` autoclosure.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let gadget: any Gadget", "@Instantiated let hostBuilder: SendableInstantiator<Host>"],
			middleTypes: [seamFixtureType(named: "User", declarations: [], conformances: ", Sendable"), seamFixtureType(named: "Account", declarations: ["@Received let user: User"], conformances: ", Sendable")],
			hostDeclarations: ["@Instantiated let account: Account", FillRoute.sendableByRoute.hostDeclaration],
			gadgetDeclarations: ["@Received let user: User"],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let session: Session", "@Instantiated let user: SendableLazilyInstantiated<User>", "@Instantiated let host: Host"]),
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {
			                public let hostBuilder: SendableInstantiator<Host>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			        nonisolated public struct shell_widgetSendableBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct hostBuilder_Sendable_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let hostBuilder_Sendable: @Sendable (hostBuilder_Sendable_Values) -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>

			                public init(hostBuilder_Sendable: @escaping @Sendable (hostBuilder_Sendable_Values) -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>) {
			                    self.hostBuilder_Sendable = hostBuilder_Sendable
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(hostBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let shell_widgetSendableBuilder_Sendable: @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>, shell_widgetSendableBuilder_Sendable: @escaping @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			                self.shell_widgetSendableBuilder_Sendable = shell_widgetSendableBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, shell_widgetSendableBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let user = SendableLazilyInstantiated<User>(__safeDI_user)
			        let account = Account(user: user.instance)
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder_Sendable(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Sendable_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    @Sendable nonisolated func __safeDI_hostBuilder() -> Host {
			                        _ = Host.__safeDI_Host_A2BF3A9AF8958F6D.self
			                        return Host(__safeDI_user: user.instance, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable.hostBuilder_Sendable(SafeDISendableScope_Gadget.DefaultWidget_Scope.hostBuilder_Sendable_Values()))
			                    }
			                    let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
			                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(hostBuilder: hostBuilder))
			                    return DefaultWidget(gadget: gadget, hostBuilder: hostBuilder)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(account: account, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_A2BF3A9AF8958F6D {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: The reason a capture in a fill gives

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingFillIsPassedOn_whenFillMadeSendableByAnotherFillCapturesWrapper() async {
		// `Top` takes `firstBuilder` `@Sendable`, so its fill is `@Sendable`. That fill passes the fill of `second` to `SubB`,
		// whose tree has no `@Sendable` function, so the fill of `second` is `@Sendable` only because the first refers to it.
		let feature = [
			"public protocol First: Sendable {}",
			"public protocol Second: Sendable {}",
			seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let first: any First"], conformances: ", Sendable"),
			seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let second: any Second"], conformances: ", Sendable"),
			seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subABuilder: SendableInstantiator<SubA>", "@Instantiated let subB: SubB"]),
		]
		let app = [
			seamFixtureType(named: "Leaf", declarations: []),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultFirst", fulfilling: "First", declarations: ["@Instantiated let subB: SubB"]),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultSecond", fulfilling: "Second", declarations: ["@Received let leafBuilder: Instantiator<Leaf>"])
				.replacingOccurrences(of: "Instantiable, Second", with: "Instantiable, Second, @unchecked Sendable"),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>", "@Instantiated let top: Top"]),
		]
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultSecond.swift"]):9:5: error: @Received property `leafBuilder: Instantiator<Leaf>` cannot be received inside a `@Sendable` function in chain: Root -> Top -> DefaultSecond. The function SafeDI generates to fill the builder for `second: any Second` on `SubB` is passed to the initializer SafeDI generates for a type with `generateDependencyTree: true` from inside a `@Sendable` function, or to one that takes it `@Sendable`, so it is `@Sendable` too, and it cannot capture `leafBuilder: Instantiator<Leaf>` on `Root`, because `Instantiator<Leaf>` is not `Sendable`. Declare `leafBuilder` on `Root`, and this property, as `SendableInstantiator<Leaf>` to fix. `SendableInstantiator<Leaf>` builds `Leaf` in a `@Sendable` function, so what the tree of `Leaf` receives from outside that function must be `Sendable` too.
			\(fixtures["App"]!["Root.swift"]):10:5: note: `leafBuilder: Instantiator<Leaf>` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A `@Sendable` fill beneath a `@Sendable` builder function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenSendableFillIsBeneathSendableBuilderFunction() async throws {
		// `shellMaker` builds in a `@Sendable` function and the fill inside it is one too, so `gadgetBuilder` has a stage for
		// each. Nothing is bound between them, but how many stages a builder has follows only from the functions on the
		// path, so that binding a value between them never adds a closure to what a caller writes.
		let fixture = Self.fixtureOfSendableFillWithPlace(hostDeclarations: ["@Received let session: Session", "@Instantiated let shellMaker: SendableInstantiator<Shell>"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shellMaker_widgetSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shellMaker_widgetSendableBuilder: @Sendable (shellMaker_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(shellMaker_widgetSendableBuilder: @escaping @Sendable (shellMaker_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.shellMaker_widgetSendableBuilder = shellMaker_widgetSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shellMaker_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        @Sendable nonisolated func __safeDI_shellMaker() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shellMaker_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shellMaker_widgetSendableBuilder(SafeDISendableScope_Gadget.shellMaker_widgetSendableBuilder_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shellMaker_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                let analytics = scope_analytics
			                func __safeDI_widget() -> DefaultWidget {
			                    let gadget: any Gadget = __safeDI_shellMaker_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                    return DefaultWidget(analytics: analytics, gadget: gadget)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shellMaker_widgetSendableBuilder: up.widget(scope_analytics)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shellMaker_widgetSendableBuilder))
			        }
			        let shellMaker = SendableInstantiator<Shell>(__safeDI_shellMaker)
			        self.init(session: session, shellMaker: shellMaker)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_8681706BAA0BE57C {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_8681706BAA0BE57C.self\(seamCallComment(seam: "Host", module: "Middle"))
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(shellMaker_widgetSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_Shell() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: Analytics) -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
			                .init(gadget: { _ in
			                    let gadget: any Gadget = DefaultGadget(session: session, analytics: analytics)
			                    return gadget
			                })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Shell() -> Shell.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
			                .init(innerBuilder: { __safeDI_gadgetBuilder_Host_Inner() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner() -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
			                .init(widget: { values_analytics in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope(analytics: values_analytics) })
			            }
			            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(session: session, host: host)
			    }
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesFieldBoundInsideSendableFill_whenSendableFillIsBeneathSendableBuilderFunction() async throws {
		// `bag` is not `Sendable` and is bound between `holderMaker`'s function and the fill, so only a stage called before
		// the fill can hand it over.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let gadget: any Gadget"],
			middleTypes: [
				seamFixtureType(named: "Bag", declarations: [], conformances: ""),
				seamFixtureType(named: "ShellHolder", declarations: ["@Instantiated let bag: Bag", "@Instantiated let shell: Shell"], conformances: ", @unchecked Sendable"),
			],
			hostDeclarations: ["@Instantiated let holderMaker: SendableInstantiator<ShellHolder>"],
			gadgetDeclarations: [],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct holderMaker_Sendable_Values: Sendable {}

			        nonisolated public enum ShellHolder_Scope {
			            nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

			                public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                    self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let holderMaker_Sendable: @Sendable (holderMaker_Sendable_Values) -> SafeDISendableScope_Gadget.ShellHolder_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(holderMaker_Sendable: @escaping @Sendable (holderMaker_Sendable_Values) -> SafeDISendableScope_Gadget.ShellHolder_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.holderMaker_Sendable = holderMaker_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(holderMaker_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        @Sendable nonisolated func __safeDI_holderMaker() -> ShellHolder {
			            let __safeDI_gadgetSendableBuilder_holderMaker_Sendable = __safeDI_gadgetSendableBuilder.holderMaker_Sendable(SafeDISendableScope_Gadget.holderMaker_Sendable_Values())
			            let bag = Bag()
			            func __safeDI_shell() -> Shell {
			                let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder_holderMaker_Sendable.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.ShellHolder_Scope.shell_widgetSendableBuilder_Values())
			                _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			                @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                    func __safeDI_widget() -> DefaultWidget {
			                        let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                        return DefaultWidget(gadget: gadget)
			                    }
			                    let widget: any Widget = __safeDI_widget()
			                    return widget
			                }
			                @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                    .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			                }
			                @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                    .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
			                }
			                return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			            }
			            let shell: Shell = __safeDI_shell()
			            return ShellHolder(bag: bag, shell: shell)
			        }
			        let holderMaker = SendableInstantiator<ShellHolder>(__safeDI_holderMaker)
			        self.init(holderMaker: holderMaker)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_0753AB21FCAF5191 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCase_whenBuilderIsSendableAndFieldIsNonSendableWrapper() async throws {
		// A call of `Host` in a `SendableInstantiator` inside the fill makes `gadgetBuilder` `@Sendable`, but the fill still
		// cannot capture `itemMaker`, so the first stage is called before it.
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let gadget: any Gadget", "@Instantiated let hostBuilder: SendableInstantiator<Host>"],
			middleTypes: [seamFixtureType(named: "Item", declarations: [], conformances: "")],
			hostDeclarations: ["@Instantiated let itemMaker: Instantiator<Item>", FillRoute.sendableByRoute.hostDeclaration],
			hostConformances: ", @unchecked Sendable",
			gadgetDeclarations: [],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {
			                public let hostBuilder: SendableInstantiator<Host>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			        nonisolated public struct shell_widgetSendableBuilder_Sendable_Values: Sendable {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct hostBuilder_Sendable_Values: Sendable {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			                public let hostBuilder_Sendable: @Sendable (hostBuilder_Sendable_Values) -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>

			                public init(hostBuilder_Sendable: @escaping @Sendable (hostBuilder_Sendable_Values) -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<__safeDI_Built>) {
			                    self.hostBuilder_Sendable = hostBuilder_Sendable
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                    self.init(hostBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>
			            public let shell_widgetSendableBuilder_Sendable: @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>

			            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>, shell_widgetSendableBuilder_Sendable: @escaping @Sendable (shell_widgetSendableBuilder_Sendable_Values) -> SafeDISendableScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>) {
			                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			                self.shell_widgetSendableBuilder_Sendable = shell_widgetSendableBuilder_Sendable
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }, shell_widgetSendableBuilder_Sendable: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_itemMaker() -> Item {
			            Item()
			        }
			        let itemMaker = Instantiator<Item>(__safeDI_itemMaker)
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder_Sendable(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Sendable_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    @Sendable nonisolated func __safeDI_hostBuilder() -> Host {
			                        _ = Host.__safeDI_Host_163AE1FD796934CA.self
			                        return Host(__safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder_Sendable.hostBuilder_Sendable(SafeDISendableScope_Gadget.DefaultWidget_Scope.hostBuilder_Sendable_Values()))
			                    }
			                    let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
			                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(hostBuilder: hostBuilder))
			                    return DefaultWidget(gadget: gadget, hostBuilder: hostBuilder)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(itemMaker: itemMaker, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_163AE1FD796934CA {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: Two sites of one label and type in the seam a fill fills

	/// `Feature`'s `Inner` builds `a: A` and `b: B`, each of which instantiates `widget: any Widget`, a hole, and `alpha` or
	/// `beta` beside it. `Host` calls `Inner`, or `Shell`, which builds `Inner` in a `SendableInstantiator`, and fills both
	/// holes with `DefaultWidget`, which builds `gadget`, a place of `Host`.
	private static func fixtureOfTwoSitesOfOneLabel(throughShell: Bool) -> ThreeModules {
		ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Alpha", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Beta", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "A", declarations: ["@Instantiated let alpha: Alpha", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "B", declarations: ["@Instantiated let beta: Beta", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let a: A", "@Instantiated let b: B"], conformances: ", Sendable"),
				seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>"], conformances: ", Sendable"),
			],
			middle: [
				gadget,
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: [throughShell ? "@Instantiated let shell: Shell" : "@Instantiated let inner: Inner"], conformances: ", Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])],
			root: root,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderForPlaceInsideEachFill_whenFilledSeamHasTwoSitesOfOneLabelAndType() async throws {
		// The fills of `a`'s and `b`'s `widget` are different functions with different fields, so `gadget` is two places.
		let fixture = Self.fixtureOfTwoSitesOfOneLabel(throughShell: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_widgetBuilder_Values {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let inner_widgetBuilder: (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_widgetBuilder: @escaping (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_widgetBuilder = inner_widgetBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_widgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_widgetBuilder = __safeDI_gadgetBuilder.inner_widgetBuilder(SafeDIScope_Gadget.inner_widgetBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_2788B70329D6DF6A.self\(seamCallComment(seam: "Inner", module: "Feature"))
			            func __safeDI_widgetBuilder_Inner_A_Scope_widget(_ scope_alpha: Alpha, __safeDI_inner_widgetBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    let gadget: any Gadget = __safeDI_inner_widgetBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                    return DefaultWidget(gadget: gadget)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            func __safeDI_widgetBuilder_Inner_B_Scope_widget(_ scope_beta: Beta, __safeDI_inner_widgetBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    let gadget: any Gadget = __safeDI_inner_widgetBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                    return DefaultWidget(gadget: gadget)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(a: __safeDI_widgetBuilder_Inner_A_Scope(up: up.a), b: { values_a in __safeDI_widgetBuilder_Inner_B_Scope(up: up.b(values_a)) })
			            }
			            func __safeDI_widgetBuilder_Inner_A_Scope(up: Inner.__safeDI_WidgetCarrier_A<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier_A<any Widget> {
			                .init(widget: { scope_alpha in __safeDI_widgetBuilder_Inner_A_Scope_widget(scope_alpha, __safeDI_inner_widgetBuilder: up.widget(scope_alpha)) })
			            }
			            func __safeDI_widgetBuilder_Inner_B_Scope(up: Inner.__safeDI_WidgetCarrier_B<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier_B<any Widget> {
			                .init(widget: { scope_beta in __safeDI_widgetBuilder_Inner_B_Scope_widget(scope_beta, __safeDI_inner_widgetBuilder: up.widget(scope_beta)) })
			            }
			            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner(up: __safeDI_gadgetBuilder_inner_widgetBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_271C991E68090D75 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableCaseForPlaceInsideEachFill_whenFilledSeamHasTwoSitesOfOneLabelAndTypeOnSendableRoute() async throws {
		let fixture = Self.fixtureOfTwoSitesOfOneLabel(throughShell: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
			            _ = Shell.__safeDI_Shell_D7C83D2C944372B2.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_A_Inner_A_Scope_widget(_ scope_alpha: Alpha, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                    return DefaultWidget(gadget: gadget)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_B_Inner_B_Scope_widget(_ scope_beta: Beta, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                    return DefaultWidget(gadget: gadget)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(a: __safeDI_widgetBuilder_Inner_A_Scope(up: up.a), b: { values_a in __safeDI_widgetBuilder_Inner_B_Scope(up: up.b(values_a)) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_A_Scope(up: Inner.__safeDI_WidgetCarrier_A<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier_A<any Widget> {
			                .init(widget: { scope_alpha in __safeDI_widgetBuilder_A_Inner_A_Scope_widget(scope_alpha, __safeDI_shell_widgetSendableBuilder: up.widget(scope_alpha)) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_B_Scope(up: Inner.__safeDI_WidgetCarrier_B<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier_B<any Widget> {
			                .init(widget: { scope_beta in __safeDI_widgetBuilder_B_Inner_B_Scope_widget(scope_beta, __safeDI_shell_widgetSendableBuilder: up.widget(scope_beta)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_010D0518E6A34BD1 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderForPlaceInsideEachFill_whenCalledSeamPassesUpSitesOfTwoSeamsWithOnePath() async throws {
		// `Top` passes up `SubA`'s and `SubB`'s `widget`, whose paths are the same in the seam that holds each.
		let fixture = ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Alpha", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Beta", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "SubA", isSeam: true, declarations: ["@Instantiated let alpha: Alpha", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "SubB", isSeam: true, declarations: ["@Instantiated let beta: Beta", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let subA: SubA", "@Instantiated let subB: SubB"], conformances: ", Sendable"),
			],
			middle: [
				Self.gadget,
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let top: Top"], conformances: ", Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: [])],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct top_widgetBuilder_Values {}

			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let top_widgetBuilder: (top_widgetBuilder_Values) -> Top.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(top_widgetBuilder: @escaping (top_widgetBuilder_Values) -> Top.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.top_widgetBuilder = top_widgetBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(top_widgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_top_widgetBuilder = __safeDI_gadgetBuilder.top_widgetBuilder(SafeDIScope_Gadget.top_widgetBuilder_Values())
			        func __safeDI_top() -> Top {
			            _ = Top.__safeDI_Top_BED1CDF2933E5930.self\(seamCallComment(seam: "Top", module: "Feature"))
			            func __safeDI_widgetBuilder_SubA_SubA_widget(_ scope_alpha: Alpha, __safeDI_top_widgetBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    let gadget: any Gadget = __safeDI_top_widgetBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                    return DefaultWidget(gadget: gadget)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            func __safeDI_widgetBuilder_SubB_SubB_widget(_ scope_beta: Beta, __safeDI_top_widgetBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    let gadget: any Gadget = __safeDI_top_widgetBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values())
			                    return DefaultWidget(gadget: gadget)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            func __safeDI_widgetBuilder_Top(up: Top.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Top.__safeDI_WidgetCarrier<any Widget> {
			                .init(subA: __safeDI_widgetBuilder_SubA(up: up.subA), subB: __safeDI_widgetBuilder_SubB(up: up.subB))
			            }
			            func __safeDI_widgetBuilder_SubA(up: SubA.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> SubA.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_alpha in __safeDI_widgetBuilder_SubA_SubA_widget(scope_alpha, __safeDI_top_widgetBuilder: up.widget(scope_alpha)) })
			            }
			            func __safeDI_widgetBuilder_SubB(up: SubB.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> SubB.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_beta in __safeDI_widgetBuilder_SubB_SubB_widget(scope_beta, __safeDI_top_widgetBuilder: up.widget(scope_beta)) })
			            }
			            return Top(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Top(up: __safeDI_gadgetBuilder_top_widgetBuilder))
			        }
			        let top: Top = __safeDI_top()
			        self.init(top: top)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_86C19AA6087C84F8 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: The reason a one-stage fill is `@Sendable`

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingFillIsPassedOn_whenFillIsSendableBecauseCalledSeamBuildsSeamInSendableFunction() async {
		// `Shell` builds `Inner` in a `SendableInstantiator`, and so takes `widgetBuilder` `@Sendable`. `Inner`'s own tree
		// builds `widget` in plain code.
		let app = [
			seamFixtureType(named: "Leaf", declarations: [], conformances: ""),
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let leafBuilder: Instantiator<Leaf>"])
				.replacingOccurrences(of: "Instantiable, Widget", with: "Instantiable, Widget, @unchecked Sendable"),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>", "@Instantiated let shell: Shell"]),
		]
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultWidget.swift"]):9:5: error: @Received property `leafBuilder: Instantiator<Leaf>` cannot be received inside a `@Sendable` function in chain: Root -> Shell -> DefaultWidget. The function SafeDI generates to fill the builder for `widget: any Widget` on `Inner` is passed to the initializer SafeDI generates for a type with `generateDependencyTree: true` from inside a `@Sendable` function, or to one that takes it `@Sendable`, so it is `@Sendable` too, and it cannot capture `leafBuilder: Instantiator<Leaf>` on `Root`, because `Instantiator<Leaf>` is not `Sendable`. Declare `leafBuilder` on `Root`, and this property, as `SendableInstantiator<Leaf>` to fix. `SendableInstantiator<Leaf>` builds `Leaf` in a `@Sendable` function, so what the tree of `Leaf` receives from outside that function must be `Sendable` too.
			\(fixtures["App"]!["Root.swift"]):10:5: note: `leafBuilder: Instantiator<Leaf>` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(feature: FillRoute.sendableByRoute.featureTypes, app: app),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A stage's name, and a generic argument of an enclosing type

	// MARK: A field a site carries beneath a nearer declaration of its label

	/// The `DefaultWidget` and `Holder` shapes that declare `analytics` nearer a place than the field of the fill's struct.
	enum NearerDeclaration: CaseIterable, CustomTestStringConvertible {
		/// `DefaultWidget` instantiates `analytics` beside `gadget`.
		case besideThePlace
		/// `DefaultWidget` instantiates `analytics` beside `holder`, which builds `gadget`.
		case aboveTheOwnerOfThePlace
		/// `holderMaker: Instantiator<Holder>` is handed `analytics`, and `Holder` builds `gadget`.
		case forwardedToTheOwnerOfThePlace

		var testDescription: String {
			switch self {
			case .besideThePlace:
				"besideThePlace"
			case .aboveTheOwnerOfThePlace:
				"aboveTheOwnerOfThePlace"
			case .forwardedToTheOwnerOfThePlace:
				"forwardedToTheOwnerOfThePlace"
			}
		}

		var widgetDeclarations: [String] {
			switch self {
			case .besideThePlace:
				["@Instantiated let analytics: Analytics", "@Instantiated let gadget: any Gadget"]
			case .aboveTheOwnerOfThePlace:
				["@Instantiated let analytics: Analytics", "@Instantiated let holder: Holder"]
			case .forwardedToTheOwnerOfThePlace:
				["@Instantiated let holderMaker: Instantiator<Holder>"]
			}
		}

		var middleTypes: [String] {
			switch self {
			case .besideThePlace:
				[]
			case .aboveTheOwnerOfThePlace:
				[seamFixtureType(named: "Holder", declarations: ["@Instantiated let gadget: any Gadget"], conformances: ", Sendable")]
			case .forwardedToTheOwnerOfThePlace:
				[seamFixtureType(named: "Holder", declarations: ["@Forwarded let analytics: Analytics", "@Instantiated let gadget: any Gadget"], conformances: ", Sendable")]
			}
		}
	}

	@Test(arguments: NearerDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotBindCarriedField_whenFulfillerDeclaresItsLabelNearerThePlace(nearerDeclaration: NearerDeclaration) async throws {
		// The place's struct carries `analytics`, as `DefaultWidget`'s tree binds it, so the fill must not bind the field of
		// its own struct with that label, which nothing would read.
		let fixture = Self.fixture(
			route: .plain,
			middleTypes: nearerDeclaration.middleTypes,
			widgetDeclarations: nearerDeclaration.widgetDeclarations,
			appTypes: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let analytics: Analytics"])],
			widgetConformances: "Instantiable, Widget, @unchecked Sendable",
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		switch nearerDeclaration {
		case .besideThePlace:
			expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
				"Middle.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Host {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public struct inner_widgetBuilder_Values {
				            public let session: Session
				        }

				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct gadget_Values {
				                public let analytics: Analytics
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner_widgetBuilder: (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_widgetBuilder: @escaping (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_widgetBuilder = inner_widgetBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(inner_widgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let __safeDI_gadgetBuilder_inner_widgetBuilder = __safeDI_gadgetBuilder.inner_widgetBuilder(SafeDIScope_Gadget.inner_widgetBuilder_Values(session: session))
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_EA4DE2878D50CCB8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_inner_widgetBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
				                func __safeDI_widget() -> DefaultWidget {
				                    let analytics = Analytics()
				                    let gadget: any Gadget = __safeDI_inner_widgetBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(analytics: analytics))
				                    return DefaultWidget(analytics: analytics, gadget: gadget)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
				                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_inner_widgetBuilder: up.widget(scope_analytics)) })
				            }
				            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner(up: __safeDI_gadgetBuilder_inner_widgetBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_49C6B79B16311EE2 {}
				}
				""",
			])
		case .aboveTheOwnerOfThePlace:
			expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
				"Middle.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Host {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public struct inner_widgetBuilder_Values {
				            public let session: Session
				        }

				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct holder_Values {
				                public let analytics: Analytics
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let holder: (holder_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>

				                public init(holder: @escaping (holder_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>) {
				                    self.holder = holder
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(holder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				                }
				            }
				        }

				        nonisolated public enum Holder_Scope {
				            nonisolated public struct gadget_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner_widgetBuilder: (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_widgetBuilder: @escaping (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_widgetBuilder = inner_widgetBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(inner_widgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let __safeDI_gadgetBuilder_inner_widgetBuilder = __safeDI_gadgetBuilder.inner_widgetBuilder(SafeDIScope_Gadget.inner_widgetBuilder_Values(session: session))
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_EA4DE2878D50CCB8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_inner_widgetBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
				                func __safeDI_widget() -> DefaultWidget {
				                    let analytics = Analytics()
				                    let __safeDI_gadgetBuilder_holder = __safeDI_inner_widgetBuilder.holder(SafeDIScope_Gadget.DefaultWidget_Scope.holder_Values(analytics: analytics))
				                    func __safeDI_holder() -> Holder {
				                        let gadget: any Gadget = __safeDI_gadgetBuilder_holder.gadget(SafeDIScope_Gadget.Holder_Scope.gadget_Values())
				                        return Holder(gadget: gadget)
				                    }
				                    let holder: Holder = __safeDI_holder()
				                    return DefaultWidget(analytics: analytics, holder: holder)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
				                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_inner_widgetBuilder: up.widget(scope_analytics)) })
				            }
				            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner(up: __safeDI_gadgetBuilder_inner_widgetBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_CF6CF8597857B3D8 {}
				}
				""",
			])
		case .forwardedToTheOwnerOfThePlace:
			expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
				"Middle.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Host {
				    nonisolated public enum SafeDIScope_Gadget {
				        nonisolated public struct inner_widgetBuilder_Values {
				            public let session: Session
				        }

				        nonisolated public enum DefaultWidget_Scope {
				            nonisolated public struct holderMaker_Values {}

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let holderMaker: (holderMaker_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>

				                public init(holderMaker: @escaping (holderMaker_Values) -> SafeDIScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>) {
				                    self.holderMaker = holderMaker
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(holderMaker: { _ in .init(__safeDI_noScope: __safeDI_builder) })
				                }
				            }
				        }

				        nonisolated public enum Holder_Scope {
				            nonisolated public struct gadget_Values {
				                public let analytics: Analytics
				            }

				            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				                public let gadget: (gadget_Values) -> __safeDI_Built

				                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
				                    self.gadget = gadget
				                }

				                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                    self.init(gadget: { _ in __safeDI_builder() })
				                }
				            }
				        }

				        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
				        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
				            public let inner_widgetBuilder: (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

				            public init(inner_widgetBuilder: @escaping (inner_widgetBuilder_Values) -> Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
				                self.inner_widgetBuilder = inner_widgetBuilder
				            }

				            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
				                self.init(inner_widgetBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
				            }
				        }
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
				    public init(__safeDI_session session: Session, __safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
				        let __safeDI_gadgetBuilder_inner_widgetBuilder = __safeDI_gadgetBuilder.inner_widgetBuilder(SafeDIScope_Gadget.inner_widgetBuilder_Values(session: session))
				        func __safeDI_inner() -> Inner {
				            _ = Inner.__safeDI_Inner_EA4DE2878D50CCB8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_inner_widgetBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
				                func __safeDI_widget() -> DefaultWidget {
				                    let __safeDI_gadgetBuilder_holderMaker = __safeDI_inner_widgetBuilder.holderMaker(SafeDIScope_Gadget.DefaultWidget_Scope.holderMaker_Values())
				                    func __safeDI_holderMaker(analytics: Analytics) -> Holder {
				                        let gadget: any Gadget = __safeDI_gadgetBuilder_holderMaker.gadget(SafeDIScope_Gadget.Holder_Scope.gadget_Values(analytics: analytics))
				                        return Holder(analytics: analytics, gadget: gadget)
				                    }
				                    let holderMaker = Instantiator<Holder> {
				                        __safeDI_holderMaker(analytics: $0)
				                    }
				                    return DefaultWidget(holderMaker: holderMaker)
				                }
				                let widget: any Widget = __safeDI_widget()
				                return widget
				            }
				            func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
				                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_inner_widgetBuilder: up.widget(scope_analytics)) })
				            }
				            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner(up: __safeDI_gadgetBuilder_inner_widgetBuilder))
				        }
				        let inner: Inner = __safeDI_inner()
				        self.init(session: session, inner: inner)
				    }
				}

				extension Host {
				    public enum __safeDI_Host_E64F18BC24025FB8 {}
				}
				""",
			])
		}
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotBindCarriedField_whenFulfillerDeclaresItsLabelNearerThePlaceInSendableFill() async throws {
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let analytics: Analytics", "@Instantiated let gadget: any Gadget"],
			gadgetDeclarations: ["@Received let analytics: Analytics"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct gadget_Values {
			                public let analytics: Analytics
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    let analytics = Analytics()
			                    let gadget: any Gadget = __safeDI_shell_widgetSendableBuilder.gadget(SafeDIScope_Gadget.DefaultWidget_Scope.gadget_Values(analytics: analytics))
			                    return DefaultWidget(analytics: analytics, gadget: gadget)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_99CCC39442B38529 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: Raw-identifier labels in the names of stages

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsSendableCaseAsIdentifier_whenPlaceInSendableFillHasRawIdentifierLabel() async throws {
		let fixture = Self.fixtureOfSendableFillWithPlace(
			widgetDeclarations: ["@Instantiated let `my gadget`: any Gadget"],
			gadgetDeclarations: ["@Received let session: Session"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public enum DefaultWidget_Scope {
			            nonisolated public struct `my gadget_Values` {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let `my gadget`: (`my gadget_Values`) -> __safeDI_Built

			                public init(`my gadget`: @escaping (`my gadget_Values`) -> __safeDI_Built) {
			                    self.`my gadget` = `my gadget`
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(`my gadget`: { _ in __safeDI_builder() })
			                }
			            }
			        }
			    }

			    nonisolated public enum SafeDISendableScope_Gadget {
			        nonisolated public struct shell_widgetSendableBuilder_Values: Sendable {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
			            public let shell_widgetSendableBuilder: @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(shell_widgetSendableBuilder: @escaping @Sendable (shell_widgetSendableBuilder_Values) -> Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.shell_widgetSendableBuilder = shell_widgetSendableBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			                self.init(shell_widgetSendableBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget>) {
			        func __safeDI_shell() -> Shell {
			            let __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder = __safeDI_gadgetSendableBuilder.shell_widgetSendableBuilder(SafeDISendableScope_Gadget.shell_widgetSendableBuilder_Values())
			            _ = Shell.__safeDI_Shell_B70E55C1014F1064.self\(seamCallComment(seam: "Shell", module: "Feature"))
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner_widget(_ scope_analytics: Analytics, __safeDI_shell_widgetSendableBuilder: SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>) -> any Widget {
			                func __safeDI_widget() -> DefaultWidget {
			                    let `my gadget`: any Gadget = __safeDI_shell_widgetSendableBuilder.`my gadget`(SafeDIScope_Gadget.DefaultWidget_Scope.`my gadget_Values`())
			                    return DefaultWidget(`my gadget`: `my gadget`)
			                }
			                let widget: any Widget = __safeDI_widget()
			                return widget
			            }
			            @Sendable nonisolated func __safeDI_widgetSendableBuilder_Shell(up: Shell.__safeDI_WidgetSendableCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Shell.__safeDI_WidgetSendableCarrier<any Widget> {
			                .init(innerBuilder: { __safeDI_widgetBuilder_Inner(up: up.innerBuilder()) })
			            }
			            @Sendable nonisolated func __safeDI_widgetBuilder_Inner(up: Inner.__safeDI_WidgetCarrier<SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_analytics, __safeDI_shell_widgetSendableBuilder: up.widget(scope_analytics)) })
			            }
			            return Shell(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Shell(up: __safeDI_gadgetSendableBuilder_shell_widgetSendableBuilder))
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(session: session, shell: shell)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_F50E374312E95A32 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_F50E374312E95A32.self\(seamCallComment(seam: "Host", module: "Middle"))
			            @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Host() -> Host.SafeDISendableScope_Gadget.__safeDI_Builder<any Gadget> {
			                .init(shell_widgetSendableBuilder: { _ in __safeDI_gadgetBuilder_Host_Shell() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_DefaultWidget_Scope() -> Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget> {
			                .init(`my gadget`: { _ in
			                    let `my gadget`: any Gadget = DefaultGadget(session: session)
			                    return `my gadget`
			                })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Shell() -> Shell.__safeDI_WidgetSendableCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
			                .init(innerBuilder: { __safeDI_gadgetBuilder_Host_Inner() })
			            }
			            @Sendable nonisolated func __safeDI_gadgetBuilder_Host_Inner() -> Inner.__safeDI_WidgetCarrier<Host.SafeDIScope_Gadget.DefaultWidget_Scope.__safeDI_Builder<any Gadget>> {
			                .init(widget: { values_analytics in __safeDI_gadgetBuilder_Host_DefaultWidget_Scope() })
			            }
			            return Host(__safeDI_session: session, __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Host())
			        }
			        let host: Host = __safeDI_host()
			        self.init(session: session, host: host)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsSendableCaseAsIdentifier_whenPlaceBeneathSendableBuilderFunctionHasRawIdentifierLabel() async throws {
		let fixture = ThreeModules(
			feature: ["public protocol Widget: Sendable {}"],
			middle: [
				Self.gadget,
				Self.session,
				seamFixtureType(named: "Holder", declarations: ["@Instantiated let `my gadget`: any Gadget"], conformances: ", Sendable"),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Received let session: Session", "@Instantiated let holderMaker: SendableInstantiator<Holder>"], conformances: ", Sendable"),
			],
			app: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let session: Session"])],
			root: Self.rootWithSession,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetCarrier_Holder<__safeDI_Built> {
			        public let `my gadget`: () -> __safeDI_Built

			        public init(`my gadget`: @escaping () -> __safeDI_Built) {
			            self.`my gadget` = `my gadget`
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(`my gadget`: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let holderMaker: @Sendable () -> __safeDI_GadgetCarrier_Holder<__safeDI_Built>

			        public init(holderMaker: @escaping @Sendable () -> __safeDI_GadgetCarrier_Holder<__safeDI_Built>) {
			            self.holderMaker = holderMaker
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(holderMaker: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_session session: Session, __safeDI_gadgetSendableBuilder: __safeDI_GadgetSendableCarrier<any Gadget>) {
			        @Sendable nonisolated func __safeDI_holderMaker() -> Holder {
			            let __safeDI_gadgetSendableBuilder_holderMaker = __safeDI_gadgetSendableBuilder.holderMaker()
			            let `my gadget`: any Gadget = __safeDI_gadgetSendableBuilder_holderMaker.`my gadget`()
			            return Holder(`my gadget`: `my gadget`)
			        }
			        let holderMaker = SendableInstantiator<Holder>(__safeDI_holderMaker)
			        self.init(session: session, holderMaker: holderMaker)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_E94ABF99CF4719C0 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsFillAsIdentifier_whenSendableFilledHoleHasRawIdentifierLabel() async throws {
		let fixture = ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let `my widget`: any Widget"], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let panelBuilder: SendableInstantiator<Panel>"], conformances: ", Sendable"),
			],
			middle: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: []),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let inner: Inner"], conformances: ", Sendable"),
			],
			app: [],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_WidgetCarrier_Panel<__safeDI_Built> {
		        public let `my widget`: () -> __safeDI_Built

		        public init(`my widget`: @escaping () -> __safeDI_Built) {
		            self.`my widget` = `my widget`
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(`my widget`: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_WidgetSendableCarrier<__safeDI_Built>: Sendable {
		        public let panelBuilder: @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>

		        public init(panelBuilder: @escaping @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>) {
		            self.panelBuilder = panelBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(panelBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_widgetSendableBuilder: __safeDI_WidgetSendableCarrier<any Widget>) {
		        let analytics = Analytics()
		        @Sendable nonisolated func __safeDI_panelBuilder() -> Panel {
		            let __safeDI_widgetSendableBuilder_panelBuilder = __safeDI_widgetSendableBuilder.panelBuilder()
		            let `my widget`: any Widget = __safeDI_widgetSendableBuilder_panelBuilder.`my widget`()
		            return Panel(`my widget`: `my widget`)
		        }
		        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
		        self.init(analytics: analytics, panelBuilder: panelBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_ECB382D43E04D2FE {}
		}
		"""])
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Inner() -> Inner.__safeDI_WidgetSendableCarrier<any Widget> {
			            .init(panelBuilder: { __safeDI_widgetBuilder_Inner_Panel_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_widgetBuilder_Inner_Panel_Scope() -> Inner.__safeDI_WidgetCarrier_Panel<any Widget> {
			            .init(`my widget`: {
			                let `my widget`: any Widget = DefaultWidget()
			                return `my widget`
			            })
			        }
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_ECB382D43E04D2FE.self\(seamCallComment(seam: "Inner", module: "Feature"))
			            return Inner(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Inner())
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_CBF29CE484222325 {}
			}
			""",
		])
	}

	// MARK: A value labeled as the fill's parameter

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillsParameterApart_whenFieldIsLabeledScope() async throws {
		let fixture = ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let scope: Analytics", "@Instantiated let analytics: Analytics", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
			],
			middle: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let scope: Analytics", "@Received let analytics: Analytics"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let inner: Inner"], conformances: ", Sendable"),
			],
			app: [],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_63280DED1B6F8D3F.self\(seamCallComment(seam: "Inner", module: "Feature"))
			            func __safeDI_widgetBuilder_Inner_widget(_ scope__scope: Analytics, _ scope__analytics: Analytics) -> any Widget {
			                let scope = scope__scope
			                let analytics = scope__analytics
			                let widget: any Widget = DefaultWidget(scope: scope, analytics: analytics)
			                return widget
			            }
			            func __safeDI_widgetBuilder_Inner() -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: { scope_scope, scope_analytics in __safeDI_widgetBuilder_Inner_widget(scope_scope, scope_analytics) })
			            }
			            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner())
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_CBF29CE484222325 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillsParameterApart_whenFulfillerReceivesValueLabeledScopeFromCallersScope() async throws {
		// The fill's parameter would hide `Host`'s `scope`, which `DefaultWidget` receives and `Inner`'s struct does not carry.
		let fixture = ThreeModules(
			feature: [
				"public protocol Widget: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let widget: any Widget"], conformances: ", Sendable"),
			],
			middle: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let scope: Analytics"]),
				seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let scope: Analytics", "@Instantiated let inner: Inner"], conformances: ", Sendable"),
			],
			app: [],
			root: Self.root,
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: fixture.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Middle.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Host {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        let scope = Analytics()
			        func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_DF0C971D70DD0421.self\(seamCallComment(seam: "Inner", module: "Feature"))
			            func __safeDI_widgetBuilder_Inner() -> Inner.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: {
			                    let widget: any Widget = DefaultWidget(scope: scope)
			                    return widget
			                })
			            }
			            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner())
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(scope: scope, inner: inner)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_CBF29CE484222325 {}
			}
			""",
		])
		try await expectValuesEqualVisibleBuild(output, fixture)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}

	/// Expects the values `output`, the run of `fixture`, builds for `Root` to equal those of the same graph in one module.
	private mutating func expectValuesEqualVisibleBuild(_ output: MultiModuleTestOutput, _ fixture: ThreeModules, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		try await expectValuesEqualVisibleBuild(output, modules: fixture.modules, visibleModules: fixture.visibleModules, sourceLocation: sourceLocation)
	}

	/// Expects the values `output`, the run of `modules`, builds for `Root` to equal those the run of `visibleModules` builds.
	private mutating func expectValuesEqualVisibleBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		visibleModules: [ModuleFixture],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
