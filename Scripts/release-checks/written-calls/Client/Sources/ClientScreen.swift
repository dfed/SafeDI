// From the manual’s “Calling a public mock from another module”: a mock in another package whose tree reaches a public
// mock that takes no `safeDIOverrides`, and whose module fills that mock’s hole.
import Feed
import SafeDI

@Instantiable(fulfillingAdditionalTypes: [FeedRenderer.self])
struct ClientRenderer: FeedRenderer, Instantiable {
	init() {}
}

@Instantiable(generateMock: true)
struct ClientScreen: Instantiable {
	init(badge: FeedBadge) {
		self.badge = badge
	}

	@Instantiated private let badge: FeedBadge
}
