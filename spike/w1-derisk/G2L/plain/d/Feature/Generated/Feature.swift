import Harness
import Inner
import SafeDI

extension Store {
	nonisolated public enum SafeDIScope_Api {
		nonisolated public struct aBuilder_Values {
			public let sideBuilder: Instantiator<Side>
		}

		nonisolated public struct __safeDI_Builder<Built> {
			public let aBuilder: (aBuilder_Values) -> A.SafeDIScope_Api.__safeDI_Builder<Built>

			public init(aBuilder: @escaping (aBuilder_Values) -> A.SafeDIScope_Api.__safeDI_Builder<Built>) {
				self.aBuilder = aBuilder
			}

			public init(__safeDI_noScope builder: @escaping () -> Built) {
				aBuilder = { _ in .init(__safeDI_noScope: builder) }
			}
		}
	}

	/// For code you write.
	public convenience init(apiBuilder: @escaping () -> any Api) {
		self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		func __safeDI_aBuilder() -> A {
			let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
			return A(__safeDI_apiBuilder: __safeDI_apiBuilder.aBuilder(.init(sideBuilder: sideBuilder)))
		}
		let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		func __safeDI_sideBuilder() -> Side {
			let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			return Side(aBuilder: aBuilder)
		}
		let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
		self.init(aBuilder: aBuilder, sideBuilder: sideBuilder)
	}
}
