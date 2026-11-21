// From the manual’s “Creating the root of your dependency tree”: a root whose generated `init()` module `App` calls,
// and “Adopting SafeDI in a large codebase”: a seam that takes a `@Forwarded` property, which an app target calls in
// place of a root.
import Core
import SafeDI

@Instantiable(isRoot: true)
public final class FeatureRoot: Instantiable {
	public init(analytics: Analytics, badgeService: BadgeService) {
		self.analytics = analytics
		self.badgeService = badgeService
	}

	@Instantiated private let analytics: Analytics
	@Instantiated private let badgeService: BadgeService
}

public struct LaunchConfiguration {
	public init(environment: String) {
		self.environment = environment
	}

	public let environment: String
}

@Instantiable(generateDependencyTree: true)
public final class AppEntry: Instantiable {
	public init(configuration: LaunchConfiguration, analytics: Analytics, badgeService: BadgeService) {
		self.configuration = configuration
		self.analytics = analytics
		self.badgeService = badgeService
	}

	@Forwarded private let configuration: LaunchConfiguration
	@Instantiated private let analytics: Analytics
	@Instantiated private let badgeService: BadgeService
}
