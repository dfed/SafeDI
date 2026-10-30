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
import Testing
@testable import SafeDICore

struct InstantiableVisitorTests {
	@Test
	func walk_recordsAccessLevelOfEachInitializer_whenInitializersSpellEveryAccessLevel() throws {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		public struct Service: Instantiable {
		    public init(publicArgument: Int) {}
		    package init(packageArgument: Int) {}
		    internal init(internalArgument: Int) {}
		    fileprivate init(fileprivateArgument: Int) {}
		    private init(privateArgument: Int) {}
		}
		""")
		let visitor = try Self.walkedVisitor(of: StructDeclSyntax.self, in: syntaxTree)
		#expect(visitor.initializers.map(\.accessLevel) == [.public, .package, .internal, .fileprivate, .private])
		#expect(visitor.initializers.map(\.accessModifierRange) == [
			Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
			Dependency.SourceRange(startLine: 4, startColumn: 5, endLine: 4, endColumn: 12),
			Dependency.SourceRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 13),
			Dependency.SourceRange(startLine: 6, startColumn: 5, endLine: 6, endColumn: 16),
			Dependency.SourceRange(startLine: 7, startColumn: 5, endLine: 7, endColumn: 12),
		])
		#expect(visitor.initializers.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 5),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 5),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 5),
		])
	}

	@Test
	func walk_recordsInternalAccessLevelWithoutModifierRange_whenInitializerSpellsNoAccessModifier() throws {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		public struct Service: Instantiable {
		    init() {}
		}
		""")
		let visitor = try Self.walkedVisitor(of: StructDeclSyntax.self, in: syntaxTree)
		#expect(visitor.initializers.map(\.accessLevel) == [.internal])
		#expect(visitor.initializers.map(\.accessModifierRange) == [nil])
		#expect(visitor.initializers.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
		])
	}

	@Test
	func walk_recordsInitializerDeclarationStartAtFirstModifierAfterAttributes_whenAccessModifierFollowsAnotherModifier() throws {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		public final class Service: Instantiable {
		    @MainActor convenience public init() {}
		}
		""")
		let visitor = try Self.walkedVisitor(of: ClassDeclSyntax.self, in: syntaxTree)
		#expect(visitor.initializers.map(\.accessLevel) == [.public])
		#expect(visitor.initializers.map(\.accessModifierRange) == [
			Dependency.SourceRange(startLine: 3, startColumn: 28, endLine: 3, endColumn: 34),
		])
		#expect(visitor.initializers.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 16),
		])
	}

	// MARK: Private

	/// A visitor that walked the first declaration in `syntaxTree`, a `Declaration`, as `FileVisitor` walks one.
	private static func walkedVisitor<Declaration: ConcreteDeclSyntaxProtocol>(
		of _: Declaration.Type,
		in syntaxTree: SourceFileSyntax,
	) throws -> InstantiableVisitor {
		let declaration = try #require(syntaxTree.statements.first.flatMap { Syntax($0.item).as(Declaration.self) })
		let visitor = InstantiableVisitor(
			declarationType: .concreteDecl,
			sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree),
		)
		visitor.walk(declaration)
		return visitor
	}
}
