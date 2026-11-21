// From the manual’s “Public mocks”: a public mock’s hole builder takes what the hole’s places forward and nothing else,
// whatever holds the place, and “Calling a public mock from another module”: a public mock whose only dependency is a
// hole takes no `safeDIOverrides`, so a calling mock’s override of it is a closure handed the builders its `mock()`
// takes.
import SafeDI

/// Built only through `LazilyInstantiated`; its public mock’s builder still takes nothing.
@Instantiable(generateMock: .public)
public final class FeedLoader: Instantiable {
	init(service: LazilyInstantiated<any FeedService>) {
		self.service = service
	}

	@Instantiated private let service: LazilyInstantiated<any FeedService>
}

/// Conforms to `Instantiable` by hand and forwards a `String`, so no `@Instantiable` declaration fulfills it.
public final class FeedReader: Instantiable {
	public typealias ForwardedProperties = String

	public init(feedName: String) {
		self.feedName = feedName
	}

	private let feedName: String
}

/// Holds a hole that forwards a value, so its public mock’s builder takes the forwarded value.
@Instantiable(generateMock: .public)
public final class FeedReaderHost: Instantiable {
	init(readerBuilder: Instantiator<FeedReader>) {
		self.readerBuilder = readerBuilder
	}

	@Instantiated private let readerBuilder: Instantiator<FeedReader>
}

public protocol FeedSyncer: Sendable {}

/// Holds a hole in a `Sendable` wrapper.
@Instantiable(generateMock: .public)
public final class FeedSyncHost: Instantiable {
	init(syncerBuilder: SendableErasedInstantiator<(), any FeedSyncer>) {
		self.syncerBuilder = syncerBuilder
	}

	@Instantiated(fulfilledByType: "AppFeedSyncer") private let syncerBuilder: SendableErasedInstantiator<(), any FeedSyncer>
}

public final class FeedToken {
	public init() {}
}

/// Receives a lazily instantiated value its mock cannot build, beside a hole: the mock takes the value, and the hole’s
/// builder still takes nothing.
@Instantiable(generateMock: .public)
public final class FeedDetail: Instantiable {
	init(token: LazilyInstantiated<FeedToken>, service: any FeedService) {
		self.token = token
		self.service = service
	}

	@Received private let token: LazilyInstantiated<FeedToken>
	@Instantiated private let service: any FeedService
}

public protocol FeedRenderer {}

/// Its only dependency is a hole, so its public mock takes no `safeDIOverrides`.
@Instantiable(generateMock: .public)
public struct FeedBadge: Instantiable {
	package init(renderer: any FeedRenderer) {
		self.renderer = renderer
	}

	@Instantiated private let renderer: any FeedRenderer
}
