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

import Testing
@testable import SafeDICore

struct GeneratedImportAccessTests {
	@Test
	func dependencyFileModuleNames_answersWithDeclaringModulesFileAlone_whenTwoModulesRecordOneRelativePath() {
		// Cell 23c: `Core` and `Session` each record a file at `Sources/Vault.swift`, as two projects of a Tuist workspace
		// do; `Core`'s imports `Kit` `public`, `Session`'s spells no level. A declaration of `Session`'s file is answered by
		// `Session`'s imports alone, never by `Core`'s file at the same path.
		let writtenLevels = GeneratedImportAccess.WrittenLevels(
			ownImportStatements: [ImportStatement(moduleName: "Kit", accessLevel: .internal, sourceFilePath: "App/Root.swift")],
			importStatements: [
				(moduleName: "Core", importStatements: [ImportStatement(moduleName: "Kit", accessLevel: .public, sourceFilePath: "Sources/Vault.swift")]),
				(moduleName: "Session", importStatements: [ImportStatement(moduleName: "Kit", sourceFilePath: "Sources/Vault.swift")]),
			],
			isOwnFile: { $0 == "App/Root.swift" },
		)

		#expect(writtenLevels.dependencyFileModuleNames(ofFileAt: "Sources/Vault.swift", declaredIn: "Core") == ["Kit"])
		#expect(writtenLevels.dependencyFileModuleNames(ofFileAt: "Sources/Vault.swift", declaredIn: "Session") == nil)
		// A declaration whose module SafeDI does not know is answered by any file at its path.
		#expect(writtenLevels.dependencyFileModuleNames(ofFileAt: "Sources/Vault.swift", declaredIn: nil) == ["Kit"])
	}
}
