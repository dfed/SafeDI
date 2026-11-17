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

import SwiftParser
import SwiftSyntax

/// What the generated configurations of a graph store: a mock's `SafeDIOverrides`, each `SafeDIMockConfiguration`, and
/// a public mock's module-level configuration (`__safeDI_<Module>_<Type>_MockConfiguration`). Each keeps its fields
/// behind one reference, so none stores another configuration by value: every builder function of a mock captures the
/// overrides, and a configuration that held the configurations beneath it by value was copied whole into each, which
/// made the compiler's memory grow with the square of the mock's paths.
enum GraphFuzzerConfigurationStorage {
	/// Each stored property of a configuration in `generatedFiles` whose type is a configuration, as
	/// `` `<configuration>` stores `<label>: <type>` by value. ``, in file name order and then in source order.
	static func fieldsStoringAnotherConfiguration(in generatedFiles: [String: String]) -> [String] {
		configurations(in: generatedFiles).flatMap { configuration in
			configuration.storedFields
				.filter { isConfigurationType($0.type) }
				.map { "`\(configuration.name)` in `\($0.fileName)` stores `\($0.label): \($0.type)` by value." }
		}
	}

	/// How many configurations `generatedFiles` declares, which the oracle judges.
	static func configurationCount(in generatedFiles: [String: String]) -> Int {
		configurations(in: generatedFiles).count
	}

	// MARK: Private

	private struct Configuration {
		let name: String
		let storedFields: [(fileName: String, label: String, type: String)]
	}

	private static func configurations(in generatedFiles: [String: String]) -> [Configuration] {
		var configurations = [Configuration]()
		for fileName in generatedFiles.keys.sorted() {
			let collector = ConfigurationCollector(fileName: fileName)
			collector.walk(Parser.parse(source: generatedFiles[fileName, default: ""]))
			configurations += collector.configurations
		}
		return configurations
	}

	/// Whether `name` names a configuration: `SafeDIOverrides`, `SafeDIMockConfiguration`, or a public mock's
	/// module-level configuration.
	fileprivate static func isConfigurationName(_ name: String) -> Bool {
		name == "SafeDIOverrides" || name == "SafeDIMockConfiguration" || (name.hasPrefix("__safeDI_") && name.hasSuffix("_MockConfiguration"))
	}

	/// Whether `type` spells a configuration, qualified by the type it is nested in or not.
	private static func isConfigurationType(_ type: String) -> Bool {
		isConfigurationName(String(type.split(separator: ".").last ?? ""))
	}

	private final class ConfigurationCollector: SyntaxVisitor {
		init(fileName: String) {
			self.fileName = fileName
			super.init(viewMode: .sourceAccurate)
		}

		private(set) var configurations = [Configuration]()

		override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
			guard GraphFuzzerConfigurationStorage.isConfigurationName(node.name.text) else { return .visitChildren }
			var storedFields = [(fileName: String, label: String, type: String)]()
			for member in node.memberBlock.members {
				// A computed property reads its value from the storage, which is the one reference the configuration holds.
				guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
				for binding in variable.bindings where binding.accessorBlock == nil {
					guard let type = binding.typeAnnotation?.type.trimmedDescription else { continue }
					storedFields.append((fileName: fileName, label: binding.pattern.trimmedDescription, type: type))
				}
			}
			configurations.append(Configuration(name: node.name.text, storedFields: storedFields))
			return .skipChildren
		}

		private let fileName: String
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph one of whose generated configurations stores another configuration by value, or `nil`.
	var configurationStorageFailure: GraphFuzzerFailure? {
		let fields = GraphFuzzerConfigurationStorage.fieldsStoringAnotherConfiguration(in: generatedFiles)
		guard !fields.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .configurationStoresAnotherByValue,
			details: "\(fields.joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)",
		)
	}
}
