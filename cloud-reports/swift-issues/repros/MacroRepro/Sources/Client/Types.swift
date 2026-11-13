import NoopMacros

@NoopMember
public final class Service {
	@NoopPeer var a: Int = 0
	@NoopPeer var b: String = ""
	@NoopPeer var c: Int {
		a
	}

	@NoopPeer
	func d() {}
	public init() {}
	public var description: String {
		""
	}
}
