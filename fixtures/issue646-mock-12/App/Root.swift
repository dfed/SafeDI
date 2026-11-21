import SafeDI

@Instantiable(isRoot: true, generateMock: true)
public final class Root {
	public init(service: Service, context: Context, screen0Builder: Instantiator<Screen0>) {
		self.service = service
		self.context = context
		self.screen0Builder = screen0Builder
	}

	@Instantiated let service: Service
	@Instantiated let context: Context
	@Instantiated let screen0Builder: Instantiator<Screen0>
}
