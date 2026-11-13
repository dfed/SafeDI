/// A peer macro that expands to nothing and declares no names.
@attached(peer)
public macro NoopPeer() = #externalMacro(module: "NoopMacrosPlugin", type: "NoopPeerMacro")

/// A member macro that expands to nothing and declares no names.
@attached(member)
public macro NoopMember() = #externalMacro(module: "NoopMacrosPlugin", type: "NoopMemberMacro")
