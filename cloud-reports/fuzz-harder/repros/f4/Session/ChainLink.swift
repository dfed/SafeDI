import SafeDI
import Core
@Instantiable(generateDependencyTree: true)
public final class ChainLink: Instantiable {
	public init(chainBase: ChainBase) { self.chainBase = chainBase }
	@Instantiated let chainBase: ChainBase
}
