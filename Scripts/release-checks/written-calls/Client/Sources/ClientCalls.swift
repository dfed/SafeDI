// A module of another package (`Client`), which calls only `public` generated declarations.
import Core
import Feature
import Feed
import Payments

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

#if DEBUG
// “Calling a public mock from another module”, verbatim.
func makeFeedScreen() -> FeedScreen {
	FeedScreen.mock(feedServiceBuilder: { _ in StubFeedService() })
}

// “Public mocks”: the calls the section shows, and each parameter kind of the `public` tier.
func callPaymentServiceMocks() {
	_ = PaymentService.mock()
	_ = PaymentService.mock(analytics: Analytics())
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
#endif
