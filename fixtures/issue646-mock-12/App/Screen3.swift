import SafeDI

@Instantiable(generateMock: true)
public final class Screen3 {
	public init(id: String, service: Service, context: Context, screen1Builder: Instantiator<Screen1>, screen7Builder: Instantiator<Screen7>, screen9Builder: Instantiator<Screen9>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen1Builder = screen1Builder
		self.screen7Builder = screen7Builder
		self.screen9Builder = screen9Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received let context: Context
	@Instantiated let screen1Builder: Instantiator<Screen1>
	@Instantiated let screen7Builder: Instantiator<Screen7>
	@Instantiated let screen9Builder: Instantiator<Screen9>
}
