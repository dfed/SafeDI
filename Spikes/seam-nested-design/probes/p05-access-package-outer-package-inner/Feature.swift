// Module Feature, package Pkg: a `package` seam whose tree calls the `package` seam `Inner`, and an `internal` seam beside
// it. Both enums are spelled `@frozen public`, as the generator spells every scope type.
// swiftformat:disable redundantPublic
import Lower

package final class Feature {
	package let inner: Inner
	init(inner: Inner) {
		self.inner = inner
	}
}

extension Feature {
	@frozen
	public enum SafeDIScope_Service {
		case inner(Inner.SafeDIScope_Service)
	}

	package convenience init(serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		self.init(inner: Inner(serviceBuilder: { serviceBuilder(.inner($0)) }))
	}
}

final class Hidden {
	let inner: Inner
	init(inner: Inner) {
		self.inner = inner
	}
}

extension Hidden {
	@frozen
	public enum SafeDIScope_Service {
		case inner(Inner.SafeDIScope_Service)
	}

	convenience init(serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		self.init(inner: Inner(serviceBuilder: { serviceBuilder(.inner($0)) }))
	}
}
