// Module Feature, package Pkg: a `public` seam whose tree calls the `package` seam `Inner`.
import Lower

public final class Feature {
	package let inner: Inner
	init(inner: Inner) { self.inner = inner }
}

extension Feature {
	@frozen public enum SafeDIScope_Service {
		case inner(Inner.SafeDIScope_Service)
	}

	public convenience init(serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		self.init(inner: Inner(serviceBuilder: { serviceBuilder(.inner($0)) }))
	}
}
