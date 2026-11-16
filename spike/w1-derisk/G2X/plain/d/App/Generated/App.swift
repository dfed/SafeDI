import Feature
import Harness
import SafeDI

extension Root {
	public convenience init() {
		func __safeDI_store() -> Store {
			// Per-type: one level function per seam type the caller calls; the fill is its own function, which builds
			// the sibling's instantiator through the sibling's function, declared below.
			func __safeDI_apiBuilder_A() -> A.SafeDIScope_Api.__safeDI_Builder<any Api> {
				func __safeDI_liveApi() -> any Api {
					let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
					return LiveApi(sideBuilder: sideBuilder)
				}
				return .init(api: { _ in __safeDI_liveApi() })
			}
			func __safeDI_aBuilder() -> A {
				A(__safeDI_apiBuilder: __safeDI_apiBuilder_A())
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
