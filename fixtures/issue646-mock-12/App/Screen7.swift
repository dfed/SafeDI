import SafeDI

@Instantiable(generateMock: true)
public final class Screen7 {
	public init(id: String, service: Service, context: Context, screen0Builder: Instantiator<Screen0>, screen2Builder: Instantiator<Screen2>, screen10Builder: Instantiator<Screen10>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen0Builder = screen0Builder
		self.screen2Builder = screen2Builder
		self.screen10Builder = screen10Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received let context: Context
	@Instantiated let screen0Builder: Instantiator<Screen0>
	@Instantiated let screen2Builder: Instantiator<Screen2>
	@Instantiated let screen10Builder: Instantiator<Screen10>
}
