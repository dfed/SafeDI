import Feature

func take(_ body: @escaping @Sendable () -> Void) {}

let builder: @Sendable (Flat.Scope) -> Void = { scope in
	take { _ = scope }
}
