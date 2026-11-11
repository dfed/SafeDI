import Feature

func needsSendable(_: (some Sendable).Type) {}
func probe() {
	needsSendable(FrozenPayloadNonSendableField.Scope.self)
}
