import SafeDI

@Instantiable(generateMock: true)
public final class Screen2 {
	public init(id: String, service: Service, context: Context, screen1Builder: Instantiator<Screen1>, screen6Builder: Instantiator<Screen6>, screen8Builder: Instantiator<Screen8>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen1Builder = screen1Builder
		self.screen6Builder = screen6Builder
		self.screen8Builder = screen8Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received let context: Context
	@Instantiated let screen1Builder: Instantiator<Screen1>
	@Instantiated let screen6Builder: Instantiator<Screen6>
	@Instantiated let screen8Builder: Instantiator<Screen8>
}
