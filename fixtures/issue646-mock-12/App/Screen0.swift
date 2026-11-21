import SafeDI

@Instantiable(generateMock: true)
public final class Screen0 {
	public init(id: String, service: Service, context: Context, screen5Builder: Instantiator<Screen5>, screen6Builder: Instantiator<Screen6>, screen10Builder: Instantiator<Screen10>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen5Builder = screen5Builder
		self.screen6Builder = screen6Builder
		self.screen10Builder = screen10Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Instantiated let context: Context
	@Instantiated let screen5Builder: Instantiator<Screen5>
	@Instantiated let screen6Builder: Instantiator<Screen6>
	@Instantiated let screen10Builder: Instantiator<Screen10>
}
