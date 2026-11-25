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
import Testing
@testable import SafeDICore

struct InstantiableCodingTests {
	@Test
	func decode_readsBackWhatEncodeWrote_whenDeclarationsSetRarelySetFields() throws {
		let instantiables = walkedInstantiables(of: Self.declarationsSettingRarelySetFields)

		let decoded = try JSONDecoder().decode([Instantiable].self, from: JSONEncoder().encode(instantiables))

		#expect(decoded == instantiables)
		#expect(decoded.map(\.customMockName) == ["fake", nil, nil])
		#expect(decoded.map { $0.mockGenerationArgumentRange != nil } == [true, false, false])
		#expect(decoded.map { $0.enclosingExtensionAccess?.level } == [nil, nil, .public])
	}

	@Test
	func encode_writesEachRarelySetFieldUnderItsOwnName_whenDeclarationSetsIt() throws {
		let instantiable = try #require(walkedInstantiables(of: Self.declarationsSettingRarelySetFields).first)

		let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(instantiable)) as? [String: Any])

		#expect(object.keys.sorted() == [
			"access", "conformanceListNamesOtherTypes", "conformanceListNamesSendable", "customMockName", "declarationLocation", "declarationType", "dependencies",
			"dependencyLabelsInUnselectedClauses", "dependencyLabelsInsideConditionalBlocks", "enclosingTypeAccess",
			"generateMock", "generatedInitializerAttributes", "generatesDependencyTree", "initializer", "instantiableTypes",
			"isInsideCompilerDecidedBlock", "isRoot", "mockAttributes", "mockDeclarationAccess", "mockDeclarationLocation",
			"mockGenerationArgumentRange", "mockInitializer", "mockOnly", "mockReturnType", "otherInitializers",
		])
	}

	@Test
	func decode_readsBackSuppliedAttributes_whenDeclarationAdoptedModuleDefaultIsolation() throws {
		let instantiable = try #require(walkedInstantiables(of: Self.declarationsSettingRarelySetFields).dropFirst().first).adoptingModuleDefaultIsolation(.mainActor)

		let encoded = try JSONEncoder().encode(instantiable)
		let decoded = try JSONDecoder().decode(Instantiable.self, from: encoded)
		let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

		#expect(decoded == instantiable)
		#expect(decoded.usesModuleDefaultIsolation)
		#expect(decoded.generatedInitializerAttributes == "@MainActor")
		#expect(decoded.mockAttributes == "@MainActor")
		#expect(object["usesModuleDefaultIsolation"] as? Bool == true)
	}

	@Test
	func adoptingModuleDefaultIsolation_keepsDeclaration_whenDeclarationSpellsAttributeText() throws {
		let instantiable = try #require(walkedInstantiables(of: """
		@Instantiable(mockAttributes: "nonisolated")
		public struct Formatter: Instantiable {
		    public init() {}
		}
		""").first)

		let adopted = instantiable.adoptingModuleDefaultIsolation(.mainActor)

		#expect(adopted == instantiable)
		#expect(!adopted.usesModuleDefaultIsolation)
		#expect(adopted.generatedInitializerAttributes == "")
		#expect(adopted.mockAttributes == "nonisolated")
	}

	@Test
	func withoutHandWrittenMock_equalsDeclarationThatNeverHadOne_whenMockProviderWasMergedIn() throws {
		let instantiables = walkedInstantiables(of: Self.declarationsSettingRarelySetFields)
		let plain = try #require(instantiables.dropFirst().first)
		let mockProvider = try #require(instantiables.first)

		let merged = plain.mergedWithMockProvider(mockProvider)

		#expect(merged.customMockName == "fake")
		#expect(merged != plain)
		#expect(merged.withoutHandWrittenMock == plain)
		#expect(merged.withoutHandWrittenMock.hashValue == plain.hashValue)
	}

	// MARK: Private

	private static let declarationsSettingRarelySetFields = """
	@Instantiable(generateMock: true, customMockName: "fake")
	public struct Screen: Instantiable, Sendable, Hashable {
	    public init() {}
	    public static func fake() -> Screen { Screen() }
	}
	@Instantiable
	public struct Plain: Instantiable {
	    public init() {}
	}
	public extension Outer {
	    @Instantiable
	    struct Inner: Instantiable {
	        init() {}
	    }
	}
	"""

	private func walkedInstantiables(of source: String) -> [Instantiable] {
		let syntaxTree = Parser.parse(source: source)
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		return fileVisitor.instantiables
	}
}
