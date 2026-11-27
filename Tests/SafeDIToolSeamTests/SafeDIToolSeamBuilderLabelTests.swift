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

/// A builder's label names what it builds alone: `<filling>Builder` where the filling type is the type the builder
/// returns, else `<filling>_<returned>Builder`, from the first place on, with `Sendable` before `Builder` in the
/// `@Sendable` family. Its enum is named by the same stem. A label equal to another parameter of its initializer takes a
/// trailing `_`, which leaves the stem and the enum alone.
struct SafeDIToolSeamBuilderLabelTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: The filling type differs from the returned type

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_labelsBuilderByFillingAndReturnedType_whenTheSeamsOwnPlaceIsFilledByAnotherType() async throws {
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.toolbar], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + Self.livePanel(receivingTheme: true),
				"import Feature\n\n" + Self.root(holding: "toolbar: Toolbar"),
				"""
				import Feature
				import SafeDI

				func handWrittenToolbar(theme: Theme) -> Toolbar {
				    Toolbar(livePanel_PanelBuilder: { title in LivePanel(title: title, theme: theme) })
				}
				""",
			], dependencies: ["Feature"]),
		])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Toolbar {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LivePanel_PanelCarrier<__safeDI_Built> {
		        public let panelBuilder: (Theme) -> ErasedInstantiator<String, __safeDI_Built>.Builder

		        public init(panelBuilder: @escaping (Theme) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.panelBuilder = panelBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(panelBuilder: { _ in __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(livePanel_PanelBuilder: @escaping ErasedInstantiator<String, any Panel>.Builder) {
		        self.init(__safeDI_livePanel_PanelBuilder: .init(__safeDI_noScope: livePanel_PanelBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_livePanel_PanelBuilder: __safeDI_LivePanel_PanelCarrier<any Panel>) {
		        let theme = Theme()
		        let panelBuilder = ErasedInstantiator<String, any Panel>(__safeDI_livePanel_PanelBuilder.panelBuilder(theme))
		        self.init(theme: theme, panelBuilder: panelBuilder)
		    }
		}

		extension Toolbar {
		    public enum __safeDI_Toolbar_7E934FE75F52C44F {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_livePanel_PanelBuilder_Toolbar_panelBuilder(theme: Theme) -> ErasedInstantiator<String, any Panel>.Builder {
		            return __safeDI_fillBody_9DB559CA6CA23750(theme: theme)
		        }
		        func __safeDI_fillBody_9DB559CA6CA23750(theme: Theme) -> ErasedInstantiator<String, any Panel>.Builder {
		            func __safeDI_panelBuilder(title: String) -> LivePanel {
		                LivePanel(title: title, theme: theme)
		            }
		            return { forwarded in __safeDI_panelBuilder(title: forwarded) }
		        }
		        func __safeDI_livePanel_PanelBuilder_Toolbar() -> Toolbar.__safeDI_LivePanel_PanelCarrier<any Panel> {
		            .init(panelBuilder: { values_theme in __safeDI_livePanel_PanelBuilder_Toolbar_panelBuilder(theme: values_theme) })
		        }
		        func __safeDI_toolbar() -> Toolbar {
		            _ = Toolbar.__safeDI_Toolbar_7E934FE75F52C44F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Toolbar(__safeDI_livePanel_PanelBuilder: __safeDI_livePanel_PanelBuilder_Toolbar())
		        }
		        let toolbar: Toolbar = __safeDI_toolbar()
		        self.init(toolbar: toolbar)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_labelsSendableBuilderByFillingAndReturnedType_whenTheSeamsOwnSendablePlaceIsFilledByAnotherType() async throws {
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.toolbar.replacingOccurrences(of: "ErasedInstantiator", with: "SendableErasedInstantiator").replacingOccurrences(of: "public protocol Panel: AnyObject {}", with: "public protocol Panel: Sendable {}")], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + Self.livePanel(receivingTheme: false),
				"import Feature\n\n" + Self.root(holding: "toolbar: Toolbar"),
				"""
				import Feature
				import SafeDI

				func handWrittenToolbar() -> Toolbar {
				    Toolbar(livePanel_PanelSendableBuilder: { title in LivePanel(title: title) })
				}
				""",
			], dependencies: ["Feature"]),
		])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Toolbar {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LivePanel_PanelSendableCarrier<__safeDI_Built>: Sendable {
		        public let panelBuilder: @Sendable () -> SendableErasedInstantiator<String, __safeDI_Built>.Builder

		        public init(panelBuilder: @escaping @Sendable () -> SendableErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.panelBuilder = panelBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(panelBuilder: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(livePanel_PanelSendableBuilder: @escaping SendableErasedInstantiator<String, any Panel>.Builder) {
		        self.init(__safeDI_livePanel_PanelSendableBuilder: .init(__safeDI_noScope: livePanel_PanelSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_livePanel_PanelSendableBuilder: __safeDI_LivePanel_PanelSendableCarrier<any Panel>) {
		        let theme = Theme()
		        let panelBuilder = SendableErasedInstantiator<String, any Panel>(__safeDI_livePanel_PanelSendableBuilder.panelBuilder())
		        self.init(theme: theme, panelBuilder: panelBuilder)
		    }
		}

		extension Toolbar {
		    public enum __safeDI_Toolbar_F39B6A30B2E5FD88 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_livePanel_PanelSendableBuilder_Toolbar_panelBuilder() -> SendableErasedInstantiator<String, any Panel>.Builder {
		            return __safeDI_fillBody_55B6CFB6A08455F2()
		        }
		        @Sendable nonisolated func __safeDI_fillBody_55B6CFB6A08455F2() -> SendableErasedInstantiator<String, any Panel>.Builder {
		            @Sendable nonisolated func __safeDI_panelBuilder(title: String) -> LivePanel {
		                LivePanel(title: title)
		            }
		            return { forwarded in __safeDI_panelBuilder(title: forwarded) }
		        }
		        @Sendable nonisolated func __safeDI_livePanel_PanelSendableBuilder_Toolbar() -> Toolbar.__safeDI_LivePanel_PanelSendableCarrier<any Panel> {
		            .init(panelBuilder: { __safeDI_livePanel_PanelSendableBuilder_Toolbar_panelBuilder() })
		        }
		        func __safeDI_toolbar() -> Toolbar {
		            _ = Toolbar.__safeDI_Toolbar_F39B6A30B2E5FD88.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Toolbar(__safeDI_livePanel_PanelSendableBuilder: __safeDI_livePanel_PanelSendableBuilder_Toolbar())
		        }
		        let toolbar: Toolbar = __safeDI_toolbar()
		        self.init(toolbar: toolbar)
		    }
		}
		"""])
	}

	// MARK: Adding a place never relabels a builder

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsBuildersLabelEnumAndCase_whenAnotherTypesPlaceOfItsFillingTypeIsAdded() async throws {
		// `F`'s place `a` is filled by `Impl` as `any Api`. Adding `Child`, whose place `o` is filled by `Impl` as `any Other`,
		// adds the builder `impl_OtherBuilder` and leaves `a`'s builder, enum and case as they were.
		let alone = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.protocols, Self.f(holdingChild: false)], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration)])
		let besideChild = try await compiledOutput(of: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.protocols, Self.f(holdingChild: true), Self.child], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration)])
		#expect(alone.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension F {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_ApiCarrier<__safeDI_Built> {
		        public let a: () -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		        public init(a: @escaping () -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.a = a
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(a: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(impl_ApiBuilder: @escaping ErasedInstantiator<Int, any Api>.Builder) {
		        self.init(__safeDI_impl_ApiBuilder: .init(__safeDI_noScope: impl_ApiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_impl_ApiBuilder: __safeDI_Impl_ApiCarrier<any Api>) {
		        let a = ErasedInstantiator<Int, any Api>(__safeDI_impl_ApiBuilder.a())
		        self.init(a: a)
		    }
		}

		extension F {
		    public enum __safeDI_F_4D7BB582FA0FAAC3 {}
		}

		#if DEBUG
		extension F {
		    nonisolated public enum SafeDIMockScope_Impl_Api {
		        nonisolated public struct a_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let a: (a_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(a: @escaping (a_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.a = a
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.init(a: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        impl_ApiBuilder: @escaping ErasedInstantiator<Int, any Api>.Builder
		    ) -> F {
		        F.__safeDI_mock(impl_ApiBuilder: .init(__safeDI_noScope: impl_ApiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        impl_ApiBuilder __safeDI_impl_ApiBuilder: F.SafeDIMockScope_Impl_Api.__safeDI_Builder<any Api>
		    ) -> F {
		        let a = ErasedInstantiator<Int, any Api>(__safeDI_impl_ApiBuilder.a(SafeDIMockScope_Impl_Api.a_Values()))
		        return F(a: a)
		    }
		}

		extension F {
		    public enum __safeDI_F_mock_C767B7BC2835A9DA {}
		}
		#endif
		"""])
		#expect(besideChild.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension F {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_ApiCarrier<__safeDI_Built> {
		        public let a: () -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		        public init(a: @escaping () -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.a = a
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(a: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_OtherCarrier<__safeDI_Built> {
		        public let child: (ErasedInstantiator<Int, any Api>) -> __safeDI_Impl_OtherCarrier_Child<__safeDI_Built>

		        public init(child: @escaping (ErasedInstantiator<Int, any Api>) -> __safeDI_Impl_OtherCarrier_Child<__safeDI_Built>) {
		            self.child = child
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(child: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_OtherCarrier_Child<__safeDI_Built> {
		        public let o: () -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		        public init(o: @escaping () -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.o = o
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(o: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(impl_ApiBuilder: @escaping ErasedInstantiator<Int, any Api>.Builder, impl_OtherBuilder: @escaping ErasedInstantiator<Int, any Other>.Builder) {
		        self.init(__safeDI_impl_ApiBuilder: .init(__safeDI_noScope: impl_ApiBuilder), __safeDI_impl_OtherBuilder: .init(__safeDI_noScope: impl_OtherBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_impl_ApiBuilder: __safeDI_Impl_ApiCarrier<any Api>, __safeDI_impl_OtherBuilder: __safeDI_Impl_OtherCarrier<any Other>) {
		        let a = ErasedInstantiator<Int, any Api>(__safeDI_impl_ApiBuilder.a())
		        let __safeDI_impl_OtherBuilder_child = __safeDI_impl_OtherBuilder.child(a)
		        @inline(never) func __safeDI_child() -> Child {
		            let o = ErasedInstantiator<Int, any Other>(__safeDI_impl_OtherBuilder_child.o())
		            return Child(o: o)
		        }
		        let child: Child = __safeDI_child()
		        self.init(a: a, child: child)
		    }
		}

		extension F {
		    public enum __safeDI_F_CC78157CEA6F00A8 {}
		}

		#if DEBUG
		extension F {
		    nonisolated public enum SafeDIMockScope_Impl_Api {
		        nonisolated public struct a_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let a: (a_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(a: @escaping (a_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.a = a
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.init(a: { _ in __safeDI_builder })
		            }
		        }
		    }

		    nonisolated public enum SafeDIMockScope_Impl_Other {
		        nonisolated public struct child_Values {
		            public let a: ErasedInstantiator<Int, any Api>
		        }

		        nonisolated public enum Child_Scope {
		            nonisolated public struct o_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let o: (o_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		                public init(o: @escaping (o_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.o = o
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.init(o: { _ in __safeDI_builder })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let child: (child_Values) -> SafeDIMockScope_Impl_Other.Child_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(child: @escaping (child_Values) -> SafeDIMockScope_Impl_Other.Child_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.child = child
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.init(child: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            child: ((ErasedInstantiator<Int, any Other>) -> Child)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                child: child
		            )
		        }

		        public var child: ((ErasedInstantiator<Int, any Other>) -> Child)? { __safeDI_storage.child }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                child: ((ErasedInstantiator<Int, any Other>) -> Child)?
		            ) {
		                self.child = child
		            }

		            let child: ((ErasedInstantiator<Int, any Other>) -> Child)?
		        }
		    }

		    public static func mock(
		        impl_ApiBuilder: @escaping ErasedInstantiator<Int, any Api>.Builder,
		        impl_OtherBuilder: @escaping ErasedInstantiator<Int, any Other>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        F.__safeDI_mock(impl_ApiBuilder: .init(__safeDI_noScope: impl_ApiBuilder), impl_OtherBuilder: .init(__safeDI_noScope: impl_OtherBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        impl_ApiBuilder __safeDI_impl_ApiBuilder: F.SafeDIMockScope_Impl_Api.__safeDI_Builder<any Api>,
		        impl_OtherBuilder __safeDI_impl_OtherBuilder: F.SafeDIMockScope_Impl_Other.__safeDI_Builder<any Other>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        let a = ErasedInstantiator<Int, any Api>(__safeDI_impl_ApiBuilder.a(SafeDIMockScope_Impl_Api.a_Values()))
		        let __safeDI_impl_OtherBuilder_child = __safeDI_impl_OtherBuilder.child(SafeDIMockScope_Impl_Other.child_Values(a: a))
		        func __safeDI_child() -> Child {
		            let o = ErasedInstantiator<Int, any Other>(__safeDI_impl_OtherBuilder_child.o(SafeDIMockScope_Impl_Other.Child_Scope.o_Values()))
		            return if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(o) } else { Child(o: o) }
		        }
		        let child: Child = __safeDI_child()
		        return F(a: a, child: child)
		    }
		}

		extension F {
		    public enum __safeDI_F_mock_379612150B7A3740 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_labelsInnerSeamsBuilderAsTheOuterSeamLabelsTheBuilderItPassesUp_whenBothFillingTypesAreOneType() async throws {
		// `Inner`, in `Lib`, holds a place filled by `Impl` as `any Other`, which `F`, in `Feature`, passes up beside its own
		// place filled by `Impl` as `any Api`: `Inner` labels its builder as `F` labels the builder it passes it to.
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Lib", packageName: "Shop", swiftFileContent: [Self.protocols, Self.inner], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["import Lib\n\n" + Self.f(holdingInner: true)], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration, dependencies: ["Lib"]),
		])
		#expect(output.modules["Lib"]?.generatedFiles == ["Lib.swift": generatedFileHeader + """
		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_OtherCarrier<__safeDI_Built> {
		        public let a2: () -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		        public init(a2: @escaping () -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.a2 = a2
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(a2: { __safeDI_builder })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(impl_OtherBuilder: @escaping ErasedInstantiator<Int, any Other>.Builder) {
		        self.init(__safeDI_impl_OtherBuilder: .init(__safeDI_noScope: impl_OtherBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_impl_OtherBuilder: __safeDI_Impl_OtherCarrier<any Other>) {
		        let a2 = ErasedInstantiator<Int, any Other>(__safeDI_impl_OtherBuilder.a2())
		        self.init(a2: a2)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_137C551F8A2B7513 {}
		}

		#if DEBUG
		extension Inner {
		    nonisolated public enum SafeDIMockScope_Impl_Other {
		        nonisolated public struct a2_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let a2: (a2_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(a2: @escaping (a2_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.a2 = a2
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.init(a2: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        impl_OtherBuilder: @escaping ErasedInstantiator<Int, any Other>.Builder
		    ) -> Inner {
		        Inner.__safeDI_mock(impl_OtherBuilder: .init(__safeDI_noScope: impl_OtherBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        impl_OtherBuilder __safeDI_impl_OtherBuilder: Inner.SafeDIMockScope_Impl_Other.__safeDI_Builder<any Other>
		    ) -> Inner {
		        let a2 = ErasedInstantiator<Int, any Other>(__safeDI_impl_OtherBuilder.a2(SafeDIMockScope_Impl_Other.a2_Values()))
		        return Inner(a2: a2)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_mock_670A3C2AA06D5DC8 {}
		}
		#endif
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Lib)
		import Lib
		#endif

		extension F {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_ApiCarrier<__safeDI_Built> {
		        public let a: (Inner) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		        public init(a: @escaping (Inner) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.a = a
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(a: { _ in __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_OtherCarrier<__safeDI_Built> {
		        public let inner: Inner.__safeDI_Impl_OtherCarrier<__safeDI_Built>

		        public init(inner: Inner.__safeDI_Impl_OtherCarrier<__safeDI_Built>) {
		            self.inner = inner
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(impl_ApiBuilder: @escaping ErasedInstantiator<Int, any Api>.Builder, impl_OtherBuilder: @escaping ErasedInstantiator<Int, any Other>.Builder) {
		        self.init(__safeDI_impl_ApiBuilder: .init(__safeDI_noScope: impl_ApiBuilder), __safeDI_impl_OtherBuilder: .init(__safeDI_noScope: impl_OtherBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_impl_ApiBuilder: __safeDI_Impl_ApiCarrier<any Api>, __safeDI_impl_OtherBuilder: __safeDI_Impl_OtherCarrier<any Other>) {
		        @inline(never) func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_137C551F8A2B7513.self // If this line does not compile, compile the code SafeDI generates for module Lib into Lib: under Bazel, add Lib’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_impl_OtherBuilder: __safeDI_impl_OtherBuilder.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        let a = ErasedInstantiator<Int, any Api>(__safeDI_impl_ApiBuilder.a(inner))
		        self.init(a: a, inner: inner)
		    }
		}

		extension F {
		    public enum __safeDI_F_CCB84A5ED067E4CA {}
		}

		#if DEBUG
		extension F {
		    nonisolated public enum SafeDIMockScope_Impl_Api {
		        nonisolated public struct a_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let a: (a_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(a: @escaping (a_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.a = a
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.init(a: { _ in __safeDI_builder })
		            }
		        }
		    }

		    nonisolated public enum SafeDIMockScope_Impl_Other {
		        nonisolated public struct inner_Values {
		            public let a: ErasedInstantiator<Int, any Api>
		        }

		        nonisolated public enum Inner_Scope {
		            nonisolated public struct a2_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let a2: (a2_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		                public init(a2: @escaping (a2_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.a2 = a2
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.init(a2: { _ in __safeDI_builder })
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (inner_Values) -> SafeDIMockScope_Impl_Other.Inner_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (inner_Values) -> SafeDIMockScope_Impl_Other.Inner_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.init(inner: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            inner: ((ErasedInstantiator<Int, any Other>) -> Inner)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                inner: inner
		            )
		        }

		        public var inner: ((ErasedInstantiator<Int, any Other>) -> Inner)? { __safeDI_storage.inner }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                inner: ((ErasedInstantiator<Int, any Other>) -> Inner)?
		            ) {
		                self.inner = inner
		            }

		            let inner: ((ErasedInstantiator<Int, any Other>) -> Inner)?
		        }
		    }

		    public static func mock(
		        impl_ApiBuilder: @escaping ErasedInstantiator<Int, any Api>.Builder,
		        impl_OtherBuilder: @escaping ErasedInstantiator<Int, any Other>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        F.__safeDI_mock(impl_ApiBuilder: .init(__safeDI_noScope: impl_ApiBuilder), impl_OtherBuilder: .init(__safeDI_noScope: impl_OtherBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        impl_ApiBuilder __safeDI_impl_ApiBuilder: F.SafeDIMockScope_Impl_Api.__safeDI_Builder<any Api>,
		        impl_OtherBuilder __safeDI_impl_OtherBuilder: F.SafeDIMockScope_Impl_Other.__safeDI_Builder<any Other>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        let a = ErasedInstantiator<Int, any Api>(__safeDI_impl_ApiBuilder.a(SafeDIMockScope_Impl_Api.a_Values()))
		        let __safeDI_impl_OtherBuilder_inner = __safeDI_impl_OtherBuilder.inner(SafeDIMockScope_Impl_Other.inner_Values(a: a))
		        func __safeDI_inner() -> Inner {
		            let a2 = ErasedInstantiator<Int, any Other>(__safeDI_impl_OtherBuilder_inner.a2(SafeDIMockScope_Impl_Other.Inner_Scope.a2_Values()))
		            return if let safeDIBuilder = safeDIOverrides.inner { safeDIBuilder(a2) } else { Inner(a2: a2) }
		        }
		        let inner: Inner = __safeDI_inner()
		        return F(a: a, inner: inner)
		    }
		}

		extension F {
		    public enum __safeDI_F_mock_8B6B84D83557BC3C {}
		}
		#endif
		"""])
	}

	// MARK: A label equal to another parameter's

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appendsUnderscoreToBuildersLabelAndKeepsItsEnum_whenTheSeamTakesAParameterOfThatLabel() async throws {
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.hostReceiving(["apiBuilder: Int"])], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + Self.live,
				"""
				import Feature

				@Instantiable
				public final class Holder: Instantiable {
				    public init(apiBuilder: Int, host: Host) {
				        self.apiBuilder = apiBuilder
				        self.host = host
				    }

				    @Forwarded public let apiBuilder: Int
				    @Instantiated public let host: Host
				}
				""",
				"import Feature\n\n" + Self.root(holding: "holderBuilder: Instantiator<Holder>"),
				"""
				import Feature
				import SafeDI

				func handWrittenHost() -> Host {
				    Host(apiBuilder: 1, apiBuilder_: { Live() })
				}
				""",
			], dependencies: ["Feature"]),
		])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Int) -> __safeDI_Built

		        public init(api: @escaping (Int) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: Int, apiBuilder_: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: apiBuilder, __safeDI_apiBuilder_: .init(__safeDI_noScope: apiBuilder_))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder apiBuilder: Int, __safeDI_apiBuilder_: __safeDI_ApiCarrier<any Api>) {
		        let api: any Api = __safeDI_apiBuilder_.api(apiBuilder)
		        self.init(apiBuilder: apiBuilder, api: api)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_BF70F492F1E5D486 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder__Host() -> Host.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_apiBuilder in
		                let api: any Api = Live()
		                return api
		            })
		        }
		        func __safeDI_holderBuilder(apiBuilder: Int) -> Holder {
		            func __safeDI_host() -> Host {
		                _ = Host.__safeDI_Host_BF70F492F1E5D486.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return Host(__safeDI_apiBuilder: apiBuilder, __safeDI_apiBuilder_: __safeDI_apiBuilder__Host())
		            }
		            let host: Host = __safeDI_host()
		            return Holder(apiBuilder: apiBuilder, host: host)
		        }
		        let holderBuilder = Instantiator<Holder> {
		            __safeDI_holderBuilder(apiBuilder: $0)
		        }
		        self.init(holderBuilder: holderBuilder)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appendsUnderscoreToPlainLabelOnly_whenTheSeamTakesAParameterOfThePlainLabel() async throws {
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.hostReceiving(["apiBuilder: Int"], holdingWorker: true), Self.worker], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
		])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Int) -> __safeDI_Built

		        public init(api: @escaping (Int) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Worker<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let workerBuilder: @Sendable () -> __safeDI_ApiCarrier_Worker<__safeDI_Built>

		        public init(workerBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Worker<__safeDI_Built>) {
		            self.workerBuilder = workerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(workerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiBuilder: Int, apiBuilder_: @escaping () -> any Api, apiSendableBuilder: @escaping @Sendable () -> any Api) {
		        self.init(__safeDI_apiBuilder: apiBuilder, __safeDI_apiBuilder_: .init(__safeDI_noScope: apiBuilder_), __safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiBuilder apiBuilder: Int, __safeDI_apiBuilder_: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        let api: any Api = __safeDI_apiBuilder_.api(apiBuilder)
		        @inline(never) @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
		            let __safeDI_apiSendableBuilder_workerBuilder = __safeDI_apiSendableBuilder.workerBuilder()
		            let api: any Api = __safeDI_apiSendableBuilder_workerBuilder.api()
		            return Worker(api: api)
		        }
		        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		        self.init(apiBuilder: apiBuilder, api: api, workerBuilder: workerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_3E4880D03222C100 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appendsUnderscoreToSendableLabelOnly_whenTheSeamTakesAParameterOfTheSendableLabel() async throws {
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.hostReceiving(["apiSendableBuilder: Int"], holdingWorker: true), Self.worker], swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
		])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Int) -> __safeDI_Built

		        public init(api: @escaping (Int) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Worker<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let workerBuilder: @Sendable () -> __safeDI_ApiCarrier_Worker<__safeDI_Built>

		        public init(workerBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Worker<__safeDI_Built>) {
		            self.workerBuilder = workerBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(workerBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiSendableBuilder: Int, apiBuilder: @escaping () -> any Api, apiSendableBuilder_: @escaping @Sendable () -> any Api) {
		        self.init(__safeDI_apiSendableBuilder: apiSendableBuilder, __safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_apiSendableBuilder_: .init(__safeDI_noScope: apiSendableBuilder_))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiSendableBuilder apiSendableBuilder: Int, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder_: __safeDI_ApiSendableCarrier<any Api>) {
		        let api: any Api = __safeDI_apiBuilder.api(apiSendableBuilder)
		        @inline(never) @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
		            let __safeDI_apiSendableBuilder__workerBuilder = __safeDI_apiSendableBuilder_.workerBuilder()
		            let api: any Api = __safeDI_apiSendableBuilder__workerBuilder.api()
		            return Worker(api: api)
		        }
		        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		        self.init(apiSendableBuilder: apiSendableBuilder, api: api, workerBuilder: workerBuilder)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_7A37A111A00D0246 {}
		}
		"""])
	}

	// MARK: Hole types whose stems are equal

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesHoleTypesApartByTheirTypes_whenATypesStemEqualsAnotherFillingAndReturnedTypesStem() async throws {
		// `Impl` fills `api` as `any Api`, whose stem is `Impl_Api`, the stem of the protocol `Impl_Api`.
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["public protocol Api {}\npublic protocol Impl_Api {}", seamFixtureType(named: "Host", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "Impl") public let api: any Api"#, "@Instantiated public let implApi: any Impl_Api"])]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + seamFixtureType(named: "Impl", declarations: [], conformances: ", Api"),
				"import Feature\n\n" + seamFixtureType(named: "LiveImplApi", declarations: [], conformances: ", Impl_Api").replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Impl_Api.self])\n"),
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let host: Host"]),
			], dependencies: ["Feature"]),
		])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_Api_ImplCarrier<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_Api_Impl_ApiCarrier<__safeDI_Built> {
		        public let implApi: (any Api) -> __safeDI_Built

		        public init(implApi: @escaping (any Api) -> __safeDI_Built) {
		            self.implApi = implApi
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(implApi: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_impl_Api_ImplBuilder: __safeDI_Impl_Api_ImplCarrier<any Api>, __safeDI_impl_Api_Impl_ApiBuilder: __safeDI_Impl_Api_Impl_ApiCarrier<any Impl_Api>) {
		        let api: any Api = __safeDI_impl_Api_ImplBuilder.api()
		        let implApi: any Impl_Api = __safeDI_impl_Api_Impl_ApiBuilder.implApi(api)
		        self.init(api: api, implApi: implApi)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_062D71729FD4D920 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_impl_Api_ImplBuilder_Host() -> Host.__safeDI_Impl_Api_ImplCarrier<any Api> {
		            .init(api: {
		                let api: any Api = Impl()
		                return api
		            })
		        }
		        func __safeDI_impl_Api_Impl_ApiBuilder_Host() -> Host.__safeDI_Impl_Api_Impl_ApiCarrier<any Impl_Api> {
		            .init(implApi: { scope_api in
		                let implApi: any Impl_Api = LiveImplApi()
		                return implApi
		            })
		        }
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_062D71729FD4D920.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Host(__safeDI_impl_Api_ImplBuilder: __safeDI_impl_Api_ImplBuilder_Host(), __safeDI_impl_Api_Impl_ApiBuilder: __safeDI_impl_Api_Impl_ApiBuilder_Host())
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
	}

	@Test(arguments: [
		["nested", "joined", "sendable"], ["nested", "sendable", "joined"], ["joined", "nested", "sendable"], ["joined", "sendable", "nested"], ["sendable", "nested", "joined"], ["sendable", "joined", "nested"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesCollidingHoleTypesAlike_whenTheirPlacesAreDeclaredInAnyOrder(order: [String]) async throws {
		// Three hole types no declaration fulfills: `Outer.Thing` and `Outer_Thing`, whose stems are equal, and
		// `Outer_ThingSendable`, whose plain label is the `@Sendable` label of either. Each place is held in a
		// `SendableInstantiator`, so its case carries no values, and only the lines that build the places follow their order.
		let declarations = [
			"nested": "@Instantiated public let nested: SendableInstantiator<Outer.Thing>",
			"joined": "@Instantiated public let joined: SendableInstantiator<Outer_Thing>",
			"sendable": "@Instantiated public let sendable: SendableInstantiator<Outer_ThingSendable>",
		]
		let builds = [
			"nested": """
			        let nested = SendableInstantiator<Outer.Thing>(__safeDI_outer_Thing_Outer_ThingSendableBuilder.nested())
			""",
			"joined": """
			        let joined = SendableInstantiator<Outer_Thing>(__safeDI_outer_Thing_Outer_Thing_SendableBuilder.joined())
			""",
			"sendable": """
			        let sendable = SendableInstantiator<Outer_ThingSendable>(__safeDI_outer_ThingSendable_Outer_ThingSendableSendableBuilder.sendable())
			""",
		]
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"""
				public enum Outer {
				    public struct Thing: Instantiable, Sendable {
				        public init() {}
				    }
				}

				public struct Outer_Thing: Instantiable, Sendable {
				    public init() {}
				}

				public struct Outer_ThingSendable: Instantiable, Sendable {
				    public init() {}
				}
				""",
				seamFixtureType(named: "Host", isSeam: true, declarations: order.compactMap { declarations[$0] }),
			]),
		])
		let body = order.compactMap { builds[$0] }.joined(separator: "\n")
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Outer_ThingSendable_Outer_ThingSendableSendableCarrier<__safeDI_Built>: Sendable {
		        public let sendable: @Sendable () -> SendableErasedInstantiator<Outer_ThingSendable.ForwardedProperties, __safeDI_Built>.Builder

		        public init(sendable: @escaping @Sendable () -> SendableErasedInstantiator<Outer_ThingSendable.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.sendable = sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Outer_ThingSendable.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(sendable: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Outer_Thing_Outer_ThingSendableCarrier<__safeDI_Built>: Sendable {
		        public let nested: @Sendable () -> SendableErasedInstantiator<Outer.Thing.ForwardedProperties, __safeDI_Built>.Builder

		        public init(nested: @escaping @Sendable () -> SendableErasedInstantiator<Outer.Thing.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.nested = nested
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Outer.Thing.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(nested: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Outer_Thing_Outer_Thing_SendableCarrier<__safeDI_Built>: Sendable {
		        public let joined: @Sendable () -> SendableErasedInstantiator<Outer_Thing.ForwardedProperties, __safeDI_Built>.Builder

		        public init(joined: @escaping @Sendable () -> SendableErasedInstantiator<Outer_Thing.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.joined = joined
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Outer_Thing.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(joined: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_outer_ThingSendable_Outer_ThingSendableSendableBuilder: __safeDI_Outer_ThingSendable_Outer_ThingSendableSendableCarrier<Outer_ThingSendable>, __safeDI_outer_Thing_Outer_ThingSendableBuilder: __safeDI_Outer_Thing_Outer_ThingSendableCarrier<Outer.Thing>, __safeDI_outer_Thing_Outer_Thing_SendableBuilder: __safeDI_Outer_Thing_Outer_Thing_SendableCarrier<Outer_Thing>) {
		\(body)
		        self.init(\(order.map { "\($0): \($0)" }.joined(separator: ", ")))
		    }
		}

		extension Host {
		    public enum __safeDI_Host_1C551801B1DCB5E7 {}
		}
		"""])
	}

	@Test(arguments: [
		["api", "implApi", "implApiSendable"], ["api", "implApiSendable", "implApi"], ["implApi", "api", "implApiSendable"], ["implApi", "implApiSendable", "api"], ["implApiSendable", "api", "implApi"], ["implApiSendable", "implApi", "api"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesCollidingHoleTypesAlike_whenAFillingTypeDiffersFromItsReturnedTypeAndTheirPlacesAreDeclaredInAnyOrder(order: [String]) async throws {
		// Three hole types no declaration fulfills: `Impl` returned as `any Api` and the type `Impl_Api`, whose stems are
		// equal, and `Impl_ApiSendable`, whose plain label is the `@Sendable` label of either. Each place is held in a
		// `Sendable` wrapper, so its case carries only what the place forwards, and only the lines that build the places
		// follow their order.
		let declarations = [
			"api": #"@Instantiated(fulfilledByType: "Impl") public let api: SendableErasedInstantiator<String, any Api>"#,
			"implApi": "@Instantiated public let implApi: SendableInstantiator<Impl_Api>",
			"implApiSendable": "@Instantiated public let implApiSendable: SendableInstantiator<Impl_ApiSendable>",
		]
		let builds = [
			"api": """
			        let api = SendableErasedInstantiator<String, any Api>(__safeDI_impl_Api_ImplSendableBuilder.api())
			""",
			"implApi": """
			        let implApi = SendableInstantiator<Impl_Api>(__safeDI_impl_Api_Impl_ApiSendableBuilder.implApi())
			""",
			"implApiSendable": """
			        let implApiSendable = SendableInstantiator<Impl_ApiSendable>(__safeDI_impl_ApiSendable_Impl_ApiSendableSendableBuilder.implApiSendable())
			""",
		]
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"""
				public protocol Api: Sendable {}

				public struct Impl_Api: Instantiable, Sendable {
				    public init() {}
				}

				public struct Impl_ApiSendable: Instantiable, Sendable {
				    public init() {}
				}
				""",
				seamFixtureType(named: "Host", isSeam: true, declarations: order.compactMap { declarations[$0] }),
			]),
		])
		let body = order.compactMap { builds[$0] }.joined(separator: "\n")
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_ApiSendable_Impl_ApiSendableSendableCarrier<__safeDI_Built>: Sendable {
		        public let implApiSendable: @Sendable () -> SendableErasedInstantiator<Impl_ApiSendable.ForwardedProperties, __safeDI_Built>.Builder

		        public init(implApiSendable: @escaping @Sendable () -> SendableErasedInstantiator<Impl_ApiSendable.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.implApiSendable = implApiSendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Impl_ApiSendable.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(implApiSendable: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_Api_ImplSendableCarrier<__safeDI_Built>: Sendable {
		        public let api: @Sendable () -> SendableErasedInstantiator<String, __safeDI_Built>.Builder

		        public init(api: @escaping @Sendable () -> SendableErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<String, __safeDI_Built>.Builder) {
		            self.init(api: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_Impl_Api_Impl_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let implApi: @Sendable () -> SendableErasedInstantiator<Impl_Api.ForwardedProperties, __safeDI_Built>.Builder

		        public init(implApi: @escaping @Sendable () -> SendableErasedInstantiator<Impl_Api.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.implApi = implApi
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Impl_Api.ForwardedProperties, __safeDI_Built>.Builder) {
		            self.init(implApi: { __safeDI_builder })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_impl_ApiSendable_Impl_ApiSendableSendableBuilder: __safeDI_Impl_ApiSendable_Impl_ApiSendableSendableCarrier<Impl_ApiSendable>, __safeDI_impl_Api_ImplSendableBuilder: __safeDI_Impl_Api_ImplSendableCarrier<any Api>, __safeDI_impl_Api_Impl_ApiSendableBuilder: __safeDI_Impl_Api_Impl_ApiSendableCarrier<Impl_Api>) {
		\(body)
		        self.init(\(order.map { "\($0): \($0)" }.joined(separator: ", ")))
		    }
		}

		extension Host {
		    public enum __safeDI_Host_DE18E654F9339849 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appendsUnderscoreToStemNamedApart_whenItsPlainLabelEqualsTheSendableLabelOfAStemNotNamedApart() async throws {
		// `Service` and `ServiceSendable` collide, the plain label of `ServiceSendable` being the `@Sendable` label of
		// `Service`, so they are named apart by their types, as `Service_Service` and `ServiceSendable_ServiceSendable`.
		// `ServiceSendable_Service` collides with neither and keeps its stem, whose `@Sendable` label is the plain label of
		// `ServiceSendable_ServiceSendable`, which so takes a trailing underscore. The seam takes both of those builders:
		// `serviceSendable` is built in plain code, and `serviceSendableService` in a `SendableInstantiator`.
		let output = try await compiledOutput(of: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"""
				public struct Service: Instantiable, Sendable {
				    public init() {}
				}

				public struct ServiceSendable: Instantiable, Sendable {
				    public init() {}
				}

				public struct ServiceSendable_Service: Instantiable, Sendable {
				    public init() {}
				}
				""",
				seamFixtureType(named: "Host", isSeam: true, declarations: [
					"@Instantiated public let serviceSendable: ServiceSendable",
					"@Instantiated public let service: SendableInstantiator<Service>",
					"@Instantiated public let serviceSendableService: SendableInstantiator<ServiceSendable_Service>",
				]),
			]),
		])
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			extension Host {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let service: @Sendable () -> SendableErasedInstantiator<Service.ForwardedProperties, __safeDI_Built>.Builder

			        public init(service: @escaping @Sendable () -> SendableErasedInstantiator<Service.ForwardedProperties, __safeDI_Built>.Builder) {
			            self.service = service
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Service.ForwardedProperties, __safeDI_Built>.Builder) {
			            self.init(service: { __safeDI_builder })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendable_ServiceSendableCarrier<__safeDI_Built>: Sendable {
			        public let serviceSendableService: @Sendable () -> SendableErasedInstantiator<ServiceSendable_Service.ForwardedProperties, __safeDI_Built>.Builder

			        public init(serviceSendableService: @escaping @Sendable () -> SendableErasedInstantiator<ServiceSendable_Service.ForwardedProperties, __safeDI_Built>.Builder) {
			            self.serviceSendableService = serviceSendableService
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<ServiceSendable_Service.ForwardedProperties, __safeDI_Built>.Builder) {
			            self.init(serviceSendableService: { __safeDI_builder })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceSendable_ServiceSendable_Carrier<__safeDI_Built> {
			        public let serviceSendable: () -> __safeDI_Built

			        public init(serviceSendable: @escaping () -> __safeDI_Built) {
			            self.serviceSendable = serviceSendable
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(serviceSendable: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_serviceSendableBuilder: __safeDI_ServiceSendableCarrier<Service>, __safeDI_serviceSendable_ServiceSendableBuilder: __safeDI_ServiceSendable_ServiceSendableCarrier<ServiceSendable_Service>, __safeDI_serviceSendable_ServiceSendable_Builder: __safeDI_ServiceSendable_ServiceSendable_Carrier<ServiceSendable>) {
			        let serviceSendable: ServiceSendable = __safeDI_serviceSendable_ServiceSendable_Builder.serviceSendable()
			        let service = SendableInstantiator<Service>(__safeDI_serviceSendableBuilder.service())
			        let serviceSendableService = SendableInstantiator<ServiceSendable_Service>(__safeDI_serviceSendable_ServiceSendableBuilder.serviceSendableService())
			        self.init(serviceSendable: serviceSendable, service: service, serviceSendableService: serviceSendableService)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_EB76ABB2A073308B {}
			}
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Toolbar`, a seam whose place `panelBuilder`, an `ErasedInstantiator` forwarding a `String`, `LivePanel` fills as
	/// `any Panel`.
	private static let toolbar = """
	public protocol Panel: AnyObject {}

	@Instantiable(generateDependencyTree: true)
	public final class Toolbar: Instantiable {
	    public init(theme: Theme, panelBuilder: ErasedInstantiator<String, any Panel>) {
	        self.theme = theme
	        self.panelBuilder = panelBuilder
	    }

	    @Instantiated public let theme: Theme
	    @Instantiated(fulfilledByType: "LivePanel") public let panelBuilder: ErasedInstantiator<String, any Panel>
	}

	@Instantiable
	public final class Theme: Instantiable {
	    public init() {}
	}
	"""

	private static func livePanel(receivingTheme: Bool) -> String {
		"""
		@Instantiable(fulfillingAdditionalTypes: [Panel.self])
		public final class LivePanel: Instantiable, Panel {
		    public init(title: String\(receivingTheme ? ", theme: Theme" : "")) {
		        self.title = title
		\(receivingTheme ? "        self.theme = theme\n" : "")    }

		    @Forwarded public let title: String
		\(receivingTheme ? "    @Received public let theme: Theme\n" : "")}
		"""
	}

	private static func root(holding declaration: String) -> String {
		let label = String(declaration.prefix { $0 != ":" })
		return """
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(\(declaration)) {
		        self.\(label) = \(label)
		    }

		    @Instantiated public let \(declaration)
		}
		"""
	}

	private static let protocols = "public protocol Api {}\npublic protocol Other {}"

	/// `F`, a seam with a public mock whose place `a` `Impl` fills as `any Api`, and which holds `Child` or `Inner` beside it.
	private static func f(holdingChild: Bool = false, holdingInner: Bool = false) -> String {
		var parameters = ["a: ErasedInstantiator<Int, any Api>"]
		var declarations = [#"@Instantiated(fulfilledByType: "Impl") let a: ErasedInstantiator<Int, any Api>"#]
		if holdingChild {
			parameters.append("child: Child")
			declarations.append("@Instantiated let child: Child")
		}
		if holdingInner {
			parameters.append("inner: Inner")
			declarations.append("@Instantiated let inner: Inner")
		}
		let labels = parameters.map { String($0.prefix { $0 != ":" }) }
		return """
		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public struct F: Instantiable {
		    public init(\(parameters.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }

		\(declarations.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}

	private static let child = """
	@Instantiable
	public struct Child: Instantiable {
	    public init(o: ErasedInstantiator<Int, any Other>) {
	        self.o = o
	    }

	    @Instantiated(fulfilledByType: "Impl") let o: ErasedInstantiator<Int, any Other>
	}
	"""

	private static let inner = """
	@Instantiable(generateDependencyTree: true, generateMock: .public)
	public struct Inner: Instantiable {
	    public init(a2: ErasedInstantiator<Int, any Other>) {
	        self.a2 = a2
	    }

	    @Instantiated(fulfilledByType: "Impl") let a2: ErasedInstantiator<Int, any Other>
	}
	"""

	/// `Host`, a seam that receives `received` and holds the place `api`, which no type of its module fills, and, when
	/// `holdingWorker`, a `SendableInstantiator<Worker>`, whose `Worker` holds another place of `any Api`.
	private static func hostReceiving(_ received: [String], holdingWorker: Bool = false) -> String {
		var parameters = received + ["api: any Api"]
		var declarations = received.map { "@Received public let \($0)" } + ["@Instantiated public let api: any Api"]
		if holdingWorker {
			parameters.append("workerBuilder: SendableInstantiator<Worker>")
			declarations.append("@Instantiated public let workerBuilder: SendableInstantiator<Worker>")
		}
		let labels = parameters.map { String($0.prefix { $0 != ":" }) }
		return """
		public protocol Api\(holdingWorker ? ": Sendable" : "") {}

		@Instantiable(generateDependencyTree: true)
		public final class Host: Instantiable {
		    public init(\(parameters.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }

		\(declarations.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}

	private static let worker = """
	@Instantiable
	public struct Worker: Instantiable, Sendable {
	    public init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated public let api: any Api
	}
	"""

	private static let live = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class Live: Instantiable, Api {
	    public init() {}
	}
	"""

	/// The output of `modules`, each module's files compiling.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func compiledOutput(of modules: [ModuleFixture], sourceLocation: SourceLocation = #_sourceLocation) async throws -> MultiModuleTestOutput {
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return output }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
		return output
	}
}
