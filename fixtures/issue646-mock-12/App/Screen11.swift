import SafeDI

@Instantiable(generateMock: true)
public final class Screen11 {
	public init(id: String, service: Service, context: Context, screen0Builder: Instantiator<Screen0>, screen5Builder: Instantiator<Screen5>, screen6Builder: Instantiator<Screen6>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen0Builder = screen0Builder
		self.screen5Builder = screen5Builder
		self.screen6Builder = screen6Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received let context: Context
	@Instantiated let screen0Builder: Instantiator<Screen0>
	@Instantiated let screen5Builder: Instantiator<Screen5>
	@Instantiated let screen6Builder: Instantiator<Screen6>
}
