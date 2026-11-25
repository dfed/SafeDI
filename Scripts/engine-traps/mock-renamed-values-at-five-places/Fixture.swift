import SafeDI

// The root instantiates three sessions under three labels. Two types each rename a different one to `session`, and
// one holder of `session` is built by value and by a builder beneath each of them and by a builder at the root. The
// holder also reads the session renamed and wrapped, and builds a leaf that reads both.

@Instantiable(isRoot: true, generateMock: true)
public final class Root: Instantiable {
	public init(first: Session, second: Session, session: Session, left: Left, right: Right, holderBuilder: Instantiator<Holder>) {
		self.first = first
		self.second = second
		self.session = session
		self.left = left
		self.right = right
		self.holderBuilder = holderBuilder
	}

	@Instantiated let first: Session
	@Instantiated let second: Session
	@Instantiated let session: Session
	@Instantiated let left: Left
	@Instantiated let right: Right
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
	public init(session: Session, wrapped: AnySession, leaf: Leaf) {
		self.session = session
		self.wrapped = wrapped
		self.leaf = leaf
	}

	@Received let session: Session
	@Received(fulfilledByDependencyNamed: "session", ofType: Session.self, erasedToConcreteExistential: true) let wrapped: AnySession
	@Instantiated let leaf: Leaf
}

@Instantiable
public final class Leaf: Instantiable {
	public init(session: Session, wrapped: AnySession, name: String = "built") {
		self.session = session
		self.wrapped = wrapped
		self.name = name
	}

	@Received let session: Session
	@Received let wrapped: AnySession
	let name: String
}

@Instantiable
public final class Session: Instantiable {
	public init(name: String = "built") {
		self.name = name
	}

	public let name: String
}

public struct AnySession {
	public init(_ session: Session) {
		self.session = session
	}

	public let session: Session
}
