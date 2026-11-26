// From the manual’s “Dependencies instantiated only if available”: a mock in another package whose tree reaches a
// public mock that takes a builder for a dependency instantiated only if available, and whose module sees no type that
// fulfills it either, so that it takes the builder and passes it on.
import Feed
import SafeDI

@Instantiable(generateMock: true)
struct ClientTrackerScreen: Instantiable {
	init(tracker: FeedTracker) {
		self.tracker = tracker
	}

	@Instantiated private let tracker: FeedTracker
}
