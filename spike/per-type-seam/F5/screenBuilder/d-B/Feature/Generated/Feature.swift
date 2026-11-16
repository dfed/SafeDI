import Harness
import SafeDI

extension Home {
	nonisolated public enum SafeDIScope_Api {
		nonisolated public struct screenBuilder_Values {}

		nonisolated public struct __safeDI_Builder<Built> {
			public let screenBuilder: (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>

			public init(screenBuilder: @escaping (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>) {
				self.screenBuilder = screenBuilder
			}

			public init(__safeDI_noScope builder: @escaping () -> Built) {
				screenBuilder = { _ in .init(__safeDI_noScope: builder) }
			}
		}

		nonisolated public enum Screen_Scope {
			nonisolated public struct api_Values {
				public let id: Int
				public let screenBuilder: Instantiator<Screen>
			}

			nonisolated public struct screenBuilder_Values {
				public let id: Int
			}

			nonisolated public struct __safeDI_Builder<Built> {
				public let api: (api_Values) -> Built
				public let screenBuilder: (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>

				public init(api: @escaping (api_Values) -> Built, screenBuilder: @escaping (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>) {
					self.api = api
					self.screenBuilder = screenBuilder
				}

				public init(__safeDI_noScope builder: @escaping () -> Built) {
					api = { _ in builder() }
					screenBuilder = { _ in .init(__safeDI_noScope: builder) }
				}
			}
		}
	}

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api) {
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	}

	/// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		func __safeDI_screen(_ __safeDI_apiBuilder: SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api>, id: Int) -> Screen {
			let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init(id: id))
			let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_screenBuilder, id: $0) }
			let api: any Api = __safeDI_apiBuilder.api(.init(id: id, screenBuilder: screenBuilder))
			return Screen(id: id, api: api, screenBuilder: screenBuilder)
		}
		let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
		let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_screenBuilder, id: $0) }
		self.init(screenBuilder: screenBuilder)
	}
}
