// From the manual’s “Dependencies instantiated only if available”: a mock whose tree reaches a public mock that takes a
// builder for a dependency instantiated only if available, and whose module sees a type that fulfills it, so that it
// builds that type and takes an optional builder that replaces it.
import Feed
import SafeDI

@Instantiable(fulfillingAdditionalTypes: [FeedAnalytics.self])
final class AppFeedAnalytics: FeedAnalytics, Instantiable {
	init() {}
}

@Instantiable(generateMock: true)
final class AppTrackerScreen: Instantiable {
	init(tracker: FeedTracker) {
		self.tracker = tracker
	}

	@Instantiated private let tracker: FeedTracker
}
