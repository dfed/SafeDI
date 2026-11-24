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

import Foundation
import SwiftParser
import SwiftSyntax

/// Whether a mock declares one builder function per class of the places its tree builds, read from the generated code
/// alone, whatever engine laid the body out. Within one generated `mock()` or `__safeDI_mock()` body, two local
/// functions whose declarations are the same text once each is read without what tells one place from another – an
/// override path (`safeDIOverrides.a.b.c`), a member chain of the configuration a function is handed, and the names of
/// the builder functions themselves – build one class of places twice: a body that shares one function per class has
/// none, and a body with one function per place has one for each place a type is built at.
///
/// The oracle judges a mock's layout, not its values, which the base value comparison judges
/// (`GraphFuzzerBaseValueComparison`). Until every mock shares, it fails nearly every graph whose mock builds a type at two
/// places, so it judges only a run that asks for it (`isRequested`, which the long run reads from
/// `SAFEDI_GRAPH_FUZZER_MOCK_SHARING_ORACLE`).
enum GraphFuzzerMockSharedBuilders {
	/// A class of places that a mock builds with more than one local function.
	struct Repetition: Equatable, CustomStringConvertible {
		let fileName: String
		/// The mock function's name, `mock` or `__safeDI_mock`.
		let mockName: String
		/// The local functions whose normalized declarations are the same, in source order.
		let functionNames: [String]

		var description: String {
			"`\(mockName)` in `\(fileName)` declares \(functionNames.count) functions of one class: \(functionNames.map { "`\($0)`" }.joined(separator: ", "))"
		}
	}

	/// Whether a run asks for the oracle.
	static var isRequested: Bool {
		ProcessInfo.processInfo.environment["SAFEDI_GRAPH_FUZZER_MOCK_SHARING_ORACLE"] == "1"
	}

	/// Every class of places a mock of `generatedFiles` builds with more than one local function, in file name order and
	/// then in the order of each class's first function.
	static func repetitions(in generatedFiles: [String: String]) -> [Repetition] {
		var repetitions = [Repetition]()
		for fileName in generatedFiles.keys.sorted() {
			let collector = MockCollector(viewMode: .sourceAccurate)
			collector.walk(Parser.parse(source: generatedFiles[fileName, default: ""]))
			for mock in collector.mocks {
				var functionNamesByText = [String: [String]]()
				var textsInOrder = [String]()
				for function in mock.localFunctions {
					let text = normalized(function)
					if functionNamesByText[text] == nil {
						textsInOrder.append(text)
					}
					functionNamesByText[text, default: []].append(function.name.text)
				}
				for text in textsInOrder {
					guard let names = functionNamesByText[text], names.count > 1 else { continue }
					repetitions.append(Repetition(fileName: fileName, mockName: mock.name, functionNames: names))
				}
			}
		}
		return repetitions
	}

	/// The repetitions in what a built `SafeDITool`, `tool`, generates for `fixture`, run as the base comparison runs it
	/// (`GraphFuzzerBaseComparison.Layout`), or `nil` where the tool rejects the graph: so the oracle judges a tool built
	/// from another commit, such as a head whose engine this checkout does not hold.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func repetitions(generatedBy tool: URL, for fixture: GraphFuzzerFixture) async throws -> [Repetition]? {
		let directory = TestTemporaryDirectory.uniquePath(prefix: "safedi-mock-sharing-")
		defer { try? FileManager.default.removeItem(at: directory) }
		let layout = try GraphFuzzerBaseComparison.Layout(writing: fixture, into: directory)
		let record = try await layout.record(running: tool)
		guard layout.accepts(record) else { return nil }
		return repetitions(in: layout.generatedFiles(of: record))
	}

	/// `function`'s declaration without what tells one place of a class from another: its own name and every name of a
	/// builder function (`__safeDI_…`), every override path read from `safeDIOverrides` or a parameter, and each
	/// parameter's name. Whitespace is collapsed, so indentation, which nesting decides, tells nothing apart.
	static func normalized(_ function: FunctionDeclSyntax) -> String {
		var text = function.trimmedDescription
		let ownName = function.name.text
		var names = Set([ownName])
		for parameter in function.signature.parameterClause.parameters {
			names.insert((parameter.secondName ?? parameter.firstName).text)
		}
		for name in names.sorted() where name != "_" {
			text = text.replacingOccurrences(of: #"\b\#(NSRegularExpression.escapedPattern(for: name))\b"#, with: "<name>", options: .regularExpression)
		}
		return text
			.replacingOccurrences(of: #"\b__safeDI_\w+"#, with: "<function>", options: .regularExpression)
			.replacingOccurrences(of: #"\bsafeDIOverrides(\.\w+)*"#, with: "<override>", options: .regularExpression)
			.replacingOccurrences(of: #"<name>(\.\w+)+"#, with: "<name>", options: .regularExpression)
			.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
	}

	// MARK: Private

	private struct Mock {
		let name: String
		let localFunctions: [FunctionDeclSyntax]
	}

	/// Each `mock()` or `__safeDI_mock()` a file declares, with every function declared anywhere in its body.
	private final class MockCollector: SyntaxVisitor {
		private(set) var mocks = [Mock]()

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			guard node.name.text == "mock" || node.name.text == "__safeDI_mock", let body = node.body else { return .visitChildren }
			let collector = LocalFunctionCollector(viewMode: .sourceAccurate)
			collector.walk(body)
			mocks.append(Mock(name: node.name.text, localFunctions: collector.functions))
			return .skipChildren
		}
	}

	private final class LocalFunctionCollector: SyntaxVisitor {
		private(set) var functions = [FunctionDeclSyntax]()

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			functions.append(node)
			return .visitChildren
		}
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph a mock of which builds one class of places with two local functions, or `nil`, judged only
	/// where `isJudged`: by default when the run asks for the oracle (`GraphFuzzerMockSharedBuilders.isRequested`).
	func mockSharingFailure(isJudged: Bool = GraphFuzzerMockSharedBuilders.isRequested) -> GraphFuzzerFailure? {
		guard isJudged else { return nil }
		let repetitions = GraphFuzzerMockSharedBuilders.repetitions(in: generatedFiles)
		guard !repetitions.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .mockSharedBodyRepeatsClass,
			details: "\(repetitions.map(\.description).joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)",
		)
	}
}
