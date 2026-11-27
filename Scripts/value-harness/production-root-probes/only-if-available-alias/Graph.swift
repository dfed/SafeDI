import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(account: Account, pane: AccountPane, otherBuilder: Instantiator<OtherPane>) { self.account = account; self.pane = pane; self.otherBuilder = otherBuilder }
    @Instantiated let account: Account
    @Instantiated let pane: AccountPane
    @Instantiated let otherBuilder: Instantiator<OtherPane>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Account: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class AccountPane: Instantiable {
    public init(maybeAccount: Account?, row: AccountRow) { self.maybeAccount = maybeAccount; self.row = row }
    @Received(fulfilledByDependencyNamed: "account", ofType: Account.self, onlyIfAvailable: true) let maybeAccount: Account?
    @Instantiated let row: AccountRow
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class AccountRow: Instantiable {
    public init(maybeAccount: Account?, account: Account) { self.maybeAccount = maybeAccount; self.account = account }
    @Received(onlyIfAvailable: true) let maybeAccount: Account?
    @Received let account: Account
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class OtherPane: Instantiable {
    public init(maybeOther: Account?) { self.maybeOther = maybeOther }
    @Received(fulfilledByDependencyNamed: "missingAccount", ofType: Account.self, onlyIfAvailable: true) let maybeOther: Account?
    let differentialValueCreationStamp = ProbeStamp.next()
}
