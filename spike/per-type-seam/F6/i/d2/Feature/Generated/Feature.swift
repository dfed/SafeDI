import Harness
import SafeDI

extension Hub {
	nonisolated public enum SafeDIScope_Api {
		nonisolated public struct t_Values {}

		nonisolated public struct __safeDI_Builder<Built> {
			public let t: (t_Values) -> T_Scope.__safeDI_Builder<Built>

			public init(t: @escaping (t_Values) -> T_Scope.__safeDI_Builder<Built>) {
				self.t = t
			}

			public init(__safeDI_noScope builder: @escaping () -> Built) {
				t = { _ in .init(__safeDI_noScope: builder) }
			}
		}

		nonisolated public enum T_Scope {
			nonisolated public struct api_Values {}

			nonisolated public struct __safeDI_Builder<Built> {
				public let api: (api_Values) -> Built

				public init(api: @escaping (api_Values) -> Built) {
					self.api = api
				}

				public init(__safeDI_noScope builder: @escaping () -> Built) {
					api = { _ in builder() }
				}
			}
		}
	}

	nonisolated public enum SafeDISendableScope_Api {
		nonisolated public struct tBuilder_Values: Sendable {}

		nonisolated public struct __safeDI_Builder<Built>: Sendable {
			public let tBuilder: @Sendable (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<Built>

			public init(tBuilder: @escaping @Sendable (tBuilder_Values) -> SafeDIScope_Api.T_Scope.__safeDI_Builder<Built>) {
				self.tBuilder = tBuilder
			}

			public init(__safeDI_noScope builder: @escaping @Sendable () -> Built) {
				tBuilder = { _ in .init(__safeDI_noScope: builder) }
			}
		}
	}

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api, apiSendableBuilder: @escaping @Sendable () -> any Api) {
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
	}

	/// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
		func __safeDI_t(_ __safeDI_apiBuilder: SafeDIScope_Api.T_Scope.__safeDI_Builder<any Api>) -> T {
			let api: any Api = __safeDI_apiBuilder.api(.init())
			return T(api: api)
		}
		@Sendable
		nonisolated func __safeDI_t_Sendable(_ __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) -> T {
			let __safeDI_apiBuilder = __safeDI_apiSendableBuilder.tBuilder(.init())
			let api: any Api = __safeDI_apiBuilder.api(.init())
			return T(api: api)
		}
		let t: T = __safeDI_t(__safeDI_apiBuilder.t(.init()))
		let tBuilder = SendableInstantiator<T> { __safeDI_t_Sendable(__safeDI_apiSendableBuilder) }
		self.init(t: t, tBuilder: tBuilder)
	}
}
