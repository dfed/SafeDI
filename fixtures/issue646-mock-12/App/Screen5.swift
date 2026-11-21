import SafeDI

@Instantiable(generateMock: true)
public final class Screen5 {
	public init(id: String, service: Service, context: Context, screen2Builder: Instantiator<Screen2>, screen7Builder: Instantiator<Screen7>, screen11Builder: Instantiator<Screen11>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen2Builder = screen2Builder
		self.screen7Builder = screen7Builder
		self.screen11Builder = screen11Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Instantiated let context: Context
	@Instantiated let screen2Builder: Instantiator<Screen2>
	@Instantiated let screen7Builder: Instantiator<Screen7>
	@Instantiated let screen11Builder: Instantiator<Screen11>
}
