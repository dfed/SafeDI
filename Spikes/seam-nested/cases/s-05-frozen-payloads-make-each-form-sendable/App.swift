import Feature

func needsSendable<T: Sendable>(_: T.Type) {}
func probe() {
	needsSendable(FlatFrozenPayload.Scope.self)
	needsSendable(NestedFrozenPayload.Scope.self)
}
