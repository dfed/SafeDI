import Feature

let flatBuilder: @Sendable (Flat.Scope) -> Int = { scope in
	switch scope {
	case let .own(values): values.name.count
	case let .Inner_x(values): values.name.count
	}
}

let nestedBuilder: @Sendable (Nested.Scope) -> Int = { scope in
	switch scope {
	case let .own(values): values.name.count
	case let .inner(.x(values)): values.name.count
	}
}

let recursiveBuilder: @Sendable (RecursiveA.Scope) -> Int = { scope in
	switch scope {
	case let .own(values): values.name.count
	case .b: 0
	}
}

let nonSendableFieldBuilder: @Sendable (FrozenPayloadNonSendableField.Scope) -> NotSendable = { scope in
	switch scope {
	case let .own(values): values.value
	}
}
