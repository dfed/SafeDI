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
import Testing
@testable import SafeDITool

/// A module of a `query` test: the name of its directory and the Swift files it holds. A name with `/` in it
/// nests the directory, for a test of how directories are named.
struct QueryTestModule {
	init(_ name: String, _ swiftFileContent: [String]) {
		self.name = name
		self.swiftFileContent = swiftFileContent
	}

	let name: String
	/// Each file's content. Files are named after the `@Instantiable` type each declares, as
	/// `executeSafeDIToolTest` names its fixtures.
	let swiftFileContent: [String]
}

extension TypeReport {
	/// What the mock needs, or `nil` when the report says why the type has none.
	var mock: Mock? {
		switch mockReport {
		case let .mock(mock):
			mock
		case .none:
			nil
		}
	}
}

/// What `query needs` reported: the first type's report, the whole report, the text and JSON `run()` prints for it,
/// and where the fixtures were written, from which a test spells the paths the report is expected to hold.
struct QueryTestOutput {
	/// The report of the type named first.
	let result: TypeReport
	let report: QueryReport
	let formatted: String
	let json: String
	/// Each module's directory, by module name, which the helper passed to `--include`.
	let moduleDirectories: [String: URL]
	/// Every fixture file written, by module name, in the order of the module's content.
	let moduleFiles: [String: [URL]]

	/// The `--include` argument that named the module, as the helper passed it.
	func paths(of moduleName: String) -> [String] {
		[moduleDirectories[moduleName]!.path]
	}

	/// The path the report spells for the module's fixture at `index`, in the order of the module's content.
	func filePath(of moduleName: String, file index: Int = 0) -> String {
		moduleFiles[moduleName]![index].path
	}

	/// A module of the report, with the path the helper included it by.
	func module(_ name: String, _ declarations: [TypeReport.Declaration]) -> TypeReport.Module {
		TypeReport.Module(name: name, paths: paths(of: name), declarations: declarations)
	}

	/// An `@Instantiable` declaration in the module's fixture at `index`.
	func instantiable(_ typeName: String, in moduleName: String, file index: Int = 0) -> TypeReport.Declaration {
		TypeReport.Declaration(kind: .instantiable, typeName: typeName, filePath: filePath(of: moduleName, file: index), methodName: nil, erasure: nil)
	}

	/// A hand-written mock declared in the module's fixture at `index`.
	func handWrittenMock(_ typeName: String, _ methodName: String, in moduleName: String, file index: Int = 0) -> TypeReport.Declaration {
		TypeReport.Declaration(kind: .handWrittenMock, typeName: typeName, filePath: filePath(of: moduleName, file: index), methodName: methodName, erasure: nil)
	}

	/// An erasure declared on `declaringType` in the module's fixture at `index`.
	func erasure(
		on declaringType: String,
		property: String,
		erasedTypeName: String,
		concreteTypeName: String,
		alsoDeclaredInModules: [String] = [],
		in moduleName: String,
		file index: Int = 0,
	) -> TypeReport.Declaration {
		TypeReport.Declaration(
			kind: .erasure,
			typeName: declaringType,
			filePath: filePath(of: moduleName, file: index),
			methodName: nil,
			erasure: TypeReport.Declaration.Erasure(
				property: property,
				erasedTypeName: erasedTypeName,
				concreteTypeName: concreteTypeName,
				alsoDeclaredInModules: alsoDeclaredInModules,
			),
		)
	}
}

/// Writes each module's fixtures into a directory of its own and runs `query needs` over them, including each
/// module's directory with `--include`.
/// - Parameters:
///   - additionalTypeNames: Type names queried after `typeName`, in one run.
///   - moduleArguments: The `--include` arguments to pass instead of one per module directory, given each
///     module's directory and files.
///   - additionalArguments: Arguments appended to the command line, after the modules.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func executeSafeDIToolQuery(
	typeName: String,
	additionalTypeNames: [String] = [],
	modules: [QueryTestModule],
	activeCompilationConditions: [String] = [],
	moduleArguments: ((_ moduleDirectories: [String: URL], _ moduleFiles: [String: [URL]]) -> [String])? = nil,
	additionalArguments: [String] = [],
	filesToDelete: inout [URL],
) async throws -> QueryTestOutput {
	let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	filesToDelete.append(fixtureDirectory)
	var moduleDirectories = [String: URL]()
	var moduleFiles = [String: [URL]]()
	var arguments = [typeName] + additionalTypeNames
	for module in modules {
		let moduleDirectory = fixtureDirectory.appendingPathComponent(module.name)
		try FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
		moduleDirectories[module.name] = moduleDirectory
		moduleFiles[module.name] = try createSwiftFixtureFiles(from: module.swiftFileContent, in: moduleDirectory)
	}
	if let moduleArguments {
		arguments += moduleArguments(moduleDirectories, moduleFiles)
	} else {
		for module in modules {
			arguments += ["--include", moduleDirectories[module.name]!.path]
		}
	}
	for condition in activeCompilationConditions {
		arguments += ["--active-compilation-conditions", condition]
	}
	arguments += additionalArguments
	// Call `query()` rather than `run()`: `run()` prints errors and rethrows them as an `ExitCode`, which would
	// hide the error from the assertion helpers.
	let report: QueryReport
	do {
		report = try await QueryNeeds.parse(arguments).query()
	} catch {
		throw SafeDIToolQueryTestError(underlyingError: error, moduleFiles: moduleFiles)
	}
	return try QueryTestOutput(
		result: report.types[0],
		report: report,
		formatted: report.formatted,
		json: report.json(),
		moduleDirectories: moduleDirectories,
		moduleFiles: moduleFiles,
	)
}

/// An error thrown by `executeSafeDIToolQuery` when `query` fails. Carries the fixture files exactly as the
/// tool read them so diagnostics that cite those paths can be asserted in full.
struct SafeDIToolQueryTestError: Error, CustomStringConvertible {
	let underlyingError: any Error
	let moduleFiles: [String: [URL]]

	var description: String {
		"\(underlyingError)"
	}
}

/// Asserts that `block` throws an error whose description is `expectedDiagnostics`, and whose JSON error report is
/// `expectedJSON` when given, both given the fixture files `executeSafeDIToolQuery` wrote, by module name.
func assertThrowsQueryError(
	diagnostics expectedDiagnostics: (_ moduleFiles: [String: [URL]]) -> String,
	json expectedJSON: ((_ moduleFiles: [String: [URL]]) -> String)? = nil,
	sourceLocation: SourceLocation = #_sourceLocation,
	block: () async throws -> some Sendable,
) async {
	do {
		_ = try await block()
		Issue.record("Did not throw error!", sourceLocation: sourceLocation)
	} catch let error as SafeDIToolQueryTestError {
		#expect(expectedDiagnostics(error.moduleFiles) == "\(error.underlyingError)", sourceLocation: sourceLocation)
		if let expectedJSON {
			do {
				let json = try QueryErrorReport(error.underlyingError).json()
				#expect(expectedJSON(error.moduleFiles) == json, sourceLocation: sourceLocation)
			} catch {
				Issue.record("Could not encode the error report: \(error)", sourceLocation: sourceLocation)
			}
		}
	} catch {
		Issue.record("Threw an error that does not carry fixture paths: \(error)", sourceLocation: sourceLocation)
	}
}
