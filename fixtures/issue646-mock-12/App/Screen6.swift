import SafeDI

@Instantiable(generateMock: true)
public final class Screen6 {
	public init(id: String, service: Service, context: Context, screen2Builder: Instantiator<Screen2>, screen8Builder: Instantiator<Screen8>, screen10Builder: Instantiator<Screen10>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen2Builder = screen2Builder
		self.screen8Builder = screen8Builder
		self.screen10Builder = screen10Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received let context: Context
	@Instantiated let screen2Builder: Instantiator<Screen2>
	@Instantiated let screen8Builder: Instantiator<Screen8>
	@Instantiated let screen10Builder: Instantiator<Screen10>
}
