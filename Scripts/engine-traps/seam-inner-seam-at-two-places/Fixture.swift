import SafeDI

// A type whose module generates its own dependency tree, called by the tree of another such type at three places: by
// a builder at the top, where it reads the session the outer caller hands over, and by value and by a builder beneath
// a type that instantiates a session of its own. The three calls spell the same text.

@Instantiable(generateDependencyTree: true)
public final class Feature: Instantiable {
	public init(innerBuilder: Instantiator<Inner>, panelBuilder: Instantiator<Panel>) {
		self.innerBuilder = innerBuilder
		self.panelBuilder = panelBuilder
	}

	@Instantiated let innerBuilder: Instantiator<Inner>
	@Instantiated let panelBuilder: Instantiator<Panel>
}

@Instantiable
public final class Panel: Instantiable {
	public init(session: Session, inner: Inner, innerBuilder: Instantiator<Inner>) {
		self.session = session
		self.inner = inner
		self.innerBuilder = innerBuilder
	}

	@Instantiated let session: Session
	@Instantiated let inner: Inner
	@Instantiated let innerBuilder: Instantiator<Inner>
}

@Instantiable(generateDependencyTree: true)
public final class Inner: Instantiable {
	public init(readerBuilder: Instantiator<Reader>) {
		self.readerBuilder = readerBuilder
	}

	@Instantiated let readerBuilder: Instantiator<Reader>
}

@Instantiable
public final class Reader: Instantiable {
	public init(session: Session) {
		self.session = session
	}

	@Received let session: Session
}

@Instantiable
public final class Session: Instantiable {
	public init() {}
}
