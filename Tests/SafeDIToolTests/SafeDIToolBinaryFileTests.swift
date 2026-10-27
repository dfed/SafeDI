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

/// How SafeDITool writes its scan cache and `.safedi` module info files and reads them back, verified on files written for real sources.
struct SafeDIToolBinaryFileTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Round trip

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scanCache_readsBackEverythingScanWrote_whenSourcesUseEveryCachedShape() async throws {
		let project = try await scannedKitchenSinkProject()

		#expect(try reflectedDescription(of: project.readCache()) == reflectedDescription(of: project.scannedModuleInfo))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scanCache_exercisesEveryTagOfEveryCachedEnumeration_whenSourcesUseEveryCachedShape() async throws {
		// The round trip above proves each tag reads back as the case that wrote it only for the tags these sources produce.
		let project = try await scannedKitchenSinkProject()
		var writtenTagsByType = [String: Set<UInt8>]()
		for case let value as any BinarySchemaMember in reflectedStructuresAndEnumerations(in: project.scannedModuleInfo)
			where Mirror(reflecting: value).displayStyle == .enum
		{
			var writer = BinaryWriter()
			writer.write(value)
			writtenTagsByType[String(reflecting: type(of: value)), default: []].insert(writer.bytes[0])
		}

		#expect(writtenTagsByType.count == 5)
		for schemaMember in BinaryFile.schemaMembers where writtenTagsByType[String(reflecting: schemaMember)] != nil {
			#expect(writtenTagsByType[String(reflecting: schemaMember)] == Set(0..<UInt8(schemaMember.binaryLayout.count)), "\(schemaMember)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scanCacheSchema_listsEveryStoredPropertyOfEveryCachedStruct() async throws {
		// A stored property added to a cached type without being listed in its `binaryLayout` fails here, which
		// is the reminder to write and read it too. Listing it changes the schema fingerprint, so caches written
		// before the change are not read after it.
		let project = try await scannedKitchenSinkProject()
		var foundTypeNames = Set<String>()
		for value in reflectedStructuresAndEnumerations(in: project.scannedModuleInfo) {
			let typeName = String(reflecting: type(of: value))
			foundTypeNames.insert(typeName)
			guard let schemaMember = value as? any BinarySchemaMember else {
				Issue.record("\(typeName) is cached but is not one of `BinaryFile.schemaMembers`")
				continue
			}
			let mirror = Mirror(reflecting: value)
			if mirror.displayStyle == .struct {
				#expect(type(of: schemaMember).binaryLayout == mirror.children.map { $0.label ?? "" }, "\(typeName)")
			}
		}

		#expect(Set(BinaryFile.schemaMembers.map { String(reflecting: $0) }) == foundTypeNames)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_writesIdenticalCache_whenScanningUnchangedSourcesTwice() async throws {
		let project = try await scannedKitchenSinkProject()
		let firstCache = try Data(contentsOf: project.cacheURL)

		try await project.scan()

		#expect(try Data(contentsOf: project.cacheURL) == firstCache)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scanCache_writesConsultedConditionsSorted_whenFileConsultsSeveralConditions() async throws {
		// A set's iteration order is seeded per process, so two scans of the same file would write its
		// consulted conditions in different orders unless they are sorted.
		let project = try await scannedProject(files: [
			"Feature.swift": """
			#if ZETA
			import ZetaKit
			#elseif ETA
			import EtaKit
			#elseif THETA
			import ThetaKit
			#endif

			#if DELTA
			@Instantiable
			public struct Feature: Instantiable {
			    public init() {}
			}
			#elseif ALPHA && !GAMMA
			@Instantiable
			public struct OtherFeature: Instantiable {
			    public init() {}
			}
			#elseif EPSILON || BETA
			@Instantiable
			public struct LastFeature: Instantiable {
			    public init() {}
			}
			#endif
			""",
		])
		let fileScan = try #require(project.scannedModuleInfo.conditionSensitiveFileScans.first?.fileScan)
		#expect(fileScan.consultedCompilationConditions == ["ALPHA", "BETA", "DELTA", "EPSILON", "GAMMA"])
		#expect(fileScan.importOnlyConsultedCompilationConditions == ["ETA", "THETA", "ZETA"])

		for conditions in [fileScan.consultedCompilationConditions, fileScan.importOnlyConsultedCompilationConditions] {
			var setWriter = BinaryWriter()
			setWriter.write(conditions)
			var sortedWriter = BinaryWriter()
			sortedWriter.write(conditions.sorted())
			#expect(setWriter.encoded == sortedWriter.encoded)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesIdenticalCode_whetherOrNotItReadsScanCache() async throws {
		// The sources lie outside the project root, so scan names them by the absolute paths the CSV lists,
		// exactly as a fresh parse in `generate` does.
		let project = try await scannedProject(files: [
			"Root.swift": """
			import SafeDI

			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(service: Service, factory: Instantiator<Feature>) {
			        self.service = service
			        self.factory = factory
			    }

			    @Instantiated let service: Service
			    @Instantiated let factory: Instantiator<Feature>
			}
			""",
			"Service.swift": """
			import Foundation

			@Instantiable(generateMock: true)
			public final class Service: Instantiable {
			    public init() {}
			}
			""",
			"Feature.swift": """
			@Instantiable(generateMock: true)
			public struct Feature: Instantiable {
			    public init(service: Service, title: String) {
			        self.service = service
			        self.title = title
			    }

			    @Received let service: Service
			    @Forwarded let title: String
			}
			""",
		], sourcesInsideProjectRoot: false)
		// Empty every source but keep the modification time scan recorded, so `generate` succeeds only by reading the cache.
		var sourcesByPath = [String: String]()
		for path in project.sourcePaths {
			sourcesByPath[path] = try String(contentsOfFile: path, encoding: .utf8)
			let scannedModificationTime = try FileModificationTime(ofItemAtPath: path)
			try "".write(toFile: path, atomically: true, encoding: .utf8)
			try scannedModificationTime.apply(toItemAtPath: path)
		}
		try await project.generate()
		let codeFromCache = try project.generatedCode()

		for (path, source) in sourcesByPath {
			try source.write(toFile: path, atomically: true, encoding: .utf8)
		}
		// An empty cache cannot be read, so `generate` parses the sources afresh.
		try Data().write(to: project.cacheURL)
		try await project.generate()

		#expect(codeFromCache.count == 4)
		#expect(try project.generatedCode() == codeFromCache)
	}

	// MARK: Dumping

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_printsEverythingScanWroteAsJSON() async throws {
		let project = try await scannedKitchenSinkProject()

		let json = try Dump.parse([project.cacheURL.path]).json()

		let dumped = try JSONDecoder().decode(CachedScannedModuleInfo.self, from: Data(json.utf8))
		#expect(reflectedDescription(of: dumped) == reflectedDescription(of: project.scannedModuleInfo))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_runs_whenCacheIsReadable() async throws {
		let project = try await scannedKitchenSinkProject()

		try Dump.parse([project.cacheURL.path]).run()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenFileIsShorterThanHeader() async throws {
		try await assertDumpThrows(
			"The file is 29 bytes long, shorter than a scan cache’s header.",
			whenCacheIs: { cache in cache.prefix(29) },
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenFileIsJSONFromAnEarlierRelease() async throws {
		try await assertDumpThrows(
			"The file is not a scan cache: it does not begin with `SDSC`.",
			whenCacheIs: { cache in try JSONEncoder().encode(CachedScannedModuleInfo(scanCacheData: cache)) },
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenFormatVersionDiffers() async throws {
		try await assertDumpThrows(
			"The scan cache is in format version 2, but this SafeDITool reads format version 1.",
			whenCacheIs: { cache in
				var cache = cache
				cache[cache.startIndex + 4] = 2
				return cache
			},
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenSchemaFingerprintDiffers() async throws {
		let expected = BinaryFile.schemaFingerprint
		try await assertDumpThrows(
			"The scan cache was written by a SafeDITool whose types are laid out differently: its schema fingerprint is 0x\(String(expected ^ 1, radix: 16)), but this SafeDITool’s is 0x\(String(expected, radix: 16)).",
			whenCacheIs: { cache in
				var cache = cache
				cache[cache.startIndex + 6] ^= 1
				return cache
			},
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenFileIsCutShort() async throws {
		let project = try await scannedKitchenSinkProject()
		let cache = try Data(contentsOf: project.cacheURL)
		try cache.dropLast().write(to: project.cacheURL)

		#expect(throws: BinaryFileReadError(kind: .scanCache, reason: .bodyLengthMismatch(recorded: UInt64(cache.count - 30), actual: cache.count - 31))) {
			try Dump.parse([project.cacheURL.path]).json()
		}
		#expect("\(BinaryFileReadError(kind: .scanCache, reason: .bodyLengthMismatch(recorded: 10, actual: 9)))" == "The scan cache’s header records a body of 10 bytes, but 9 bytes follow the header.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyIsCorrupted() async throws {
		try await assertDumpThrows(
			"The scan cache’s body does not match the checksum in its header.",
			whenCacheIs: { cache in
				var cache = cache
				cache[cache.endIndex - 1] ^= 0x10
				return cache
			},
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyEndsBeforeItsValues() async throws {
		let project = try await scannedKitchenSinkProject()
		let body = Self.body(of: project.scannedModuleInfo)
		try BinaryFile.data(.scanCache, body: Array(body.dropLast())).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body ends unexpectedly at byte \(body.count - 1).", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyContinuesPastItsValues() async throws {
		let project = try await scannedKitchenSinkProject()
		let body = Self.body(of: project.scannedModuleInfo)
		try BinaryFile.data(.scanCache, body: body + [0]).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body continues past its end at byte \(body.count).", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyHoldsIntegerLongerThan64Bits() async throws {
		let project = try await scannedKitchenSinkProject()
		// The string table's count, with a continuation bit on each of ten bytes.
		try BinaryFile.data(.scanCache, body: [UInt8](repeating: 0xFF, count: 10)).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body holds an integer longer than 64 bits at byte 0.", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyCountsMoreElementsThanBytesRemain() async throws {
		let project = try await scannedKitchenSinkProject()
		// A string table of five strings, with no bytes left to hold them.
		try BinaryFile.data(.scanCache, body: [5]).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body records a count of 5 at byte 0, more than the bytes that remain.", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyRefersToStringOutsideItsTable() async throws {
		let project = try await scannedKitchenSinkProject()
		// An empty string table, then one import whose attribute is the first string.
		try BinaryFile.data(.scanCache, body: [0, 1, 0]).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body refers to string 0 at byte 2, which its string table does not hold.", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenBodyHoldsInvalidTag() async throws {
		let project = try await scannedKitchenSinkProject()
		// An empty string table; no imports, mock imports, instantiables, or configurations; then 2 where a
		// `Bool` says whether files with unexpected nodes are listed.
		try BinaryFile.data(.scanCache, body: [0, 0, 0, 0, 0, 2]).write(to: project.cacheURL)

		try assertDumpThrows("The scan cache’s body holds 2 at byte 5, which is not a tag of BooleanTag.", project: project)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dumpScanCache_explains_whenTypeNestsTooDeeply() async throws {
		let project = try await scannedProject(files: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(value: Int\(String(repeating: "?", count: 128))) {
			        self.value = value
			    }

			    @Forwarded let value: Int\(String(repeating: "?", count: 128))
			}
			""",
		])

		do {
			_ = try Dump.parse([project.cacheURL.path]).json()
			Issue.record("Did not throw error!")
		} catch let error as BinaryFileReadError {
			guard case .malformedBody(.nestedTooDeeply) = error.reason else {
				Issue.record("Unexpected error: \(error)")
				return
			}
			#expect("\(error)".hasPrefix("The scan cache’s body nests values too deeply at byte "))
		}
	}

	// MARK: Module info

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func dump_printsEverythingModuleInfoFileHoldsAsJSON() async throws {
		let upstream = try await executeSafeDIToolTest(
			swiftFileContent: [Self.upstreamServiceSource],
			filesToDelete: &filesToDelete,
		)

		let json = try Dump.parse([upstream.moduleInfoOutputPath]).json()

		let dumped = try JSONDecoder().decode(ModuleInfo.self, from: Data(json.utf8))
		#expect(dumped.instantiables.map(\.concreteInstantiable) == [.simple(name: "UpstreamService")])
		#expect(reflectedDescription(of: dumped) == reflectedDescription(of: upstream.moduleInfo))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenDependentModuleInfoFileIsCorrupted() async throws {
		let upstream = try await executeSafeDIToolTest(
			swiftFileContent: [Self.upstreamServiceSource],
			filesToDelete: &filesToDelete,
		)
		var moduleInfo = try Data(contentsOf: URL(fileURLWithPath: upstream.moduleInfoOutputPath))
		moduleInfo[moduleInfo.endIndex - 1] ^= 0x01
		try moduleInfo.write(to: URL(fileURLWithPath: upstream.moduleInfoOutputPath))

		await assertThrowsError("Could not read the SafeDI module info file at \(URL(fileURLWithPath: upstream.moduleInfoOutputPath).path): The module info file’s body does not match the checksum in its header. A different version of SafeDI most likely wrote this file, or its write was interrupted. To fix this, clean your build (in Xcode: Product > Clean Build Folder) and build again, so that the module that wrote the file regenerates it.") {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.downstreamRootSource],
				dependentModuleInfoPaths: [upstream.moduleInfoOutputPath],
				buildCombinedOutput: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenDependentModuleInfoFileIsJSONFromAnEarlierRelease() async throws {
		let upstream = try await executeSafeDIToolTest(
			swiftFileContent: [Self.upstreamServiceSource],
			filesToDelete: &filesToDelete,
		)
		try JSONEncoder().encode(upstream.moduleInfo).write(to: URL(fileURLWithPath: upstream.moduleInfoOutputPath))

		await assertThrowsError("Could not read the SafeDI module info file at \(URL(fileURLWithPath: upstream.moduleInfoOutputPath).path): The file is not a module info file: it does not begin with `SDMI`. A different version of SafeDI most likely wrote this file, or its write was interrupted. To fix this, clean your build (in Xcode: Product > Clean Build Folder) and build again, so that the module that wrote the file regenerates it.") {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.downstreamRootSource],
				dependentModuleInfoPaths: [upstream.moduleInfoOutputPath],
				buildCombinedOutput: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private static let upstreamServiceSource = """
	@Instantiable
	public struct UpstreamService: Instantiable {
	    public init() {}
	}
	"""

	private static let downstreamRootSource = """
	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init(upstreamService: UpstreamService) {
	        self.upstreamService = upstreamService
	    }

	    @Instantiated let upstreamService: UpstreamService
	}
	"""

	private var filesToDelete: [URL]

	private struct ScannedProject {
		let sourcePaths: [String]
		let swiftFileCSV: URL
		let projectRoot: URL
		let outputDirectory: URL
		let manifestFile: URL
		let scannedModuleInfo: CachedScannedModuleInfo

		var cacheURL: URL {
			scannedModuleInfoURL(forManifestPath: manifestFile.path)
		}

		func readCache() throws -> CachedScannedModuleInfo {
			try CachedScannedModuleInfo(scanCacheData: Data(contentsOf: cacheURL))
		}

		@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
		@discardableResult
		func scan() async throws -> CachedScannedModuleInfo {
			try await performScan(
				inputSourcesFile: swiftFileCSV.path,
				projectRoot: projectRoot.path,
				outputDirectory: outputDirectory.path,
				manifestFile: manifestFile.path,
			)
		}

		@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
		func generate() async throws {
			try await Generate.parse([
				swiftFileCSV.path,
				"--swift-manifest", manifestFile.path,
			]).run()
		}

		/// Every file `generate` wrote, keyed by name.
		func generatedCode() throws -> [String: Data] {
			var generatedCode = [String: Data]()
			for fileName in try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path) {
				generatedCode[fileName] = try Data(contentsOf: outputDirectory.appendingPathComponent(fileName))
			}
			return generatedCode
		}
	}

	/// The body of the scan cache that holds `scannedModuleInfo`.
	private static func body(of scannedModuleInfo: CachedScannedModuleInfo) -> [UInt8] {
		var writer = BinaryWriter()
		writer.write(scannedModuleInfo)
		return writer.encoded
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func assertDumpThrows(
		_ expectedDescription: String,
		whenCacheIs rewrite: (Data) throws -> Data,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let project = try await scannedKitchenSinkProject()
		try rewrite(Data(contentsOf: project.cacheURL)).write(to: project.cacheURL)

		try assertDumpThrows(expectedDescription, project: project, sourceLocation: sourceLocation)
	}

	private func assertDumpThrows(
		_ expectedDescription: String,
		project: ScannedProject,
		sourceLocation: SourceLocation = #_sourceLocation,
	) throws {
		let command = try Dump.parse([project.cacheURL.path])
		do {
			_ = try command.json()
			Issue.record("Did not throw error!", sourceLocation: sourceLocation)
		} catch {
			#expect(expectedDescription == "\(error)", sourceLocation: sourceLocation)
		}
	}

	/// A project whose cache holds every shape the cache can hold: each kind of type description, dependency
	/// source, and declaration, imports kept as segments, files whose scans consulted compilation conditions,
	/// and files reached through `additionalDirectoriesToInclude`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func scannedKitchenSinkProject() async throws -> ScannedProject {
		let additionalDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: additionalDirectory, withIntermediateDirectories: true)
		filesToDelete.append(additionalDirectory)
		try """
		@Instantiable
		public struct AdditionalService: Instantiable {
		    public init() {}
		}
		""".write(to: additionalDirectory.appendingPathComponent("AdditionalService.swift"), atomically: true, encoding: .utf8)
		try """
		#if FEATURE
		@Instantiable
		public struct AdditionalFeature: Instantiable {
		    public init() {}
		}
		#endif
		""".write(to: additionalDirectory.appendingPathComponent("AdditionalFeature.swift"), atomically: true, encoding: .utf8)

		return try await scannedProject(files: [
			"SafeDIConfiguration.swift": """
			import SafeDI

			#SafeDIConfiguration(
			    additionalImportedModules: ["Extra"],
			    additionalDirectoriesToInclude: ["\(additionalDirectory.path)"],
			    additionalMocksToGenerate: ["Other"],
			    mockConditionalCompilation: nil,
			)
			""",
			"Kitchen.swift": """
			@preconcurrency import Foundation
			import struct Swift.Int
			#if FEATURE
			import FeatureKit
			#endif

			@Instantiable(isRoot: true, fulfillingAdditionalTypes: [KitchenProtocol.self], generateMock: true, mockAttributes: "@MainActor")
			public final class Kitchen: Instantiable {
			    public init(
			        pantry kitchenPantry: Pantry,
			        stove: any Stove,
			        timer: Timer? = nil,
			        storage: Pantry?,
			        recipe: Recipe.Ingredient<String>,
			        mixers: [any Mixer & Sendable],
			        oven: Oven!,
			        shape: some Shape,
			        kitchenType: Kitchen.Type,
			        stoveProtocol: Stove.Protocol,
			        handler: @escaping @Sendable (Int, String) async throws -> Void,
			        nothing: (),
			        lookup: [String: Int],
			        pair: (first: Int, String),
			        unknown: ~Copyable,
			        ovenFactory: Instantiator<Oven>,
			    ) {
			        pantry = kitchenPantry
			        self.stove = stove
			        self.timer = timer
			        self.storage = storage
			        self.recipe = recipe
			        self.mixers = mixers
			        self.oven = oven
			        self.shape = shape
			        self.kitchenType = kitchenType
			        self.stoveProtocol = stoveProtocol
			        self.handler = handler
			        self.nothing = nothing
			        self.lookup = lookup
			        self.pair = pair
			        self.unknown = unknown
			        self.ovenFactory = ovenFactory
			    }

			    @Instantiated let pantry: Pantry
			    @Instantiated(fulfilledByType: "GasStove", erasedToConcreteExistential: true) let stove: any Stove
			    @Received(onlyIfAvailable: true) let timer: Timer?
			    @Received(fulfilledByDependencyNamed: "pantry", ofType: Pantry.self, erasedToConcreteExistential: false, onlyIfAvailable: true) let storage: Pantry?
			    @Forwarded let recipe: Recipe.Ingredient<String>
			    @Received let mixers: [any Mixer & Sendable]
			    @Received let oven: Oven!
			    @Received let shape: some Shape
			    @Received let kitchenType: Kitchen.Type
			    @Received let stoveProtocol: Stove.Protocol
			    @Received let handler: @Sendable (Int, String) async throws -> Void
			    @Received let nothing: ()
			    @Received let lookup: [String: Int]
			    @Received let pair: (first: Int, String)
			    @Received let unknown: ~Copyable
			    @Instantiated let ovenFactory: Instantiator<Oven>
			}
			""",
			"Pantry.swift": """
			@Instantiable(generateMock: true, customMockName: "customMock")
			public struct Pantry: Instantiable {
			    public init() {}
			    public static func customMock() -> Pantry {
			        Pantry()
			    }
			}
			""",
			"Oven.swift": """
			@Instantiable
			public actor Oven: Instantiable {
			    public init(level: Void) {
			        self.level = level
			    }

			    @Forwarded let level: Void
			}
			""",
			"Timer.swift": """
			#if FEATURE
			@Instantiable
			public struct FeatureTimer: Instantiable {
			    public init() {}
			}
			#endif

			@Instantiable
			extension Timer: Instantiable {
			    public static func instantiate() -> Timer {
			        Timer()
			    }
			}
			""",
			"Broken.swift": """
			@Instantiable
			public struct Broken: Instantiable {
			    public init() {}
			    let value: = 1
			}
			""",
		])
	}

	/// Writes `files` and scans them.
	/// - Parameter sourcesInsideProjectRoot: Whether the project root is the directory that holds `files`, so
	///   that scan names them relative to it, or another directory, so that scan names them as the CSV does.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func scannedProject(files: [String: String], sourcesInsideProjectRoot: Bool = true) async throws -> ScannedProject {
		let sourceDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
		let projectRoot = if sourcesInsideProjectRoot {
			sourceDirectory
		} else {
			URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		}
		var filePaths = [String]()
		for (fileName, content) in files.sorted(by: { $0.key < $1.key }) {
			let file = sourceDirectory.appendingPathComponent(fileName)
			try content.write(to: file, atomically: true, encoding: .utf8)
			filePaths.append(file.path)
		}
		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try filePaths.joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		filesToDelete += [sourceDirectory, swiftFileCSV, outputDirectory, manifestFile, scannedModuleInfoURL(forManifestPath: manifestFile.path)]

		let scannedModuleInfo = try await performScan(
			inputSourcesFile: swiftFileCSV.path,
			projectRoot: projectRoot.path,
			outputDirectory: outputDirectory.path,
			manifestFile: manifestFile.path,
		)
		return ScannedProject(
			sourcePaths: filePaths,
			swiftFileCSV: swiftFileCSV,
			projectRoot: projectRoot,
			outputDirectory: outputDirectory,
			manifestFile: manifestFile,
			scannedModuleInfo: scannedModuleInfo,
		)
	}
}
