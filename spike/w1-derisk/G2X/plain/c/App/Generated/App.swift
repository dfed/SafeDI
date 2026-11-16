import Feature
import Harness
import SafeDI

extension Root {
	public convenience init() {
		func __safeDI_store() -> Store {
			func __safeDI_aBuilder() -> A {
				let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
				return A(__safeDI_apiBuilder: .init(api: { _ in LiveApi(sideBuilder: sideBuilder) }))
			}
			let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			func __safeDI_sideBuilder() -> Side {
				let aBuilder = Instantiator<A>(__safeDI_aBuilder)
				return Side(aBuilder: aBuilder)
			}
			let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
			return Store(aBuilder: aBuilder, sideBuilder: sideBuilder)
		}
		let store: Store = __safeDI_store()
		self.init(store: store)
	}
}
