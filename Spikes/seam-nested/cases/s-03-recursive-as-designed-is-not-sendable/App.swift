import Feature

func needsSendable<T: Sendable>(_: T.Type) {}
func probe() { needsSendable(RecursiveA.Scope.self) }
