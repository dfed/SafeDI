import SafeDI

// A type whose module generates its own dependency tree, which receives three sessions from its caller under three
// labels. Two types rename one each to `session`, so one reader of `session` is built at five places that read three
// different values, each created when the tree first reads it.

@Instantiable(generateDependencyTree: true)
public final class Feature: Instantiable {
	public init(leftBuilder: Instantiator<Left>, rightBuilder: Instantiator<Right>, holderBuilder: Instantiator<Holder>) {
		self.leftBuilder = leftBuilder
		self.rightBuilder = rightBuilder
		self.holderBuilder = holderBuilder
	}

	@Instantiated let leftBuilder: Instantiator<Left>
	@Instantiated let rightBuilder: Instantiator<Right>
	@Instantiated let holderBuilder: Instantiator<Holder>
}

@Instantiable
public final class Left: Instantiable {
	public init(session: Session, holder: Holder, holderBuilder: Instantiator<Holder>) {
		self.session = session
		self.holder = holder
		self.holderBuilder = holderBuilder
	}

	@Received(fulfilledByDependencyNamed: "first", ofType: Session.self) let session: Session
	@Instantiated let holder: Holder
	@Instantiated let holderBuilder: Instantiator<Holder>
}

@Instantiable
public final class Right: Instantiable {
	public init(session: Session, holder: Holder, holderBuilder: Instantiator<Holder>) {
		self.session = session
		self.holder = holder
		self.holderBuilder = holderBuilder
	}

	@Received(fulfilledByDependencyNamed: "second", ofType: Session.self) let session: Session
	@Instantiated let holder: Holder
	@Instantiated let holderBuilder: Instantiator<Holder>
}

@Instantiable
public final class Holder: Instantiable {
	public init(session: Session) {
		self.session = session
	}

	@Received let session: Session
}

public final class Session {
	public init(name: String) {
		self.name = name
	}

	public let name: String
}
