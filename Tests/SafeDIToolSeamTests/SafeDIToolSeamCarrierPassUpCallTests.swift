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

/// A feature's seam that calls an earlier feature's seam and passes the places of that seam's hole type up through a
/// member of its own carrier, the shape of an app's feature modules (`Feature1Entry` calling `Feature0Entry` with
/// `__safeDI_analyticsClientBuilder.feature0Builder`), one and two features deep, in plain and `Sendable` instantiators,
/// with every module nonisolated or on the main actor by default. Each feature reaches one type, `Detail`, from two
/// screens. In plain instantiators the first feature's seam, which makes no call, builds `Detail`'s tree once, shared by
/// both screens, and a calling feature's seam is expected to as well: each builder function it declares is declared
/// once. In `Sendable` instantiators every feature's tree is laid out per path, the call changing nothing.
struct SafeDIToolSeamCarrierPassUpCallTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	/// `Feature1Entry` builds `Feature0Entry` in an `Instantiator` and passes its place of `AnalyticsClient` up through its carrier's `feature0Builder` member; `Feature1Entry`'s own tree builds `Detail1`'s tree once, shared by both screens, as `Feature0Entry`'s does.
	@Test(arguments: CarrierPassUpCallIsolation.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesCallingFeaturesTree_whenFeaturePassesEarlierFeaturesPlacesUpOneFeatureDeepInInstantiators(isolation: CarrierPassUpCallIsolation) async throws {
		let modules = Self.modules(featureCount: 2, wrapper: .instantiator, isolation: isolation)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		Self.expectEachBuilderFunctionDeclaredOnce(in: output.modules["F1"]?.generatedFiles)
		CarrierCells.expectGeneratedFiles(output.modules["Core"]?.generatedFiles, ["Core.swift": generatedFileHeader])
		CarrierCells.expectGeneratedFiles(output.modules["F0"]?.generatedFiles, ["F0.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		extension Feature0Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier<__safeDI_Built> {
		        public let firstScreenBuilder: (Network) -> __safeDI_AnalyticsClientCarrier_FirstScreen0<__safeDI_Built>
		        public let secondScreenBuilder: (Network, Instantiator<FirstScreen0>) -> __safeDI_AnalyticsClientCarrier_SecondScreen0<__safeDI_Built>

		        public init(firstScreenBuilder: @escaping (Network) -> __safeDI_AnalyticsClientCarrier_FirstScreen0<__safeDI_Built>, secondScreenBuilder: @escaping (Network, Instantiator<FirstScreen0>) -> __safeDI_AnalyticsClientCarrier_SecondScreen0<__safeDI_Built>) {
		            self.firstScreenBuilder = firstScreenBuilder
		            self.secondScreenBuilder = secondScreenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(firstScreenBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, secondScreenBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_FirstScreen0<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_SecondScreen0<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientBuilder: __safeDI_AnalyticsClientCarrier<any AnalyticsClient>) {
		        let __safeDI_analyticsClientBuilder_firstScreenBuilder = __safeDI_analyticsClientBuilder.firstScreenBuilder(network)
		        func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<any AnalyticsClient>) -> Detail0 {
		            let __safeDI_analyticsClientBuilder_viewModel = __safeDI_analyticsClientBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel0 = __safeDI_viewModel(id: id, __safeDI_analyticsClientBuilder_viewModel: __safeDI_analyticsClientBuilder_viewModel)
		            return Detail0(id: id, viewModel: viewModel)
		        }
		        func __safeDI_viewModel(id: Int, __safeDI_analyticsClientBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel0<any AnalyticsClient>) -> ViewModel0 {
		            let __safeDI_analyticsClientBuilder_repository = __safeDI_analyticsClientBuilder_viewModel.repository
		            let repository: Repository0 = __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_analyticsClientBuilder_repository)
		            return ViewModel0(id: id, repository: repository)
		        }
		        func __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository0<any AnalyticsClient>) -> Repository0 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientBuilder_repository.analytics(formatter)
		            return Repository0(network: network, formatter: formatter, analytics: analytics)
		        }
		        func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        func __safeDI_firstScreenBuilder() -> FirstScreen0 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_firstScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail0> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return FirstScreen0(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = Instantiator<FirstScreen0>(__safeDI_firstScreenBuilder)
		        let __safeDI_analyticsClientBuilder_secondScreenBuilder = __safeDI_analyticsClientBuilder.secondScreenBuilder(network, firstScreenBuilder)
		        func __safeDI_secondScreenBuilder() -> SecondScreen0 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_secondScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail0> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return SecondScreen0(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = Instantiator<SecondScreen0>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder)
		    }
		}

		extension Feature0Entry {
		    public enum __safeDI_Feature0Entry_8B16125A03853C52 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["F1"]?.generatedFiles, ["F1.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif

		extension Feature1Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier<__safeDI_Built> {
		        public let firstScreenBuilder: (Network, Instantiator<Feature0Entry>) -> __safeDI_AnalyticsClientCarrier_FirstScreen1<__safeDI_Built>
		        public let secondScreenBuilder: (Network, Instantiator<Feature0Entry>, Instantiator<FirstScreen1>) -> __safeDI_AnalyticsClientCarrier_SecondScreen1<__safeDI_Built>
		        public let feature0Builder: Feature0Entry.__safeDI_AnalyticsClientCarrier<__safeDI_Built>

		        public init(firstScreenBuilder: @escaping (Network, Instantiator<Feature0Entry>) -> __safeDI_AnalyticsClientCarrier_FirstScreen1<__safeDI_Built>, secondScreenBuilder: @escaping (Network, Instantiator<Feature0Entry>, Instantiator<FirstScreen1>) -> __safeDI_AnalyticsClientCarrier_SecondScreen1<__safeDI_Built>, feature0Builder: Feature0Entry.__safeDI_AnalyticsClientCarrier<__safeDI_Built>) {
		            self.firstScreenBuilder = firstScreenBuilder
		            self.secondScreenBuilder = secondScreenBuilder
		            self.feature0Builder = feature0Builder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(firstScreenBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) }, secondScreenBuilder: { _, _, _ in .init(__safeDI_noScope: __safeDI_builder) }, feature0Builder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_FirstScreen1<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_SecondScreen1<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientBuilder: __safeDI_AnalyticsClientCarrier<any AnalyticsClient>) {
		        func __safeDI_feature0Builder() -> Feature0Entry {
		            _ = Feature0Entry.__safeDI_Feature0Entry_8B16125A03853C52.self // If this line does not compile, compile the code SafeDI generates for module F0 into F0: under Bazel, add F0’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feature0Entry(__safeDI_network: network, __safeDI_analyticsClientBuilder: __safeDI_analyticsClientBuilder.feature0Builder)
		        }
		        let feature0Builder = Instantiator<Feature0Entry>(__safeDI_feature0Builder)
		        let __safeDI_analyticsClientBuilder_firstScreenBuilder = __safeDI_analyticsClientBuilder.firstScreenBuilder(network, feature0Builder)
		        func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<any AnalyticsClient>) -> Detail1 {
		            let __safeDI_analyticsClientBuilder_viewModel = __safeDI_analyticsClientBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel1 = __safeDI_viewModel(id: id, __safeDI_analyticsClientBuilder_viewModel: __safeDI_analyticsClientBuilder_viewModel)
		            return Detail1(id: id, viewModel: viewModel)
		        }
		        func __safeDI_viewModel(id: Int, __safeDI_analyticsClientBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel1<any AnalyticsClient>) -> ViewModel1 {
		            let __safeDI_analyticsClientBuilder_repository = __safeDI_analyticsClientBuilder_viewModel.repository
		            let repository: Repository1 = __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_analyticsClientBuilder_repository)
		            return ViewModel1(id: id, repository: repository)
		        }
		        func __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository1<any AnalyticsClient>) -> Repository1 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientBuilder_repository.analytics(formatter)
		            return Repository1(network: network, formatter: formatter, analytics: analytics)
		        }
		        func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        func __safeDI_firstScreenBuilder() -> FirstScreen1 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_firstScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail1> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return FirstScreen1(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = Instantiator<FirstScreen1>(__safeDI_firstScreenBuilder)
		        let __safeDI_analyticsClientBuilder_secondScreenBuilder = __safeDI_analyticsClientBuilder.secondScreenBuilder(network, feature0Builder, firstScreenBuilder)
		        func __safeDI_secondScreenBuilder() -> SecondScreen1 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_secondScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail1> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return SecondScreen1(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = Instantiator<SecondScreen1>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder, feature0Builder: feature0Builder)
		    }
		}

		extension Feature1Entry {
		    public enum __safeDI_Feature1Entry_824FA1E88641FD73 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif
		#if canImport(F1)
		import F1
		#endif

		extension Root {
		    public init() {
		        func __safeDI_analyticsClientBuilder_Feature1Entry() -> Feature1Entry.__safeDI_AnalyticsClientCarrier<any AnalyticsClient> {
		            .init(firstScreenBuilder: { values_network, values_feature0Builder in __safeDI_analyticsClientBuilder_Feature1Entry_FirstScreen1_Scope(network: values_network) }, secondScreenBuilder: { values_network, values_feature0Builder, values_firstScreenBuilder in __safeDI_analyticsClientBuilder_Feature1Entry_SecondScreen1_Scope(network: values_network) }, feature0Builder: __safeDI_analyticsClientBuilder_Feature0Entry())
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_FirstScreen1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_FirstScreen1<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_Detail1<any AnalyticsClient> {
		            .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature1Entry_ViewModel1_Scope(network: network) })
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_ViewModel1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_ViewModel1<any AnalyticsClient> {
		            .init(repository: __safeDI_analyticsClientBuilder_Feature1Entry_Repository1_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_Repository1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_Repository1<any AnalyticsClient> {
		            .init(analytics: { scope_formatter in
		                let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                return analytics
		            })
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_SecondScreen1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_SecondScreen1<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry() -> Feature0Entry.__safeDI_AnalyticsClientCarrier<any AnalyticsClient> {
		            .init(firstScreenBuilder: { values_network in __safeDI_analyticsClientBuilder_Feature0Entry_FirstScreen0_Scope(network: values_network) }, secondScreenBuilder: { values_network, values_firstScreenBuilder in __safeDI_analyticsClientBuilder_Feature0Entry_SecondScreen0_Scope(network: values_network) })
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_FirstScreen0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_FirstScreen0<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_Detail0<any AnalyticsClient> {
		            .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature0Entry_ViewModel0_Scope(network: network) })
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_ViewModel0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_ViewModel0<any AnalyticsClient> {
		            .init(repository: __safeDI_analyticsClientBuilder_Feature0Entry_Repository0_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_Repository0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_Repository0<any AnalyticsClient> {
		            .init(analytics: { scope_formatter in
		                let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                return analytics
		            })
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_SecondScreen0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_SecondScreen0<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope(network: network))
		        }
		        let network = Network()
		        func __safeDI_feature() -> Feature1Entry {
		            _ = Feature1Entry.__safeDI_Feature1Entry_824FA1E88641FD73.self // If this line does not compile, compile the code SafeDI generates for module F1 into F1: under Bazel, add F1’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feature1Entry(__safeDI_network: network, __safeDI_analyticsClientBuilder: __safeDI_analyticsClientBuilder_Feature1Entry())
		        }
		        let feature: Feature1Entry = __safeDI_feature()
		        self.init(network: network, feature: feature)
		    }
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: [DifferentialValueSample(type: "Int", expression: "7")], filesToDelete: &filesToDelete)
	}

	/// The same feature modules built in `SendableInstantiator`s: the `@Sendable` family lays the calling feature's tree out as it lays out the called feature's, which makes no call.
	@Test(arguments: CarrierPassUpCallIsolation.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutCallingFeatureAsFirstFeature_whenFeaturePassesEarlierFeaturesPlacesUpOneFeatureDeepInSendableInstantiators(isolation: CarrierPassUpCallIsolation) async throws {
		let modules = Self.modules(featureCount: 2, wrapper: .sendableInstantiator, isolation: isolation)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Core"]?.generatedFiles, ["Core.swift": generatedFileHeader])
		CarrierCells.expectGeneratedFiles(output.modules["F0"]?.generatedFiles, ["F0.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		extension Feature0Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>: Sendable {
		        public let firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen0<__safeDI_Built>
		        public let secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen0<__safeDI_Built>

		        public init(firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen0<__safeDI_Built>, secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen0<__safeDI_Built>) {
		            self.firstScreenBuilder_Sendable = firstScreenBuilder_Sendable
		            self.secondScreenBuilder_Sendable = secondScreenBuilder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(firstScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder), secondScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_FirstScreen0<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_SecondScreen0<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientSendableBuilder: __safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient>) {
		        @Sendable nonisolated func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen0<any AnalyticsClient>) -> Detail0 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel0 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail0(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_viewModel(id: Int, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel0<any AnalyticsClient>) -> ViewModel0 {
		            let __safeDI_analyticsClientSendableBuilder_repository = __safeDI_analyticsClientSendableBuilder_viewModel.repository
		            let repository: Repository0 = __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_analyticsClientSendableBuilder_repository)
		            return ViewModel0(id: id, repository: repository)
		        }
		        @Sendable nonisolated func __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository0<any AnalyticsClient>) -> Repository0 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientSendableBuilder_repository.analytics(formatter)
		            return Repository0(network: network, formatter: formatter, analytics: analytics)
		        }
		        @Sendable nonisolated func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        @Sendable nonisolated func __safeDI_firstScreenBuilder() -> FirstScreen0 {
		            let __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.firstScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail0> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable)
		            }
		            return FirstScreen0(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = SendableInstantiator<FirstScreen0>(__safeDI_firstScreenBuilder)
		        @Sendable nonisolated func __safeDI_detailBuilder_(id: Int, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen0<any AnalyticsClient>) -> Detail0 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel0 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail0(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_secondScreenBuilder() -> SecondScreen0 {
		            let __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.secondScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail0> {
		                __safeDI_detailBuilder_(id: $0, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable)
		            }
		            return SecondScreen0(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = SendableInstantiator<SecondScreen0>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder)
		    }
		}

		extension Feature0Entry {
		    public enum __safeDI_Feature0Entry_D3596DAC6DF7FC8E {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["F1"]?.generatedFiles, ["F1.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif

		extension Feature1Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>: Sendable {
		        public let firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen1<__safeDI_Built>
		        public let secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen1<__safeDI_Built>
		        public let feature0Builder_Sendable: Feature0Entry.__safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>

		        public init(firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen1<__safeDI_Built>, secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen1<__safeDI_Built>, feature0Builder_Sendable: Feature0Entry.__safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>) {
		            self.firstScreenBuilder_Sendable = firstScreenBuilder_Sendable
		            self.secondScreenBuilder_Sendable = secondScreenBuilder_Sendable
		            self.feature0Builder_Sendable = feature0Builder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(firstScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder), secondScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder), feature0Builder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_FirstScreen1<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_SecondScreen1<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientSendableBuilder: __safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient>) {
		        @Sendable nonisolated func __safeDI_feature0Builder() -> Feature0Entry {
		            _ = Feature0Entry.__safeDI_Feature0Entry_D3596DAC6DF7FC8E.self // If this line does not compile, compile the code SafeDI generates for module F0 into F0: under Bazel, add F0’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feature0Entry(__safeDI_network: network, __safeDI_analyticsClientSendableBuilder: __safeDI_analyticsClientSendableBuilder.feature0Builder_Sendable)
		        }
		        let feature0Builder = SendableInstantiator<Feature0Entry>(__safeDI_feature0Builder)
		        @Sendable nonisolated func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen1<any AnalyticsClient>) -> Detail1 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel1 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail1(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_viewModel(id: Int, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel1<any AnalyticsClient>) -> ViewModel1 {
		            let __safeDI_analyticsClientSendableBuilder_repository = __safeDI_analyticsClientSendableBuilder_viewModel.repository
		            let repository: Repository1 = __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_analyticsClientSendableBuilder_repository)
		            return ViewModel1(id: id, repository: repository)
		        }
		        @Sendable nonisolated func __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository1<any AnalyticsClient>) -> Repository1 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientSendableBuilder_repository.analytics(formatter)
		            return Repository1(network: network, formatter: formatter, analytics: analytics)
		        }
		        @Sendable nonisolated func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        @Sendable nonisolated func __safeDI_firstScreenBuilder() -> FirstScreen1 {
		            let __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.firstScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail1> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable)
		            }
		            return FirstScreen1(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = SendableInstantiator<FirstScreen1>(__safeDI_firstScreenBuilder)
		        @Sendable nonisolated func __safeDI_detailBuilder_(id: Int, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen1<any AnalyticsClient>) -> Detail1 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel1 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail1(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_secondScreenBuilder() -> SecondScreen1 {
		            let __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.secondScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail1> {
		                __safeDI_detailBuilder_(id: $0, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable)
		            }
		            return SecondScreen1(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = SendableInstantiator<SecondScreen1>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder, feature0Builder: feature0Builder)
		    }
		}

		extension Feature1Entry {
		    public enum __safeDI_Feature1Entry_CF8DB3BC69D52074 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif
		#if canImport(F1)
		import F1
		#endif

		extension Root {
		    public init() {
		        let network = Network()
		        func __safeDI_feature() -> Feature1Entry {
		            _ = Feature1Entry.__safeDI_Feature1Entry_CF8DB3BC69D52074.self // If this line does not compile, compile the code SafeDI generates for module F1 into F1: under Bazel, add F1’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature1Entry() -> Feature1Entry.__safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient> {
		                .init(firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature1Entry_FirstScreen1_Scope(), secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature1Entry_SecondScreen1_Scope(), feature0Builder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature0Entry())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature1Entry_FirstScreen1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientSendableCarrier_FirstScreen1<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientCarrier_Detail1<any AnalyticsClient> {
		                .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature1Entry_ViewModel1_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature1Entry_ViewModel1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientCarrier_ViewModel1<any AnalyticsClient> {
		                .init(repository: __safeDI_analyticsClientBuilder_Feature1Entry_Repository1_Scope())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature1Entry_Repository1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientCarrier_Repository1<any AnalyticsClient> {
		                .init(analytics: { scope_formatter in
		                    let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                    return analytics
		                })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature1Entry_SecondScreen1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientSendableCarrier_SecondScreen1<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature0Entry() -> Feature0Entry.__safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient> {
		                .init(firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature0Entry_FirstScreen0_Scope(), secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature0Entry_SecondScreen0_Scope())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature0Entry_FirstScreen0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientSendableCarrier_FirstScreen0<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientCarrier_Detail0<any AnalyticsClient> {
		                .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature0Entry_ViewModel0_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature0Entry_ViewModel0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientCarrier_ViewModel0<any AnalyticsClient> {
		                .init(repository: __safeDI_analyticsClientBuilder_Feature0Entry_Repository0_Scope())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature0Entry_Repository0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientCarrier_Repository0<any AnalyticsClient> {
		                .init(analytics: { scope_formatter in
		                    let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                    return analytics
		                })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature0Entry_SecondScreen0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientSendableCarrier_SecondScreen0<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope() })
		            }
		            return Feature1Entry(__safeDI_network: network, __safeDI_analyticsClientSendableBuilder: __safeDI_analyticsClientSendableBuilder_Feature1Entry())
		        }
		        let feature: Feature1Entry = __safeDI_feature()
		        self.init(network: network, feature: feature)
		    }
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: [DifferentialValueSample(type: "Int", expression: "7")], filesToDelete: &filesToDelete)
	}

	/// `Feature2Entry` calls `Feature1Entry`, which calls `Feature0Entry`, each passing the places of the seam it calls up through its own carrier, and each calling feature's tree builds its `Detail`'s tree once.
	@Test(arguments: CarrierPassUpCallIsolation.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sharesCallingFeaturesTree_whenFeaturePassesEarlierFeaturesPlacesUpTwoFeaturesDeepInInstantiators(isolation: CarrierPassUpCallIsolation) async throws {
		let modules = Self.modules(featureCount: 3, wrapper: .instantiator, isolation: isolation)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		Self.expectEachBuilderFunctionDeclaredOnce(in: output.modules["F1"]?.generatedFiles)
		Self.expectEachBuilderFunctionDeclaredOnce(in: output.modules["F2"]?.generatedFiles)
		CarrierCells.expectGeneratedFiles(output.modules["Core"]?.generatedFiles, ["Core.swift": generatedFileHeader])
		CarrierCells.expectGeneratedFiles(output.modules["F0"]?.generatedFiles, ["F0.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		extension Feature0Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier<__safeDI_Built> {
		        public let firstScreenBuilder: (Network) -> __safeDI_AnalyticsClientCarrier_FirstScreen0<__safeDI_Built>
		        public let secondScreenBuilder: (Network, Instantiator<FirstScreen0>) -> __safeDI_AnalyticsClientCarrier_SecondScreen0<__safeDI_Built>

		        public init(firstScreenBuilder: @escaping (Network) -> __safeDI_AnalyticsClientCarrier_FirstScreen0<__safeDI_Built>, secondScreenBuilder: @escaping (Network, Instantiator<FirstScreen0>) -> __safeDI_AnalyticsClientCarrier_SecondScreen0<__safeDI_Built>) {
		            self.firstScreenBuilder = firstScreenBuilder
		            self.secondScreenBuilder = secondScreenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(firstScreenBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, secondScreenBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_FirstScreen0<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_SecondScreen0<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientBuilder: __safeDI_AnalyticsClientCarrier<any AnalyticsClient>) {
		        let __safeDI_analyticsClientBuilder_firstScreenBuilder = __safeDI_analyticsClientBuilder.firstScreenBuilder(network)
		        func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_AnalyticsClientCarrier_Detail0<any AnalyticsClient>) -> Detail0 {
		            let __safeDI_analyticsClientBuilder_viewModel = __safeDI_analyticsClientBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel0 = __safeDI_viewModel(id: id, __safeDI_analyticsClientBuilder_viewModel: __safeDI_analyticsClientBuilder_viewModel)
		            return Detail0(id: id, viewModel: viewModel)
		        }
		        func __safeDI_viewModel(id: Int, __safeDI_analyticsClientBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel0<any AnalyticsClient>) -> ViewModel0 {
		            let __safeDI_analyticsClientBuilder_repository = __safeDI_analyticsClientBuilder_viewModel.repository
		            let repository: Repository0 = __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_analyticsClientBuilder_repository)
		            return ViewModel0(id: id, repository: repository)
		        }
		        func __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository0<any AnalyticsClient>) -> Repository0 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientBuilder_repository.analytics(formatter)
		            return Repository0(network: network, formatter: formatter, analytics: analytics)
		        }
		        func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        func __safeDI_firstScreenBuilder() -> FirstScreen0 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_firstScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail0> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return FirstScreen0(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = Instantiator<FirstScreen0>(__safeDI_firstScreenBuilder)
		        let __safeDI_analyticsClientBuilder_secondScreenBuilder = __safeDI_analyticsClientBuilder.secondScreenBuilder(network, firstScreenBuilder)
		        func __safeDI_secondScreenBuilder() -> SecondScreen0 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_secondScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail0> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return SecondScreen0(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = Instantiator<SecondScreen0>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder)
		    }
		}

		extension Feature0Entry {
		    public enum __safeDI_Feature0Entry_8B16125A03853C52 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["F1"]?.generatedFiles, ["F1.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif

		extension Feature1Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier<__safeDI_Built> {
		        public let firstScreenBuilder: (Network, Instantiator<Feature0Entry>) -> __safeDI_AnalyticsClientCarrier_FirstScreen1<__safeDI_Built>
		        public let secondScreenBuilder: (Network, Instantiator<Feature0Entry>, Instantiator<FirstScreen1>) -> __safeDI_AnalyticsClientCarrier_SecondScreen1<__safeDI_Built>
		        public let feature0Builder: Feature0Entry.__safeDI_AnalyticsClientCarrier<__safeDI_Built>

		        public init(firstScreenBuilder: @escaping (Network, Instantiator<Feature0Entry>) -> __safeDI_AnalyticsClientCarrier_FirstScreen1<__safeDI_Built>, secondScreenBuilder: @escaping (Network, Instantiator<Feature0Entry>, Instantiator<FirstScreen1>) -> __safeDI_AnalyticsClientCarrier_SecondScreen1<__safeDI_Built>, feature0Builder: Feature0Entry.__safeDI_AnalyticsClientCarrier<__safeDI_Built>) {
		            self.firstScreenBuilder = firstScreenBuilder
		            self.secondScreenBuilder = secondScreenBuilder
		            self.feature0Builder = feature0Builder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(firstScreenBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) }, secondScreenBuilder: { _, _, _ in .init(__safeDI_noScope: __safeDI_builder) }, feature0Builder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_FirstScreen1<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_SecondScreen1<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientBuilder: __safeDI_AnalyticsClientCarrier<any AnalyticsClient>) {
		        func __safeDI_feature0Builder() -> Feature0Entry {
		            _ = Feature0Entry.__safeDI_Feature0Entry_8B16125A03853C52.self // If this line does not compile, compile the code SafeDI generates for module F0 into F0: under Bazel, add F0’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feature0Entry(__safeDI_network: network, __safeDI_analyticsClientBuilder: __safeDI_analyticsClientBuilder.feature0Builder)
		        }
		        let feature0Builder = Instantiator<Feature0Entry>(__safeDI_feature0Builder)
		        let __safeDI_analyticsClientBuilder_firstScreenBuilder = __safeDI_analyticsClientBuilder.firstScreenBuilder(network, feature0Builder)
		        func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_AnalyticsClientCarrier_Detail1<any AnalyticsClient>) -> Detail1 {
		            let __safeDI_analyticsClientBuilder_viewModel = __safeDI_analyticsClientBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel1 = __safeDI_viewModel(id: id, __safeDI_analyticsClientBuilder_viewModel: __safeDI_analyticsClientBuilder_viewModel)
		            return Detail1(id: id, viewModel: viewModel)
		        }
		        func __safeDI_viewModel(id: Int, __safeDI_analyticsClientBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel1<any AnalyticsClient>) -> ViewModel1 {
		            let __safeDI_analyticsClientBuilder_repository = __safeDI_analyticsClientBuilder_viewModel.repository
		            let repository: Repository1 = __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_analyticsClientBuilder_repository)
		            return ViewModel1(id: id, repository: repository)
		        }
		        func __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository1<any AnalyticsClient>) -> Repository1 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientBuilder_repository.analytics(formatter)
		            return Repository1(network: network, formatter: formatter, analytics: analytics)
		        }
		        func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        func __safeDI_firstScreenBuilder() -> FirstScreen1 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_firstScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail1> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return FirstScreen1(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = Instantiator<FirstScreen1>(__safeDI_firstScreenBuilder)
		        let __safeDI_analyticsClientBuilder_secondScreenBuilder = __safeDI_analyticsClientBuilder.secondScreenBuilder(network, feature0Builder, firstScreenBuilder)
		        func __safeDI_secondScreenBuilder() -> SecondScreen1 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_secondScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail1> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return SecondScreen1(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = Instantiator<SecondScreen1>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder, feature0Builder: feature0Builder)
		    }
		}

		extension Feature1Entry {
		    public enum __safeDI_Feature1Entry_824FA1E88641FD73 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["F2"]?.generatedFiles, ["F2.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif
		#if canImport(F1)
		import F1
		#endif

		extension Feature2Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier<__safeDI_Built> {
		        public let firstScreenBuilder: (Network, Instantiator<Feature1Entry>) -> __safeDI_AnalyticsClientCarrier_FirstScreen2<__safeDI_Built>
		        public let secondScreenBuilder: (Network, Instantiator<Feature1Entry>, Instantiator<FirstScreen2>) -> __safeDI_AnalyticsClientCarrier_SecondScreen2<__safeDI_Built>
		        public let feature1Builder: Feature1Entry.__safeDI_AnalyticsClientCarrier<__safeDI_Built>

		        public init(firstScreenBuilder: @escaping (Network, Instantiator<Feature1Entry>) -> __safeDI_AnalyticsClientCarrier_FirstScreen2<__safeDI_Built>, secondScreenBuilder: @escaping (Network, Instantiator<Feature1Entry>, Instantiator<FirstScreen2>) -> __safeDI_AnalyticsClientCarrier_SecondScreen2<__safeDI_Built>, feature1Builder: Feature1Entry.__safeDI_AnalyticsClientCarrier<__safeDI_Built>) {
		            self.firstScreenBuilder = firstScreenBuilder
		            self.secondScreenBuilder = secondScreenBuilder
		            self.feature1Builder = feature1Builder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(firstScreenBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) }, secondScreenBuilder: { _, _, _ in .init(__safeDI_noScope: __safeDI_builder) }, feature1Builder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_FirstScreen2<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_SecondScreen2<__safeDI_Built> {
		        public let detailBuilder: __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built>

		        public init(detailBuilder: __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel2<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel2<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel2<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository2<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository2<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository2<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientBuilder: __safeDI_AnalyticsClientCarrier<any AnalyticsClient>) {
		        func __safeDI_feature1Builder() -> Feature1Entry {
		            _ = Feature1Entry.__safeDI_Feature1Entry_824FA1E88641FD73.self // If this line does not compile, compile the code SafeDI generates for module F1 into F1: under Bazel, add F1’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feature1Entry(__safeDI_network: network, __safeDI_analyticsClientBuilder: __safeDI_analyticsClientBuilder.feature1Builder)
		        }
		        let feature1Builder = Instantiator<Feature1Entry>(__safeDI_feature1Builder)
		        let __safeDI_analyticsClientBuilder_firstScreenBuilder = __safeDI_analyticsClientBuilder.firstScreenBuilder(network, feature1Builder)
		        func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_AnalyticsClientCarrier_Detail2<any AnalyticsClient>) -> Detail2 {
		            let __safeDI_analyticsClientBuilder_viewModel = __safeDI_analyticsClientBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel2 = __safeDI_viewModel(id: id, __safeDI_analyticsClientBuilder_viewModel: __safeDI_analyticsClientBuilder_viewModel)
		            return Detail2(id: id, viewModel: viewModel)
		        }
		        func __safeDI_viewModel(id: Int, __safeDI_analyticsClientBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel2<any AnalyticsClient>) -> ViewModel2 {
		            let __safeDI_analyticsClientBuilder_repository = __safeDI_analyticsClientBuilder_viewModel.repository
		            let repository: Repository2 = __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_analyticsClientBuilder_repository)
		            return ViewModel2(id: id, repository: repository)
		        }
		        func __safeDI_repository(__safeDI_analyticsClientBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository2<any AnalyticsClient>) -> Repository2 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientBuilder_repository.analytics(formatter)
		            return Repository2(network: network, formatter: formatter, analytics: analytics)
		        }
		        func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        func __safeDI_firstScreenBuilder() -> FirstScreen2 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_firstScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail2> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return FirstScreen2(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = Instantiator<FirstScreen2>(__safeDI_firstScreenBuilder)
		        let __safeDI_analyticsClientBuilder_secondScreenBuilder = __safeDI_analyticsClientBuilder.secondScreenBuilder(network, feature1Builder, firstScreenBuilder)
		        func __safeDI_secondScreenBuilder() -> SecondScreen2 {
		            let __safeDI_analyticsClientBuilder_detailBuilder = __safeDI_analyticsClientBuilder_secondScreenBuilder.detailBuilder
		            let detailBuilder = Instantiator<Detail2> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientBuilder_detailBuilder: __safeDI_analyticsClientBuilder_detailBuilder)
		            }
		            return SecondScreen2(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = Instantiator<SecondScreen2>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder, feature1Builder: feature1Builder)
		    }
		}

		extension Feature2Entry {
		    public enum __safeDI_Feature2Entry_FCB1BD22856BD623 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif
		#if canImport(F1)
		import F1
		#endif
		#if canImport(F2)
		import F2
		#endif

		extension Root {
		    public init() {
		        func __safeDI_analyticsClientBuilder_Feature2Entry() -> Feature2Entry.__safeDI_AnalyticsClientCarrier<any AnalyticsClient> {
		            .init(firstScreenBuilder: { values_network, values_feature1Builder in __safeDI_analyticsClientBuilder_Feature2Entry_FirstScreen2_Scope(network: values_network) }, secondScreenBuilder: { values_network, values_feature1Builder, values_firstScreenBuilder in __safeDI_analyticsClientBuilder_Feature2Entry_SecondScreen2_Scope(network: values_network) }, feature1Builder: __safeDI_analyticsClientBuilder_Feature1Entry())
		        }
		        func __safeDI_analyticsClientBuilder_Feature2Entry_FirstScreen2_Scope(network: Network) -> Feature2Entry.__safeDI_AnalyticsClientCarrier_FirstScreen2<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature2Entry_Detail2_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature2Entry_Detail2_Scope(network: Network) -> Feature2Entry.__safeDI_AnalyticsClientCarrier_Detail2<any AnalyticsClient> {
		            .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature2Entry_ViewModel2_Scope(network: network) })
		        }
		        func __safeDI_analyticsClientBuilder_Feature2Entry_ViewModel2_Scope(network: Network) -> Feature2Entry.__safeDI_AnalyticsClientCarrier_ViewModel2<any AnalyticsClient> {
		            .init(repository: __safeDI_analyticsClientBuilder_Feature2Entry_Repository2_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature2Entry_Repository2_Scope(network: Network) -> Feature2Entry.__safeDI_AnalyticsClientCarrier_Repository2<any AnalyticsClient> {
		            .init(analytics: { scope_formatter in
		                let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                return analytics
		            })
		        }
		        func __safeDI_analyticsClientBuilder_Feature2Entry_SecondScreen2_Scope(network: Network) -> Feature2Entry.__safeDI_AnalyticsClientCarrier_SecondScreen2<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature2Entry_Detail2_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry() -> Feature1Entry.__safeDI_AnalyticsClientCarrier<any AnalyticsClient> {
		            .init(firstScreenBuilder: { values_network, values_feature0Builder in __safeDI_analyticsClientBuilder_Feature1Entry_FirstScreen1_Scope(network: values_network) }, secondScreenBuilder: { values_network, values_feature0Builder, values_firstScreenBuilder in __safeDI_analyticsClientBuilder_Feature1Entry_SecondScreen1_Scope(network: values_network) }, feature0Builder: __safeDI_analyticsClientBuilder_Feature0Entry())
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_FirstScreen1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_FirstScreen1<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_Detail1<any AnalyticsClient> {
		            .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature1Entry_ViewModel1_Scope(network: network) })
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_ViewModel1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_ViewModel1<any AnalyticsClient> {
		            .init(repository: __safeDI_analyticsClientBuilder_Feature1Entry_Repository1_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_Repository1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_Repository1<any AnalyticsClient> {
		            .init(analytics: { scope_formatter in
		                let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                return analytics
		            })
		        }
		        func __safeDI_analyticsClientBuilder_Feature1Entry_SecondScreen1_Scope(network: Network) -> Feature1Entry.__safeDI_AnalyticsClientCarrier_SecondScreen1<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry() -> Feature0Entry.__safeDI_AnalyticsClientCarrier<any AnalyticsClient> {
		            .init(firstScreenBuilder: { values_network in __safeDI_analyticsClientBuilder_Feature0Entry_FirstScreen0_Scope(network: values_network) }, secondScreenBuilder: { values_network, values_firstScreenBuilder in __safeDI_analyticsClientBuilder_Feature0Entry_SecondScreen0_Scope(network: values_network) })
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_FirstScreen0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_FirstScreen0<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_Detail0<any AnalyticsClient> {
		            .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature0Entry_ViewModel0_Scope(network: network) })
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_ViewModel0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_ViewModel0<any AnalyticsClient> {
		            .init(repository: __safeDI_analyticsClientBuilder_Feature0Entry_Repository0_Scope(network: network))
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_Repository0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_Repository0<any AnalyticsClient> {
		            .init(analytics: { scope_formatter in
		                let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                return analytics
		            })
		        }
		        func __safeDI_analyticsClientBuilder_Feature0Entry_SecondScreen0_Scope(network: Network) -> Feature0Entry.__safeDI_AnalyticsClientCarrier_SecondScreen0<any AnalyticsClient> {
		            .init(detailBuilder: __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope(network: network))
		        }
		        let network = Network()
		        func __safeDI_feature() -> Feature2Entry {
		            _ = Feature2Entry.__safeDI_Feature2Entry_FCB1BD22856BD623.self // If this line does not compile, compile the code SafeDI generates for module F2 into F2: under Bazel, add F2’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feature2Entry(__safeDI_network: network, __safeDI_analyticsClientBuilder: __safeDI_analyticsClientBuilder_Feature2Entry())
		        }
		        let feature: Feature2Entry = __safeDI_feature()
		        self.init(network: network, feature: feature)
		    }
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: [DifferentialValueSample(type: "Int", expression: "7")], filesToDelete: &filesToDelete)
	}

	/// The two-deep feature modules built in `SendableInstantiator`s: each calling feature's tree is laid out as the first feature's, which makes no call.
	@Test(arguments: CarrierPassUpCallIsolation.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutCallingFeatureAsFirstFeature_whenFeaturePassesEarlierFeaturesPlacesUpTwoFeaturesDeepInSendableInstantiators(isolation: CarrierPassUpCallIsolation) async throws {
		let modules = Self.modules(featureCount: 3, wrapper: .sendableInstantiator, isolation: isolation)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Core"]?.generatedFiles, ["Core.swift": generatedFileHeader])
		CarrierCells.expectGeneratedFiles(output.modules["F0"]?.generatedFiles, ["F0.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		extension Feature0Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel0<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository0<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>: Sendable {
		        public let firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen0<__safeDI_Built>
		        public let secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen0<__safeDI_Built>

		        public init(firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen0<__safeDI_Built>, secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen0<__safeDI_Built>) {
		            self.firstScreenBuilder_Sendable = firstScreenBuilder_Sendable
		            self.secondScreenBuilder_Sendable = secondScreenBuilder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(firstScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder), secondScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_FirstScreen0<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_SecondScreen0<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail0<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientSendableBuilder: __safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient>) {
		        @Sendable nonisolated func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen0<any AnalyticsClient>) -> Detail0 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel0 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail0(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_viewModel(id: Int, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel0<any AnalyticsClient>) -> ViewModel0 {
		            let __safeDI_analyticsClientSendableBuilder_repository = __safeDI_analyticsClientSendableBuilder_viewModel.repository
		            let repository: Repository0 = __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_analyticsClientSendableBuilder_repository)
		            return ViewModel0(id: id, repository: repository)
		        }
		        @Sendable nonisolated func __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository0<any AnalyticsClient>) -> Repository0 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientSendableBuilder_repository.analytics(formatter)
		            return Repository0(network: network, formatter: formatter, analytics: analytics)
		        }
		        @Sendable nonisolated func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        @Sendable nonisolated func __safeDI_firstScreenBuilder() -> FirstScreen0 {
		            let __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.firstScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail0> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable)
		            }
		            return FirstScreen0(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = SendableInstantiator<FirstScreen0>(__safeDI_firstScreenBuilder)
		        @Sendable nonisolated func __safeDI_detailBuilder_(id: Int, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen0<any AnalyticsClient>) -> Detail0 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel0 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail0(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_secondScreenBuilder() -> SecondScreen0 {
		            let __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.secondScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail0> {
		                __safeDI_detailBuilder_(id: $0, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable)
		            }
		            return SecondScreen0(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = SendableInstantiator<SecondScreen0>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder)
		    }
		}

		extension Feature0Entry {
		    public enum __safeDI_Feature0Entry_D3596DAC6DF7FC8E {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["F1"]?.generatedFiles, ["F1.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif

		extension Feature1Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel1<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository1<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>: Sendable {
		        public let firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen1<__safeDI_Built>
		        public let secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen1<__safeDI_Built>
		        public let feature0Builder_Sendable: Feature0Entry.__safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>

		        public init(firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen1<__safeDI_Built>, secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen1<__safeDI_Built>, feature0Builder_Sendable: Feature0Entry.__safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>) {
		            self.firstScreenBuilder_Sendable = firstScreenBuilder_Sendable
		            self.secondScreenBuilder_Sendable = secondScreenBuilder_Sendable
		            self.feature0Builder_Sendable = feature0Builder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(firstScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder), secondScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder), feature0Builder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_FirstScreen1<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_SecondScreen1<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail1<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientSendableBuilder: __safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient>) {
		        @Sendable nonisolated func __safeDI_feature0Builder() -> Feature0Entry {
		            _ = Feature0Entry.__safeDI_Feature0Entry_D3596DAC6DF7FC8E.self // If this line does not compile, compile the code SafeDI generates for module F0 into F0: under Bazel, add F0’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feature0Entry(__safeDI_network: network, __safeDI_analyticsClientSendableBuilder: __safeDI_analyticsClientSendableBuilder.feature0Builder_Sendable)
		        }
		        let feature0Builder = SendableInstantiator<Feature0Entry>(__safeDI_feature0Builder)
		        @Sendable nonisolated func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen1<any AnalyticsClient>) -> Detail1 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel1 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail1(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_viewModel(id: Int, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel1<any AnalyticsClient>) -> ViewModel1 {
		            let __safeDI_analyticsClientSendableBuilder_repository = __safeDI_analyticsClientSendableBuilder_viewModel.repository
		            let repository: Repository1 = __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_analyticsClientSendableBuilder_repository)
		            return ViewModel1(id: id, repository: repository)
		        }
		        @Sendable nonisolated func __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository1<any AnalyticsClient>) -> Repository1 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientSendableBuilder_repository.analytics(formatter)
		            return Repository1(network: network, formatter: formatter, analytics: analytics)
		        }
		        @Sendable nonisolated func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        @Sendable nonisolated func __safeDI_firstScreenBuilder() -> FirstScreen1 {
		            let __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.firstScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail1> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable)
		            }
		            return FirstScreen1(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = SendableInstantiator<FirstScreen1>(__safeDI_firstScreenBuilder)
		        @Sendable nonisolated func __safeDI_detailBuilder_(id: Int, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen1<any AnalyticsClient>) -> Detail1 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel1 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail1(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_secondScreenBuilder() -> SecondScreen1 {
		            let __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.secondScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail1> {
		                __safeDI_detailBuilder_(id: $0, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable)
		            }
		            return SecondScreen1(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = SendableInstantiator<SecondScreen1>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder, feature0Builder: feature0Builder)
		    }
		}

		extension Feature1Entry {
		    public enum __safeDI_Feature1Entry_CF8DB3BC69D52074 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["F2"]?.generatedFiles, ["F2.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif
		#if canImport(F1)
		import F1
		#endif

		extension Feature2Entry {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built> {
		        public let viewModel: (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel2<__safeDI_Built>

		        public init(viewModel: @escaping (Int) -> __safeDI_AnalyticsClientCarrier_ViewModel2<__safeDI_Built>) {
		            self.viewModel = viewModel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(viewModel: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_ViewModel2<__safeDI_Built> {
		        public let repository: __safeDI_AnalyticsClientCarrier_Repository2<__safeDI_Built>

		        public init(repository: __safeDI_AnalyticsClientCarrier_Repository2<__safeDI_Built>) {
		            self.repository = repository
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(repository: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientCarrier_Repository2<__safeDI_Built> {
		        public let analytics: (LazilyInstantiated<Formatter>) -> __safeDI_Built

		        public init(analytics: @escaping (LazilyInstantiated<Formatter>) -> __safeDI_Built) {
		            self.analytics = analytics
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(analytics: { _ in __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>: Sendable {
		        public let firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen2<__safeDI_Built>
		        public let secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen2<__safeDI_Built>
		        public let feature1Builder_Sendable: Feature1Entry.__safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>

		        public init(firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen2<__safeDI_Built>, secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen2<__safeDI_Built>, feature1Builder_Sendable: Feature1Entry.__safeDI_AnalyticsClientSendableCarrier<__safeDI_Built>) {
		            self.firstScreenBuilder_Sendable = firstScreenBuilder_Sendable
		            self.secondScreenBuilder_Sendable = secondScreenBuilder_Sendable
		            self.feature1Builder_Sendable = feature1Builder_Sendable
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(firstScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder), secondScreenBuilder_Sendable: .init(__safeDI_noScope: __safeDI_builder), feature1Builder_Sendable: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_FirstScreen2<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_AnalyticsClientSendableCarrier_SecondScreen2<__safeDI_Built>: Sendable {
		        public let detailBuilder: @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built>

		        public init(detailBuilder: @escaping @Sendable () -> __safeDI_AnalyticsClientCarrier_Detail2<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(detailBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    // SafeDI counts `AnalyticsClient` as `public`: no module it reads declares it narrower. If `AnalyticsClient` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_network network: Network, __safeDI_analyticsClientSendableBuilder: __safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient>) {
		        @Sendable nonisolated func __safeDI_feature1Builder() -> Feature1Entry {
		            _ = Feature1Entry.__safeDI_Feature1Entry_CF8DB3BC69D52074.self // If this line does not compile, compile the code SafeDI generates for module F1 into F1: under Bazel, add F1’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feature1Entry(__safeDI_network: network, __safeDI_analyticsClientSendableBuilder: __safeDI_analyticsClientSendableBuilder.feature1Builder_Sendable)
		        }
		        let feature1Builder = SendableInstantiator<Feature1Entry>(__safeDI_feature1Builder)
		        @Sendable nonisolated func __safeDI_detailBuilder(id: Int, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_FirstScreen2<any AnalyticsClient>) -> Detail2 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel2 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail2(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_viewModel(id: Int, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_AnalyticsClientCarrier_ViewModel2<any AnalyticsClient>) -> ViewModel2 {
		            let __safeDI_analyticsClientSendableBuilder_repository = __safeDI_analyticsClientSendableBuilder_viewModel.repository
		            let repository: Repository2 = __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_analyticsClientSendableBuilder_repository)
		            return ViewModel2(id: id, repository: repository)
		        }
		        @Sendable nonisolated func __safeDI_repository(__safeDI_analyticsClientSendableBuilder_repository: __safeDI_AnalyticsClientCarrier_Repository2<any AnalyticsClient>) -> Repository2 {
		            let formatter = LazilyInstantiated<Formatter>(__safeDI_formatter)
		            let analytics: any AnalyticsClient = __safeDI_analyticsClientSendableBuilder_repository.analytics(formatter)
		            return Repository2(network: network, formatter: formatter, analytics: analytics)
		        }
		        @Sendable nonisolated func __safeDI_formatter() -> Formatter {
		            Formatter()
		        }
		        @Sendable nonisolated func __safeDI_firstScreenBuilder() -> FirstScreen2 {
		            let __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.firstScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail2> {
		                __safeDI_detailBuilder(id: $0, __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_firstScreenBuilder_Sendable)
		            }
		            return FirstScreen2(detailBuilder: detailBuilder)
		        }
		        let firstScreenBuilder = SendableInstantiator<FirstScreen2>(__safeDI_firstScreenBuilder)
		        @Sendable nonisolated func __safeDI_detailBuilder_(id: Int, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_AnalyticsClientSendableCarrier_SecondScreen2<any AnalyticsClient>) -> Detail2 {
		            let __safeDI_analyticsClientSendableBuilder_detailBuilder = __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable.detailBuilder()
		            let __safeDI_analyticsClientSendableBuilder_viewModel = __safeDI_analyticsClientSendableBuilder_detailBuilder.viewModel(id)
		            let viewModel: ViewModel2 = __safeDI_viewModel(id: id, __safeDI_analyticsClientSendableBuilder_viewModel: __safeDI_analyticsClientSendableBuilder_viewModel)
		            return Detail2(id: id, viewModel: viewModel)
		        }
		        @Sendable nonisolated func __safeDI_secondScreenBuilder() -> SecondScreen2 {
		            let __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable = __safeDI_analyticsClientSendableBuilder.secondScreenBuilder_Sendable
		            let detailBuilder = SendableInstantiator<Detail2> {
		                __safeDI_detailBuilder_(id: $0, __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_secondScreenBuilder_Sendable)
		            }
		            return SecondScreen2(detailBuilder: detailBuilder)
		        }
		        let secondScreenBuilder = SendableInstantiator<SecondScreen2>(__safeDI_secondScreenBuilder)
		        self.init(network: network, firstScreenBuilder: firstScreenBuilder, secondScreenBuilder: secondScreenBuilder, feature1Builder: feature1Builder)
		    }
		}

		extension Feature2Entry {
		    public enum __safeDI_Feature2Entry_0CD1DB196F4B45E0 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(F0)
		import F0
		#endif
		#if canImport(F1)
		import F1
		#endif
		#if canImport(F2)
		import F2
		#endif

		extension Root {
		    public init() {
		        let network = Network()
		        func __safeDI_feature() -> Feature2Entry {
		            _ = Feature2Entry.__safeDI_Feature2Entry_0CD1DB196F4B45E0.self // If this line does not compile, compile the code SafeDI generates for module F2 into F2: under Bazel, add F2’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature2Entry() -> Feature2Entry.__safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient> {
		                .init(firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature2Entry_FirstScreen2_Scope(), secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature2Entry_SecondScreen2_Scope(), feature1Builder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature1Entry())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature2Entry_FirstScreen2_Scope() -> Feature2Entry.__safeDI_AnalyticsClientSendableCarrier_FirstScreen2<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature2Entry_Detail2_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature2Entry_Detail2_Scope() -> Feature2Entry.__safeDI_AnalyticsClientCarrier_Detail2<any AnalyticsClient> {
		                .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature2Entry_ViewModel2_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature2Entry_ViewModel2_Scope() -> Feature2Entry.__safeDI_AnalyticsClientCarrier_ViewModel2<any AnalyticsClient> {
		                .init(repository: __safeDI_analyticsClientBuilder_Feature2Entry_Repository2_Scope())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature2Entry_Repository2_Scope() -> Feature2Entry.__safeDI_AnalyticsClientCarrier_Repository2<any AnalyticsClient> {
		                .init(analytics: { scope_formatter in
		                    let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                    return analytics
		                })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature2Entry_SecondScreen2_Scope() -> Feature2Entry.__safeDI_AnalyticsClientSendableCarrier_SecondScreen2<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature2Entry_Detail2_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature1Entry() -> Feature1Entry.__safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient> {
		                .init(firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature1Entry_FirstScreen1_Scope(), secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature1Entry_SecondScreen1_Scope(), feature0Builder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature0Entry())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature1Entry_FirstScreen1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientSendableCarrier_FirstScreen1<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientCarrier_Detail1<any AnalyticsClient> {
		                .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature1Entry_ViewModel1_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature1Entry_ViewModel1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientCarrier_ViewModel1<any AnalyticsClient> {
		                .init(repository: __safeDI_analyticsClientBuilder_Feature1Entry_Repository1_Scope())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature1Entry_Repository1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientCarrier_Repository1<any AnalyticsClient> {
		                .init(analytics: { scope_formatter in
		                    let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                    return analytics
		                })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature1Entry_SecondScreen1_Scope() -> Feature1Entry.__safeDI_AnalyticsClientSendableCarrier_SecondScreen1<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature1Entry_Detail1_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature0Entry() -> Feature0Entry.__safeDI_AnalyticsClientSendableCarrier<any AnalyticsClient> {
		                .init(firstScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature0Entry_FirstScreen0_Scope(), secondScreenBuilder_Sendable: __safeDI_analyticsClientSendableBuilder_Feature0Entry_SecondScreen0_Scope())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature0Entry_FirstScreen0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientSendableCarrier_FirstScreen0<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientCarrier_Detail0<any AnalyticsClient> {
		                .init(viewModel: { values_id in __safeDI_analyticsClientBuilder_Feature0Entry_ViewModel0_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature0Entry_ViewModel0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientCarrier_ViewModel0<any AnalyticsClient> {
		                .init(repository: __safeDI_analyticsClientBuilder_Feature0Entry_Repository0_Scope())
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientBuilder_Feature0Entry_Repository0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientCarrier_Repository0<any AnalyticsClient> {
		                .init(analytics: { scope_formatter in
		                    let analytics: any AnalyticsClient = LiveAnalytics(network: network)
		                    return analytics
		                })
		            }
		            @Sendable nonisolated func __safeDI_analyticsClientSendableBuilder_Feature0Entry_SecondScreen0_Scope() -> Feature0Entry.__safeDI_AnalyticsClientSendableCarrier_SecondScreen0<any AnalyticsClient> {
		                .init(detailBuilder: { __safeDI_analyticsClientBuilder_Feature0Entry_Detail0_Scope() })
		            }
		            return Feature2Entry(__safeDI_network: network, __safeDI_analyticsClientSendableBuilder: __safeDI_analyticsClientSendableBuilder_Feature2Entry())
		        }
		        let feature: Feature2Entry = __safeDI_feature()
		        self.init(network: network, feature: feature)
		    }
		}
		"""])
		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(output, modules: modules, samples: [DifferentialValueSample(type: "Int", expression: "7")], filesToDelete: &filesToDelete)
	}

	// MARK: Private

	/// Whether each feature's types are built in plain instantiators or `Sendable` ones.
	private enum Wrapper {
		case instantiator
		case sendableInstantiator

		var name: String {
			switch self {
			case .instantiator: "Instantiator"
			case .sendableInstantiator: "SendableInstantiator"
			}
		}
	}

	/// `Core`, which declares the services and `AnalyticsClient`; `featureCount` feature modules `F0`, `F1`…, each a
	/// seam `Feature<k>Entry` that opens two screens, both of which open `Detail<k>`, whose repository instantiates
	/// `any AnalyticsClient`, a place no feature module can fill, and each feature after the first also calling the one
	/// before it; and `App`, which fulfills `AnalyticsClient` and whose root builds the last feature.
	private static func modules(featureCount: Int, wrapper: Wrapper, isolation: CarrierPassUpCallIsolation) -> [ModuleFixture] {
		var modules = [ModuleFixture(
			name: "Core",
			packageName: "pkg",
			swiftFileContent: [
				seamFixtureType(named: "Network", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Formatter", isFinalClass: true, declarations: [], conformances: ", Sendable"),
				"public protocol AnalyticsClient: AnyObject {}",
			],
		)]
		for feature in 0..<featureCount {
			let imports = "import Core\n" + (feature > 0 ? "import F\(feature - 1)\n" : "") + "\n"
			var entryDeclarations = [
				"@Received let network: Network",
				"@Instantiated let firstScreenBuilder: \(wrapper.name)<FirstScreen\(feature)>",
				"@Instantiated let secondScreenBuilder: \(wrapper.name)<SecondScreen\(feature)>",
			]
			if feature > 0 {
				entryDeclarations.append("@Instantiated let feature\(feature - 1)Builder: \(wrapper.name)<Feature\(feature - 1)Entry>")
			}
			modules.append(ModuleFixture(
				name: "F\(feature)",
				packageName: "pkg",
				swiftFileContent: [
					seamFixtureType(named: "Feature\(feature)Entry", isSeam: true, isFinalClass: true, declarations: entryDeclarations),
					seamFixtureType(named: "FirstScreen\(feature)", isFinalClass: true, declarations: ["@Instantiated let detailBuilder: \(wrapper.name)<Detail\(feature)>"]),
					seamFixtureType(named: "SecondScreen\(feature)", isFinalClass: true, declarations: ["@Instantiated let detailBuilder: \(wrapper.name)<Detail\(feature)>"]),
					seamFixtureType(named: "Detail\(feature)", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let viewModel: ViewModel\(feature)"]),
					seamFixtureType(named: "ViewModel\(feature)", isFinalClass: true, declarations: ["@Received let id: Int", "@Instantiated let repository: Repository\(feature)"]),
					seamFixtureType(named: "Repository\(feature)", isFinalClass: true, declarations: ["@Received let network: Network", "@Instantiated let formatter: LazilyInstantiated<Formatter>", "@Instantiated let analytics: any AnalyticsClient"]),
				].map { imports + $0 },
				dependencies: ["Core"] + (feature > 0 ? ["F\(feature - 1)"] : []),
				compilerSettings: isolation.featureModuleSettings,
			))
		}
		let lastFeature = featureCount - 1
		modules.append(ModuleFixture(
			name: "App",
			packageName: "pkg",
			swiftFileContent: [
				CarrierCells.fulfillingImpl(named: "LiveAnalytics", fulfilling: "AnalyticsClient", reading: ["@Received let network: Network"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let network: Network", "@Instantiated let feature: Feature\(lastFeature)Entry"]),
			].map { "import Core\n" + (0..<featureCount).map { "import F\($0)\n" }.joined() + "\n" + $0 },
			dependencies: ["Core"] + (0..<featureCount).map { "F\($0)" },
			compilerSettings: isolation.featureModuleSettings,
		))
		return modules
	}

	/// Expects each local function a generated file declares to be declared once in it: a builder function written
	/// once per path the seam's tree reaches its type on is declared again under the same name.
	private static func expectEachBuilderFunctionDeclaredOnce(in generatedFiles: [String: String]?, sourceLocation: SourceLocation = #_sourceLocation) {
		for (fileName, content) in generatedFiles ?? [:] {
			var declarationCounts = [String: Int]()
			for line in content.split(separator: "\n") where line.contains("func __safeDI_") {
				let name = line.split(separator: "func ", maxSplits: 1)[1].prefix { $0 != "(" }
				declarationCounts[String(name), default: 0] += 1
			}
			let repeated = declarationCounts.filter { $0.value > 1 }.sorted { $0.key < $1.key }.map { "\($0.key) (\($0.value) times)" }
			#expect(repeated == [], "\(fileName) declares these builder functions more than once", sourceLocation: sourceLocation)
		}
	}

	private var filesToDelete: [URL]
}

/// The isolation every feature module and the app module default to: none, or the main actor.
struct CarrierPassUpCallIsolation: CustomTestStringConvertible, Sendable {
	static let allCases = [
		CarrierPassUpCallIsolation(isMainActorByDefault: false),
		CarrierPassUpCallIsolation(isMainActorByDefault: true),
	]

	let isMainActorByDefault: Bool

	var featureModuleSettings: VerificationCompilerSettings {
		VerificationCompilerSettings(defaultIsolation: isMainActorByDefault ? "MainActor" : nil, prependsSafeDIImport: true)
	}

	var testDescription: String {
		isMainActorByDefault ? "modules on the main actor by default" : "modules nonisolated by default"
	}
}
