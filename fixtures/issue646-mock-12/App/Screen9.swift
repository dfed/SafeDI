import SafeDI

@Instantiable(generateMock: true)
public final class Screen9 {
	public init(id: String, service: Service, context: Context, screen3Builder: Instantiator<Screen3>, screen5Builder: Instantiator<Screen5>, screen8Builder: Instantiator<Screen8>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen3Builder = screen3Builder
		self.screen5Builder = screen5Builder
		self.screen8Builder = screen8Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received let context: Context
	@Instantiated let screen3Builder: Instantiator<Screen3>
	@Instantiated let screen5Builder: Instantiator<Screen5>
	@Instantiated let screen8Builder: Instantiator<Screen8>
}
