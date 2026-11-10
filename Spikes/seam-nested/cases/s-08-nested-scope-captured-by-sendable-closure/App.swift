import Feature

func take(_ body: @escaping @Sendable () -> Void) {}

let builder: @Sendable (Nested.Scope) -> Void = { scope in
	take { _ = scope }
}
