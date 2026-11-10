import Feature

func needsSendable<T: Sendable>(_: T.Type) {}
func probe() { needsSendable(EmptyPayload.Scope.self) }
