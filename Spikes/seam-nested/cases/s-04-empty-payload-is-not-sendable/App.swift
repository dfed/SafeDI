import Feature

func needsSendable(_: (some Sendable).Type) {}
func probe() {
	needsSendable(EmptyPayload.Scope.self)
}
