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

/// Whether a mock declares one builder function per class of the places its tree builds, read from the generated code,
/// judged against what the type key's layout says it did with each mock root. Within one generated `mock()` or
/// `__safeDI_mock()` body, two local functions whose declarations are the same text once each is read without what tells
/// one place from another – an override path (`safeDIOverrides.a.b.c`), a member chain of the configuration a function is
/// handed, and the names of the builder functions themselves – build one class of places twice: a body that shares one
/// function per class has none, and a body with one function per place has one for each place a type is built at.
///
/// The layout reports each internal mock root it is asked to lay out (`MockLowering.typeKeyLayoutObserver`): `laidOut`,
/// or the fallback that kept the root's walk body. Each root with a repetition is counted once under its outcome's name,
/// and those counts are pinned per corpus, so a share the layout newly loses moves a pin rather than hiding among known
/// seeds. A repetition is extra text, not a wrong value (production's own layout repeats a function in cycles), so a laid-out
/// root that repeats a class is counted under `laidOut` rather than failed; the values are the base value comparison's to
/// judge. A root the layout reported nothing about (a public mock, whose sharing is another engine's part) is counted as
/// `unreported`.
///
/// The judge reads a mock's layout, not its values, which the base value comparison judges
/// (`GraphFuzzerBaseValueComparison`).
enum GraphFuzzerMockSharedBuilders {
	/// A class of places that a mock builds with more than one local function.
	struct Repetition: Equatable, CustomStringConvertible {
		let fileName: String
		/// The type the mock's extension extends, as the layout reports it (`MockLowering.typeKeyLayoutObserver`).
		let mockedTypeName: String
		/// The mock function's name, `mock` or `__safeDI_mock`.
		let mockName: String
		/// The local functions whose normalized declarations are the same, in source order.
		let functionNames: [String]

		var description: String {
			"`\(mockName)` of `\(mockedTypeName)` in `\(fileName)` declares \(functionNames.count) functions of one class: \(functionNames.map { "`\($0)`" }.joined(separator: ", "))"
		}
	}

	/// The name an outcome is counted under: `laidOut`, or a fallback's kind, with an unrecorded place's reason (`unrecorded:publicMockCall`),
	/// without what names one place or label (`readUnresolved:token` is `readUnresolved`); `unreported` where the layout
	/// reported nothing about the root.
	static func fallbackName(of outcome: String?) -> String {
		guard let outcome else { return "unreported" }
		let parts = outcome.split(separator: ":", omittingEmptySubsequences: false)
		if parts.first == "unrecorded", parts.count > 1 {
			return "unrecorded:\(parts[1])"
		} else {
			return String(parts.first ?? "")
		}
	}

	/// For each outcome's name (`fallbackName(of:)`, `laidOut` among them), the mock roots with one of `repetitions`: a root
	/// counts once however many classes it repeats.
	static func repeatingRootCounts(of repetitions: [Repetition], outcomesByMockedType outcomes: [String: String]) -> [String: Int] {
		var counts = [String: Int]()
		var countedRoots = Set<String>()
		for repetition in repetitions where countedRoots.insert("\(repetition.fileName)\t\(repetition.mockedTypeName)\t\(repetition.mockName)").inserted {
			counts[fallbackName(of: outcomes[repetition.mockedTypeName]), default: 0] += 1
		}
		return counts
	}

	/// Every class of places a mock of `generatedFiles` builds with more than one local function, in file name order and
	/// then in the order of each class's first function.
	static func repetitions(in generatedFiles: [String: String]) -> [Repetition] {
		var repetitions = [Repetition]()
		for fileName in generatedFiles.keys.sorted() {
			let collector = MockCollector(viewMode: .sourceAccurate)
			collector.walk(Parser.parse(source: generatedFiles[fileName, default: ""]))
			for mock in collector.mocks {
				let classes = classes(of: mock.localFunctions)
				var functionNamesByClass = [Int: [String]]()
				var classesInOrder = [Int]()
				for (function, functionClass) in zip(mock.localFunctions, classes) {
					if functionNamesByClass[functionClass] == nil {
						classesInOrder.append(functionClass)
					}
					functionNamesByClass[functionClass, default: []].append(function.declaration.name.text)
				}
				for functionClass in classesInOrder {
					guard let names = functionNamesByClass[functionClass], names.count > 1 else { continue }
					repetitions.append(Repetition(fileName: fileName, mockedTypeName: mock.mockedTypeName, mockName: mock.name, functionNames: names))
				}
			}
		}
		return repetitions
	}

	/// The class of each of `functions`: two functions are of one class when their declarations are the same text once
	/// read without what tells places apart (`normalized(_:)`) and once each builder function they call is read as its own
	/// class, so that two functions that build one type with builder functions of other classes beneath are two classes.
	/// A call names the function its name declares nearest: one the caller declares itself, else one an enclosing body
	/// declares. The classes are refined until they stop splitting.
	static func classes(of functions: [LocalFunction]) -> [Int] {
		let texts = functions.map { normalized($0.declaration, keepingBuilderFunctionNames: true) }
		var classes = denseClasses(of: functions.map { normalized($0.declaration) })
		for _ in functions.indices {
			let keys = functions.indices.map { index in
				var key = texts[index]
				for name in referencedBuilderFunctionNames(in: key).sorted() {
					let replacement = calledFunctionIndex(named: name, from: index, in: functions).map { "<class \(classes[$0])>" } ?? "<function>"
					key = key.replacingOccurrences(of: #"\b\#(name)\b"#, with: replacement, options: .regularExpression)
				}
				return key
			}
			let refined = denseClasses(of: keys)
			guard Set(refined).count > Set(classes).count else { break }
			classes = refined
		}
		return classes
	}

	/// `function`'s declaration without what tells one place of a class from another: its own name and every name of a
	/// builder function (`__safeDI_…`), every override path read from `safeDIOverrides` or a parameter, and each
	/// parameter's name. Whitespace is collapsed, so indentation, which nesting decides, tells nothing apart.
	static func normalized(_ function: FunctionDeclSyntax, keepingBuilderFunctionNames: Bool = false) -> String {
		var text = function.trimmedDescription
		let ownName = function.name.text
		var names = Set([ownName])
		for parameter in function.signature.parameterClause.parameters {
			names.insert((parameter.secondName ?? parameter.firstName).text)
		}
		for name in names.sorted() where name != "_" {
			text = text.replacingOccurrences(of: #"\b\#(NSRegularExpression.escapedPattern(for: name))\b"#, with: "<name>", options: .regularExpression)
		}
		if !keepingBuilderFunctionNames {
			text = text.replacingOccurrences(of: #"\b__safeDI_\w+"#, with: "<function>", options: .regularExpression)
		}
		return text
			.replacingOccurrences(of: #"\bsafeDIOverrides(\.\w+)*"#, with: "<override>", options: .regularExpression)
			.replacingOccurrences(of: #"<name>(\.\w+)+"#, with: "<name>", options: .regularExpression)
			.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
	}

	/// A function declared in a mock's body, with the index of the local function whose body declares it, `nil` for the
	/// mock's own body.
	struct LocalFunction {
		let declaration: FunctionDeclSyntax
		let parentIndex: Int?
	}

	// MARK: Private

	private struct Mock {
		let mockedTypeName: String
		let name: String
		let localFunctions: [LocalFunction]
	}

	/// The index of each text's class, numbered in order of first appearance.
	private static func denseClasses(of texts: [String]) -> [Int] {
		var classByText = [String: Int]()
		return texts.map { text in
			if let existing = classByText[text] {
				return existing
			} else {
				classByText[text] = classByText.count
				return classByText.count - 1
			}
		}
	}

	private static let builderFunctionNameExpression = try! NSRegularExpression(pattern: #"\b__safeDI_\w+"#)

	private static func referencedBuilderFunctionNames(in text: String) -> Set<String> {
		let range = NSRange(text.startIndex..., in: text)
		return Set(builderFunctionNameExpression.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } })
	}

	/// The function `name` calls from the function at `index`: one that function declares, else the nearest one an
	/// enclosing body declares, or `nil` where none is a local function (a generated type's member, such as
	/// `__safeDI_mock`).
	private static func calledFunctionIndex(named name: String, from index: Int, in functions: [LocalFunction]) -> Int? {
		var scope: Int? = index
		while true {
			if let declared = functions.indices.first(where: { functions[$0].parentIndex == scope && functions[$0].declaration.name.text == name }) {
				return declared
			}
			guard let current = scope else { return nil }
			scope = functions[current].parentIndex
		}
	}

	/// Each `mock()` or `__safeDI_mock()` a file declares, with the type its extension extends and every function declared
	/// anywhere in its body.
	private final class MockCollector: SyntaxVisitor {
		private(set) var mocks = [Mock]()
		private var extendedTypeNames = [String]()

		override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
			extendedTypeNames.append(node.extendedType.trimmedDescription)
			return .visitChildren
		}

		override func visitPost(_: ExtensionDeclSyntax) {
			extendedTypeNames.removeLast()
		}

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			guard node.name.text == "mock" || node.name.text == "__safeDI_mock", let body = node.body else { return .visitChildren }
			let collector = LocalFunctionCollector(viewMode: .sourceAccurate)
			collector.walk(body)
			mocks.append(Mock(mockedTypeName: extendedTypeNames.last ?? "", name: node.name.text, localFunctions: collector.functions))
			return .skipChildren
		}
	}

	private final class LocalFunctionCollector: SyntaxVisitor {
		private(set) var functions = [LocalFunction]()
		private var enclosingIndices = [Int]()

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			functions.append(LocalFunction(declaration: node, parentIndex: enclosingIndices.last))
			enclosingIndices.append(functions.count - 1)
			return .visitChildren
		}

		override func visitPost(_: FunctionDeclSyntax) {
			enclosingIndices.removeLast()
		}
	}
}
