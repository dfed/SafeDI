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

import SafeDICore
import SwiftParser
import SwiftSyntax
import Testing
@testable import SafeDIToolLibrary

/// The bytes SafeDITool's scan cache and `.safedi` files hold for an instantiable, pinned so that a change to how
/// `Instantiable` stores its fields cannot change what a file holds.
struct SafeDIToolInstantiableBytesTests {
	@Test
	func binaryWriter_writesPinnedBytes_whenDeclarationsSetEveryRarelySetField() {
		let instantiables = declaredInstantiables()
		var writer = BinaryWriter()
		writer.write(instantiables)

		#expect(hexadecimal(writer.encoded) == Self.expectedBytes)
	}

	@Test
	func binaryWriter_writesDeclarationsSettingEveryRarelySetField_whenFixtureIsWalked() {
		let instantiables = declaredInstantiables()

		#expect(instantiables.map(\.customMockName) == ["fake", nil, nil])
		#expect(instantiables.map { $0.mockInitializer != nil } == [true, false, false])
		#expect(instantiables.map { $0.mockReturnType != nil } == [true, false, false])
		#expect(instantiables.map { $0.mockDeclarationLocation != nil } == [true, false, false])
		#expect(instantiables.map { $0.mockDeclarationAccess != nil } == [true, false, false])
		#expect(instantiables.map(\.mockDeclarationModuleName) == ["Feature", nil, nil])
		#expect(instantiables.map(\.mockDeclarationPackageName) == ["Bench", nil, nil])
		#expect(instantiables.map { $0.mockGenerationArgumentRange != nil } == [true, false, false])
		#expect(instantiables.map { $0.enclosingExtensionAccess?.level } == [nil, nil, .public])
	}

	@Test
	func binaryLayout_writesEachFieldOfTheBoxButDeclaredName_whenInstantiableStoresRarelySetFields() throws {
		// `Instantiable` keeps its rarely set fields in a box its layout lists as unwritten, and writes each of them
		// under its own name, so a field added to the box without being listed in the layout fails here.
		let screen = try #require(declaredInstantiables().first)
		let box = try #require(Mirror(reflecting: screen).children.first { $0.label == "rarelySetFields" }?.value)
		let boxedValue = try #require(Mirror(reflecting: box).children.first?.value)
		let fields = try #require(Mirror(reflecting: boxedValue).children.first { $0.label == "fields" }?.value)
		guard case let .structure(writtenFields, _) = Instantiable.binaryLayout else {
			Issue.record("Instantiable is a struct, but its layout lists cases")
			return
		}

		#expect(Mirror(reflecting: fields).children.compactMap(\.label).filter { label in
			!writtenFields.contains { $0.name == label }
		} == ["declaredName"])
	}

	// MARK: Private

	/// What a file holds for the fixture's declarations. Bytes that change here change every scan cache and `.safedi`
	/// file, which `BinaryFile.schemaFingerprint` must then change with.
	private static let expectedBytes = """
	0b0653637265656e0d466978747572652e737769667405706c61696e05506c61696e00072e696e697428290466616b650746656174757265
	0542656e636805496e6e6572054f7574657203e4ff0701000000070101060a060a06160100020103000000010f02010300000000010c0a0c
	2e0c380c3c0c460c0a0c240207010104020402040e00040401000701010e0a0e0a0e160102020103000501000006010e0a07010104020402
	040e0708010202023a0242070801000084a00701030000070101160a160a1616000000000207010114021402140e00040400011202070801
	00008ca0070209010a000000020301201200000000020203011e0a000f01011a021a021a0e040400011c0a0708010000
	""".replacingOccurrences(of: "\n", with: "")

	private func declaredInstantiables() -> [Instantiable] {
		let source = """
		@Instantiable(generateMock: true, customMockName: "fake")
		public struct Screen: Instantiable {
		    public init(plain: Plain) {
		        self.plain = plain
		    }
		    @Instantiated let plain: Plain
		    public static func fake(plain: Plain = .init()) -> Screen { Screen(plain: plain) }
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
		let syntaxTree = Parser.parse(source: source)
		let fileVisitor = FileVisitor(
			sourceLocationConverter: SourceLocationConverter(fileName: "Fixture.swift", tree: syntaxTree),
			sourceFilePath: "Fixture.swift",
		)
		fileVisitor.walk(syntaxTree)
		return fileVisitor.instantiables.map {
			$0.declared(in: DeclaringModule(moduleName: "Feature", packageName: "Bench"))
		}
	}

	private func hexadecimal(_ bytes: [UInt8]) -> String {
		bytes.map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
	}
}
