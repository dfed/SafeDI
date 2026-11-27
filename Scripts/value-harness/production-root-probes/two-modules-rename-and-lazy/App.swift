// module: FuzzApp
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(database: LazilyInstantiated<Database>, repoBuilder: Instantiator<Repo>) { self.database = database; self.repoBuilder = repoBuilder }
    @Instantiated let database: LazilyInstantiated<Database>
    @Instantiated let repoBuilder: Instantiator<Repo>
    let differentialValueCreationStamp = ProbeStamp.next()
}
