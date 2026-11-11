import Feature

func take(_: @escaping @Sendable () -> Void) {}

let builder: @Sendable (Nested.Scope) -> Void = { scope in
	take { _ = scope }
}
