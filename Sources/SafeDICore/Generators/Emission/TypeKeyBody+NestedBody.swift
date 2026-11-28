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

extension TypeKeyBody {
	/// The statements, unindented, of a function's body whose one statement is `place`, laid out as a root's body is with
	/// `outerDeclarations` declared before it and its functions placed as a production root's are, in the body itself
	/// where no loop is; `nil` where the layout keeps the path key's body.
	static func statements(ofBodyHolding place: GeneratedCode, outerDeclarations: [Property], namesInScope: Set<String>) -> [GeneratedCode]? {
		guard let statements = statements(
			ofRootBody: [.indented(place, by: rootStatementIndentation)],
			outerDeclarations: outerDeclarations,
			namesInScope: namesInScope,
			// As a production root laid out from node records is (`DependencyTreeGenerator+NodeRecords.swift`).
			laysOutEveryLoop: true,
			declaresLoopMembersAsThePathKeyDoes: true,
		) else { return nil }
		var unindented = [GeneratedCode]()
		for statement in statements {
			// Each statement of a root's body is indented as one (`spelledRootStatements`).
			guard case let .indented(inner, indentation) = statement.node, indentation == rootStatementIndentation else { return nil }
			unindented.append(inner)
		}
		return unindented
	}

	/// The lines of `statements(ofBodyHolding:outerDeclarations:namesInScope:)`. A bridge, until a dispatcher's case holds
	/// an inlined body as code (`ScopeGenerator.FillDispatcher.InlinedFill`), which takes the body's lines.
	static func lines(ofBodyHolding place: GeneratedCode, outerDeclarations: [Property], namesInScope: Set<String>) -> [String]? {
		statements(ofBodyHolding: place, outerDeclarations: outerDeclarations, namesInScope: namesInScope).map { statements in
			GeneratedCodeText.lines(of: GeneratedCode.lines(statements).spelled())
		}
	}
}
