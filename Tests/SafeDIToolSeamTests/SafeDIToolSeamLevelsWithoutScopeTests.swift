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

/// A seam's levels declare no initializer that takes only a builder. The two callers that build a seam's levels from one
/// builder – the seam's plain initializer, which a person calls with a builder that takes no scope, and a caller that
/// fills an optional place nothing fulfills with `{ nil }` – each declare one local function per level they reach,
/// which builds the level from its members, and a looping level's function calls itself. Each cell here builds a level
/// that loops, a level of another module's seam, a level of the `@Sendable` family and a place held in a wrapper that
/// forwards nothing beneath a builder that takes nothing, and compares the values with the same graph built inline.
struct SafeDIToolSeamLevelsWithoutScopeTests: ~Copyable {
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
	mutating func generate_buildsEachLevelInALocalFunction_whenPlainInitializerTakesBuilders() async throws {
		let modules = Self.modules
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif

			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let screenABuilder: (Inner) -> __safeDI_ApiCarrier_ScreenA<__safeDI_Built>
			        public let screenBBuilder: (Inner) -> __safeDI_ApiCarrier_ScreenB<__safeDI_Built>
			        public let folder: (Inner, Instantiator<ScreenA>, Instantiator<ScreenB>, ErasedInstantiator<(), any Widget>, SendableInstantiator<Worker>) -> __safeDI_ApiCarrier_Folder<__safeDI_Built>
			        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

			        public init(screenABuilder: @escaping (Inner) -> __safeDI_ApiCarrier_ScreenA<__safeDI_Built>, screenBBuilder: @escaping (Inner) -> __safeDI_ApiCarrier_ScreenB<__safeDI_Built>, folder: @escaping (Inner, Instantiator<ScreenA>, Instantiator<ScreenB>, ErasedInstantiator<(), any Widget>, SendableInstantiator<Worker>) -> __safeDI_ApiCarrier_Folder<__safeDI_Built>, inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
			            self.screenABuilder = screenABuilder
			            self.screenBBuilder = screenBBuilder
			            self.folder = folder
			            self.inner = inner
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_ScreenA<__safeDI_Built> {
			        public let api: (Int, Instantiator<ScreenB>) -> __safeDI_Built

			        public init(api: @escaping (Int, Instantiator<ScreenB>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_ScreenB<__safeDI_Built> {
			        public let api: (Int, Instantiator<ScreenA>) -> __safeDI_Built

			        public init(api: @escaping (Int, Instantiator<ScreenA>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_Folder<__safeDI_Built> {
			        public let api: () -> __safeDI_Built
			        public let subfolderBuilder: (any Api, (any Tracker)?) -> __safeDI_ApiCarrier_Folder<__safeDI_Built>

			        public init(api: @escaping () -> __safeDI_Built, subfolderBuilder: @escaping (any Api, (any Tracker)?) -> __safeDI_ApiCarrier_Folder<__safeDI_Built>) {
			            self.api = api
			            self.subfolderBuilder = subfolderBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_DefaultWidget_WidgetCarrier<__safeDI_Built> {
			        public let widgetBuilder: (Inner, Instantiator<ScreenA>, Instantiator<ScreenB>) -> ErasedInstantiator<(), __safeDI_Built>.Builder

			        public init(widgetBuilder: @escaping (Inner, Instantiator<ScreenA>, Instantiator<ScreenB>) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
			            self.widgetBuilder = widgetBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetCarrier_Worker<__safeDI_Built> {
			        public let gadget: () -> __safeDI_Built

			        public init(gadget: @escaping () -> __safeDI_Built) {
			            self.gadget = gadget
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let workerBuilder: @Sendable () -> __safeDI_GadgetCarrier_Worker<__safeDI_Built>

			        public init(workerBuilder: @escaping @Sendable () -> __safeDI_GadgetCarrier_Worker<__safeDI_Built>) {
			            self.workerBuilder = workerBuilder
			        }
			    }

			    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerOptionalCarrier<__safeDI_Built> {
			        public let screenABuilder: (Inner) -> __safeDI_TrackerOptionalCarrier_ScreenA<__safeDI_Built>
			        public let folder: (Inner, Instantiator<ScreenA>, Instantiator<ScreenB>, ErasedInstantiator<(), any Widget>, SendableInstantiator<Worker>) -> __safeDI_TrackerOptionalCarrier_Folder<__safeDI_Built>
			        public let inner: Inner.__safeDI_TrackerOptionalCarrier<__safeDI_Built>

			        public init(screenABuilder: @escaping (Inner) -> __safeDI_TrackerOptionalCarrier_ScreenA<__safeDI_Built>, folder: @escaping (Inner, Instantiator<ScreenA>, Instantiator<ScreenB>, ErasedInstantiator<(), any Widget>, SendableInstantiator<Worker>) -> __safeDI_TrackerOptionalCarrier_Folder<__safeDI_Built>, inner: Inner.__safeDI_TrackerOptionalCarrier<__safeDI_Built>) {
			            self.screenABuilder = screenABuilder
			            self.folder = folder
			            self.inner = inner
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerOptionalCarrier_ScreenA<__safeDI_Built> {
			        public let tracker: (Int, Instantiator<ScreenB>, any Api) -> __safeDI_Built

			        public init(tracker: @escaping (Int, Instantiator<ScreenB>, any Api) -> __safeDI_Built) {
			            self.tracker = tracker
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerOptionalCarrier_Folder<__safeDI_Built> {
			        public let tracker: (any Api) -> __safeDI_Built
			        public let subfolderBuilder: (any Api, (any Tracker)?) -> __safeDI_TrackerOptionalCarrier_Folder<__safeDI_Built>

			        public init(tracker: @escaping (any Api) -> __safeDI_Built, subfolderBuilder: @escaping (any Api, (any Tracker)?) -> __safeDI_TrackerOptionalCarrier_Folder<__safeDI_Built>) {
			            self.tracker = tracker
			            self.subfolderBuilder = subfolderBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerOptionalCarrier_Worker<__safeDI_Built> {
			        public let tracker: (any Gadget) -> __safeDI_Built

			        public init(tracker: @escaping (any Gadget) -> __safeDI_Built) {
			            self.tracker = tracker
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerOptionalSendableCarrier<__safeDI_Built>: Sendable {
			        public let workerBuilder: @Sendable () -> __safeDI_TrackerOptionalCarrier_Worker<__safeDI_Built>

			        public init(workerBuilder: @escaping @Sendable () -> __safeDI_TrackerOptionalCarrier_Worker<__safeDI_Built>) {
			            self.workerBuilder = workerBuilder
			        }
			    }

			    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
			    public convenience init(apiBuilder: @escaping () -> any Api, defaultWidget_WidgetBuilder: @escaping () -> any Widget, gadgetSendableBuilder: @escaping @Sendable () -> any Gadget, trackerOptionalBuilder: @escaping () -> (any Tracker)?, trackerOptionalSendableBuilder: @escaping @Sendable () -> (any Tracker)?) {
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier<__safeDI_Built> {
			            .init(screenABuilder: { _ in __safeDI_noScope_Home_SafeDICarrierScope_Api_ScreenA_Scope(__safeDI_builder) }, screenBBuilder: { _ in __safeDI_noScope_Home_SafeDICarrierScope_Api_ScreenB_Scope(__safeDI_builder) }, folder: { _, _, _, _, _ in __safeDI_noScope_Home_SafeDICarrierScope_Api_Folder_Scope(__safeDI_builder) }, inner: __safeDI_noScope_Inner_SafeDICarrierScope_Api(__safeDI_builder))
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api_ScreenA_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier_ScreenA<__safeDI_Built> {
			            .init(api: { _, _ in __safeDI_builder() })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api_ScreenB_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier_ScreenB<__safeDI_Built> {
			            .init(api: { _, _ in __safeDI_builder() })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api_Folder_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier_Folder<__safeDI_Built> {
			            .init(api: { __safeDI_builder() }, subfolderBuilder: { _, _ in __safeDI_noScope_Home_SafeDICarrierScope_Api_Folder_Scope(__safeDI_builder) })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Inner_SafeDICarrierScope_Api<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Inner.__safeDI_ApiCarrier<__safeDI_Built> {
			            .init(api: { __safeDI_builder() })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_DefaultWidget_Widget<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_DefaultWidget_WidgetCarrier<__safeDI_Built> {
			            .init(widgetBuilder: { _, _, _ in { _ in __safeDI_builder() } })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDISendableCarrierScope_Gadget<__safeDI_Built>(_ __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) -> Home.__safeDI_GadgetSendableCarrier<__safeDI_Built> {
			            .init(workerBuilder: { __safeDI_noScope_Home_SafeDICarrierScope_Gadget_Worker_Scope(__safeDI_builder) })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Gadget_Worker_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_GadgetCarrier_Worker<__safeDI_Built> {
			            .init(gadget: { __safeDI_builder() })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalCarrier<__safeDI_Built> {
			            .init(screenABuilder: { _ in __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_ScreenA_Scope(__safeDI_builder) }, folder: { _, _, _, _, _ in __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Folder_Scope(__safeDI_builder) }, inner: __safeDI_noScope_Inner_SafeDICarrierScope_TrackerOptional(__safeDI_builder))
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_ScreenA_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalCarrier_ScreenA<__safeDI_Built> {
			            .init(tracker: { _, _, _ in __safeDI_builder() })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Folder_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalCarrier_Folder<__safeDI_Built> {
			            .init(tracker: { _ in __safeDI_builder() }, subfolderBuilder: { _, _ in __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Folder_Scope(__safeDI_builder) })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Inner_SafeDICarrierScope_TrackerOptional<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Inner.__safeDI_TrackerOptionalCarrier<__safeDI_Built> {
			            .init(tracker: { _ in __safeDI_builder() })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDISendableCarrierScope_TrackerOptional<__safeDI_Built>(_ __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalSendableCarrier<__safeDI_Built> {
			            .init(workerBuilder: { __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Worker_Scope(__safeDI_builder) })
			        }
			        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Worker_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalCarrier_Worker<__safeDI_Built> {
			            .init(tracker: { _ in __safeDI_builder() })
			        }
			        self.init(__safeDI_apiBuilder: __safeDI_noScope_Home_SafeDICarrierScope_Api(apiBuilder), __safeDI_defaultWidget_WidgetBuilder: __safeDI_noScope_Home_SafeDICarrierScope_DefaultWidget_Widget(defaultWidget_WidgetBuilder), __safeDI_gadgetSendableBuilder: __safeDI_noScope_Home_SafeDISendableCarrierScope_Gadget(gadgetSendableBuilder), __safeDI_trackerOptionalBuilder: __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional(trackerOptionalBuilder), __safeDI_trackerOptionalSendableBuilder: __safeDI_noScope_Home_SafeDISendableCarrierScope_TrackerOptional(trackerOptionalSendableBuilder))
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// From code you write, call the initializer above instead.
			    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_defaultWidget_WidgetBuilder: __safeDI_DefaultWidget_WidgetCarrier<any Widget>, __safeDI_gadgetSendableBuilder: __safeDI_GadgetSendableCarrier<any Gadget>, __safeDI_trackerOptionalBuilder: __safeDI_TrackerOptionalCarrier<(any Tracker)?>, __safeDI_trackerOptionalSendableBuilder: __safeDI_TrackerOptionalSendableCarrier<(any Tracker)?>) {
			        @inline(never) func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_8DC036CACD7DFCF8.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Inner(__safeDI_apiBuilder: __safeDI_apiBuilder.inner, __safeDI_trackerOptionalBuilder: __safeDI_trackerOptionalBuilder.inner)
			        }
			        let inner: Inner = __safeDI_inner()
			        let __safeDI_screenABuilder_loopLevels = __safeDI_LoopLevels_1E0F643EBCB1C209(
			            __safeDI_apiBuilder_screenABuilder: __safeDI_apiBuilder.screenABuilder(inner),
			            __safeDI_trackerOptionalBuilder_screenABuilder: __safeDI_trackerOptionalBuilder.screenABuilder(inner),
			            __safeDI_apiBuilder_screenBBuilder: __safeDI_apiBuilder.screenBBuilder(inner)
			        )
			        @inline(never) func __safeDI_screenABuilder(id: Int) -> ScreenA {
			            let __safeDI_apiBuilder_screenABuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenABuilder
			            let __safeDI_trackerOptionalBuilder_screenABuilder = __safeDI_screenABuilder_loopLevels.__safeDI_trackerOptionalBuilder_screenABuilder
			            let screenBBuilder = Instantiator<ScreenB> {
			                __safeDI_screenBBuilder(id: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_screenABuilder.api(id, screenBBuilder)
			            let tracker: (any Tracker)? = __safeDI_trackerOptionalBuilder_screenABuilder.tracker(id, screenBBuilder, api)
			            return ScreenA(id: id, api: api, tracker: tracker, screenBBuilder: screenBBuilder)
			        }
			        let screenABuilder = Instantiator<ScreenA> {
			            __safeDI_screenABuilder(id: $0)
			        }
			        @inline(never) func __safeDI_screenBBuilder(id: Int) -> ScreenB {
			            let __safeDI_apiBuilder_screenBBuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenBBuilder
			            let screenABuilder = Instantiator<ScreenA> {
			                __safeDI_screenABuilder(id: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_screenBBuilder.api(id, screenABuilder)
			            return ScreenB(id: id, api: api, screenABuilder: screenABuilder)
			        }
			        let screenBBuilder = Instantiator<ScreenB> {
			            __safeDI_screenBBuilder(id: $0)
			        }
			        let widgetBuilder = ErasedInstantiator<(), any Widget>(__safeDI_defaultWidget_WidgetBuilder.widgetBuilder(inner, screenABuilder, screenBBuilder))
			        @inline(never) @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
			            let __safeDI_gadgetSendableBuilder_workerBuilder = __safeDI_gadgetSendableBuilder.workerBuilder()
			            let __safeDI_trackerOptionalSendableBuilder_workerBuilder = __safeDI_trackerOptionalSendableBuilder.workerBuilder()
			            let gadget: any Gadget = __safeDI_gadgetSendableBuilder_workerBuilder.gadget()
			            let tracker: (any Tracker)? = __safeDI_trackerOptionalSendableBuilder_workerBuilder.tracker(gadget)
			            return Worker(gadget: gadget, tracker: tracker)
			        }
			        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
			        let __safeDI_apiBuilder_folder = __safeDI_apiBuilder.folder(inner, screenABuilder, screenBBuilder, widgetBuilder, workerBuilder)
			        let __safeDI_trackerOptionalBuilder_folder = __safeDI_trackerOptionalBuilder.folder(inner, screenABuilder, screenBBuilder, widgetBuilder, workerBuilder)
			        @inline(never) func __safeDI_folder() -> Folder {
			            let api: any Api = __safeDI_apiBuilder_folder.api()
			            let tracker: (any Tracker)? = __safeDI_trackerOptionalBuilder_folder.tracker(api)
			            let __safeDI_apiBuilder_subfolderBuilder = __safeDI_apiBuilder_folder.subfolderBuilder(api, tracker)
			            let __safeDI_trackerOptionalBuilder_subfolderBuilder = __safeDI_trackerOptionalBuilder_folder.subfolderBuilder(api, tracker)
			            @inline(never) func __safeDI_subfolderBuilder() -> Folder {
			                let api: any Api = __safeDI_apiBuilder_subfolderBuilder.api()
			                let tracker: (any Tracker)? = __safeDI_trackerOptionalBuilder_subfolderBuilder.tracker(api)
			                let subfolderBuilder = Instantiator<Folder>(__safeDI_subfolderBuilder)
			                return Folder(api: api, tracker: tracker, subfolderBuilder: subfolderBuilder)
			            }
			            let subfolderBuilder = Instantiator<Folder>(__safeDI_subfolderBuilder)
			            return Folder(api: api, tracker: tracker, subfolderBuilder: subfolderBuilder)
			        }
			        let folder: Folder = __safeDI_folder()
			        self.init(screenABuilder: screenABuilder, screenBBuilder: screenBBuilder, widgetBuilder: widgetBuilder, workerBuilder: workerBuilder, folder: folder, inner: inner)
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_1E0F643EBCB1C209 {
			        init(
			            __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>,
			            __safeDI_trackerOptionalBuilder_screenABuilder: __safeDI_TrackerOptionalCarrier_ScreenA<(any Tracker)?>,
			            __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
			        ) {
			            self.__safeDI_apiBuilder_screenABuilder = __safeDI_apiBuilder_screenABuilder
			            self.__safeDI_trackerOptionalBuilder_screenABuilder = __safeDI_trackerOptionalBuilder_screenABuilder
			            self.__safeDI_apiBuilder_screenBBuilder = __safeDI_apiBuilder_screenBBuilder
			        }

			        let __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>
			        let __safeDI_trackerOptionalBuilder_screenABuilder: __safeDI_TrackerOptionalCarrier_ScreenA<(any Tracker)?>
			        let __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
			    }
			}

			extension Home {
			    public enum __safeDI_Home_33C41EF320BE023C {}
			}
			""",
		])
		try await expectValuesAndRetentionEqualInlineBuild(output, modules: modules, probes: [
			DifferentialValueProbe(name: "Home", expression: Self.plainInitializerCall, knownRightExpression: "Root().home"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachLevelInALocalFunction_whenCallerFillsOptionalPlaceNothingFulfillsWithNil() async throws {
		let modules = Self.modules
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_defaultWidget_WidgetBuilder_Home_widgetBuilder() -> ErasedInstantiator<(), any Widget>.Builder {
			            return __safeDI_fillBody_15C1B4CA72A2CC76()
			        }
			        func __safeDI_fillBody_15C1B4CA72A2CC76() -> ErasedInstantiator<(), any Widget>.Builder {
			            func __safeDI_widgetBuilder() -> DefaultWidget {
			                DefaultWidget()
			            }
			            return { _ in __safeDI_widgetBuilder() }
			        }
			        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
			            .init(screenABuilder: { values_inner in __safeDI_apiBuilder_Home_ScreenA_Scope() }, screenBBuilder: { values_inner in __safeDI_apiBuilder_Home_ScreenB_Scope() }, folder: { values_inner, values_screenABuilder, values_screenBBuilder, values_widgetBuilder, values_workerBuilder in __safeDI_apiBuilder_Home_Folder_Scope() }, inner: __safeDI_apiBuilder_Inner())
			        }
			        func __safeDI_apiBuilder_Home_ScreenA_Scope() -> Home.__safeDI_ApiCarrier_ScreenA<any Api> {
			            .init(api: { scope_id, scope_screenBBuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_apiBuilder_Home_ScreenB_Scope() -> Home.__safeDI_ApiCarrier_ScreenB<any Api> {
			            .init(api: { scope_id, scope_screenABuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_apiBuilder_Home_Folder_Scope() -> Home.__safeDI_ApiCarrier_Folder<any Api> {
			            .init(
			                api: {
			                    let api: any Api = DefaultApi()
			                    return api
			                },
			                subfolderBuilder: { values_api, values_tracker in __safeDI_apiBuilder_Home_Folder_Scope() }
			            )
			        }
			        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
			            .init(api: {
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_defaultWidget_WidgetBuilder_Home() -> Home.__safeDI_DefaultWidget_WidgetCarrier<any Widget> {
			            .init(widgetBuilder: { values_inner, values_screenABuilder, values_screenBBuilder in __safeDI_defaultWidget_WidgetBuilder_Home_widgetBuilder() })
			        }
			        @Sendable nonisolated func __safeDI_gadgetSendableBuilder_Home() -> Home.__safeDI_GadgetSendableCarrier<any Gadget> {
			            .init(workerBuilder: { __safeDI_gadgetBuilder_Home_Worker_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_gadgetBuilder_Home_Worker_Scope() -> Home.__safeDI_GadgetCarrier_Worker<any Gadget> {
			            .init(gadget: {
			                let gadget: any Gadget = DefaultGadget()
			                return gadget
			            })
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_33C41EF320BE023C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_defaultWidget_WidgetBuilder: __safeDI_defaultWidget_WidgetBuilder_Home(), __safeDI_gadgetSendableBuilder: __safeDI_gadgetSendableBuilder_Home(), __safeDI_trackerOptionalBuilder: {
			                @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalCarrier<__safeDI_Built> {
			                    .init(screenABuilder: { _ in __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_ScreenA_Scope(__safeDI_builder) }, folder: { _, _, _, _, _ in __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Folder_Scope(__safeDI_builder) }, inner: __safeDI_noScope_Inner_SafeDICarrierScope_TrackerOptional(__safeDI_builder))
			                }
			                @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_ScreenA_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalCarrier_ScreenA<__safeDI_Built> {
			                    .init(tracker: { _, _, _ in __safeDI_builder() })
			                }
			                @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Folder_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalCarrier_Folder<__safeDI_Built> {
			                    .init(tracker: { _ in __safeDI_builder() }, subfolderBuilder: { _, _ in __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Folder_Scope(__safeDI_builder) })
			                }
			                @Sendable nonisolated func __safeDI_noScope_Inner_SafeDICarrierScope_TrackerOptional<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Inner.__safeDI_TrackerOptionalCarrier<__safeDI_Built> {
			                    .init(tracker: { _ in __safeDI_builder() })
			                }
			                return __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional({ nil })
			            }(), __safeDI_trackerOptionalSendableBuilder: {
			                @Sendable nonisolated func __safeDI_noScope_Home_SafeDISendableCarrierScope_TrackerOptional<__safeDI_Built>(_ __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalSendableCarrier<__safeDI_Built> {
			                    .init(workerBuilder: { __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Worker_Scope(__safeDI_builder) })
			                }
			                @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_TrackerOptional_Worker_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_TrackerOptionalCarrier_Worker<__safeDI_Built> {
			                    .init(tracker: { _ in __safeDI_builder() })
			                }
			                return __safeDI_noScope_Home_SafeDISendableCarrierScope_TrackerOptional({ nil })
			            }())
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""",
		])
		try await expectValuesAndRetentionEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()")])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The call of `Home`'s plain initializer that builds what `Root` builds inline.
	private static let plainInitializerCall = "Home(apiBuilder: { DefaultApi() }, defaultWidget_WidgetBuilder: { DefaultWidget() }, gadgetSendableBuilder: { DefaultGadget() }, trackerOptionalBuilder: { nil }, trackerOptionalSendableBuilder: { nil })"

	/// `Core` declares `Inner`, a seam with a place of `Api` and an optional place of `Tracker`, which `Home` passes up.
	/// `Feature`, whose seams people call, declares `Home`, a seam that holds the loop of builders of `ScreenA` and
	/// `ScreenB`, each forwarding an `id` and holding a place of `Api`, the place `widgetBuilder` held in a wrapper that
	/// forwards nothing, the `Sendable` `Worker`, whose places are of the `@Sendable` family, `Folder`, whose level holds
	/// itself through `subfolderBuilder`, and `Inner`. `App` fills every place but those of `Tracker`.
	private static let modules = [
		ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
			"public protocol Api {}",
			"public protocol Tracker: Sendable {}",
			"public protocol Gadget: Sendable {}",
			seamFixtureType(named: "Inner", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Instantiated(onlyIfAvailable: true) let tracker: (any Tracker)?"]),
		]),
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
			"public protocol Widget {}",
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: [
				"@Instantiated let screenABuilder: Instantiator<ScreenA>",
				"@Instantiated let screenBBuilder: Instantiator<ScreenB>",
				"@Instantiated(fulfilledByType: \"DefaultWidget\") let widgetBuilder: ErasedInstantiator<(), any Widget>",
				"@Instantiated let workerBuilder: SendableInstantiator<Worker>",
				"@Instantiated let folder: Folder",
				"@Instantiated let inner: Inner",
			]),
			seamFixtureType(named: "Folder", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Instantiated(onlyIfAvailable: true) let tracker: (any Tracker)?", "@Instantiated let subfolderBuilder: Instantiator<Folder>"]),
			seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Instantiated(onlyIfAvailable: true) let tracker: (any Tracker)?", "@Received let screenBBuilder: Instantiator<ScreenB>"]),
			seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenABuilder: Instantiator<ScreenA>"]),
			seamFixtureType(named: "Worker", declarations: ["@Instantiated let gadget: any Gadget", "@Instantiated(onlyIfAvailable: true) let tracker: (any Tracker)?"], conformances: ", Sendable"),
		].map { "import Core\n\n" + $0 }, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration, dependencies: ["Core"]),
		ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			seamFixtureType(named: "DefaultApi", isFinalClass: true, declarations: [], conformances: ", Api").replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n"),
			seamFixtureType(named: "DefaultWidget", isFinalClass: true, declarations: [], conformances: ", Widget").replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Widget.self])\n"),
			seamFixtureType(named: "DefaultGadget", declarations: [], conformances: ", Gadget").replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Gadget.self])\n"),
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let home: Home"]),
		].map { "import Core\nimport Feature\n\n" + $0 }, dependencies: ["Core", "Feature"]),
	]

	/// Expects `output`, the run of `modules`, to build the values the same graph built inline builds for each of
	/// `probes`, and to keep alive no more of them than the inline build keeps once each is released, calling each
	/// screen's instantiator with the `id` 7.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesAndRetentionEqualInlineBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let inlineModules = modules.map { module in
			ModuleFixture(
				name: module.name,
				packageName: module.packageName,
				swiftFileContent: inlineFixture(module.swiftFileContent),
				dependencies: module.dependencies,
			)
		}
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let graph = try DifferentialValueGraph(
			name: "levels without scope",
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: probes,
			samples: ["ScreenA", "ScreenB"].map { DifferentialValueSample(type: "\($0).ForwardedProperties", expression: "7") },
			judgesRetention: true,
		)
		let comparison = try #require(try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete)?.first?.result.get(), sourceLocation: sourceLocation)
		#expect(comparison.differences == [], sourceLocation: sourceLocation)
		#expect(comparison.retentionDifferences == [], sourceLocation: sourceLocation)
		#expect(comparison.retentionJudgedProbes == probes.map(\.name), sourceLocation: sourceLocation)
	}

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
