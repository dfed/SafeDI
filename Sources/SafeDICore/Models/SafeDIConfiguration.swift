// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

public struct SafeDIConfiguration: Codable, Equatable, Sendable {
	public let additionalImportedModules: [String]
	public let additionalDirectoriesToInclude: [String]
	/// Type names of `@Instantiable` types from other modules to generate mocks for.
	/// The types must be known to the dependency tree (i.e., imported via module info).
	public let additionalMocksToGenerate: [String]
	public let mockConditionalCompilation: String?
	/// Whether each initializer generated for a type the module declares with `generateDependencyTree: true` has, beside
	/// the one generated code calls, a plain one for code a person writes. It decides only the code the module generates
	/// for its own types, so a module that reads another module's `.safedi` file never reads it.
	public let generatePlainDependencyTreeInitializers: Bool
	/// The source file path where this configuration was declared.
	/// Set during parsing to scope configuration to the current module.
	public var sourceFilePath: String?
	/// Where the `#SafeDIConfiguration` invocation begins.
	/// Set during parsing so diagnostics about the configuration point at it.
	public var declarationLocation: Dependency.DeclarationLocation?

	public init(
		additionalImportedModules: [String],
		additionalDirectoriesToInclude: [String],
		additionalMocksToGenerate: [String] = [],
		mockConditionalCompilation: String? = "DEBUG",
		generatePlainDependencyTreeInitializers: Bool = false,
		declarationLocation: Dependency.DeclarationLocation? = nil,
	) {
		self.additionalImportedModules = additionalImportedModules
		self.additionalDirectoriesToInclude = additionalDirectoriesToInclude
		self.additionalMocksToGenerate = additionalMocksToGenerate
		self.mockConditionalCompilation = mockConditionalCompilation
		self.generatePlainDependencyTreeInitializers = generatePlainDependencyTreeInitializers
		self.declarationLocation = declarationLocation
	}

	/// This configuration as a module's `.safedi` file holds it, with `generatePlainDependencyTreeInitializers` at its
	/// default: no reader of the file reads it, so turning it on or off leaves the file's bytes, and the builds of the
	/// modules that read the file, as they were.
	public var asHeldByModuleInfoFile: SafeDIConfiguration {
		var configuration = SafeDIConfiguration(
			additionalImportedModules: additionalImportedModules,
			additionalDirectoriesToInclude: additionalDirectoriesToInclude,
			additionalMocksToGenerate: additionalMocksToGenerate,
			mockConditionalCompilation: mockConditionalCompilation,
			declarationLocation: declarationLocation,
		)
		configuration.sourceFilePath = sourceFilePath
		return configuration
	}
}
