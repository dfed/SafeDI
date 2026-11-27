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
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// `--module-info-positions-in-own-file`, as the Bazel rule runs it: `generate` per module, every module beneath as a
/// transitive input, and the unused-inputs list.
struct SafeDIToolModulePositionsTests: ~Copyable {
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
	mutating func generate_listsDependencysPositionsFileUnused_whenRunReportsNothingInDependency() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Dep.swift": Self.dependency])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingDependency])
		_ = try await fixture.generate(module: "Core")

		let output = try await fixture.generate(module: "App", dependencies: ["Core"])

		#expect(!output.readPositionsFilesInSecondRun)
		#expect(try String(contentsOf: fixture.unusedInputsList(of: "App"), encoding: .utf8) == """
		\(fixture.moduleInfoPath(of: "Core"))positions

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warnsAsOverWholeFilesInSecondRun_whenWarningIsLocatedInDependency() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Owner.swift": Self.ownerReadingLazyInstance])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingOwner])
		_ = try await fixture.generate(module: "Core")

		let output = try await fixture.generate(module: "App", dependencies: ["Core"])

		#expect(output.readPositionsFilesInSecondRun)
		#expect(output.warnings.map(\.formatted) == [
			"\(fixture.sourcePath(module: "Core", file: "Owner.swift")):3:5: warning: @Instantiated property `session: LazilyInstantiated<Session>` is instantiated whenever `Owner` is created: `Reader` is created with `Owner` and receives the instance as `session: Session`. To instantiate it lazily, receive `session: LazilyInstantiated<Session>` on `Reader`.",
		])
		#expect(try String(contentsOf: fixture.unusedInputsList(of: "App"), encoding: .utf8) == "")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_runsOnce_whenWarningIsLocatedInOwnModule() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Dep.swift": Self.dependency])
		try fixture.write(module: "App", files: ["Owner.swift": Self.ownerReadingLazyInstance, "Root.swift": Self.rootInstantiatingOwnerAndDependency])
		_ = try await fixture.generate(module: "Core")

		let output = try await fixture.generate(module: "App", dependencies: ["Core"])

		#expect(!output.readPositionsFilesInSecondRun)
		#expect(output.warnings.map(\.formatted) == [
			"\(fixture.sourcePath(module: "App", file: "Owner.swift")):3:5: warning: @Instantiated property `session: LazilyInstantiated<Session>` is instantiated whenever `Owner` is created: `Reader` is created with `Owner` and receives the instance as `session: Session`. To instantiate it lazily, receive `session: LazilyInstantiated<Session>` on `Reader`.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsLocatedError_whenErrorIsLocatedInDependency() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingChild])
		_ = try await fixture.generate(module: "Core")

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Child.swift")):3:5: error: @Received property `missing: Missing` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let missing: Missing` on `Root` or on another type in the chain to fix.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithoutPositionAndPairingError_whenPositionsFileIsMissing() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingChild])
		_ = try await fixture.generate(module: "Core")
		try FileManager.default.removeItem(atPath: fixture.moduleInfoPath(of: "Core") + "positions")

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Child.swift")): error: @Received property `missing: Missing` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let missing: Missing` on `Root` or on another type in the chain to fix.
			error: SafeDI could not read the positions of the module info file at \(fixture.moduleInfoPath(of: "Core")) from \(fixture.moduleInfoPath(of: "Core"))positions: no positions file exists at that path. The lines and columns of that module’s declarations are left out above. Build the module that writes both files again, and give this module both.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithoutPositionAndPairingError_whenPositionsFileBelongsToAnotherModuleInfoFile() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingChild])
		_ = try await fixture.generate(module: "Core")
		let stalePositions = try Data(contentsOf: (fixture.moduleInfoPath(of: "Core") + "positions").asFileURL)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing, "Other.swift": Self.dependency])
		_ = try await fixture.generate(module: "Core")
		try stalePositions.write(to: (fixture.moduleInfoPath(of: "Core") + "positions").asFileURL)

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Child.swift")): error: @Received property `missing: Missing` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let missing: Missing` on `Root` or on another type in the chain to fix.
			error: SafeDI could not read the positions of the module info file at \(fixture.moduleInfoPath(of: "Core")) from \(fixture.moduleInfoPath(of: "Core"))positions: the positions file was written beside another version of the module info file. The lines and columns of that module’s declarations are left out above. Build the module that writes both files again, and give this module both.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsPairingErrorAfterWarning_whenWarningIsLocatedInDependencyWhosePositionsFileIsMissing() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Owner.swift": Self.ownerReadingLazyInstance])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingOwner])
		_ = try await fixture.generate(module: "Core")
		try FileManager.default.removeItem(atPath: fixture.moduleInfoPath(of: "Core") + "positions")

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Owner.swift")): warning: @Instantiated property `session: LazilyInstantiated<Session>` is instantiated whenever `Owner` is created: `Reader` is created with `Owner` and receives the instance as `session: Session`. To instantiate it lazily, receive `session: LazilyInstantiated<Session>` on `Reader`.
			error: SafeDI could not read the positions of the module info file at \(fixture.moduleInfoPath(of: "Core")) from \(fixture.moduleInfoPath(of: "Core"))positions: no positions file exists at that path. The lines and columns of that module’s declarations are left out above. Build the module that writes both files again, and give this module both.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithoutPositionAndPairingError_whenPositionsFileIsNotAPositionsFile() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingChild])
		_ = try await fixture.generate(module: "Core")
		try Data("not positions".utf8).write(to: (fixture.moduleInfoPath(of: "Core") + "positions").asFileURL)

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Child.swift")): error: @Received property `missing: Missing` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let missing: Missing` on `Root` or on another type in the chain to fix.
			error: SafeDI could not read the positions of the module info file at \(fixture.moduleInfoPath(of: "Core")) from \(fixture.moduleInfoPath(of: "Core"))positions: the positions file cannot be read. The file is not a module positions file: it does not begin with `SDIP`. The lines and columns of that module’s declarations are left out above. Build the module that writes both files again, and give this module both.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithoutPositionAndPairingError_whenPositionsFileBodyIsMalformed() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingChild])
		_ = try await fixture.generate(module: "Core")
		let positionsURL = (fixture.moduleInfoPath(of: "Core") + "positions").asFileURL
		let positions = try Data(contentsOf: positionsURL)
		// The header, then a count of values far larger than the bytes that follow.
		try (positions.prefix(BinaryFile.Kind.modulePositions.magic.count + 8) + Data([0xFF, 0xFF, 0xFF, 0x7F])).write(to: positionsURL)

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Child.swift")): error: @Received property `missing: Missing` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let missing: Missing` on `Root` or on another type in the chain to fix.
			error: SafeDI could not read the positions of the module info file at \(fixture.moduleInfoPath(of: "Core")) from \(fixture.moduleInfoPath(of: "Core"))positions: the positions file cannot be read. The module positions file’s body records a count of 268435455 at byte 0, more than the bytes that remain. The lines and columns of that module’s declarations are left out above. Build the module that writes both files again, and give this module both.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithoutPositionAndPairingError_whenPositionsFileHoldsTooFewPositions() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingChild])
		_ = try await fixture.generate(module: "Core")
		let positionsURL = (fixture.moduleInfoPath(of: "Core") + "positions").asFileURL
		let positions = try ModulePositionsFile(data: Data(contentsOf: positionsURL))
		try ModulePositionsFile(moduleInfoChecksum: positions.moduleInfoChecksum, values: positions.values.dropLast()).data.write(to: positionsURL)

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Child.swift")): error: @Received property `missing: Missing` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let missing: Missing` on `Root` or on another type in the chain to fix.
			error: SafeDI could not read the positions of the module info file at \(fixture.moduleInfoPath(of: "Core")) from \(fixture.moduleInfoPath(of: "Core"))positions: the positions file holds fewer lines and columns than the module info file stores in it. The lines and columns of that module’s declarations are left out above. Build the module that writes both files again, and give this module both.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithoutPositionAndPairingError_whenPositionsFileHoldsTooManyPositions() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingChild])
		_ = try await fixture.generate(module: "Core")
		let positionsURL = (fixture.moduleInfoPath(of: "Core") + "positions").asFileURL
		let positions = try ModulePositionsFile(data: Data(contentsOf: positionsURL))
		try ModulePositionsFile(moduleInfoChecksum: positions.moduleInfoChecksum, values: positions.values + [2]).data.write(to: positionsURL)

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Child.swift")): error: @Received property `missing: Missing` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let missing: Missing` on `Root` or on another type in the chain to fix.
			error: SafeDI could not read the positions of the module info file at \(fixture.moduleInfoPath(of: "Core")) from \(fixture.moduleInfoPath(of: "Core"))positions: the positions file holds more lines and columns than the module info file stores in it. The lines and columns of that module’s declarations are left out above. Build the module that writes both files again, and give this module both.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func queryGraph_reportsLinesFromPositionsFile_whenPositionsFileIsBesideModuleInfo() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing])
		_ = try await fixture.generate(module: "Core")

		let report = try await QueryGraph.parse(["--module-info", fixture.moduleInfoPath(of: "Core")]).graph()

		#expect(report.declarations.map { "\($0.typeName) \($0.line.map(String.init) ?? "absent")" } == ["Child 1", "Missing 9"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func queryGraph_reportsNoLines_whenPositionsFileIsMissing() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingMissing])
		_ = try await fixture.generate(module: "Core")
		try FileManager.default.removeItem(atPath: fixture.moduleInfoPath(of: "Core") + "positions")

		let report = try await QueryGraph.parse(["--module-info", fixture.moduleInfoPath(of: "Core")]).graph()

		#expect(report.declarations.map { "\($0.typeName) \($0.line.map(String.init) ?? "absent")" } == ["Child absent", "Missing absent"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dump_printsLinesFromPositionsFile_whenPositionsFileIsBesideModuleInfo() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingAliasedDependency])
		_ = try await fixture.generate(module: "Core")

		let locations = try Self.dumpedDependencyLocations(ofModuleInfoAt: fixture.moduleInfoPath(of: "Core"))

		let childPath = fixture.sourcePath(module: "Core", file: "Child.swift")
		#expect(locations == [
			#"{"column":5,"filePath":"\#(childPath)","line":3,"order":3}"#,
			#"{"column":5,"filePath":"\#(childPath)","line":4,"order":4}"#,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dump_printsRanksAlone_whenPositionsFileIsMissing() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingAliasedDependency])
		_ = try await fixture.generate(module: "Core")
		try FileManager.default.removeItem(atPath: fixture.moduleInfoPath(of: "Core") + "positions")

		let locations = try Self.dumpedDependencyLocations(ofModuleInfoAt: fixture.moduleInfoPath(of: "Core"))

		let childPath = fixture.sourcePath(module: "Core", file: "Child.swift")
		#expect(locations == [
			#"{"filePath":"\#(childPath)","order":3}"#,
			#"{"column":5,"filePath":"\#(childPath)","line":4,"order":4}"#,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOwnErrorAlone_whenErrorIsLocatedInOwnModuleAndDependencysPositionsFileIsMissing() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Dep.swift": Self.dependency])
		try fixture.write(module: "App", files: ["Child.swift": Self.childReceivingMissing, "Root.swift": Self.rootInstantiatingDependencyAndChildReceivingMissing])
		_ = try await fixture.generate(module: "Core")
		try FileManager.default.removeItem(atPath: fixture.moduleInfoPath(of: "Core") + "positions")

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "App", file: "Child.swift")):3:5: error: @Received property `missing: Missing` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let missing: Missing` on `Root` or on another type in the chain to fix.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_returnsWarningWithPosition_whenWarningIsLocatedInDependencyAndAnotherDependencysPositionsFileIsMissing() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Owner.swift": Self.ownerReadingLazyInstance])
		try fixture.write(module: "Base", files: ["Dep.swift": Self.dependency])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingOwnerAndDependencyOfTwoModules])
		_ = try await fixture.generate(module: "Core")
		_ = try await fixture.generate(module: "Base")
		try FileManager.default.removeItem(atPath: fixture.moduleInfoPath(of: "Base") + "positions")

		let output = try await fixture.generate(module: "App", dependencies: ["Base", "Core"])

		#expect(output.readPositionsFilesInSecondRun)
		#expect(output.warnings.map(\.formatted) == [
			"\(fixture.sourcePath(module: "Core", file: "Owner.swift")):3:5: warning: @Instantiated property `session: LazilyInstantiated<Session>` is instantiated whenever `Owner` is created: `Reader` is created with `Owner` and receives the instance as `session: Session`. To instantiate it lazily, receive `session: LazilyInstantiated<Session>` on `Reader`.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithInsertingFixItAtDependency_whenConstructedTypeOfDependencySpellsNoAccess() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Hidden.swift": Self.typeSpellingNoAccess])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingHidden])
		_ = try await fixture.generate(module: "Core")

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Hidden.swift")):2:1: error: `Hidden` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Hidden` `package` to fix.
			\(fixture.sourcePath(module: "Core", file: "Hidden.swift")):2:1-2:1: fixit: package 
			\(fixture.sourcePath(module: "Core", file: "Hidden.swift")):3:5: error: `Hidden`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
			\(fixture.sourcePath(module: "Core", file: "Hidden.swift")):3:5-3:5: fixit: package 
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithoutPositionOrFixItAndPairingError_whenConstructedTypeOfDependencySpellsNoAccessAndPositionsFileIsMissing() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Hidden.swift": Self.typeSpellingNoAccess])
		try fixture.write(module: "App", files: ["Root.swift": Self.rootInstantiatingHidden])
		_ = try await fixture.generate(module: "Core")
		try FileManager.default.removeItem(atPath: fixture.moduleInfoPath(of: "Core") + "positions")

		await #expect {
			try await fixture.generate(module: "App", dependencies: ["Core"])
		} throws: { error in
			"\(error)" == """
			\(fixture.sourcePath(module: "Core", file: "Hidden.swift")): error: `Hidden` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Hidden` `package` to fix.
			\(fixture.sourcePath(module: "Core", file: "Hidden.swift")): error: `Hidden`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
			error: SafeDI could not read the positions of the module info file at \(fixture.moduleInfoPath(of: "Core")) from \(fixture.moduleInfoPath(of: "Core"))positions: no positions file exists at that path. The lines and columns of that module’s declarations are left out above. Build the module that writes both files again, and give this module both.
			"""
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesOnlyPositionsFile_whenLineOfDeclarationMoves() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingAliasedDependency])
		_ = try await fixture.generate(module: "Core")
		let moduleInfo = try Data(contentsOf: fixture.moduleInfoPath(of: "Core").asFileURL)
		let positions = try Data(contentsOf: (fixture.moduleInfoPath(of: "Core") + "positions").asFileURL)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingAliasedDependency.replacingOccurrences(of: "}\n\n@Instantiable", with: "}\n\n\n@Instantiable")])

		_ = try await fixture.generate(module: "Core")

		#expect(try Data(contentsOf: fixture.moduleInfoPath(of: "Core").asFileURL) == moduleInfo)
		#expect(try Data(contentsOf: (fixture.moduleInfoPath(of: "Core") + "positions").asFileURL) != positions)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesModuleInfoFile_whenLineOfAliasedDependencyMoves() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingAliasedDependency])
		_ = try await fixture.generate(module: "Core")
		let moduleInfo = try Data(contentsOf: fixture.moduleInfoPath(of: "Core").asFileURL)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingAliasedDependency.replacingOccurrences(of: "    @Received(fulfilledByDependencyNamed:", with: "\n    @Received(fulfilledByDependencyNamed:")])

		_ = try await fixture.generate(module: "Core")

		#expect(try Data(contentsOf: fixture.moduleInfoPath(of: "Core").asFileURL) != moduleInfo)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func encode_codesLocationsAndRangesWithoutPositionsStoredElsewhere_whenModuleInfoIsReadWithoutPositionsFile() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingAliasedDependency])
		_ = try await fixture.generate(module: "Core")
		let moduleInfoData = try Data(contentsOf: fixture.moduleInfoPath(of: "Core").asFileURL)
		let positionsData = try Data(contentsOf: (fixture.moduleInfoPath(of: "Core") + "positions").asFileURL)
		let alone = try ModuleInfoFile.reading(moduleInfoData: moduleInfoData, readingView: false, positionsData: nil, reattachesPositions: false).file
		let withPositions = try ModuleInfoFile.reading(moduleInfoData: moduleInfoData, readingView: false, positionsData: positionsData, reattachesPositions: true).file
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
		func json(of file: ModuleInfoFile) throws -> (locations: [String], ranges: [String]) {
			let child = try #require(file.instantiables.first)
			return try (
				locations: child.dependencies.compactMap(\.declarationLocation).map { try String(decoding: encoder.encode($0), as: UTF8.self) },
				ranges: [child.access.modifierRange].compactMap(\.self).map { try String(decoding: encoder.encode($0), as: UTF8.self) },
			)
		}

		let (locationsAlone, rangesAlone) = try json(of: alone)
		let (locationsWithPositions, rangesWithPositions) = try json(of: withPositions)

		let childPath = fixture.sourcePath(module: "Core", file: "Child.swift")
		#expect(locationsAlone == [
			#"{"filePath":"\#(childPath)","order":3}"#,
			#"{"column":5,"filePath":"\#(childPath)","line":4,"order":4}"#,
		])
		#expect(rangesAlone == ["{}"])
		#expect(locationsWithPositions == [
			#"{"column":5,"filePath":"\#(childPath)","line":3,"order":3}"#,
			#"{"column":5,"filePath":"\#(childPath)","line":4,"order":4}"#,
		])
		#expect(rangesWithPositions == [#"{"endColumn":7,"endLine":2,"startColumn":1,"startLine":2}"#])
		let decoder = JSONDecoder()
		#expect(try (locationsAlone + locationsWithPositions).map { try decoder.decode(Dependency.DeclarationLocation.self, from: Data($0.utf8)).identity } == [
			"\(childPath)#3", "\(childPath):4:5", "\(childPath):3:5", "\(childPath):4:5",
		])
		#expect(try (rangesAlone + rangesWithPositions).map { try decoder.decode(Dependency.SourceRange.self, from: Data($0.utf8)).placement } == [
			.storedElsewhere, .here(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func lineAndColumn_isAbsentOnlyWherePositionIsStoredElsewhere_whenModuleInfoIsReadWithoutPositionsFile() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Child.swift": Self.childReceivingAliasedDependency])
		_ = try await fixture.generate(module: "Core")
		let moduleInfoData = try Data(contentsOf: fixture.moduleInfoPath(of: "Core").asFileURL)
		let alone = try ModuleInfoFile.reading(moduleInfoData: moduleInfoData, readingView: false, positionsData: nil, reattachesPositions: false).file
		let child = try #require(alone.instantiables.first)

		let lineAndColumns = child.dependencies.compactMap(\.declarationLocation).map { $0.lineAndColumn.map { "\($0.line):\($0.column)" } ?? "absent" }

		#expect(lineAndColumns == ["absent", "4:5"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsValidationError_whenPositionsInOwnFileHasNoModuleInfoOutput() async throws {
		let fixture = try PositionsFixture(filesToDelete: &filesToDelete)
		try fixture.write(module: "Core", files: ["Dep.swift": Self.dependency])

		await #expect {
			try await Generate.parse([
				"--include", fixture.root.appendingPathComponent("Core").path,
				"--combined-output", fixture.root.appendingPathComponent("Core.swift").path,
				"--module-info-positions-in-own-file",
			]).generate()
		} throws: { error in
			"\(error)" == "'--module-info-positions-in-own-file' requires '--module-info-output': the positions file is written beside the module info file."
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let dependency = """
	@Instantiable
	public final class Dep: Instantiable {
	    public init() {}
	}
	"""

	private static let rootInstantiatingDependency = """
	import Core

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(dep: Dep) {
	        self.dep = dep
	    }
	    @Instantiated let dep: Dep
	}
	"""

	private static let ownerReadingLazyInstance = """
	@Instantiable
	public final class Owner: Instantiable {
	    @Instantiated let session: LazilyInstantiated<Session>
	    @Instantiated let reader: Reader
	    public init(session: LazilyInstantiated<Session>, reader: Reader) {
	        self.session = session
	        self.reader = reader
	    }
	}

	@Instantiable
	public final class Reader: Instantiable {
	    @Received let session: Session
	    public init(session: Session) {
	        self.session = session
	    }
	}

	@Instantiable
	public final class Session: Instantiable {
	    public init() {}
	}
	"""

	private static let rootInstantiatingOwner = """
	import Core

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(owner: Owner) {
	        self.owner = owner
	    }
	    @Instantiated let owner: Owner
	}
	"""

	private static let rootInstantiatingOwnerAndDependency = """
	import Core

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(owner: Owner, dep: Dep) {
	        self.owner = owner
	        self.dep = dep
	    }
	    @Instantiated let owner: Owner
	    @Instantiated let dep: Dep
	}
	"""

	private static let rootInstantiatingDependencyAndChildReceivingMissing = """
	import Core

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(dep: Dep, child: Child) {
	        self.dep = dep
	        self.child = child
	    }
	    @Instantiated let dep: Dep
	    @Instantiated let child: Child
	}
	"""

	private static let rootInstantiatingOwnerAndDependencyOfTwoModules = """
	import Base
	import Core

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(owner: Owner, dep: Dep) {
	        self.owner = owner
	        self.dep = dep
	    }
	    @Instantiated let owner: Owner
	    @Instantiated let dep: Dep
	}
	"""

	/// The JSON `dump` prints for each dependency location of the first instantiable of the module info file at `path`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func dumpedDependencyLocations(ofModuleInfoAt path: String) throws -> [String] {
		let dumped = try #require(JSONSerialization.jsonObject(with: Data(Dump.parse([path]).json().utf8)) as? [String: Any])
		let instantiables = try #require(dumped["instantiables"] as? [[String: Any]])
		let dependencies = try #require(instantiables.first?["dependencies"] as? [[String: Any]])
		return try dependencies.compactMap { $0["declarationLocation"] }.map { location in
			try String(decoding: JSONSerialization.data(withJSONObject: location, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
		}
	}

	private static let childReceivingMissing = """
	@Instantiable
	public final class Child: Instantiable {
	    @Received let missing: Missing
	    public init(missing: Missing) {
	        self.missing = missing
	    }
	}

	@Instantiable
	public final class Missing: Instantiable {
	    public init() {}
	}
	"""

	private static let rootInstantiatingChild = """
	import Core

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(child: Child) {
	        self.child = child
	    }
	    @Instantiated let child: Child
	}
	"""

	private static let typeSpellingNoAccess = """
	@Instantiable
	final class Hidden: Instantiable {
	    init() {}
	}
	"""

	private static let rootInstantiatingHidden = """
	import Core

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(hidden: Hidden) {
	        self.hidden = hidden
	    }
	    @Instantiated let hidden: Hidden
	}
	"""

	private static let childReceivingAliasedDependency = """
	@Instantiable
	public final class Child: Instantiable {
	    @Received let dep: Dep
	    @Received(fulfilledByDependencyNamed: "dep", ofType: Dep.self) let renamedDep: Dep
	    public init(dep: Dep, renamedDep: Dep) {
	        self.dep = dep
	        self.renamedDep = renamedDep
	    }
	}

	@Instantiable
	public final class Dep: Instantiable {
	    public init() {}
	}
	"""
}

/// Modules written under one directory, each run as the Bazel rule runs it, with positions in a file of their own.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private struct PositionsFixture {
	init(filesToDelete: inout [URL]) throws {
		root = TestTemporaryDirectory.root.appendingPathComponent("SafeDIToolModulePositions-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		filesToDelete.append(root)
	}

	let root: URL

	func sourcePath(module: String, file: String) -> String {
		root.appendingPathComponent(module).appendingPathComponent(file).path
	}

	func moduleInfoPath(of module: String) -> String {
		root.appendingPathComponent("\(module).safedi").path
	}

	func unusedInputsList(of module: String) -> URL {
		root.appendingPathComponent("\(module)_unused.txt")
	}

	/// Replaces the module's files with `files`.
	func write(module: String, files: [String: String]) throws {
		let directory = root.appendingPathComponent(module, isDirectory: true)
		try? FileManager.default.removeItem(at: directory)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		for (name, content) in files {
			try content.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
		}
	}

	/// Runs `generate` for `module`, which writes its module info and positions files, reading those of `dependencies`.
	func generate(module: String, dependencies: [String] = []) async throws -> Generate.Output {
		let sources = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(module).path)
			.sorted()
			.map { sourcePath(module: module, file: $0) }
		let sourcesList = root.appendingPathComponent("\(module).csv")
		try sources.joined(separator: ",").write(to: sourcesList, atomically: true, encoding: .utf8)
		var arguments = [
			sourcesList.path,
			"--combined-output", root.appendingPathComponent("\(module).swift").path,
			"--compiler-receives-input-paths-unchanged",
			"--module-info-output", moduleInfoPath(of: module),
			"--module-info-positions-in-own-file",
			"--module-info-views-refer-to-modules",
			"--module-name", module,
			"--package-name", "Positions",
			"--unused-inputs-list-output", unusedInputsList(of: module).path,
		]
		if !dependencies.isEmpty {
			let dependencyList = root.appendingPathComponent("\(module)-dependencies.csv")
			try dependencies.map(moduleInfoPath(of:)).joined(separator: ",").write(to: dependencyList, atomically: true, encoding: .utf8)
			arguments += [
				"--dependent-module-info-file-path", dependencyList.path,
				"--transitive-module-info-file-path", dependencyList.path,
			]
		}
		return try await Generate.parse(arguments).generate()
	}
}
