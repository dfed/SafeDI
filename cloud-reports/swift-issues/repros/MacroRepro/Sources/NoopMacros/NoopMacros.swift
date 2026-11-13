/// Expands to nothing. Declares no `names:`, so it cannot add a stored property.
@attached(peer)
public macro NoopPeer() = #externalMacro(module: "NoopMacrosPlugin", type: "NoopPeerMacro")

/// Expands to nothing. Declares no `names:`, so it cannot add a stored property.
@attached(member)
public macro NoopMember() = #externalMacro(module: "NoopMacrosPlugin", type: "NoopMemberMacro")
