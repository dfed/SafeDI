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

/// The file path generated code names in the `#sourceLocation` directive that reports an aliased
/// dependency’s diagnostics at its declaration.
///
/// The compiler collects every file path a module uses – each source file’s path exactly as the
/// compiler was handed it, and each `#sourceLocation` directive’s file – and groups them by file name.
/// It warns at every directive whose file name is shared by more than one distinct path. It compares
/// the strings as written: it does not resolve symbolic links, and a relative path is not the absolute
/// path it names. A directive is therefore emitted only when its path is the only one with its file
/// name. That leaves out a directive whose file shares its name with another file of the module, and a
/// directive for one of the module's own files whenever SafeDITool was told two spellings of its path.
public struct SourceLocationDirectiveFilePaths: Sendable {
	/// - Parameters:
	///   - declarationFilePaths: The files that declare aliased dependencies, as they were parsed.
	///   - moduleFilePaths: The files of the module the code is generated for, as the integration listed them.
	///   - compilerModuleFilePath: The path the compiler is handed for one of `moduleFilePaths`, as the
	///     integration reported it. Called only for a module file that shares a file name with a declaration's.
	///   - compilerFilePath: The path the compiler is handed for the file at a parsed path, as the integration
	///     reported its input paths.
	public init(
		declarationFilePaths: Set<String>,
		moduleFilePaths: Set<String>,
		compilerModuleFilePath: (String) -> String,
		compilerFilePath: (String) -> String,
	) {
		let candidateFilePathByDeclarationFilePath = Dictionary(
			uniqueKeysWithValues: declarationFilePaths.map { ($0, compilerFilePath($0)) },
		)
		let declarationFileNames = Set(candidateFilePathByDeclarationFilePath.values.map(\.fileName))
		// A module file the integration spelled as the candidate does is the same path, so it adds nothing. One
		// it spelled differently might be the file the compiler is handed under the other spelling.
		let pathCountByFileName = Set(candidateFilePathByDeclarationFilePath.values)
			.union(moduleFilePaths.filter { declarationFileNames.contains($0.fileName) }.map(compilerModuleFilePath))
			.reduce(into: [String: Int]()) { partialResult, path in
				partialResult[path.fileName, default: 0] += 1
			}
		directiveFilePathByDeclarationFilePath = candidateFilePathByDeclarationFilePath.filter { _, candidateFilePath in
			pathCountByFileName[candidateFilePath.fileName] == 1
		}
	}

	/// The location a `#sourceLocation` directive names for a declaration at `declarationLocation`, or `nil`
	/// when no directive should be emitted.
	public func directiveLocation(for declarationLocation: Dependency.DeclarationLocation?) -> Dependency.DeclarationLocation? {
		guard let declarationLocation,
		      let directiveFilePath = directiveFilePathByDeclarationFilePath[declarationLocation.filePath]
		else { return nil }
		return Dependency.DeclarationLocation(
			filePath: directiveFilePath,
			line: declarationLocation.line,
			column: declarationLocation.column,
		)
	}

	// MARK: Private

	private let directiveFilePathByDeclarationFilePath: [String: String]
}

extension String {
	fileprivate var fileName: String {
		(self as NSString).lastPathComponent
	}
}
