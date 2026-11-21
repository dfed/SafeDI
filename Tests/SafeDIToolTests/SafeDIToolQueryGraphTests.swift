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

import ArgumentParser
import Foundation
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The `query graph` subcommand, which exports every production declaration, its dependencies, and which type
/// fulfills each type, as one JSON document.
struct SafeDIToolQueryGraphTests: ~Copyable {
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
	mutating func graph_exportsEachProductionDeclarationWithItsEdgesAndFulfillment_whenModuleResolves() async throws {
		let directory = try temporaryDirectory()
		let moduleDirectory = directory.appendingPathComponent("App")
		_ = try createSwiftFixtureFiles(atFilePaths: Self.appModule, in: moduleDirectory, alongside: [])

		let report = try await QueryGraph.parse(["--include", moduleDirectory.path]).graph()

		let path = moduleDirectory.path
		#expect(try report.json() == """
		{
		  "errors" : [

		  ],
		  "formatVersion" : 0,
		  "fulfillment" : [
		    {
		      "fulfilledBy" : "App.Cache",
		      "type" : "Cache"
		    },
		    {
		      "fulfilledBy" : "App.Clock",
		      "type" : "Clock"
		    },
		    {
		      "fulfilledBy" : "App.DefaultService",
		      "type" : "DefaultService"
		    },
		    {
		      "fulfilledBy" : "App.Log",
		      "type" : "Log"
		    },
		    {
		      "fulfilledBy" : "App.Root",
		      "type" : "Root"
		    },
		    {
		      "fulfilledBy" : "App.DefaultService",
		      "type" : "Service"
		    }
		  ],
		  "modules" : [
		    "App"
		  ],
		  "resolved" : true,
		  "types" : [
		    {
		      "declarationKind" : "extension",
		      "edges" : [

		      ],
		      "filePath" : "\(path)/Cache.swift",
		      "fulfills" : [
		        "Cache"
		      ],
		      "id" : "App.Cache",
		      "isRoot" : false,
		      "isSeam" : false,
		      "line" : 3,
		      "module" : "App",
		      "name" : "Cache"
		    },
		    {
		      "declarationKind" : "actor",
		      "edges" : [

		      ],
		      "filePath" : "\(path)/Clock.swift",
		      "fulfills" : [
		        "Clock"
		      ],
		      "id" : "App.Clock",
		      "isRoot" : false,
		      "isSeam" : false,
		      "line" : 1,
		      "module" : "App",
		      "name" : "Clock"
		    },
		    {
		      "declarationKind" : "class",
		      "edges" : [
		        {
		          "filePath" : "\(path)/DefaultService.swift",
		          "kind" : "received",
		          "label" : "cache",
		          "line" : 8,
		          "onlyIfAvailable" : true,
		          "type" : "Cache?"
		        },
		        {
		          "aliasOf" : {
		            "label" : "cache",
		            "type" : "Cache"
		          },
		          "erased" : true,
		          "filePath" : "\(path)/DefaultService.swift",
		          "kind" : "alias",
		          "label" : "anyCache",
		          "line" : 9,
		          "type" : "AnyCache"
		        }
		      ],
		      "filePath" : "\(path)/DefaultService.swift",
		      "fulfills" : [
		        "DefaultService",
		        "Service"
		      ],
		      "id" : "App.DefaultService",
		      "isRoot" : false,
		      "isSeam" : false,
		      "line" : 1,
		      "module" : "App",
		      "name" : "DefaultService"
		    },
		    {
		      "declarationKind" : "struct",
		      "edges" : [
		        {
		          "filePath" : "\(path)/Log.swift",
		          "kind" : "forwarded",
		          "label" : "name",
		          "line" : 7,
		          "type" : "String"
		        }
		      ],
		      "filePath" : "\(path)/Log.swift",
		      "fulfills" : [
		        "Log"
		      ],
		      "id" : "App.Log",
		      "isRoot" : false,
		      "isSeam" : true,
		      "line" : 1,
		      "module" : "App",
		      "name" : "Log"
		    },
		    {
		      "declarationKind" : "class",
		      "edges" : [
		        {
		          "builds" : "DefaultService",
		          "filePath" : "\(path)/Root.swift",
		          "fulfilledBy" : "App.DefaultService",
		          "kind" : "instantiated",
		          "label" : "service",
		          "line" : 12,
		          "type" : "any Service"
		        },
		        {
		          "builds" : "Log",
		          "filePath" : "\(path)/Root.swift",
		          "fulfilledBy" : "App.Log",
		          "kind" : "builder",
		          "label" : "logBuilder",
		          "line" : 13,
		          "type" : "Instantiator<Log>",
		          "wrapper" : "Instantiator"
		        },
		        {
		          "builds" : "Cache",
		          "filePath" : "\(path)/Root.swift",
		          "fulfilledBy" : "App.Cache",
		          "kind" : "lazy",
		          "label" : "cache",
		          "line" : 14,
		          "type" : "LazilyInstantiated<Cache>",
		          "wrapper" : "LazilyInstantiated"
		        },
		        {
		          "builds" : "Missing",
		          "filePath" : "\(path)/Root.swift",
		          "kind" : "instantiated",
		          "label" : "missing",
		          "line" : 15,
		          "type" : "Missing"
		        }
		      ],
		      "filePath" : "\(path)/Root.swift",
		      "fulfills" : [
		        "Root"
		      ],
		      "id" : "App.Root",
		      "isRoot" : true,
		      "isSeam" : false,
		      "line" : 3,
		      "module" : "App",
		      "name" : "Root"
		    }
		  ]
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_exportsTheSameBytes_whenModulesAreNamedInAnyOrder() async throws {
		// Twenty-four modules, each a type that builds the next one's and receives the first one's, so that a set or a
		// dictionary order reaching the output would change it on nearly every run.
		let directory = try temporaryDirectory()
		let moduleCount = 24
		var moduleDirectories = [URL]()
		for index in 0..<moduleCount {
			let moduleDirectory = directory.appendingPathComponent("Module\(index)")
			let next = index + 1 < moduleCount ? """
			    @Instantiated let next: Type\(index + 1)
			""" : ""
			_ = try createSwiftFixtureFiles(
				atFilePaths: ["Type\(index).swift": """
				@Instantiable(isRoot: \(index == 0))
				public final class Type\(index): Instantiable {
				    public init(\(index + 1 < moduleCount ? "next: Type\(index + 1)" : "")) {}
				\(next)
				    @Received(onlyIfAvailable: true) let first: Type0?
				}
				"""],
				in: moduleDirectory,
				alongside: [],
			)
			moduleDirectories.append(moduleDirectory)
		}
		let paths = moduleDirectories.map(\.path)
		// A fixed permutation that interleaves the modules.
		let interleaved = paths.enumerated().sorted { ($0.offset * 7) % moduleCount < ($1.offset * 7) % moduleCount }.map(\.element)

		let inOrder = try await QueryGraph.parse(["--include"] + paths).graph().json()
		let reversed = try await QueryGraph.parse(["--include"] + paths.reversed()).graph().json()
		let shuffled = try await QueryGraph.parse(["--include"] + interleaved).graph().json()
		let again = try await QueryGraph.parse(["--include"] + paths).graph().json()

		#expect(inOrder == reversed)
		#expect(inOrder == shuffled)
		#expect(inOrder == again)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_exportsDeclarationsWithoutFulfillment_whenTwoDeclarationsFulfillOneType() async throws {
		let directory = try temporaryDirectory()
		let moduleDirectory = directory.appendingPathComponent("App")
		_ = try createSwiftFixtureFiles(
			atFilePaths: [
				"Feature.swift": """
				@Instantiable(isRoot: true)
				public final class Feature: Instantiable {
				    public init(service: Service) {}
				    @Instantiated let service: Service
				}
				""",
				"Service.swift": """
				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
				"Twin.swift": """
				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public final class Twin: Instantiable {
				    public init() {}
				}
				""",
			],
			in: moduleDirectory,
			alongside: [],
		)

		let report = try await QueryGraph.parse(["--include", moduleDirectory.path]).graph()

		let path = moduleDirectory.path
		#expect(try report.json() == """
		{
		  "errors" : [
		    {
		      "filePath" : "\(path)/Service.swift",
		      "line" : 1,
		      "message" : "Found multiple @Instantiable types or extensions that fulfill `Service`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. Keep one, and remove `Service` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
		    },
		    {
		      "filePath" : "\(path)/Twin.swift",
		      "line" : 1,
		      "message" : "Found multiple @Instantiable types or extensions that fulfill `Service`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. Keep one, and remove `Service` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
		    }
		  ],
		  "formatVersion" : 0,
		  "fulfillment" : [

		  ],
		  "modules" : [
		    "App"
		  ],
		  "resolved" : false,
		  "types" : [
		    {
		      "declarationKind" : "class",
		      "edges" : [
		        {
		          "builds" : "Service",
		          "filePath" : "\(path)/Feature.swift",
		          "kind" : "instantiated",
		          "label" : "service",
		          "line" : 4,
		          "type" : "Service"
		        }
		      ],
		      "filePath" : "\(path)/Feature.swift",
		      "fulfills" : [
		        "Feature"
		      ],
		      "id" : "App.Feature",
		      "isRoot" : true,
		      "isSeam" : false,
		      "line" : 1,
		      "module" : "App",
		      "name" : "Feature"
		    },
		    {
		      "declarationKind" : "class",
		      "edges" : [

		      ],
		      "filePath" : "\(path)/Service.swift",
		      "fulfills" : [
		        "Service"
		      ],
		      "id" : "App.Service",
		      "isRoot" : false,
		      "isSeam" : false,
		      "line" : 1,
		      "module" : "App",
		      "name" : "Service"
		    },
		    {
		      "declarationKind" : "class",
		      "edges" : [

		      ],
		      "filePath" : "\(path)/Twin.swift",
		      "fulfills" : [
		        "Twin",
		        "Service"
		      ],
		      "id" : "App.Twin",
		      "isRoot" : false,
		      "isSeam" : false,
		      "line" : 1,
		      "module" : "App",
		      "name" : "Twin"
		    }
		  ]
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_ordersTypesAsItDoesForTheDirectory_whenModuleIsReadFromModuleInfo() async throws {
		let directory = try temporaryDirectory()
		let moduleDirectory = directory.appendingPathComponent("App")
		let fixtures = try createSwiftFixtureFiles(atFilePaths: Self.appModule, in: moduleDirectory, alongside: [])
		let filePaths = Set(fixtures.map { NormalizedFilePath($0.path).path })
		let parsed = try await parseModule(filePaths: filePaths, configurationFilePaths: filePaths, activeCompilationConditions: [])
		let moduleInfoFile = directory.appendingPathComponent("App.safedi")
		try ModuleInfoFile(module: parsed.module.moduleInfo, moduleName: "App", seamSignatures: [], view: .empty)
			.moduleInfoData
			.write(to: moduleInfoFile)

		let fromDirectory = try await QueryGraph.parse(["--include", moduleDirectory.path]).graph()
		let fromModuleInfo = try await QueryGraph.parse(["--module-info", moduleInfoFile.path]).graph()

		#expect(fromModuleInfo.types.map(\.id) == ["App.Cache", "App.Clock", "App.DefaultService", "App.Log", "App.Root"])
		#expect(fromModuleInfo.types.map(\.id) == fromDirectory.types.map(\.id))
		#expect(fromModuleInfo.fulfillment == fromDirectory.fulfillment)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesOutputOnlyWhenItsBytesChange_whenOutputIsNamed() async throws {
		let directory = try temporaryDirectory()
		let moduleDirectory = directory.appendingPathComponent("App")
		_ = try createSwiftFixtureFiles(atFilePaths: Self.appModule, in: moduleDirectory, alongside: [])
		let output = directory.appendingPathComponent("graph.json")
		let arguments = ["--include", moduleDirectory.path, "--output", output.path]

		try await QueryGraph.parse(arguments).run()
		let written = try String(contentsOf: output, encoding: .utf8)
		let printed = try await QueryGraph.parse(["--include", moduleDirectory.path]).graph().json()
		#expect(written == printed)

		// An unchanged graph leaves the file as it was.
		let past = Date(timeIntervalSince1970: 1_000_000)
		try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: output.path)
		try await QueryGraph.parse(arguments).run()
		#expect(try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date == past)

		// A changed graph rewrites it.
		try "{}".write(to: output, atomically: true, encoding: .utf8)
		try await QueryGraph.parse(arguments).run()
		#expect(try String(contentsOf: output, encoding: .utf8) == written)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_printsGraph_whenNoOutputIsNamed() async throws {
		let directory = try temporaryDirectory()
		let moduleDirectory = directory.appendingPathComponent("App")
		_ = try createSwiftFixtureFiles(atFilePaths: Self.appModule, in: moduleDirectory, alongside: [])

		try await QueryGraph.parse(["--include", moduleDirectory.path]).run()
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func run_throwsFailureExitCode_whenNoModuleIsIncluded() async throws {
		let query = try QueryGraph.parse([])

		await #expect(throws: ExitCode.failure) {
			try await query.run()
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private mutating func temporaryDirectory() throws -> URL {
		let directory = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		return directory
	}

	/// A module with every kind of edge: instantiated (through `fulfilledByType:`), a builder, a lazy value, one
	/// that no declaration fulfills, a receive only if available, an erased alias, and a forwarded value; an extension
	/// declaration, an actor, a seam, and a `mockOnly` declaration the graph leaves out.
	private static let appModule = [
		"Root.swift": """
		public protocol Service {}

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(service: any Service, logBuilder: Instantiator<Log>, cache: LazilyInstantiated<Cache>, missing: Missing) {
		        self.service = service
		        self.logBuilder = logBuilder
		        self.cache = cache
		        self.missing = missing
		    }

		    @Instantiated(fulfilledByType: "DefaultService") let service: any Service
		    @Instantiated let logBuilder: Instantiator<Log>
		    @Instantiated let cache: LazilyInstantiated<Cache>
		    @Instantiated let missing: Missing
		}
		""",
		"DefaultService.swift": """
		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class DefaultService: Service, Instantiable {
		    public init(cache: Cache?, anyCache: AnyCache) {
		        self.cache = cache
		        self.anyCache = anyCache
		    }

		    @Received(onlyIfAvailable: true) let cache: Cache?
		    @Received(fulfilledByDependencyNamed: "cache", ofType: Cache.self, erasedToConcreteExistential: true) let anyCache: AnyCache
		}
		""",
		"Log.swift": """
		@Instantiable(generateDependencyTree: true)
		public struct Log: Instantiable {
		    public init(name: String) {
		        self.name = name
		    }

		    @Forwarded let name: String
		}
		""",
		"Cache.swift": """
		public final class Cache {}

		@Instantiable
		extension Cache: Instantiable {
		    public static func instantiate() -> Cache {
		        Cache()
		    }
		}
		""",
		"Clock.swift": """
		@Instantiable
		public actor Clock: Instantiable {
		    public init() {}
		}
		""",
		"FakeClock.swift": """
		@Instantiable(mockOnly: true)
		public final class FakeClock {
		    public static func mock() -> FakeClock {
		        FakeClock()
		    }
		}
		""",
	]
}
