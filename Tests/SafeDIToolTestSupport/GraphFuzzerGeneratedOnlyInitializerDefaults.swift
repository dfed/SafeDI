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

/// The initializers only generated code calls: each tier of a seam declares one, every parameter and builder of which
/// is labeled `__safeDI_<label>`, and each builder struct of a public mock's scope enum declares
/// `init(__safeDI_noScope __safeDI_builder:)`. No parameter of one has a default (`seam-access-proof.md`): every call
/// is generated and writes every argument, so a default would only let a call SafeDI generated against an older
/// signature compile while it passes nothing for a parameter the tree now reads.
enum GraphFuzzerGeneratedOnlyInitializerDefaults {
	/// Each parameter with a default of an initializer in `generatedFiles` only generated code calls, as
	/// `` `<file>` line <n>: `<type>`’s initializer only generated code calls gives `<label>` a default: <parameter> ``,
	/// in file name order and then in source order.
	static func parametersWithDefaults(in generatedFiles: [String: String]) -> [String] {
		initializers(in: generatedFiles).flatMap { initializer in
			initializer.parametersWithDefaults.map { parameter in
				"`\(initializer.fileName)` line \(parameter.line): `\(initializer.typeName)`’s initializer only generated code calls gives `\(parameter.label)` a default: \(parameter.text)"
			}
		}
	}

	/// How many initializers only generated code calls `generatedFiles` declares, which the oracle judges.
	static func initializerCount(in generatedFiles: [String: String]) -> Int {
		initializers(in: generatedFiles).count
	}

	// MARK: Private

	private struct Initializer {
		let fileName: String
		let typeName: String
		let parametersWithDefaults: [(line: Int, label: String, text: String)]
	}

	private static func initializers(in generatedFiles: [String: String]) -> [Initializer] {
		var initializers = [Initializer]()
		for fileName in generatedFiles.keys.sorted() {
			let source = Parser.parse(source: generatedFiles[fileName, default: ""])
			let collector = InitializerCollector(fileName: fileName, converter: SourceLocationConverter(fileName: fileName, tree: source))
			collector.walk(source)
			initializers += collector.initializers
		}
		return initializers
	}

	private final class InitializerCollector: SyntaxVisitor {
		init(fileName: String, converter: SourceLocationConverter) {
			self.fileName = fileName
			self.converter = converter
			super.init(viewMode: .sourceAccurate)
		}

		private(set) var initializers = [Initializer]()

		override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
			typeNames.append(node.extendedType.trimmedDescription)
			return .visitChildren
		}

		override func visitPost(_: ExtensionDeclSyntax) {
			typeNames.removeLast()
		}

		override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
			typeNames.append(node.name.text)
			return .visitChildren
		}

		override func visitPost(_: EnumDeclSyntax) {
			typeNames.removeLast()
		}

		override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
			typeNames.append(node.name.text)
			return .visitChildren
		}

		override func visitPost(_: StructDeclSyntax) {
			typeNames.removeLast()
		}

		override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
			let parameters = node.signature.parameterClause.parameters
			// An initializer only generated code calls labels every parameter `__safeDI_`; its first label says which it is.
			guard let firstLabel = parameters.first?.firstName.text, firstLabel.hasPrefix("__safeDI_") else { return .skipChildren }
			initializers.append(Initializer(
				fileName: fileName,
				typeName: typeNames.joined(separator: "."),
				// `SyntaxCollection.filter` builds a detached collection, whose positions no longer read the file's lines.
				parametersWithDefaults: parameters.compactMap { parameter -> (line: Int, label: String, text: String)? in
					guard parameter.defaultValue != nil else { return nil }
					return (
						line: converter.location(for: parameter.positionAfterSkippingLeadingTrivia).line,
						label: parameter.firstName.text,
						text: parameter.with(\.trailingComma, nil).trimmedDescription,
					)
				},
			))
			return .skipChildren
		}

		private let fileName: String
		private let converter: SourceLocationConverter
		private var typeNames = [String]()
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph one of whose initializers only generated code calls gives a parameter a default, in one
	/// module or under the module-info integration of a split of it, or `nil`.
	var generatedOnlyInitializerTakesDefaultFailure: GraphFuzzerFailure? {
		for (description, files) in judgedGeneratedFiles {
			let findings = GraphFuzzerGeneratedOnlyInitializerDefaults.parametersWithDefaults(in: files)
			guard !findings.isEmpty else { continue }
			return GraphFuzzerFailure(
				seed: fixture.seed,
				kind: .generatedOnlyInitializerTakesDefault,
				details: "\(findings.joined(separator: "\n"))\n\(description):\n\(files.keys.sorted().map { "// \($0)\n\(files[$0, default: ""])" }.joined(separator: "\n"))",
			)
		}
		return nil
	}

	/// How many initializers only generated code calls the oracle judges in this graph's generated code, in one module
	/// and in each split of it.
	var generatedOnlyInitializerCount: Int {
		judgedGeneratedFiles.reduce(0) { $0 + GraphFuzzerGeneratedOnlyInitializerDefaults.initializerCount(in: $1.files) }
	}
}
