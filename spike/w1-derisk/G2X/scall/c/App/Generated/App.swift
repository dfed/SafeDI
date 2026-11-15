import Feature
import Harness
import SafeDI

extension Root {
	public convenience init() {
		func __safeDI_store() -> Store {
			@Sendable
			func __safeDI_aBuilder() -> A {
				let sideBuilder = SendableInstantiator<Side>(__safeDI_sideBuilder)
				return A(__safeDI_apiBuilder: .init(api: { _ in LiveApi(sideBuilder: sideBuilder) }))
			}
			let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			@Sendable
			func __safeDI_sideBuilder() -> Side {
				let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
				return Side(aBuilder: aBuilder)
			}
			let sideBuilder = SendableInstantiator<Side>(__safeDI_sideBuilder)
			return Store(aBuilder: aBuilder, sideBuilder: sideBuilder)
		}
		let store: Store = __safeDI_store()
		self.init(store: store)
	}
}
