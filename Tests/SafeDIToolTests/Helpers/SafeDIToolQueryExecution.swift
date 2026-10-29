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

/// A module of a `query` test: the name of its directory and the Swift files it holds. A name with `/` in it
/// nests the directory, for a test of how directories are named.
struct QueryTestModule {
	init(_ name: String, _ swiftFileContent: [String], swiftFileContentByFilePath: [String: String] = [:], input: Input = .directory) {
		self.name = name
		self.swiftFileContent = swiftFileContent
		self.swiftFileContentByFilePath = swiftFileContentByFilePath
		self.input = input
	}

	let name: String
	/// Each file's content. Files are named after the `@Instantiable` type each declares, as
	/// `executeSafeDIToolTest` names its fixtures.
	let swiftFileContent: [String]
	/// Each file's content at the path it is given, relative to the module's directory, for a file whose name
	/// matters, as `executeSafeDIToolTest` writes them.
	let swiftFileContentByFilePath: [String: String]
	/// How the module is named to `query needs`.
	let input: Input

	enum Input {
		/// With `--include`, as the module's directory.
		case directory
		/// With `--module-info`, as a module info file written into the module's directory from its Swift files,
		/// parsed as `generate` parses a module's own files. The file is named `<last component of name>.safedi`
		/// unless `fileName` says otherwise. `sourcesOf` names another test module whose Swift files are written
		/// into the file instead of this module's own, for a test of a file in two modules.
		case moduleInfo(fileName: String? = nil, sourcesOf: String? = nil)
	}
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
	/// Each module's directory, by test module name, which the helper passed to `--include` for a directory module.
	let moduleDirectories: [String: URL]
	/// Every fixture file written, by test module name, in the order of the module's content.
	let moduleFiles: [String: [URL]]
	/// Each module info file written, by test module name, which the helper passed to `--module-info`.
	let moduleInfoFiles: [String: URL]

	/// The argument that named the test module, as the helper passed it.
	func paths(of testModuleName: String) -> [String] {
		[moduleInfoFiles[testModuleName]?.path ?? moduleDirectories[testModuleName]!.path]
	}

	/// The path the report spells for the test module's fixture at `index`, in the order of the module's content:
	/// the fixture's path, which a module info file records normalized, as `generate` found it.
	func filePath(of testModuleName: String, file index: Int = 0) -> String {
		let fixture = moduleFiles[testModuleName]![index]
		return if moduleInfoFiles[testModuleName] != nil {
			NormalizedFilePath(fixture.path).path
		} else {
			fixture.path
		}
	}

	/// A module of the report, with the path the helper named it by. `testModuleName` is the test module's name
	/// when the report names the module otherwise, as it does a module info file with a name of its own.
	func module(_ name: String, testModule testModuleName: String? = nil, _ declarations: [TypeReport.Declaration]) -> TypeReport.Module {
		TypeReport.Module(name: name, paths: paths(of: testModuleName ?? name), declarations: declarations)
	}

	/// An `@Instantiable` declaration in the test module's fixture at `index`.
	func instantiable(_ typeName: String, in testModuleName: String, file index: Int = 0) -> TypeReport.Declaration {
		TypeReport.Declaration(kind: .instantiable, typeName: typeName, filePath: filePath(of: testModuleName, file: index), methodName: nil, erasure: nil)
	}

	/// A hand-written mock declared in the test module's fixture at `index`.
	func handWrittenMock(_ typeName: String, _ methodName: String, in testModuleName: String, file index: Int = 0) -> TypeReport.Declaration {
		TypeReport.Declaration(kind: .handWrittenMock, typeName: typeName, filePath: filePath(of: testModuleName, file: index), methodName: methodName, erasure: nil)
	}

	/// An erasure declared on `declaringType` in the test module's fixture at `index`.
	func erasure(
		on declaringType: String,
		property: String,
		erasedTypeName: String,
		concreteTypeName: String,
		alsoDeclaredInModules: [String] = [],
		in testModuleName: String,
		file index: Int = 0,
	) -> TypeReport.Declaration {
		TypeReport.Declaration(
			kind: .erasure,
			typeName: declaringType,
			filePath: filePath(of: testModuleName, file: index),
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

/// Writes each module's fixtures into a directory of its own and runs `query needs` over them, naming each module
/// as its `input` says: a directory with `--include`, or a module info file written from its fixtures with
/// `--module-info`.
/// - Parameters:
///   - additionalTypeNames: Type names queried after `typeName`, in one run.
///   - moduleArguments: The arguments to pass instead of one per module, given each module's directory, files,
///     and module info file.
///   - additionalArguments: Arguments appended to the command line, after the modules.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func executeSafeDIToolQuery(
	typeName: String,
	additionalTypeNames: [String] = [],
	modules: [QueryTestModule],
	activeCompilationConditions: [String] = [],
	moduleArguments: ((_ moduleDirectories: [String: URL], _ moduleFiles: [String: [URL]], _ moduleInfoFiles: [String: URL]) -> [String])? = nil,
	additionalArguments: [String] = [],
	filesToDelete: inout [URL],
) async throws -> QueryTestOutput {
	let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	// Created even for a run that names no module, since the test removes it when it ends.
	try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
	filesToDelete.append(fixtureDirectory)
	var moduleDirectories = [String: URL]()
	var moduleFiles = [String: [URL]]()
	var moduleInfoFiles = [String: URL]()
	var arguments = [typeName] + additionalTypeNames
	for module in modules {
		let moduleDirectory = fixtureDirectory.appendingPathComponent(module.name)
		try FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
		moduleDirectories[module.name] = moduleDirectory
		let contentNamedSwiftFiles = try createSwiftFixtureFiles(from: module.swiftFileContent, in: moduleDirectory)
		moduleFiles[module.name] = try contentNamedSwiftFiles + createSwiftFixtureFiles(
			atFilePaths: module.swiftFileContentByFilePath,
			in: moduleDirectory,
			alongside: contentNamedSwiftFiles,
		)
	}
	// Module info files are written once every module's fixtures exist, since one may be written from another's.
	for module in modules {
		guard case let .moduleInfo(fileName, sourcesOf) = module.input else { continue }
		let fixtures = moduleFiles[sourcesOf ?? module.name]!
		// What `generate` writes with `--module-info-output` for a module whose own files these are, naming each
		// file as `generate --include` finds it.
		let filePaths = Set(fixtures.map { NormalizedFilePath($0.path).path })
		let parsed = try await parseModule(
			filePaths: filePaths,
			configurationFilePaths: filePaths,
			activeCompilationConditions: Set(activeCompilationConditions),
		)
		let moduleInfoFile = moduleDirectories[module.name]!
			.appendingPathComponent(fileName ?? "\((module.name as NSString).lastPathComponent).safedi")
		try parsed.module.moduleInfo.moduleInfoData.write(to: moduleInfoFile)
		moduleInfoFiles[module.name] = moduleInfoFile
	}
	if let moduleArguments {
		arguments += moduleArguments(moduleDirectories, moduleFiles, moduleInfoFiles)
	} else {
		for module in modules {
			switch module.input {
			case .directory:
				arguments += ["--include", moduleDirectories[module.name]!.path]
			case .moduleInfo:
				arguments += ["--module-info", moduleInfoFiles[module.name]!.path]
			}
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
		moduleInfoFiles: moduleInfoFiles,
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
