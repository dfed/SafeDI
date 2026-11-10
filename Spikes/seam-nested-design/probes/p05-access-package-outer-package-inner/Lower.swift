// Module Lower, package Pkg: `Inner` is a `package` seam.
public protocol Service: Sendable { var tag: String { get } }

package final class Inner {
	package let x: any Service
	init(x: any Service) { self.x = x }
}

extension Inner {
	// Spelled `public`, as today's scope structs are: its access is the seam's, `package`.
	@frozen public enum SafeDIScope_Service {
		case x(x_Values)

		public struct x_Values {}
	}

	package convenience init(serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		let x: any Service = serviceBuilder(.x(SafeDIScope_Service.x_Values()))
		self.init(x: x)
	}
}
