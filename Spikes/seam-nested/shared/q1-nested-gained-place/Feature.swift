// Hand-written. The nested shape after `Inner` gained a third plain place, `z_service`. The callers in the cases below
// were written against the two-place `Inner`.
import SafeDI

public protocol Service { var tag: String { get } }

public final class Inner {
	public let x: any Service
	public let y: any Service
	public let z: any Service
	init(x: any Service, y: any Service, z: any Service) {
		self.x = x
		self.y = y
		self.z = z
	}
}

extension Inner {
	@frozen
	public enum SafeDIScope_Service {
		case x_service(x_service_Values)
		case y_service(y_service_Values)
		case z_service(z_service_Values)

		public struct x_service_Values {}
		public struct y_service_Values {}
		public struct z_service_Values {}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		self.init(
			x: __safeDI_serviceBuilder(.x_service(SafeDIScope_Service.x_service_Values())),
			y: __safeDI_serviceBuilder(.y_service(SafeDIScope_Service.y_service_Values())),
			z: __safeDI_serviceBuilder(.z_service(SafeDIScope_Service.z_service_Values())),
		)
	}
}

public final class Outer {
	public let own: any Service
	public let inner: Inner
	init(own: any Service, inner: Inner) {
		self.own = own
		self.inner = inner
	}
}

extension Outer {
	@frozen
	public enum SafeDIScope_Service {
		case own(own_Values)
		case inner(Inner.SafeDIScope_Service)

		public struct own_Values {}
	}

	public convenience init(serviceBuilder __safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		func __safeDI_serviceBuilder_inner(_ scope: Inner.SafeDIScope_Service) -> any Service {
			__safeDI_serviceBuilder(.inner(scope))
		}
		self.init(own: __safeDI_serviceBuilder(.own(SafeDIScope_Service.own_Values())), inner: Inner(serviceBuilder: __safeDI_serviceBuilder_inner))
	}
}
