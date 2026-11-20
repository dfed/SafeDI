// From the manual’s “Generating a dependency tree per module”: a `public` seam whose tree builds a type with a
// `package` initializer, and receives a `package` type only if available, so the seam has a `public` tier and a
// `package` tier. (The manual names the seam `Service`.)
import Core
import SafeDI

@Instantiable(generateDependencyTree: true)
public struct BadgeService: Instantiable {
	public init(badge: Badge) {
		self.badge = badge
	}

	@Instantiated private let badge: Badge
}

@Instantiable
public struct Badge: Instantiable {
	package init(analytics: Analytics, theme: Theme?) {
		self.analytics = analytics
		self.theme = theme
	}

	@Received private let analytics: Analytics
	@Received(onlyIfAvailable: true) private let theme: Theme?
}

package final class Theme {
	package init() {}
}
