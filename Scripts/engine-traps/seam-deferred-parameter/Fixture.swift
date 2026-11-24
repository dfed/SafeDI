import SafeDI

// A type whose module generates its own dependency tree, which receives a session from its caller. The session is
// created when the tree first reads it. One reader of it is built in three places: by a builder at the top, by a
// builder beneath a type that instantiates a session of its own, and by value inside a type a builder builds.

@Instantiable(generateDependencyTree: true)
public final class Feature: Instantiable {
	public init(screenBuilder: Instantiator<Screen>, panel: Panel, subBuilder: Instantiator<Sub>) {
		self.screenBuilder = screenBuilder
		self.panel = panel
		self.subBuilder = subBuilder
	}

	@Instantiated let screenBuilder: Instantiator<Screen>
	@Instantiated let panel: Panel
	@Instantiated let subBuilder: Instantiator<Sub>
}

@Instantiable
public final class Panel: Instantiable {
	public init(session: Session, screenBuilder: Instantiator<Screen>) {
		self.session = session
		self.screenBuilder = screenBuilder
	}

	@Instantiated let session: Session
	@Instantiated let screenBuilder: Instantiator<Screen>
}

@Instantiable
public final class Sub: Instantiable {
	public init(screen: Screen) {
		self.screen = screen
	}

	@Instantiated let screen: Screen
}

@Instantiable
public final class Screen: Instantiable {
	public init(session: Session) {
		self.session = session
	}

	@Received let session: Session
}

@Instantiable
public final class Session: Instantiable {
	public init() {}
}
