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

/// What a generated mock's shared functions build: in a `mock()` whose body shares places by class, each class gets one
/// function declared in the mock's body, which takes the place's configuration, or its override closure, as a
/// parameter labeled `safeDIOverrides` or `safeDIOverride`. Two such functions of one `mock()` with the same class – the
/// same parameter types, the same return type, and the same body once the names SafeDI generates are mapped – build one
/// class twice: a place that should have called the first function got a copy of it, so the mock's size grows again
/// with its places, which sharing is for.
///
/// A `mock()` that declares no such function kept today's body, as a root does when one of its places cannot be shared,
/// and is not judged.
enum GraphFuzzerMockSharedBodies {
	/// Each function of a `mock()` in `generatedFiles` that repeats an earlier function's class, as
	/// `` `<function>` in `<Type>.mock()` in `<file>` builds the class of `<earlier function>` again. ``, in file name
	/// order and then in source order.
	static func functionsRepeatingAClass(in generatedFiles: [String: String]) -> [String] {
		sharedBodies(in: generatedFiles).flatMap { body in
			var firstFunctionNameByClass = [FunctionClass: String]()
			var repeats = [String]()
			for function in body.functions {
				if let earlier = firstFunctionNameByClass[function.functionClass] {
					repeats.append("`\(function.name)` in `\(body.mockName)` in `\(body.fileName)` builds the class of `\(earlier)` again.")
				} else {
					firstFunctionNameByClass[function.functionClass] = function.name
				}
			}
			return repeats
		}
	}

	/// How many `mock()` bodies in `generatedFiles` share places, which the oracle judges.
	static func sharedBodyCount(in generatedFiles: [String: String]) -> Int {
		sharedBodies(in: generatedFiles).count
	}

	// MARK: Private

	/// What decides a shared function's class: the types it takes, in order, the type it returns, and its body with
	/// every name SafeDI generates (`__safeDI_…`) replaced by one placeholder, so that a copy under the next name
	/// (`__safeDI_leaf_`) and a copy that calls the copy are of the class it copies.
	private struct FunctionClass: Hashable {
		let parameterTypes: [String]
		let returnType: String
		let normalizedBody: String
	}

	private struct SharedFunction {
		let name: String
		let functionClass: FunctionClass
	}

	private struct SharedBody {
		let fileName: String
		let mockName: String
		let functions: [SharedFunction]
	}

	private static func sharedBodies(in generatedFiles: [String: String]) -> [SharedBody] {
		var bodies = [SharedBody]()
		for fileName in generatedFiles.keys.sorted() {
			let collector = MockCollector(fileName: fileName)
			collector.walk(Parser.parse(source: generatedFiles[fileName, default: ""]))
			bodies += collector.bodies
		}
		return bodies
	}

	/// The labels a shared function gives the parameter that carries its place's configuration or override closure.
	private static let configurationParameterLabels: Set<String> = ["safeDIOverrides", "safeDIOverride"]

	private static func sharedFunction(_ function: FunctionDeclSyntax) -> SharedFunction? {
		let parameters = function.signature.parameterClause.parameters
		guard function.name.text.hasPrefix("__safeDI_"),
		      parameters.contains(where: { configurationParameterLabels.contains($0.firstName.text) }),
		      let body = function.body
		else { return nil }
		return SharedFunction(
			name: function.name.text,
			functionClass: FunctionClass(
				parameterTypes: parameters.map(\.type.trimmedDescription),
				returnType: function.signature.returnClause?.type.trimmedDescription ?? "Void",
				normalizedBody: normalizingGeneratedNames(in: body.statements.trimmedDescription),
			),
		)
	}

	/// `text` with every identifier that begins `__safeDI_` replaced by `__safeDI_`.
	private static func normalizingGeneratedNames(in text: String) -> String {
		var normalized = ""
		var remainder = Substring(text)
		while let range = remainder.range(of: "__safeDI_") {
			normalized += remainder[..<range.lowerBound]
			normalized += "__safeDI_"
			remainder = remainder[range.upperBound...].drop(while: { $0.isLetter || $0.isNumber || $0 == "_" })
		}
		return normalized + remainder
	}

	private final class MockCollector: SyntaxVisitor {
		init(fileName: String) {
			self.fileName = fileName
			super.init(viewMode: .sourceAccurate)
		}

		private(set) var bodies = [SharedBody]()

		override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
			extendedTypeNames.append(node.extendedType.trimmedDescription)
			return .visitChildren
		}

		override func visitPost(_: ExtensionDeclSyntax) {
			extendedTypeNames.removeLast()
		}

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			guard node.name.text == "mock" || node.name.text == "__safeDI_mock", let body = node.body else { return .skipChildren }
			// Only the functions declared in the mock's body itself are shared: R1's placement, depth 1.
			let functions = body.statements.compactMap { item in
				item.item.as(FunctionDeclSyntax.self).flatMap(GraphFuzzerMockSharedBodies.sharedFunction)
			}
			if !functions.isEmpty {
				bodies.append(SharedBody(fileName: fileName, mockName: "\(extendedTypeNames.last ?? "").\(node.name.text)()", functions: functions))
			}
			return .skipChildren
		}

		private let fileName: String
		private var extendedTypeNames = [String]()
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph one of whose generated mocks builds one class in two shared functions, or `nil`.
	var mockSharedBodyFailure: GraphFuzzerFailure? {
		let repeats = GraphFuzzerMockSharedBodies.functionsRepeatingAClass(in: generatedFiles)
		guard !repeats.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .mockSharedBodyRepeatsClass,
			details: "\(repeats.joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)",
		)
	}
}
