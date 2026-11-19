import SafeDI

public protocol HoleProtocol {}
public struct AnyHole: HoleProtocol {
	public init(_ value: any HoleProtocol) { self.value = value }
	public let value: any HoleProtocol
}
public final class Session: Instantiable, Sendable {
	public init() {}
}
@Instantiable(generateMock: .public)
public final class Screen: Instantiable {
	init(session: LazilyInstantiated<Session>?, holeBuilder: ErasedInstantiator<Int, AnyHole>) {
		self.session = session
		self.holeBuilder = holeBuilder
	}
	@Received(onlyIfAvailable: true) public let session: LazilyInstantiated<Session>?
	@Instantiated(fulfilledByType: "Fill", erasedToConcreteExistential: true) public let holeBuilder: ErasedInstantiator<Int, AnyHole>
}
