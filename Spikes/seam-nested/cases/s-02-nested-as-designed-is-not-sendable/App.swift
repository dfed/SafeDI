import Feature

func needsSendable<T: Sendable>(_: T.Type) {}
func probe() { needsSendable(Nested.Scope.self) }
