// From the manual’s “Adopting SafeDI in a large codebase”: a seam with a public mock whose tree instantiates a protocol
// only the app implements.
import Core
import SafeDI

public protocol FeedService {
	func refresh() async
}

@Instantiable(generateDependencyTree: true, generateMock: .public)
public final class FeedScreen: Instantiable {
	init(session: Session, service: FeedService) {
		self.session = session
		self.service = service
	}

	@Received private let session: Session
	@Instantiated private let service: FeedService
}
