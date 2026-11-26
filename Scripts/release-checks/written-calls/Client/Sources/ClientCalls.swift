// A module of another package (`Client`), which calls only `public` generated declarations.
import Core
import Feature
import Feed
import Payments
import SafeDI

// “Creating the root of your dependency tree”: a root’s `init()`, from a module that depends on the root’s.
func makeFeatureRoot() -> FeatureRoot {
	FeatureRoot()
}

// “Generating a dependency tree per module”: a seam’s `public` tier with readable labels, from another package.
func makeBadgeService(analytics: Analytics) -> BadgeService {
	BadgeService(analytics: analytics)
}

struct StubFeedService: FeedService {
	func refresh() async {}
}

struct StubFeedSyncer: FeedSyncer {}

#if DEBUG
// “Calling a public mock from another module”, verbatim.
func makeFeedScreen() -> FeedScreen {
	FeedScreen.mock(feedServiceBuilder: { StubFeedService() })
}

// “Public mocks”: the calls the section shows, verbatim but for names, and each parameter kind of the `public` tier;
// a lazily instantiated received dependency is taken as the wrapper.
func callPaymentServiceMocks() {
	_ = PaymentService.mock()
	_ = PaymentService.mock(analytics: LazilyInstantiated { Analytics() })
	_ = PaymentService.mock(safeDIOverrides: .init(tokenCache: .init(capacity: 5)))
	// A default-valued parameter is `T? = nil`, where `nil` means the declaration’s default.
	_ = PaymentService.mock(retries: 5)
	_ = PaymentService.mock(retries: nil, analytics: nil, safeDIOverrides: .init())
}

func callPollerMocks() {
	_ = Poller.mock()
	// An `@autoclosure` default-valued parameter becomes `(() -> Int)? = nil`.
	_ = Poller.mock(interval: { 5 })
}

// “Public mocks”, under “Holes”: a hole’s builder takes what a person writes for a seam’s hole, whatever holds the
// place: a lazily instantiated place, a place beside a lazily instantiated value the mock takes, a place held in an
// instantiator, which is handed the forwarded value, a place in a `Sendable` wrapper, and a place of another module’s
// seam that the mock passes up.
func callHoleBuilderMocks() {
	let _: FeedLoader = FeedLoader.mock(feedServiceBuilder: { StubFeedService() })
	let _: FeedDetail = FeedDetail.mock(token: LazilyInstantiated { FeedToken() }, feedServiceBuilder: { StubFeedService() })
	let _: FeedReaderHost = FeedReaderHost.mock(feedReaderBuilder: { feedName in FeedReader(feedName: feedName) })
	let _: FeedSyncHost = FeedSyncHost.mock(appFeedSyncer_FeedSyncerSendableBuilder: { StubFeedSyncer() })
	let _: FeedCheckout = FeedCheckout.mock(feedServiceBuilder: { StubFeedService() })
}

// “Calling a public mock from another module”: where the called mock takes no `safeDIOverrides`, an override of it is a
// closure that builds the type, handed the builders its `mock()` takes.
func callOverrideOfPublicMockWithoutOverrides() {
	let _: ClientScreen = ClientScreen.mock()
	let _: ClientScreen = ClientScreen.mock(safeDIOverrides: .init(badge: { feedRendererBuilder in
		FeedBadge.mock(feedRendererBuilder: feedRendererBuilder)
	}))
}

struct StubFeedAnalytics: FeedAnalytics {}

// “Dependencies instantiated only if available”: a public mock takes a builder for such a dependency that nothing its
// module sees fulfills, which defaults to one that returns `nil`; a mock in another module that sees no type fulfilling
// it either takes the builder too and passes it on.
func callOptionalBuilderMocks() {
	let _: FeedTracker = FeedTracker.mock()
	let _: FeedTracker = FeedTracker.mock(feedAnalyticsOptionalBuilder: { StubFeedAnalytics() })
	let _: FeedTracker = FeedTracker.mock(feedAnalyticsOptionalBuilder: { nil })
	let _: ClientTrackerScreen = ClientTrackerScreen.mock()
	let _: ClientTrackerScreen = ClientTrackerScreen.mock(feedAnalyticsOptionalBuilder: { StubFeedAnalytics() })
}
#endif
