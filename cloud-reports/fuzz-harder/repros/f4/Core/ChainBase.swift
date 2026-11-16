import SafeDI
import Base
@Instantiable(generateDependencyTree: true)
public final class ChainBase: Instantiable {
	public init(chainLeaf: ChainLeaf) { self.chainLeaf = chainLeaf }
	@Instantiated let chainLeaf: ChainLeaf
}
