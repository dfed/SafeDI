/// Declares no names, but tries to add a stored property next to the declaration it is attached to.
@attached(peer)
public macro PeerAddsStoredProperty() = #externalMacro(module: "RuleMacrosPlugin", type: "PeerAddsStoredProperty")

/// Declares no names, but tries to add a stored property to the type it is attached to.
@attached(member)
public macro MemberAddsStoredProperty() = #externalMacro(module: "RuleMacrosPlugin", type: "MemberAddsStoredProperty")
