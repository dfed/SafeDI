import Feature

func needsSendable(_: (some Sendable).Type) {}
func probe() {
	needsSendable(FlatFrozenPayload.Scope.self)
	needsSendable(NestedFrozenPayload.Scope.self)
}
