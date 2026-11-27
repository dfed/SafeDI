// module: FuzzFeature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

public protocol Api: AnyObject {}
@Instantiable(generateDependencyTree: true)
public final class Inbox: Instantiable {
    public init(user: User, threadBuilder: Instantiator<ThreadView>) { self.user = user; self.threadBuilder = threadBuilder }
    @Received let user: User
    @Instantiated let threadBuilder: Instantiator<ThreadView>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class User: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class ThreadView: Instantiable {
    public init(api: any Api, user: User) { self.api = api; self.user = user }
    @Instantiated let api: any Api
    @Received let user: User
    let differentialValueCreationStamp = ProbeStamp.next()
}
