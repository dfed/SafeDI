import SafeDI

// Three types whose module generates their own dependency trees. The innermost leaves one type, an api, for its
// caller to build, at two places. The middle one calls the innermost beneath one type, a side, built at two places
// with a token each, and so passes the api up to its own caller. The outermost calls the middle one beneath one type,
// a half, built at two places with a token each, and passes the api up again.

@Instantiable(generateDependencyTree: true)
public final class Outer: Instantiable {
	public init(nearHalf: Half, farHalfBuilder: Instantiator<Half>) {
		self.nearHalf = nearHalf
		self.farHalfBuilder = farHalfBuilder
	}

	@Instantiated let nearHalf: Half
	@Instantiated let farHalfBuilder: Instantiator<Half>
}

@Instantiable
public final class Half: Instantiable {
	public init(token: Token, middle: Middle, middleBuilder: Instantiator<Middle>) {
		self.token = token
		self.middle = middle
		self.middleBuilder = middleBuilder
	}

	@Instantiated let token: Token
	@Instantiated let middle: Middle
	@Instantiated let middleBuilder: Instantiator<Middle>
}

@Instantiable(generateDependencyTree: true)
public final class Middle: Instantiable {
	public init(leftSide: Side, rightSideBuilder: Instantiator<Side>) {
		self.leftSide = leftSide
		self.rightSideBuilder = rightSideBuilder
	}

	@Instantiated let leftSide: Side
	@Instantiated let rightSideBuilder: Instantiator<Side>
}

@Instantiable
public final class Side: Instantiable {
	public init(mark: Mark, inner: Inner, innerBuilder: Instantiator<Inner>) {
		self.mark = mark
		self.inner = inner
		self.innerBuilder = innerBuilder
	}

	@Instantiated let mark: Mark
	@Instantiated let inner: Inner
	@Instantiated let innerBuilder: Instantiator<Inner>
}

@Instantiable(generateDependencyTree: true)
public final class Inner: Instantiable {
	public init(client: Client, clientBuilder: Instantiator<Client>) {
		self.client = client
		self.clientBuilder = clientBuilder
	}

	@Instantiated let client: Client
	@Instantiated let clientBuilder: Instantiator<Client>
}

@Instantiable
public final class Client: Instantiable {
	public init(token: Token, mark: Mark, api: Api) {
		self.token = token
		self.mark = mark
		self.api = api
	}

	@Received let token: Token
	@Received let mark: Mark
	@Instantiated let api: Api
}

@Instantiable
public final class Token: Instantiable {
	public init() {}
}

@Instantiable
public final class Mark: Instantiable {
	public init() {}
}

public final class Api {
	public init(place: String) {
		self.place = place
	}

	public let place: String
}
