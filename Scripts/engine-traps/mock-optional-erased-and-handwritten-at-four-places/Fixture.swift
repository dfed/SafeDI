import SafeDI

// One holder built by value and by a builder beneath two types that differ in what they offer it. The left type
// instantiates a token, an extra and a left service; the right type a token and a right service, and no extra. The
// holder reads the token, the extra only if one is available, and the service as its protocol; it builds a widget
// whose mock is written by hand, and lazily a leaf that reads the same three values.

public protocol Service {
	var side: String { get }
}

@Instantiable(isRoot: true, generateMock: true)
public final class Root: Instantiable {
	public init(left: Left, right: Right) {
		self.left = left
		self.right = right
	}

	@Instantiated let left: Left
	@Instantiated let right: Right
}

@Instantiable
public final class Left: Instantiable {
	public init(token: Token, extra: Extra, service: any Service, holder: Holder, holderBuilder: Instantiator<Holder>) {
		self.token = token
		self.extra = extra
		self.service = service
		self.holder = holder
		self.holderBuilder = holderBuilder
	}

	@Instantiated let token: Token
	@Instantiated let extra: Extra
	@Instantiated(fulfilledByType: "LeftService") let service: any Service
	@Instantiated let holder: Holder
	@Instantiated let holderBuilder: Instantiator<Holder>
}

@Instantiable
public final class Right: Instantiable {
	public init(token: Token, service: any Service, holder: Holder, holderBuilder: Instantiator<Holder>) {
		self.token = token
		self.service = service
		self.holder = holder
		self.holderBuilder = holderBuilder
	}

	@Instantiated let token: Token
	@Instantiated(fulfilledByType: "RightService") let service: any Service
	@Instantiated let holder: Holder
	@Instantiated let holderBuilder: Instantiator<Holder>
}

@Instantiable
public final class Holder: Instantiable {
	public init(token: Token, extra: Extra?, service: any Service, widget: Widget, lazyLeaf: LazilyInstantiated<Leaf>) {
		self.token = token
		self.extra = extra
		self.service = service
		self.widget = widget
		self.lazyLeaf = lazyLeaf
	}

	@Received let token: Token
	@Received(onlyIfAvailable: true) let extra: Extra?
	@Received let service: any Service
	@Instantiated let widget: Widget
	@Instantiated let lazyLeaf: LazilyInstantiated<Leaf>
}

@Instantiable
public final class Widget: Instantiable {
	public init(token: Token, service: any Service, name: String = "built") {
		self.token = token
		self.service = service
		self.name = name
	}

	@Received let token: Token
	@Received let service: any Service
	let name: String

	#if DEBUG
		public static func mock(token: Token, service: any Service, name: String = "mocked by hand") -> Widget {
			Widget(token: token, service: service, name: name)
		}
	#endif
}

@Instantiable
public final class Leaf: Instantiable {
	public init(token: Token, extra: Extra?, service: any Service, name: String = "built") {
		self.token = token
		self.extra = extra
		self.service = service
		self.name = name
	}

	@Received let token: Token
	@Received(onlyIfAvailable: true) let extra: Extra?
	@Received let service: any Service
	let name: String
}

@Instantiable
public final class Token: Instantiable {
	public init() {}
}

@Instantiable
public final class Extra: Instantiable {
	public init() {}
}

@Instantiable
public final class LeftService: Instantiable, Service {
	public init() {}

	public let side = "left"
}

@Instantiable
public final class RightService: Instantiable, Service {
	public init() {}

	public let side = "right"
}
