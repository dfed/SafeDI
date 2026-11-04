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

/// When `generate` reuses the module `scan` cached, verified through the two commands.
///
/// The input CSV lists absolute paths while scan records paths relative to the project root,
/// so a fresh parse in `generate` names the root differently from the manifest and fails with
/// `rootNotInManifest`. Success therefore shows `generate` reused scan's cache, and that error shows
/// it parsed afresh.
struct SafeDIToolScanCacheFreshnessTests: ~Copyable {
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
	mutating func generate_reusesCache_whenNoInputChanged() async throws {
		let project = try await scannedProject()

		try await project.generate()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenInputContentAndModificationTimeChange() async throws {
		let project = try await scannedProject()
		try Self.rootContent.appending("\n// Edited.\n").write(to: project.rootFile, atomically: true, encoding: .utf8)
		try FileModificationTime(seconds: 4_000_000_000, nanoseconds: 0).apply(toItemAtPath: project.rootFile.path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenModificationTimeMovesBackward() async throws {
		// A checkout or copy that restores an older file reports an earlier time than the scan saw.
		let project = try await scannedProject()
		try FileModificationTime(seconds: 0, nanoseconds: 0).apply(toItemAtPath: project.rootFile.path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenModificationTimeChangesWithinTheSameSecond() async throws {
		let project = try await scannedProject()
		let scannedTime = try FileModificationTime(ofItemAtPath: project.rootFile.path)
		try FileModificationTime(
			seconds: scannedTime.seconds,
			nanoseconds: scannedTime.nanoseconds == 0 ? 1 : scannedTime.nanoseconds - 1,
		).apply(toItemAtPath: project.rootFile.path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesCache_whenContentChangesButModificationTimeIsRestored() async throws {
		// The check reads modification times only, which is what lets other tests hide an edit from it.
		let project = try await scannedProject()
		let scannedTime = try FileModificationTime(ofItemAtPath: project.rootFile.path)
		try Self.rootContent.appending("\n// Edited.\n").write(to: project.rootFile, atomically: true, encoding: .utf8)
		try scannedTime.apply(toItemAtPath: project.rootFile.path)

		try await project.generate()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesCache_whenSymbolicLinkAndTargetAreUnchanged() async throws {
		let project = try await scannedProject(throughSymbolicLink: true)

		try await project.generate()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenSymbolicLinkTargetChanges() async throws {
		let project = try await scannedProject(throughSymbolicLink: true)
		try FileModificationTime(seconds: 0, nanoseconds: 0).apply(toItemAtPath: project.targetFile.path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenSymbolicLinkIsRetargetedToFileWithTheSameModificationTime() async throws {
		let project = try await scannedProject(throughSymbolicLink: true)
		let otherTarget = project.directory.appendingPathComponent("OtherTarget.swift")
		try Self.rootContent.write(to: otherTarget, atomically: true, encoding: .utf8)
		try FileModificationTime(ofItemAtPath: project.targetFile.path).apply(toItemAtPath: otherTarget.path)
		let linkTime = try FileModificationTime(ofItemAtPath: project.rootFile.path)
		try FileManager.default.removeItem(at: project.rootFile)
		try FileManager.default.createSymbolicLink(at: project.rootFile, withDestinationURL: otherTarget)
		// Only the link itself changed, and a link's own time is what reveals that.
		#expect(try FileModificationTime(ofItemAtPath: project.rootFile.path) != linkTime)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenSymbolicLinkTargetIsDeleted() async throws {
		let project = try await scannedProject(throughSymbolicLink: true)
		try FileManager.default.removeItem(at: project.targetFile)

		// The fresh parse cannot read the dangling link.
		await assertThrowsError(containing: "Root.swift") {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheIsJSONFromAnEarlierRelease() async throws {
		// Earlier releases wrote the cache as JSON, under another name.
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			try JSONEncoder().encode(CachedScannedModuleInfo(scanCacheData: cache))
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheIsEmpty() async throws {
		let project = try await scannedProject()
		try project.rewriteCache { _ in Data() }

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheIsCutShort() async throws {
		// A write interrupted before it finished, for a build system that does not write atomically.
		let project = try await scannedProject()
		try project.rewriteCache { cache in cache.dropLast() }

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheIsCorrupted() async throws {
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			var cache = cache
			cache[cache.endIndex - 1] ^= 0x01
			return cache
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheDoesNotBeginWithMagic() async throws {
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			var cache = cache
			cache[cache.startIndex] = UInt8(ascii: "X")
			return cache
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheHasAnotherFormatVersion() async throws {
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			var cache = cache
			cache[cache.startIndex + 4] &+= 1
			return cache
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenCacheHasAnotherSchemaFingerprint() async throws {
		// A SafeDITool whose cached types are laid out differently, such as another development build.
		let project = try await scannedProject()
		try project.rewriteCache { cache in
			var cache = cache
			cache[cache.startIndex + 6] ^= 0x01
			return cache
		}

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesTypeDeclarationOfFileWithoutSafeDIMarker_whenExtensionHoldingInstantiableExtendsItsType() async throws {
		let project = try await scannedProject(alongside: Self.namespaceFiles)

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.typeDescription) == [.simple(name: "Space")])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.access.level) == [.package])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.sourceFilePath) == ["Space.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenFileWithoutSafeDIMarkerDeclaringExtendedTypeChanges() async throws {
		let project = try await scannedProject(alongside: Self.namespaceFiles)
		try FileModificationTime(seconds: 0, nanoseconds: 0).apply(toItemAtPath: project.directory.appendingPathComponent("Space.swift").path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesProtocolDeclarationOfFileWithoutSafeDIMarker_whenDeclarationsInitializerMentionsIt() async throws {
		let project = try await scannedProject(alongside: Self.mentionedProtocolFiles)

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.typeDescription) == [.simple(name: "Theme")])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.access.level) == [.public])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.sourceFilePath) == ["Theme.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenFileWithoutSafeDIMarkerDeclaringMentionedProtocolChanges() async throws {
		let project = try await scannedProject(alongside: Self.mentionedProtocolFiles)
		try FileModificationTime(seconds: 0, nanoseconds: 0).apply(toItemAtPath: project.directory.appendingPathComponent("Theme.swift").path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenFileWalkedAgainUnderGeneratesConditionsMentionsTypeScansDeclarationsDidNot() async throws {
		// Under scan's conditions no declaration mentions `Theme`, so scan read no declaration of it; under `STAGING`
		// `Badge`'s does, which only a fresh parse reads.
		let project = try await scannedProject(alongside: [
			"Theme.swift": "public protocol Theme {}",
			"Badge.swift": """
			@Instantiable
			public struct Badge: Instantiable {
			    #if STAGING
			    public init(theme: (any Theme)?) {
			        self.theme = theme
			    }

			    @Received(onlyIfAvailable: true) let theme: (any Theme)?
			    #else
			    public init() {}
			    #endif
			}
			""",
		])

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate(activeCompilationConditions: ["STAGING"])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesTypeDeclarationInsideConditionalBlock_whenDeclarationsInitializerMentionsIt() async throws {
		// B7: `Token` is declared inside an `#if` block, once in each clause, in a file whose text holds a SafeDI marker: each
		// record is cached marked as such, with its spelled level.
		let project = try await scannedProject(alongside: Self.conditionalTokenFiles)

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.typeDescription) == [.simple(name: "Token"), .simple(name: "Token")])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.isInsideConditionalBlock) == [true, true])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.access.level) == [.package, .package])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.sourceFilePath) == ["Badge.swift", "Badge.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_parsesAfresh_whenFileDeclaringTypeInsideConditionalBlockChanges() async throws {
		// B7: editing the file whose `#if` block declares `Token` reads it again rather than the records scan cached.
		let project = try await scannedProject(alongside: Self.conditionalTokenFiles)
		let badgeFile = project.directory.appendingPathComponent("Badge.swift")
		try Self.conditionalTokenFiles["Badge.swift", default: ""].replacingOccurrences(of: "#if FLAG\npackage struct Token {}", with: "#if FLAG\npublic struct Token {}").write(to: badgeFile, atomically: true, encoding: .utf8)
		try FileModificationTime(seconds: 0, nanoseconds: 0).apply(toItemAtPath: badgeFile.path)

		await assertThrowsError(project.rootNotInManifestMessage) {
			try await project.generate()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesTheSameDeclarationsInsideConditionalBlock_whenScannedWithEitherConditionSet() async throws {
		// B7b: a declaration inside an `#if` block is recorded from every clause, so scanning without `FLAG` and with it
		// records the same declarations, which `generate` can reuse under either condition set.
		let withoutFlag = try await scannedProject(alongside: Self.conditionalTokenFiles)
		let withFlag = try await scannedAgain(withoutFlag, activeCompilationConditions: ["FLAG"])

		let cacheWithoutFlag = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: withoutFlag.manifestFile.path)))
		let cacheWithFlag = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: withFlag.manifestFile.path)))
		#expect(cacheWithFlag.moduleInfo.plainTypeDeclarations.count == 2)
		#expect(cacheWithoutFlag.moduleInfo.plainTypeDeclarations == cacheWithFlag.moduleInfo.plainTypeDeclarations)
		try await withoutFlag.generate(activeCompilationConditions: ["FLAG"])
		try await withFlag.generate()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_cachesTypealias_whenFileWithoutSafeDIMarkerDeclaresTypeADeclarationMentions() async throws {
		// C8: the text search finds `typealias Handler`, so the file is parsed and its typealias recorded.
		let project = try await scannedProject(alongside: [
			"Handler.swift": "public typealias Handler = () -> Void",
			"Badge.swift": """
			@Instantiable
			public struct Badge: Instantiable {
			    public init(handler: @escaping Handler) {
			        self.handler = handler
			    }

			    @Received let handler: Handler
			}
			""",
		])

		let cache = try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: scannedModuleInfoURL(forManifestPath: project.manifestFile.path)))
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.typeDescription) == [.simple(name: "Handler")])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.access.level) == [.public])
		#expect(cache.moduleInfo.plainTypeDeclarations.map(\.sourceFilePath) == ["Handler.swift"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A `package` type declared inside an `#if` block of a file that also declares a type whose initializer mentions it.
	private static let conditionalTokenFiles = [
		"Badge.swift": """
		#if FLAG
		package struct Token {}
		#else
		package struct Token {
		    let value: Int
		}
		#endif

		@Instantiable
		public struct Badge: Instantiable {
		    init(token: Token) {
		        self.token = token
		    }

		    @Received let token: Token
		}
		""",
	]

	/// A protocol in a file of its own, which mentions no SafeDI marker, and a declaration whose initializer mentions it.
	private static let mentionedProtocolFiles = [
		"Theme.swift": "public protocol Theme {}",
		"Badge.swift": """
		@Instantiable
		public struct Badge: Instantiable {
		    public init(theme: any Theme) {
		        self.theme = theme
		    }

		    @Received let theme: any Theme
		}
		""",
	]

	/// A namespace enum in a file of its own, which mentions no SafeDI marker, and an extension of it that declares an
	/// `@Instantiable` type.
	private static let namespaceFiles = [
		"Space.swift": "package enum Space {}",
		"Shelf.swift": """
		extension Space {
		    @Instantiable
		    public final class Shelf: Instantiable {
		        public init() {}
		    }
		}
		""",
	]

	private static let rootContent = """
	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init() {}
	}
	"""

	private struct ScannedProject {
		let directory: URL
		/// The input the CSV lists.
		let rootFile: URL
		/// The file `rootFile` links to, or `rootFile` itself.
		let targetFile: URL
		let swiftFileCSV: URL
		let manifestFile: URL

		/// Replaces the cache scan wrote with what `rewrite` makes of it.
		@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
		func rewriteCache(_ rewrite: (Data) throws -> Data) throws {
			let cacheURL = scannedModuleInfoURL(forManifestPath: manifestFile.path)
			try rewrite(Data(contentsOf: cacheURL)).write(to: cacheURL)
		}

		/// The error a fresh parse in `generate` throws, naming the root as the CSV does.
		var rootNotInManifestMessage: String {
			"Found @Instantiable(isRoot: true) in '\(rootFile.path)', but this file is not listed in the manifest’s dependencyTreeGeneration. SafeDI decides which files to generate before the build runs, listing every file that declares a root, a type that sets `generateDependencyTree: true` or `generateMock: true`, or a #SafeDIConfiguration in any clause of its `#if` blocks, so the file most likely changed after that decision; building again lists it. A hand-written manifest must list the file, or the type must not be a root."
		}

		func generate(activeCompilationConditions: [String] = []) async throws {
			try await Generate.parse([
				swiftFileCSV.path,
				"--swift-manifest", manifestFile.path,
			] + (activeCompilationConditions.isEmpty ? [] : ["--active-compilation-conditions"] + activeCompilationConditions)).run()
		}
	}

	/// A project whose root is in `Root.swift`, and which holds the content of `otherFiles` at each file name.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func scannedProject(throughSymbolicLink: Bool = false, alongside otherFiles: [String: String] = [:]) async throws -> ScannedProject {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let rootFile = directory.appendingPathComponent("Root.swift")
		let targetFile = throughSymbolicLink ? directory.appendingPathComponent("Target.swift") : rootFile
		try Self.rootContent.write(to: targetFile, atomically: true, encoding: .utf8)
		if throughSymbolicLink {
			try FileManager.default.createSymbolicLink(at: rootFile, withDestinationURL: targetFile)
		}
		let otherFileURLs = try otherFiles.keys.sorted().map { fileName in
			let fileURL = directory.appendingPathComponent(fileName)
			try otherFiles[fileName]?.write(to: fileURL, atomically: true, encoding: .utf8)
			return fileURL
		}
		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try ([rootFile] + otherFileURLs).map(\.path).joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		filesToDelete += [directory, swiftFileCSV, outputDirectory, manifestFile, scannedModuleInfoURL(forManifestPath: manifestFile.path)]

		try await Scan.parse([
			"--input-sources-file", swiftFileCSV.path,
			"--project-root", directory.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
		]).run()
		return ScannedProject(
			directory: directory,
			rootFile: rootFile,
			targetFile: targetFile,
			swiftFileCSV: swiftFileCSV,
			manifestFile: manifestFile,
		)
	}

	/// `project`, scanned again under `activeCompilationConditions` into a manifest and cache of its own, so that the two
	/// caches name the same files.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func scannedAgain(_ project: ScannedProject, activeCompilationConditions: [String]) async throws -> ScannedProject {
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		filesToDelete += [outputDirectory, manifestFile, scannedModuleInfoURL(forManifestPath: manifestFile.path)]

		try await Scan.parse([
			"--input-sources-file", project.swiftFileCSV.path,
			"--project-root", project.directory.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
			"--active-compilation-conditions",
		] + activeCompilationConditions).run()
		return ScannedProject(
			directory: project.directory,
			rootFile: project.rootFile,
			targetFile: project.targetFile,
			swiftFileCSV: project.swiftFileCSV,
			manifestFile: manifestFile,
		)
	}
}
