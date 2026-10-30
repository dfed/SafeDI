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
import SafeDICore
import Testing
@testable import SafeDITool

/// The declaration `resolveSafeDIFulfilledTypes` keeps for each type once a `mockOnly` declaration's mock is merged
/// into the production declaration. Files are walked in path order, so the names of the fixture files decide which
/// of the two merge branches runs: the one that meets the production declaration first, or the `mockOnly` one.
struct SafeDIToolInstantiableResolutionTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func resolveSafeDIFulfilledTypes_keepsProductionAccessAndTakesMockDeclarationAccess_whenProductionDeclarationIsMetFirst() async throws {
		let resolved = try await resolvedInstantiables(fromFilesNamed: [
			"AService.swift": Self.productionDeclaration,
			"BServiceMock.swift": Self.mockOnlyExtension,
		])

		let service = try #require(resolved.instantiables[.simple(name: "Service")])
		#expect(service.access == AccessDeclaration(
			level: .public,
			modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
			declarationStartLocation: Dependency.DeclarationLocation(filePath: resolved.filePaths["AService.swift"]!, line: 2, column: 1),
		))
		#expect(service.mockDeclarationAccess == AccessDeclaration(
			level: .package,
			modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 8),
			declarationStartLocation: Dependency.DeclarationLocation(filePath: resolved.filePaths["BServiceMock.swift"]!, line: 2, column: 1),
		))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func resolveSafeDIFulfilledTypes_keepsProductionAccessAndTakesMockDeclarationAccess_whenMockOnlyExtensionIsMetFirst() async throws {
		let resolved = try await resolvedInstantiables(fromFilesNamed: [
			"AServiceMock.swift": Self.mockOnlyExtension,
			"BService.swift": Self.productionDeclaration,
		])

		let service = try #require(resolved.instantiables[.simple(name: "Service")])
		#expect(service.access == AccessDeclaration(
			level: .public,
			modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
			declarationStartLocation: Dependency.DeclarationLocation(filePath: resolved.filePaths["BService.swift"]!, line: 2, column: 1),
		))
		#expect(service.mockDeclarationAccess == AccessDeclaration(
			level: .package,
			modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 8),
			declarationStartLocation: Dependency.DeclarationLocation(filePath: resolved.filePaths["AServiceMock.swift"]!, line: 2, column: 1),
		))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let productionDeclaration = """
	@Instantiable
	public struct Service: Instantiable {
	    public init() {}
	}
	"""

	private static let mockOnlyExtension = """
	@Instantiable(mockOnly: true)
	package extension Service {
	    static func mock() -> Service {
	        Service()
	    }
	}
	"""

	/// Writes each file of `contentByFileName` into a new directory, parses them as one module as `generate` does, and
	/// resolves the type each declaration fulfills.
	/// - Returns: The resolved declarations, and the path each file was parsed at, keyed by file name.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func resolvedInstantiables(
		fromFilesNamed contentByFileName: [String: String],
	) async throws -> (instantiables: [TypeDescription: Instantiable], filePaths: [String: String]) {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		var filePaths = [String: String]()
		for (fileName, content) in contentByFileName {
			let file = directory.appendingPathComponent(fileName)
			try content.write(to: file, atomically: true, encoding: .utf8)
			filePaths[fileName] = file.path
		}
		let parsed = try await parseModule(
			filePaths: Set(filePaths.values),
			configurationFilePaths: Set(filePaths.values),
			activeCompilationConditions: [],
		)
		return (
			try resolveSafeDIFulfilledTypes(instantiables: normalizingInstantiableTypes(of: parsed.module.moduleInfo.instantiables)),
			filePaths,
		)
	}
}
