// Module App, package Pkg: opens the package enum through the package seam.
import Feature
import Lower

struct Impl: Service { let tag: String }

package func make() -> Feature {
	Feature(serviceBuilder: { scope in
		switch scope {
		case .inner(.x): Impl(tag: "x")
		}
	})
}
