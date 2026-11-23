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
import Testing
@testable import SafeDIToolTestSupport

/// The graph fuzzer's readers of generated code over a seam whose hole type hands its levels to its builders as carriers
/// (`seam-carriers.md`). `carrierBanner` is the code the tool generates for public mock corpus graph 208's seam, whose
/// hole type's stem holds `Carrier`, and `nestedCarriersHome` the carriers of `SafeDIToolSeamCarrierIsolationTests`'
/// seam without its initializer's body: levels nested by type, one a `let` of its child carrier and one in the
/// `@Sendable` family.
struct GraphFuzzerCarrierReaderTests {
	// MARK: seamInitializers

	@Test
	func seamInitializers_qualifiesCarrierBySeam_whenBuilderTakesCarrier() {
		let initializers = GraphFuzzerOracle.seamInitializers(inGeneratedFile: Self.carrierBanner, keepsGeneratedOnlySpelling: true)

		#expect(initializers.map(\.parameters) == [["__safeDI_s208_CarrierApiBuilder: S208_CarrierBanner.__safeDI_S208_CarrierApiCarrier<any S208_CarrierApi>"]])
	}

	@Test
	func callerSpelling_leavesLabelHoldingCarrierAlone_whenLabelIsFollowedByNoGenericArguments() {
		#expect(GraphFuzzerOracle.callerSpelling(ofParameter: "__safeDI_carrierBuilder: __safeDI_CarrierCarrier_Screen<any Carrier>", of: "Home") == "__safeDI_carrierBuilder: Home.__safeDI_CarrierCarrier_Screen<any Carrier>")
	}

	// MARK: GraphFuzzerScopeDeclarations

	@Test
	func scopeDeclarations_readsCarrierAsRootEnumWithACasePerMember_whenStemHoldsCarrier() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["FuzzFeature/S208_CarrierBanner+SafeDI.swift": Self.carrierBanner])

		#expect(declarations.enums == [
			.init(extendedType: "S208_CarrierBanner", path: ["SafeDIScope_S208_CarrierApi"], cases: [.init(label: "carrierApi", payload: [])]),
		])
	}

	@Test
	func scopeDeclarations_readsNestedCarriersAsNestedEnums_whenLevelsNestByType() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Seam/Home+SafeDI.swift": Self.nestedCarriersHome])

		#expect(declarations.enums == [
			.init(extendedType: "Home", path: ["SafeDIScope_Api"], cases: [
				.init(label: "screenBuilder", payload: ["SafeDIScope_Api.Screen_Scope"]),
			]),
			.init(extendedType: "Home", path: ["SafeDIScope_Api", "Screen_Scope"], cases: [
				.init(label: "api", payload: ["Int", "Model"]),
				.init(label: "detailBuilder", payload: ["Int", "Model", "any Api", "SafeDIScope_Api.Detail_Scope"]),
			]),
			.init(extendedType: "Home", path: ["SafeDIScope_Api", "Work_Scope"], cases: [
				.init(label: "detailBuilder", payload: ["Int", "Model", "SafeDIScope_Api.Detail_Scope"]),
			]),
			.init(extendedType: "Home", path: ["SafeDIScope_Api", "Detail_Scope"], cases: [
				.init(label: "api", payload: []),
			]),
			.init(extendedType: "Home", path: ["SafeDISendableScope_Api"], cases: [
				.init(label: "workBuilder", payload: ["SafeDIScope_Api.Work_Scope"]),
			]),
		])
	}

	@Test
	func scopeDeclarations_readsLevelCarrierAsPlainFamily_whenItExtendsPlainSpellingOfRootDeclaredOnlyInSendableFamily() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Feature/Host+SafeDI.swift": Self.sendableRootHandingPlainLevelHost])

		#expect(declarations.enums == [
			.init(extendedType: "Host", path: ["SafeDIScope_Widget", "Panel_Scope"], cases: [
				.init(label: "widget", payload: ["String"]),
			]),
			.init(extendedType: "Host", path: ["SafeDISendableScope_Widget"], cases: [
				.init(label: "shell_Sendable", payload: ["SafeDISendableScope_Widget.Shell_Scope"]),
			]),
			.init(extendedType: "Host", path: ["SafeDISendableScope_Widget", "Shell_Scope"], cases: [
				.init(label: "panelBuilder", payload: ["SafeDIScope_Widget.Panel_Scope"]),
			]),
		])
	}

	@Test
	func carrierPaths_readsPlainFamily_whenPlainRootsStemEndsInSendable() {
		let paths = GraphFuzzerScopeDeclarations.carrierPaths(in: [Self.plainRootWhoseStemEndsInSendable])

		#expect(paths == [
			"__safeDI_GaugeSendableCarrier": ["SafeDIScope_GaugeSendable"],
			"__safeDI_GaugeSendableCarrier_Dial": ["SafeDIScope_GaugeSendable", "Dial_Scope"],
		])
	}

	// MARK: Fixtures

	private static let carrierBanner = """
	extension S208_CarrierBanner {
	    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	    nonisolated public final class __safeDI_S208_CarrierApiCarrier<__safeDI_Built> {
	        public let carrierApi: () -> __safeDI_Built

	        public init(carrierApi: @escaping () -> __safeDI_Built) {
	            self.carrierApi = carrierApi
	        }

	        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	            self.init(carrierApi: { __safeDI_builder() })
	        }
	    }

	    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
	    public convenience init(s208_CarrierApiBuilder: @escaping () -> any S208_CarrierApi) {
	        self.init(__safeDI_s208_CarrierApiBuilder: .init(__safeDI_noScope: s208_CarrierApiBuilder))
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// From code you write, call the initializer above instead.
	    public convenience init(__safeDI_s208_CarrierApiBuilder: __safeDI_S208_CarrierApiCarrier<any S208_CarrierApi>) {
	        let carrierApi: any S208_CarrierApi = __safeDI_s208_CarrierApiBuilder.carrierApi()
	        self.init(carrierApi: carrierApi)
	    }
	}

	extension S208_CarrierBanner {
	    public enum __safeDI_S208_CarrierBanner_5A047D24C33632AF {}
	}

	"""

	private static let nestedCarriersHome = """
	extension Home {
	    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
	        public let screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>

	        public init(screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
	            self.screenBuilder = screenBuilder
	        }
	    }

	    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
	        public let api: (Int, Model) -> __safeDI_Built
	        public let detailBuilder: (Int, Model, any Api) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

	        public init(api: @escaping (Int, Model) -> __safeDI_Built, detailBuilder: @escaping (Int, Model, any Api) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
	            self.api = api
	            self.detailBuilder = detailBuilder
	        }
	    }

	    nonisolated public final class __safeDI_ApiCarrier_Work<__safeDI_Built> {
	        public let detailBuilder: (Int, Model) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

	        public init(detailBuilder: @escaping (Int, Model) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
	            self.detailBuilder = detailBuilder
	        }
	    }

	    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
	        public let api: () -> __safeDI_Built

	        public init(api: @escaping () -> __safeDI_Built) {
	            self.api = api
	        }
	    }

	    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
	        public let workBuilder: @Sendable () -> __safeDI_ApiCarrier_Work<__safeDI_Built>

	        public init(workBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Work<__safeDI_Built>) {
	            self.workBuilder = workBuilder
	        }
	    }

	    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
	    }
	}

	extension Home {
	    public enum __safeDI_Home_0123456789ABCDEF {}
	}

	"""

	/// The carriers the tool generates for `GraphFuzzerNestedScopeOracleTests`' `Host`, whose `Shell` builds `Panel`, the
	/// holder of the place, in a `SendableInstantiator`: the module declares only the `@Sendable` family's root, whose level
	/// for `Shell` returns `Panel`'s level in the plain family, spelled after a plain root no file declares.
	private static let sendableRootHandingPlainLevelHost = """
	extension Host {
	    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	    nonisolated public final class __safeDI_WidgetCarrier_Panel<__safeDI_Built> {
	        public let widget: (String) -> __safeDI_Built

	        public init(widget: @escaping (String) -> __safeDI_Built) {
	            self.widget = widget
	        }

	        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	            self.init(widget: { _ in __safeDI_builder() })
	        }
	    }

	    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	    nonisolated public final class __safeDI_WidgetSendableCarrier<__safeDI_Built>: Sendable {
	        public let shell_Sendable: __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>

	        public init(shell_Sendable: __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>) {
	            self.shell_Sendable = shell_Sendable
	        }

	        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
	            self.init(shell_Sendable: .init(__safeDI_noScope: __safeDI_builder))
	        }
	    }

	    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	    nonisolated public final class __safeDI_WidgetSendableCarrier_Shell<__safeDI_Built>: Sendable {
	        public let panelBuilder: @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>

	        public init(panelBuilder: @escaping @Sendable () -> __safeDI_WidgetCarrier_Panel<__safeDI_Built>) {
	            self.panelBuilder = panelBuilder
	        }

	        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
	            self.init(panelBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
	        }
	    }

	    public init(__safeDI_widgetSendableBuilder: __safeDI_WidgetSendableCarrier<any Widget>) {
	    }
	}

	extension Host {
	    public enum __safeDI_Host_09320D882312EACD {}
	}

	"""

	/// A plain root of a hole type whose name ends in `Sendable`, and its level: both read as the plain family.
	private static let plainRootWhoseStemEndsInSendable = """
	extension Meter {
	    nonisolated public final class __safeDI_GaugeSendableCarrier<__safeDI_Built> {
	        public let dialBuilder: __safeDI_GaugeSendableCarrier_Dial<__safeDI_Built>
	    }

	    nonisolated public final class __safeDI_GaugeSendableCarrier_Dial<__safeDI_Built> {
	        public let gaugeSendable: () -> __safeDI_Built
	    }
	}

	"""
}
