// Hand-written. The scope enum in each form, to ask the compiler whether it is Sendable.
public protocol Service {}

public final class NotSendable {}

// MARK: As the design emits them: @frozen enums, payload structs public and not @frozen

public enum Flat {
	@frozen public enum Scope {
		case own(Own_Values)
		case Inner_x(InnerAsDesigned.x_Values)

		public struct Own_Values {
			public let name: String
		}
	}
}

public enum InnerAsDesigned {
	@frozen public enum Scope {
		case x(x_Values)
	}

	public struct x_Values {
		public let name: String
	}
}

public enum Nested {
	@frozen public enum Scope {
		case own(Flat.Scope.Own_Values)
		case inner(InnerAsDesigned.Scope)
	}
}

public enum RecursiveA {
	@frozen public enum Scope {
		case own(Flat.Scope.Own_Values)
		indirect case b(RecursiveB.Scope)
	}
}

public enum RecursiveB {
	@frozen public enum Scope {
		case own(Flat.Scope.Own_Values)
		indirect case a(RecursiveA.Scope)
	}
}

public enum EmptyPayload {
	@frozen public enum Scope {
		case own(Values)

		public struct Values {}
	}
}

// MARK: What if the payload structs were @frozen too

public enum FlatFrozenPayload {
	@frozen public enum Scope {
		case own(Own_Values)

		@frozen public struct Own_Values {
			public let name: String
		}
	}
}

public enum NestedFrozenPayload {
	@frozen public enum Scope {
		case own(FlatFrozenPayload.Scope.Own_Values)
		case inner(FlatFrozenPayload.Scope)
	}
}

public enum RecursiveFrozenPayloadA {
	@frozen public enum Scope {
		case own(FlatFrozenPayload.Scope.Own_Values)
		indirect case b(RecursiveFrozenPayloadB.Scope)
	}
}

public enum RecursiveFrozenPayloadB {
	@frozen public enum Scope {
		case own(FlatFrozenPayload.Scope.Own_Values)
		indirect case a(RecursiveFrozenPayloadA.Scope)
	}
}

public enum FrozenPayloadNonSendableField {
	@frozen public enum Scope {
		case own(Own_Values)

		@frozen public struct Own_Values {
			public let value: NotSendable
		}
	}
}
