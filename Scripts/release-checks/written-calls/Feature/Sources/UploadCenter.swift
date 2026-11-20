// From the manual’s “Dependency kinds in the generated mock”: the `mock()` of a seam takes, for a dependency its
// initializer takes a builder for, the same builder in place of the flat parameter.
import SafeDI

@Instantiable(generateDependencyTree: true, generateMock: true)
public final class UploadCenter: Instantiable {
	public init(uploader: any Uploader) {
		self.uploader = uploader
	}

	@Instantiated private let uploader: any Uploader
}
