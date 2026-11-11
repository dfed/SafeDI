import Feature

func take(_: @escaping @Sendable () -> Void) {}

let builder: @Sendable (Flat.Scope) -> Void = { scope in
	take { _ = scope }
}
