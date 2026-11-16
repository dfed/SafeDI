import SafeDI
import Feature

@Instantiable(generateMock: .public)
public final class T8: Instantiable {
	public init(anyT0: AnyT0, analytics: LazilyInstantiated<Analytics>) {
		self.anyT0 = anyT0
		self.analytics = analytics
	}

	@Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true) let anyT0: AnyT0
	@Received let analytics: LazilyInstantiated<Analytics>
}
