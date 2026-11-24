import SafeDI
import Synchronization

// A type whose module generates its own dependency tree, which receives a session from its caller and builds its
// readers with builders that can cross isolation. A screen forwards an identifier, and one reader of the session and
// the identifier is built beneath the top screen and beneath the screen of a type with a session of its own.

@Instantiable(generateDependencyTree: true)
public final class Feature: Instantiable, Sendable {
	public init(screenBuilder: SendableInstantiator<Screen>, panelBuilder: SendableInstantiator<Panel>) {
		self.screenBuilder = screenBuilder
		self.panelBuilder = panelBuilder
	}

	@Instantiated let screenBuilder: SendableInstantiator<Screen>
	@Instantiated let panelBuilder: SendableInstantiator<Panel>
}

@Instantiable
public final class Panel: Instantiable, Sendable {
	public init(session: Session, screenBuilder: SendableInstantiator<Screen>) {
		self.session = session
		self.screenBuilder = screenBuilder
	}

	@Instantiated let session: Session
	@Instantiated let screenBuilder: SendableInstantiator<Screen>
}

@Instantiable
public final class Screen: Instantiable, Sendable {
	public init(id: String, reader: Reader, readerBuilder: SendableInstantiator<Reader>) {
		self.id = id
		self.reader = reader
		self.readerBuilder = readerBuilder
	}

	@Forwarded let id: String
	@Instantiated let reader: Reader
	@Instantiated let readerBuilder: SendableInstantiator<Reader>
}

@Instantiable
public final class Reader: Instantiable, Sendable {
	public init(id: String, session: Session) {
		self.id = id
		self.session = session
	}

	@Received let id: String
	@Received let session: Session
}

@Instantiable
public final class Session: Instantiable, Sendable {
	public init() {}
}

public enum Counts {
	public static let sessionsFromTheCaller = Mutex(0)
}
