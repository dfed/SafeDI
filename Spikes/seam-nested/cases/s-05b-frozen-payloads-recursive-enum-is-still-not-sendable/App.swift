import Feature

func needsSendable(_: (some Sendable).Type) {}
func probe() {
	needsSendable(RecursiveFrozenPayloadA.Scope.self)
	needsSendable(RecursiveFrozenPayloadB.Scope.self)
}
