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
		  "treesBuilt" : true,
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
		          "suppliers" : [
		            {
		              "label" : "cache",
		              "type" : "App.Root"
		            }
		          ],
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
		          "suppliers" : [
		            {
		              "label" : "cache",
		              "type" : "App.Root"
		            }
		          ],
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
		          "line" : 11,
		          "type" : "any Service"
		        },
		        {
		          "builds" : "Log",
		          "filePath" : "\(path)/Root.swift",
		          "fulfilledBy" : "App.Log",
		          "kind" : "builder",
		          "label" : "logBuilder",
		          "line" : 12,
		          "type" : "Instantiator<Log>",
		          "wrapper" : "Instantiator"
		        },
		        {
		          "builds" : "Cache",
		          "filePath" : "\(path)/Root.swift",
		          "fulfilledBy" : "App.Cache",
		          "kind" : "lazy",
		          "label" : "cache",
		          "line" : 13,
		          "type" : "LazilyInstantiated<Cache>",
		          "wrapper" : "LazilyInstantiated"
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
		  "treesBuilt" : false,
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
	mutating func graph_listsEveryDeclarationACallPasses_whenLazyCycleBuildsReceiverAgainBeneathAnotherDeclaration() async throws {
		// A flow instantiates a per-step session: the screen a step builds again receives the step's session, not the app's,
		// and so does the screen's alias of it.
		let report = try await graph(of: [
			"App.swift": """
			@Instantiable(isRoot: true)
			public final class App: Instantiable {
			    public init(session: Session, screenBuilder: Instantiator<Screen>) {
			        self.session = session
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated let session: Session
			    @Instantiated let screenBuilder: Instantiator<Screen>
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(session: Session, currentSession: Session, stepBuilder: Instantiator<Step>) {
			        self.session = session
			        self.currentSession = currentSession
			        self.stepBuilder = stepBuilder
			    }

			    @Received let session: Session
			    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self) let currentSession: Session
			    @Instantiated let stepBuilder: Instantiator<Step>
			}
			""",
			"Step.swift": """
			@Instantiable
			public final class Step: Instantiable {
			    public init(session: Session, screenBuilder: Instantiator<Screen>) {
			        self.session = session
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated let session: Session
			    @Instantiated let screenBuilder: Instantiator<Screen>
			}
			""",
			"Session.swift": """
			@Instantiable
			public final class Session: Instantiable {
			    public init() {}
			}
			""",
		])

		#expect(Self.supplies(in: report) == [
			"App.Screen.currentSession": "App.App.session, App.Step.session",
			"App.Screen.session": "App.App.session, App.Step.session",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesLoopMemberEachCallPasses_whenLoopOfBuildersMemberTakesLazyCycleParameter() async throws {
		// The editor's and the preview's builders receive each other, a loop of builders, and the sheet builds both again,
		// so the editor's builder function takes the preview's builder as a parameter. Each loop hands it through a function
		// that passes the preview's builder made again, though the editor's own receive of it is generated before it.
		let report = try await graph(of: [
			"App.swift": """
			@Instantiable(isRoot: true)
			public final class App: Instantiable {
			    public init(editorBuilder: Instantiator<Editor>, previewBuilder: Instantiator<Preview>) {
			        self.editorBuilder = editorBuilder
			        self.previewBuilder = previewBuilder
			    }

			    @Instantiated let editorBuilder: Instantiator<Editor>
			    @Instantiated let previewBuilder: Instantiator<Preview>
			}
			""",
			"Editor.swift": """
			@Instantiable
			public final class Editor: Instantiable {
			    public init(previewBuilder: Instantiator<Preview>?, sheetBuilder: Instantiator<Sheet>) {
			        self.previewBuilder = previewBuilder
			        self.sheetBuilder = sheetBuilder
			    }

			    @Received(onlyIfAvailable: true) let previewBuilder: Instantiator<Preview>?
			    @Instantiated let sheetBuilder: Instantiator<Sheet>
			}
			""",
			"Preview.swift": """
			@Instantiable
			public final class Preview: Instantiable {
			    public init(editorBuilder: Instantiator<Editor>) {
			        self.editorBuilder = editorBuilder
			    }

			    @Received let editorBuilder: Instantiator<Editor>
			}
			""",
			"Sheet.swift": """
			@Instantiable
			public final class Sheet: Instantiable {
			    public init(editorBuilder: Instantiator<Editor>, previewBuilder: Instantiator<Preview>) {
			        self.editorBuilder = editorBuilder
			        self.previewBuilder = previewBuilder
			    }

			    @Instantiated let editorBuilder: Instantiator<Editor>
			    @Instantiated let previewBuilder: Instantiator<Preview>
			}
			""",
		])

		#expect(Self.supplies(in: report) == [
			"App.Editor.previewBuilder": "App.App.previewBuilder, App.Sheet.previewBuilder",
			"App.Preview.editorBuilder": "App.App.editorBuilder, App.Sheet.editorBuilder",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesLoopMembersRenameEachCallPasses_whenLoopOfBuildersMemberTakesRenameAsLazyCycleParameter() async throws {
		// As above, but the editor receives a rename of the preview's builder, which each loop makes again of the preview's
		// builder function and hands the editor's.
		let report = try await graph(of: [
			"App.swift": """
			@Instantiable(isRoot: true)
			public final class App: Instantiable {
			    public init(editorBuilder: Instantiator<Editor>, previewBuilder: Instantiator<Preview>, draftPreviewBuilder: Instantiator<Preview>) {
			        self.editorBuilder = editorBuilder
			        self.previewBuilder = previewBuilder
			        self.draftPreviewBuilder = draftPreviewBuilder
			    }

			    @Instantiated let editorBuilder: Instantiator<Editor>
			    @Instantiated let previewBuilder: Instantiator<Preview>
			    @Received(fulfilledByDependencyNamed: "previewBuilder", ofType: Instantiator<Preview>.self) let draftPreviewBuilder: Instantiator<Preview>
			}
			""",
			"Editor.swift": """
			@Instantiable
			public final class Editor: Instantiable {
			    public init(draftPreviewBuilder: Instantiator<Preview>?, sheetBuilder: Instantiator<Sheet>) {
			        self.draftPreviewBuilder = draftPreviewBuilder
			        self.sheetBuilder = sheetBuilder
			    }

			    @Received(onlyIfAvailable: true) let draftPreviewBuilder: Instantiator<Preview>?
			    @Instantiated let sheetBuilder: Instantiator<Sheet>
			}
			""",
			"Preview.swift": """
			@Instantiable
			public final class Preview: Instantiable {
			    public init(editorBuilder: Instantiator<Editor>) {
			        self.editorBuilder = editorBuilder
			    }

			    @Received let editorBuilder: Instantiator<Editor>
			}
			""",
			"Sheet.swift": """
			@Instantiable
			public final class Sheet: Instantiable {
			    public init(editorBuilder: Instantiator<Editor>, previewBuilder: Instantiator<Preview>, draftPreviewBuilder: Instantiator<Preview>) {
			        self.editorBuilder = editorBuilder
			        self.previewBuilder = previewBuilder
			        self.draftPreviewBuilder = draftPreviewBuilder
			    }

			    @Instantiated let editorBuilder: Instantiator<Editor>
			    @Instantiated let previewBuilder: Instantiator<Preview>
			    @Received(fulfilledByDependencyNamed: "previewBuilder", ofType: Instantiator<Preview>.self) let draftPreviewBuilder: Instantiator<Preview>
			}
			""",
		])

		#expect(Self.supplies(in: report) == [
			"App.App.draftPreviewBuilder": "App.App.previewBuilder",
			"App.Editor.draftPreviewBuilder": "App.App.draftPreviewBuilder, App.Sheet.draftPreviewBuilder",
			"App.Preview.editorBuilder": "App.App.editorBuilder, App.Sheet.editorBuilder",
			"App.Sheet.draftPreviewBuilder": "App.Sheet.previewBuilder",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksReceivesNil_whenLazyCyclePassesNilFromOneCall() async throws {
		// The app declares no session, so its call of the screen's builder function passes `nil`; the step's passes its own.
		let report = try await graph(of: [
			"App.swift": """
			@Instantiable(isRoot: true)
			public final class App: Instantiable {
			    public init(screenBuilder: Instantiator<Screen>) {
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated let screenBuilder: Instantiator<Screen>
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(session: Session?, stepBuilder: Instantiator<Step>) {
			        self.session = session
			        self.stepBuilder = stepBuilder
			    }

			    @Received(onlyIfAvailable: true) let session: Session?
			    @Instantiated let stepBuilder: Instantiator<Step>
			}
			""",
			"Step.swift": """
			@Instantiable
			public final class Step: Instantiable {
			    public init(session: Session, screenBuilder: Instantiator<Screen>) {
			        self.session = session
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated let session: Session
			    @Instantiated let screenBuilder: Instantiator<Screen>
			}
			""",
			"Session.swift": """
			@Instantiable
			public final class Session: Instantiable {
			    public init() {}
			}
			""",
		])

		#expect(Self.supplies(in: report) == [
			"App.Screen.session": "App.Step.session, nil",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksReceivesNil_whenSiblingThatDeclaresReceiveIsBuiltAfterReceiver() async throws {
		// `c` receives `b`, so `b` is built first, and its receive of `c` only if available is handed `nil`.
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(b: B, c: C) {
			        self.b = b
			        self.c = c
			    }

			    @Instantiated let b: B
			    @Instantiated let c: C
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(c: C?) {
			        self.c = c
			    }

			    @Received(onlyIfAvailable: true) let c: C?
			}
			""",
			"C.swift": """
			@Instantiable
			public final class C: Instantiable {
			    public init(b: B) {
			        self.b = b
			    }

			    @Received let b: B
			}
			""",
		])

		#expect(Self.supplies(in: report) == [
			"App.B.c": "nil",
			"App.C.b": "App.Root.b",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesAliasAsSupplier_whenReceiveReadsAliasDeclaredAbove() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(service: Service, feature: Feature) {
			        self.service = service
			        self.feature = feature
			    }

			    @Instantiated let service: Service
			    @Instantiated let feature: Feature
			}
			""",
			"Feature.swift": """
			@Instantiable
			public final class Feature: Instantiable {
			    public init(renamedService: Service, screen: Screen) {
			        self.renamedService = renamedService
			        self.screen = screen
			    }

			    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let renamedService: Service
			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(renamedService: Service) {
			        self.renamedService = renamedService
			    }

			    @Received let renamedService: Service
			}
			""",
			"Service.swift": """
			@Instantiable
			public final class Service: Instantiable {
			    public init() {}
			}
			""",
		])

		#expect(Self.supplies(in: report) == [
			"App.Feature.renamedService": "App.Root.service",
			"App.Screen.renamedService": "App.Feature.renamedService",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesDeclarationAboveAsAliasSupplier_whenAliasKeepsLabelItRetypes() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(service: Service, feature: Feature) {
			        self.service = service
			        self.feature = feature
			    }

			    @Instantiated let service: Service
			    @Instantiated let feature: Feature
			}
			""",
			"Feature.swift": """
			@Instantiable
			public final class Feature: Instantiable {
			    public init(service: any ServiceProtocol, screen: Screen) {
			        self.service = service
			        self.screen = screen
			    }

			    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let service: any ServiceProtocol
			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(service: any ServiceProtocol) {
			        self.service = service
			    }

			    @Received let service: any ServiceProtocol
			}
			""",
			"Service.swift": """
			public protocol ServiceProtocol {}

			@Instantiable
			public final class Service: Instantiable, ServiceProtocol {
			    public init() {}
			}
			""",
		])

		#expect(Self.supplies(in: report) == [
			"App.Feature.service": "App.Root.service",
			"App.Screen.service": "App.Feature.service",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_leavesSuppliersOut_whenNoRootBuildsType() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(service: Service) {
			        self.service = service
			    }

			    @Instantiated let service: Service
			}
			""",
			"Service.swift": """
			@Instantiable
			public final class Service: Instantiable {
			    public init() {}
			}
			""",
			"Unreached.swift": """
			@Instantiable
			public final class Unreached: Instantiable {
			    public init(service: Service) {
			        self.service = service
			    }

			    @Received let service: Service
			}
			""",
		])

		#expect(report.treesBuilt)
		#expect(report.types.flatMap(\.edges).filter { $0.kind == .received }.map(\.suppliers) == [nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsTreeErrorWithoutSuppliers_whenTreeInstantiatesTypeNoDeclarationFulfills() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(service: Service, missing: Missing) {
			        self.service = service
			        self.missing = missing
			    }

			    @Instantiated let service: Service
			    @Instantiated let missing: Missing
			}
			""",
			"Service.swift": """
			@Instantiable
			public final class Service: Instantiable {
			    public init(missing: Missing) {
			        self.missing = missing
			    }

			    @Received let missing: Missing
			}
			""",
		])

		#expect(report.resolved)
		#expect(!report.treesBuilt)
		#expect(report.errors.map(\.line) == [9])
		#expect(report.errors.map(\.message).allSatisfy { $0.hasPrefix("No @Instantiable type or extension fulfills `Missing`") })
		#expect(report.types.flatMap(\.edges).map(\.suppliers) == [nil, nil, nil])
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

	/// The export of one module, `App`, of the files `filesByName` holds.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func graph(of filesByName: [String: String]) async throws -> QueryGraphReport {
		let moduleDirectory = try temporaryDirectory().appendingPathComponent("App")
		_ = try createSwiftFixtureFiles(atFilePaths: filesByName, in: moduleDirectory, alongside: [])
		return try await QueryGraph.parse(["--include", moduleDirectory.path]).graph()
	}

	/// What each received edge or alias of `report` that has suppliers is handed, by `<type id>.<label>`: its suppliers as
	/// `<type id>.<label>`, then `nil` where it receives `nil`, joined.
	private static func supplies(in report: QueryGraphReport) -> [String: String] {
		var supplies = [String: String]()
		for type in report.types {
			for edge in type.edges {
				guard let suppliers = edge.suppliers else { continue }
				supplies["\(type.id).\(edge.label)"] = (suppliers.map { "\($0.type).\($0.label)" } + (edge.receivesNil == true ? ["nil"] : [])).joined(separator: ", ")
			}
		}
		return supplies
	}

	private mutating func temporaryDirectory() throws -> URL {
		let directory = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		return directory
	}

	/// A module with every kind of edge: instantiated (through `fulfilledByType:`), a builder, a lazy value, a
	/// receive only if available, an erased alias, and a forwarded value; an extension
	/// declaration, an actor, a seam, and a `mockOnly` declaration the graph leaves out.
	private static let appModule = [
		"Root.swift": """
		public protocol Service {}

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(service: any Service, logBuilder: Instantiator<Log>, cache: LazilyInstantiated<Cache>) {
		        self.service = service
		        self.logBuilder = logBuilder
		        self.cache = cache
		    }

		    @Instantiated(fulfilledByType: "DefaultService") let service: any Service
		    @Instantiated let logBuilder: Instantiator<Log>
		    @Instantiated let cache: LazilyInstantiated<Cache>
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
