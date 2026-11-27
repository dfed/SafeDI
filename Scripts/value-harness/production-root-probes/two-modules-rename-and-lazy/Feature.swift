// module: FuzzFeature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

@Instantiable
public final class Database: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Repo: Instantiable {
    public init(storage: Database, query: Query) { self.storage = storage; self.query = query }
    @Received(fulfilledByDependencyNamed: "database", ofType: Database.self) let storage: Database
    @Instantiated let query: Query
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Query: Instantiable {
    public init(storage: Database, database: LazilyInstantiated<Database>) { self.storage = storage; self.database = database }
    @Received let storage: Database
    @Received let database: LazilyInstantiated<Database>
    let differentialValueCreationStamp = ProbeStamp.next()
}
