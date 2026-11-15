import Harness
import SafeDI

extension A {
	nonisolated public enum SafeDIScope_Api {
		nonisolated public enum InnerT_Scope {
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
			public let tBuilder: @Sendable (tBuilder_Values) -> SafeDIScope_Api.InnerT_Scope.__safeDI_Builder<Built>

			public init(tBuilder: @escaping @Sendable (tBuilder_Values) -> SafeDIScope_Api.InnerT_Scope.__safeDI_Builder<Built>) {
				self.tBuilder = tBuilder
			}

			public init(__safeDI_noScope builder: @escaping @Sendable () -> Built) {
				tBuilder = { _ in .init(__safeDI_noScope: builder) }
			}
		}
	}

	/// For code you write.
	public convenience init(apiSendableBuilder: @escaping @Sendable () -> any Api) {
		self.init(__safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
	}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
		@Sendable
		nonisolated func __safeDI_innerT_Sendable(_ __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) -> InnerT {
			let __safeDI_apiBuilder = __safeDI_apiSendableBuilder.tBuilder(.init())
			let api: any Api = __safeDI_apiBuilder.api(.init())
			return InnerT(api: api)
		}
		let tBuilder = SendableInstantiator<InnerT> { __safeDI_innerT_Sendable(__safeDI_apiSendableBuilder) }
		self.init(tBuilder: tBuilder)
	}
}
