internal import Lower

public final class Feature { public init() {} }
extension Feature {
	@frozen
	public enum SafeDIScope_Service { case inner(Inner.SafeDIScope_Service) }
	public convenience init(serviceBuilder _: @escaping (SafeDIScope_Service) -> Int) {
		self.init()
	}
}
