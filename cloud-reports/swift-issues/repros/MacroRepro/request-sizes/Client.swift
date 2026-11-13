@attached(peer)
macro NoopPeer() = #externalMacro(module: "NoopMacrosPlugin", type: "NoopPeerMacro")

struct S {
	@NoopPeer var a: Int = 0
}
