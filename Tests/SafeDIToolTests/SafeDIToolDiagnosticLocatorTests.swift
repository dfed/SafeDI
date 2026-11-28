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

/// A `.safedi` file keeps each location as its file and rank, never its line or column, so a run that reports a
/// diagnostic about another module's declaration reads that declaration's file again to print its line, column and
/// fix-its (`DiagnosticLocator`). Each test runs `generate` as Bazel does, once per module, `Feature` beneath `App`.
/// A readable file's diagnostics with their fix-its are `SafeDIToolAccessEnforcementTests`' `.moduleInfo` cases.
struct SafeDIToolDiagnosticLocatorTests: ~Copyable {
	// MARK: Initialization

	init() {
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
	mutating func generate_locatesErrorAndFixItInAnotherModulesFile_whenFileIsReadable() async throws {
		let project = try makeProject(featureFiles: ["Service.swift": Self.packageServiceWithInternalInitializer])
		try await project.runFeature()

		let description = try await project.appErrorDescription()

		#expect(description == """
		\(project.featurePath("Service.swift")):3:5: error: `Service`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
		\(project.featurePath("Service.swift")):3:5-3:5: fixit: package\(" ")
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_printsFileAndMessageWithoutLine_whenAnotherModulesFileCannotBeRead() async throws {
		let project = try makeProject(
			featureFiles: ["Store.swift": Self.publicStore],
			appFiles: ["Store.swift": Self.publicStore, "Root.swift": Self.rootInstantiatingStore],
		)
		try await project.runFeature()
		try FileManager.default.removeItem(atPath: project.featurePath("Store.swift"))

		let description = try await project.appErrorDescription()

		#expect(description == """
		\(project.appPath("Store.swift")):1:1: error: `Store` is declared in modules `App` and `Feature`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one.
		\(project.featurePath("Store.swift")): error: `Store` is declared in modules `App` and `Feature`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one.
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_printsFileAndMessageWithoutLineOrFixIt_whenAnotherModulesFileHoldsOtherDeclarationsSinceItsRun() async throws {
		let project = try makeProject(featureFiles: ["Service.swift": Self.packageServiceWithInternalInitializer])
		try await project.runFeature()
		// A declaration added since `Feature`'s run gives the file another number of locations than its `.safedi` records.
		try (Self.packageServiceWithInternalInitializer + """


		@Instantiable
		package final class Added: Instantiable {
		    package init() {}
		}
		""").write(toFile: project.featurePath("Service.swift"), atomically: true, encoding: .utf8)

		let description = try await project.appErrorDescription()

		#expect(description == """
		\(project.featurePath("Service.swift")): error: `Service`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_locatesErrorInAnotherModulesFileUnderResolvedRootOfInput_whenRecordedRelativePathOpensOnlyThere() async throws {
		// As in a sandboxed Bazel action: `App`'s run reads its own files through symbolic links into the execution root,
		// which alone holds `Feature`'s file at the relative path `Feature`'s `.safedi` records.
		let project = try makeProject(
			featureFiles: ["Store.swift": Self.publicStore],
			appFiles: ["Store.swift": Self.publicStore, "Root.swift": Self.rootInstantiatingStore],
			underWorkingDirectory: true,
		)
		try await project.runFeature()
		let executionRoot = project.root.appendingPathComponent("ExecutionRoot")
		for relativePath in [project.featurePath("Store.swift"), project.appPath("Store.swift"), project.appPath("Root.swift")] {
			let destination = executionRoot.appendingPathComponent(relativePath)
			try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
			try FileManager.default.moveItem(atPath: relativePath, toPath: destination.path)
		}
		for relativePath in [project.appPath("Store.swift"), project.appPath("Root.swift")] {
			try FileManager.default.createSymbolicLink(atPath: relativePath, withDestinationPath: executionRoot.appendingPathComponent(relativePath).path)
		}
		#expect(!FileManager.default.fileExists(atPath: project.featurePath("Store.swift")))

		let description = try await project.appErrorDescription()

		#expect(description == """
		\(project.appPath("Store.swift")):1:1: error: `Store` is declared in modules `App` and `Feature`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one.
		\(project.featurePath("Store.swift")):1:1: error: `Store` is declared in modules `App` and `Feature`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one.
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_locatesWarningInAnotherModulesFile_whenWarningsAreNotReplayedFromCache() async throws {
		let project = try makeProject(featureFiles: ["Owner.swift": Self.ownerInstantiatingSessionWithIt], appFiles: ["Root.swift": Self.rootInstantiatingOwner])
		try await project.runFeature()

		let output = try await project.runApp()

		#expect(output.warnings.map(\.formatted) == [
			"\(project.featurePath("Owner.swift")):7:5: warning: @Instantiated property `session: LazilyInstantiated<Session>` is instantiated whenever `Owner` is created: `Reader` is created with `Owner` and receives the instance as `session: Session`. To instantiate it lazily, receive `session: LazilyInstantiated<Session>` on `Reader`.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_printsWarningInAnotherModulesFileWithoutLine_whenWarningsMayBeReplayedFromCache() async throws {
		let project = try makeProject(featureFiles: ["Owner.swift": Self.ownerInstantiatingSessionWithIt], appFiles: ["Root.swift": Self.rootInstantiatingOwner])
		try await project.runFeature()

		let output = try await project.runApp(arguments: ["--warnings-may-be-replayed-from-cache"])

		#expect(output.warnings.map(\.formatted) == [
			"\(project.featurePath("Owner.swift")): warning: @Instantiated property `session: LazilyInstantiated<Session>` is instantiated whenever `Owner` is created: `Reader` is created with `Owner` and receives the instance as `session: Session`. To instantiate it lazily, receive `session: LazilyInstantiated<Session>` on `Reader`.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_locatesErrorInAnotherModulesFile_whenWarningsMayBeReplayedFromCache() async throws {
		let project = try makeProject(featureFiles: ["Service.swift": Self.packageServiceWithInternalInitializer])
		try await project.runFeature()

		let description = try await project.appErrorDescription(arguments: ["--warnings-may-be-replayed-from-cache"])

		#expect(description == """
		\(project.featurePath("Service.swift")):3:5: error: `Service`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
		\(project.featurePath("Service.swift")):3:5-3:5: fixit: package\(" ")
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsAnotherModulesFileOnce_whenTwoDiagnosticsNameIt() async throws {
		let project = try makeProject(featureFiles: ["Service.swift": """
		@Instantiable
		package final class Service: Instantiable {
		    package init() {}
		}
		"""], appPackageName: "Storefront")
		try await project.runFeature()
		let (filesRead, filesReadContinuation) = AsyncStream<String>.makeStream()

		let description = try await DiagnosticLocatorObservation.$fileReadObserver.withValue({ filesReadContinuation.yield($0) }) {
			try await project.appErrorDescription()
		}
		filesReadContinuation.finish()

		#expect(description == """
		\(project.featurePath("Service.swift")):2:1: error: `Service` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix.
		\(project.featurePath("Service.swift")):2:1-2:8: fixit: public
		\(project.featurePath("Service.swift")):3:5: error: `Service`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
		\(project.featurePath("Service.swift")):3:5-3:12: fixit: public
		""")
		var pathsRead = [String]()
		for await path in filesRead {
			pathsRead.append(path)
		}
		#expect(pathsRead == [project.featurePath("Service.swift")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsNoFileAgain_whenRunReportsNothing() async throws {
		let project = try makeProject(featureFiles: ["Service.swift": """
		@Instantiable
		public final class Service: Instantiable {
		    public init() {}
		}
		"""])
		try await project.runFeature()
		let (filesRead, filesReadContinuation) = AsyncStream<String>.makeStream()

		let output = try await DiagnosticLocatorObservation.$fileReadObserver.withValue({ filesReadContinuation.yield($0) }) {
			try await project.runApp()
		}
		filesReadContinuation.finish()

		#expect(output.warnings.isEmpty)
		var pathsRead = [String]()
		for await path in filesRead {
			pathsRead.append(path)
		}
		#expect(pathsRead.isEmpty)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feature`, in package `Shop`, declares `Service`, a `package` type whose initializer, at line 3, spells no modifier.
	private static let packageServiceWithInternalInitializer = """
	@Instantiable
	package final class Service: Instantiable {
	    init() {}
	}
	"""

	private static let publicStore = """
	@Instantiable
	public final class Store: Instantiable {
	    public init() {}
	}
	"""

	private static let rootInstantiatingStore = """
	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(store: Store) {
	        self.store = store
	    }

	    @Instantiated let store: Store
	}
	"""

	private static let rootInstantiatingService = """
	import Feature

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(service: Service) {
	        self.service = service
	    }

	    @Instantiated let service: Service
	}
	"""

	/// `Owner` declares `session` lazily at line 7, and builds `Reader`, which reads its instance, whenever it is created.
	private static let ownerInstantiatingSessionWithIt = """
	@Instantiable
	public final class Owner: Instantiable {
	    public init(session: LazilyInstantiated<Session>, reader: Reader) {
	        self.session = session
	        self.reader = reader
	    }
	    @Instantiated let session: LazilyInstantiated<Session>
	    @Instantiated let reader: Reader
	}

	@Instantiable
	public final class Session: Instantiable {
	    public init() {}
	}

	@Instantiable
	public final class Reader: Instantiable {
	    public init(session: Session) {
	        self.session = session
	    }
	    @Received let session: Session
	}
	"""

	private static let rootInstantiatingOwner = """
	import Feature

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(owner: Owner) {
	        self.owner = owner
	    }

	    @Instantiated let owner: Owner
	}
	"""

	/// Writes `Feature`'s and `App`'s files, `App` holding `rootInstantiatingService` unless `appFiles` says otherwise.
	/// - Parameter underWorkingDirectory: Whether the project is written under the working directory's `.build`
	///   directory and its files named relative to the working directory, as a Bazel action names them, rather than by
	///   absolute paths in a temporary directory.
	private mutating func makeProject(
		featureFiles: [String: String],
		appFiles: [String: String] = ["Root.swift": rootInstantiatingService],
		appPackageName: String = "Shop",
		underWorkingDirectory: Bool = false,
	) throws -> LocatorProject {
		let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		let relativeRoot = ".build/SafeDIToolTestFixtures/\(UUID().uuidString)"
		let root = underWorkingDirectory
			? workingDirectory.appendingPathComponent(relativeRoot)
			: TestTemporaryDirectory.root.appendingPathComponent("SafeDIToolDiagnosticLocatorTests-\(UUID().uuidString)")
		filesToDelete.append(root)
		let project = LocatorProject(root: root, sourcesDirectory: underWorkingDirectory ? relativeRoot : root.path, appPackageName: appPackageName)
		for (moduleName, files) in [("Feature", featureFiles), ("App", appFiles)] {
			for (fileName, content) in files {
				let path = project.path(of: fileName, inModule: moduleName)
				try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
				try content.write(toFile: path, atomically: true, encoding: .utf8)
			}
			try files.keys.sorted().map { project.path(of: $0, inModule: moduleName) }.joined(separator: ",")
				.write(to: project.csv(ofModule: moduleName), atomically: true, encoding: .utf8)
		}
		try project.moduleInfo(ofModule: "Feature").path.write(to: project.root.appendingPathComponent("AppDependencies.csv"), atomically: true, encoding: .utf8)
		return project
	}
}

/// Two modules' files and the paths their runs of `generate` write.
private struct LocatorProject {
	let root: URL
	/// The directory the modules' sources are under, as their files are named: absolute, or relative to the working
	/// directory.
	let sourcesDirectory: String
	let appPackageName: String

	func path(of fileName: String, inModule moduleName: String) -> String {
		"\(sourcesDirectory)/Sources/\(moduleName)/\(fileName)"
	}

	func featurePath(_ fileName: String) -> String {
		path(of: fileName, inModule: "Feature")
	}

	func appPath(_ fileName: String) -> String {
		path(of: fileName, inModule: "App")
	}

	func csv(ofModule moduleName: String) -> URL {
		root.appendingPathComponent("\(moduleName).csv")
	}

	func moduleInfo(ofModule moduleName: String) -> URL {
		root.appendingPathComponent("\(moduleName).safedi")
	}

	func runFeature() async throws {
		try await Generate.parse([
			csv(ofModule: "Feature").path,
			"--combined-output", root.appendingPathComponent("Feature.swift").path,
			"--module-info-output", moduleInfo(ofModule: "Feature").path,
			"--module-name", "Feature",
			"--package-name", "Shop",
			"--compiler-receives-input-paths-unchanged",
		]).generate()
	}

	@discardableResult
	func runApp(arguments: [String] = []) async throws -> Generate.Output {
		try await Generate.parse([
			csv(ofModule: "App").path,
			"--combined-output", root.appendingPathComponent("App.swift").path,
			"--module-name", "App",
			"--package-name", appPackageName,
			"--dependent-module-info-file-path", root.appendingPathComponent("AppDependencies.csv").path,
			"--compiler-receives-input-paths-unchanged",
		] + arguments).generate()
	}

	/// What `App`'s run prints for the error it throws, or a description saying it threw none.
	func appErrorDescription(arguments: [String] = []) async throws -> String {
		do {
			try await runApp(arguments: arguments)
			return "App’s run threw no error"
		} catch {
			return "\(error)"
		}
	}
}
