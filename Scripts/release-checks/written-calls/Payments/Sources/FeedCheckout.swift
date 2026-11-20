// From the manual’s “Public mocks”, under “Holes”: a public mock whose tree calls another module’s seam, whose hole the
// mock passes up.
import Core
import Feed
import SafeDI

@Instantiable(generateMock: .public)
public final class FeedCheckout: Instantiable {
	init(session: Session, feedScreen: FeedScreen) {
		self.session = session
		self.feedScreen = feedScreen
	}

	@Instantiated private let session: Session
	@Instantiated private let feedScreen: FeedScreen
}
