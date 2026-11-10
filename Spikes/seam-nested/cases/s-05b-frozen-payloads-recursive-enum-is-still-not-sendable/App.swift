import Feature

func needsSendable<T: Sendable>(_: T.Type) {}
func probe() {
	needsSendable(RecursiveFrozenPayloadA.Scope.self)
	needsSendable(RecursiveFrozenPayloadB.Scope.self)
}
