// module: FuzzApp, fills a hole
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(user: User, inbox: Inbox, session: AppSession) { self.user = user; self.inbox = inbox; self.session = session }
    @Instantiated let user: User
    @Instantiated let inbox: Inbox
    @Instantiated let session: AppSession
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class AppSession: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class ApiImpl: Instantiable, Api {
    public init(user: User, session: AppSession) { self.user = user; self.session = session }
    @Received let user: User
    @Received let session: AppSession
    let differentialValueCreationStamp = ProbeStamp.next()
}
