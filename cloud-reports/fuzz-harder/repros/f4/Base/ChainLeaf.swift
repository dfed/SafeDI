import SafeDI
@Instantiable
public final class ChainLeaf: Instantiable {
	public init(chainToken: ChainToken?) { self.chainToken = chainToken }
	@Received(onlyIfAvailable: true) let chainToken: ChainToken?
}
public final class ChainToken {
	public init() {}
}
