#if canImport(Feed)
import Feed
#endif
import SafeDI

@Instantiable(generateMock: true)
public final class Root: Instantiable {
	public init(screen: Screen, session: LazilyInstantiated<Session>) {
		self.screen = screen
		self.session = session
	}
	@Instantiated public let screen: Screen
	@Instantiated public let session: LazilyInstantiated<Session>
}
@Instantiable(conformsElsewhere: true)
extension Session {
	public static func instantiate() -> Session { Session() }
}
@Instantiable
public final class Fill: Instantiable, HoleProtocol {
	public init(ticket: Int, screenBuilder: Instantiator<Screen>, child: Child) {
		self.ticket = ticket
		self.screenBuilder = screenBuilder
		self.child = child
	}
	@Forwarded let ticket: Int
	@Instantiated let screenBuilder: Instantiator<Screen>
	@Instantiated let child: Child
}
@Instantiable
public final class Child: Instantiable {
	public init(session: Session) { self.session = session }
	@Received public let session: Session
}

