// The seam builds the wrapper; the forwarded value is the case's second value, absent for `()`.
import SafeDI

public protocol Service { var tag: String { get } }
public final class Feature {
	public let maker: ErasedInstantiator<String, any Service>
	public let pairMaker: ErasedInstantiator<(name: String, count: Int), any Service>
	public let plainMaker: ErasedInstantiator<Void, any Service>
	public let lazy: LazilyInstantiated<any Service>
	init(maker: ErasedInstantiator<String, any Service>, pairMaker: ErasedInstantiator<(name: String, count: Int), any Service>, plainMaker: ErasedInstantiator<Void, any Service>, lazy: LazilyInstantiated<any Service>) {
		self.maker = maker; self.pairMaker = pairMaker; self.plainMaker = plainMaker; self.lazy = lazy
	}
}

extension Feature {
	@frozen
	public enum SafeDIScope_Service {
		case maker(maker_Values, String)
		case pairMaker(pairMaker_Values, (name: String, count: Int))
		case plainMaker(plainMaker_Values)
		case lazy(lazy_Values)
		public struct maker_Values {}
		public struct pairMaker_Values { public let maker: ErasedInstantiator<String, any Service> }
		public struct plainMaker_Values {}
		public struct lazy_Values {}
	}

	public convenience init(serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		func __safeDI_maker(__safeDI_forwarded: String) -> any Service {
			serviceBuilder(.maker(SafeDIScope_Service.maker_Values(), __safeDI_forwarded))
		}
		let maker = ErasedInstantiator<String, any Service> {
			__safeDI_maker(__safeDI_forwarded: $0)
		}
		func __safeDI_pairMaker(__safeDI_forwarded: (name: String, count: Int)) -> any Service {
			serviceBuilder(.pairMaker(SafeDIScope_Service.pairMaker_Values(maker: maker), __safeDI_forwarded))
		}
		let pairMaker = ErasedInstantiator<(name: String, count: Int), any Service> {
			__safeDI_pairMaker(__safeDI_forwarded: $0)
		}
		func __safeDI_plainMaker() -> any Service {
			serviceBuilder(.plainMaker(SafeDIScope_Service.plainMaker_Values()))
		}
		let plainMaker = ErasedInstantiator<Void, any Service>(__safeDI_plainMaker)
		func __safeDI_lazy() -> any Service {
			serviceBuilder(.lazy(SafeDIScope_Service.lazy_Values()))
		}
		let lazy = LazilyInstantiated<any Service>(__safeDI_lazy)
		self.init(maker: maker, pairMaker: pairMaker, plainMaker: plainMaker, lazy: lazy)
	}
}
