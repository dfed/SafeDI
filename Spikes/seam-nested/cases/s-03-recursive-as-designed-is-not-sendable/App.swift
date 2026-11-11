import Feature

func needsSendable(_: (some Sendable).Type) {}
func probe() {
	needsSendable(RecursiveA.Scope.self)
}
