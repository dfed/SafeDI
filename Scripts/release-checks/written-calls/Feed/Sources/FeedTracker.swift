// From the manual’s “Dependencies instantiated only if available”: a public mock whose tree instantiates, only if
// available, a type that nothing its module sees fulfills takes a builder that returns the optional value.
import SafeDI

public protocol FeedAnalytics {}

@Instantiable(generateMock: .public)
public final class FeedTracker: Instantiable {
	init(analytics: (any FeedAnalytics)?) {
		self.analytics = analytics
	}

	@Instantiated(onlyIfAvailable: true) private let analytics: (any FeedAnalytics)?
}
