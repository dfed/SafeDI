import RuleMacros

@MemberAddsStoredProperty
public struct S {
	@PeerAddsStoredProperty var a: Int = 0
}
