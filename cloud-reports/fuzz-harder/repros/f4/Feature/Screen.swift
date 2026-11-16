import SafeDI
import Session
@Instantiable(generateMock: true)
public final class Screen: Instantiable {
	public init(chainLink: ChainLink) { self.chainLink = chainLink }
	@Instantiated let chainLink: ChainLink
}
