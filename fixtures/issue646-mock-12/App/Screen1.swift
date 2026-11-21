import SafeDI

@Instantiable(generateMock: true)
public final class Screen1 {
	public init(id: String, service: Service, context: Context, screen0Builder: Instantiator<Screen0>, screen4Builder: Instantiator<Screen4>, screen8Builder: Instantiator<Screen8>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen0Builder = screen0Builder
		self.screen4Builder = screen4Builder
		self.screen8Builder = screen8Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received let context: Context
	@Instantiated let screen0Builder: Instantiator<Screen0>
	@Instantiated let screen4Builder: Instantiator<Screen4>
	@Instantiated let screen8Builder: Instantiator<Screen8>
}
