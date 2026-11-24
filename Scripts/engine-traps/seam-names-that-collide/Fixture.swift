import SafeDI

// The tree of the renamed-sessions trap, whose caller also hands over two values read when the tree is built, under
// the labels generated code would otherwise pick for a second shared function and for a session's creating closure.

@Instantiable(generateDependencyTree: true)
public final class Feature: Instantiable {
	public init(eager: Eager, leftBuilder: Instantiator<Left>, rightBuilder: Instantiator<Right>, holderBuilder: Instantiator<Holder>) {
		self.eager = eager
		self.leftBuilder = leftBuilder
		self.rightBuilder = rightBuilder
		self.holderBuilder = holderBuilder
	}

	@Instantiated let eager: Eager
	@Instantiated let leftBuilder: Instantiator<Left>
	@Instantiated let rightBuilder: Instantiator<Right>
	@Instantiated let holderBuilder: Instantiator<Holder>
}

@Instantiable
public final class Eager: Instantiable {
	public init(holderBuilder_: Session, session_: Session) {
		self.holderBuilder_ = holderBuilder_
		self.session_ = session_
	}

	@Received let holderBuilder_: Session
	@Received let session_: Session
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
