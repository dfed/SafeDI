import Harness
import Inner
import SafeDI

extension Store {
	nonisolated public enum SafeDISendableScope_Api {
		nonisolated public struct aBuilder_Values: Sendable {
			public let sideBuilder: SendableInstantiator<Side>
		}

		nonisolated public struct __safeDI_Builder<Built>: Sendable {
			public let aBuilder: @Sendable (aBuilder_Values) -> A.SafeDIScope_Api.__safeDI_Builder<Built>

			public init(aBuilder: @escaping @Sendable (aBuilder_Values) -> A.SafeDIScope_Api.__safeDI_Builder<Built>) {
				self.aBuilder = aBuilder
			}

			public init(__safeDI_noScope builder: @escaping @Sendable () -> Built) {
				aBuilder = { _ in .init(__safeDI_noScope: builder) }
			}
		}
	}

	/// For code you write.
	public convenience init(apiSendableBuilder: @escaping @Sendable () -> any Api) {
		self.init(__safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
	}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
		@Sendable func __safeDI_aBuilder() -> A {
			let sideBuilder = SendableInstantiator<Side>(__safeDI_sideBuilder)
			return A(__safeDI_apiBuilder: __safeDI_apiSendableBuilder.aBuilder(.init(sideBuilder: sideBuilder)))
		}
		let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
		@Sendable func __safeDI_sideBuilder() -> Side {
			let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			return Side(aBuilder: aBuilder)
		}
		let sideBuilder = SendableInstantiator<Side>(__safeDI_sideBuilder)
		self.init(aBuilder: aBuilder, sideBuilder: sideBuilder)
	}
}
