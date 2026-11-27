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
		  "command" : "graph",
		  "completeness" : "trees",
		  "declarations" : [
		    {
		      "constructedBy" : [
		        {
		          "declaredBy" : "App.Root",
		          "label" : "cache"
		        }
		      ],
		      "declarationKind" : "extension",
		      "dependencies" : [

		      ],
		      "filePath" : "\(path)/Cache.swift",
		      "fulfills" : [
		        "Cache"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.Cache",
		      "isReachedByRoot" : true,
		      "isRoot" : false,
		      "line" : 3,
		      "module" : "App",
		      "typeName" : "Cache"
		    },
		    {
		      "constructedBy" : [

		      ],
		      "declarationKind" : "actor",
		      "dependencies" : [

		      ],
		      "filePath" : "\(path)/Clock.swift",
		      "fulfills" : [
		        "Clock"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.Clock",
		      "isReachedByRoot" : false,
		      "isRoot" : false,
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "Clock"
		    },
		    {
		      "constructedBy" : [
		        {
		          "declaredBy" : "App.Root",
		          "label" : "service"
		        }
		      ],
		      "declarationKind" : "class",
		      "dependencies" : [
		        {
		          "filePath" : "\(path)/DefaultService.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : true,
		          "label" : "cache",
		          "line" : 8,
		          "plainType" : "Cache",
		          "provenance" : [
		            {
		              "declaredBy" : "App.Root",
		              "label" : "cache",
		              "source" : "declaration"
		            }
		          ],
		          "source" : "received",
		          "type" : "Cache?"
		        },
		        {
		          "aliasOf" : {
		            "label" : "cache",
		            "plainType" : "Cache",
		            "type" : "Cache"
		          },
		          "filePath" : "\(path)/DefaultService.swift",
		          "isErased" : true,
		          "isOnlyIfAvailable" : false,
		          "label" : "anyCache",
		          "line" : 9,
		          "plainType" : "AnyCache",
		          "provenance" : [
		            {
		              "declaredBy" : "App.Root",
		              "label" : "cache",
		              "source" : "declaration"
		            }
		          ],
		          "source" : "received",
		          "type" : "AnyCache"
		        }
		      ],
		      "filePath" : "\(path)/DefaultService.swift",
		      "fulfills" : [
		        "DefaultService",
		        "Service"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.DefaultService",
		      "isReachedByRoot" : true,
		      "isRoot" : false,
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "DefaultService"
		    },
		    {
		      "constructedBy" : [
		        {
		          "declaredBy" : "App.Root",
		          "label" : "logBuilder"
		        }
		      ],
		      "declarationKind" : "struct",
		      "dependencies" : [
		        {
		          "filePath" : "\(path)/Log.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "name",
		          "line" : 7,
		          "plainType" : "String",
		          "source" : "forwarded",
		          "type" : "String"
		        }
		      ],
		      "filePath" : "\(path)/Log.swift",
		      "fulfills" : [
		        "Log"
		      ],
		      "generatesDependencyTree" : true,
		      "id" : "App.Log",
		      "isReachedByRoot" : true,
		      "isRoot" : false,
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "Log"
		    },
		    {
		      "constructedBy" : [

		      ],
		      "declarationKind" : "class",
		      "dependencies" : [
		        {
		          "filePath" : "\(path)/Root.swift",
		          "fulfilledBy" : "App.DefaultService",
		          "fulfilledByType" : "DefaultService",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "service",
		          "lifetime" : "eager",
		          "line" : 11,
		          "plainType" : "Service",
		          "source" : "instantiated",
		          "type" : "any Service"
		        },
		        {
		          "filePath" : "\(path)/Root.swift",
		          "fulfilledBy" : "App.Log",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "logBuilder",
		          "lifetime" : "builder",
		          "line" : 12,
		          "plainType" : "Log",
		          "source" : "instantiated",
		          "type" : "Instantiator<Log>",
		          "wrapper" : "Instantiator"
		        },
		        {
		          "filePath" : "\(path)/Root.swift",
		          "fulfilledBy" : "App.Cache",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "cache",
		          "lifetime" : "lazy",
		          "line" : 13,
		          "plainType" : "Cache",
		          "source" : "instantiated",
		          "type" : "LazilyInstantiated<Cache>",
		          "wrapper" : "LazilyInstantiated"
		        }
		      ],
		      "filePath" : "\(path)/Root.swift",
		      "fulfills" : [
		        "Root"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.Root",
		      "isReachedByRoot" : true,
		      "isRoot" : true,
		      "line" : 3,
		      "module" : "App",
		      "typeName" : "Root"
		    }
		  ],
		  "errors" : [

		  ],
		  "formatVersion" : 0,
		  "fulfillments" : [
		    {
		      "fulfilledBy" : "App.Cache",
		      "plainType" : "Cache"
		    },
		    {
		      "fulfilledBy" : "App.Clock",
		      "plainType" : "Clock"
		    },
		    {
		      "fulfilledBy" : "App.DefaultService",
		      "plainType" : "DefaultService"
		    },
		    {
		      "fulfilledBy" : "App.Log",
		      "plainType" : "Log"
		    },
		    {
		      "fulfilledBy" : "App.Root",
		      "plainType" : "Root"
		    },
		    {
		      "fulfilledBy" : "App.DefaultService",
		      "plainType" : "Service"
		    }
		  ],
		  "modules" : [
		    {
		      "name" : "App",
		      "paths" : [
		        "\(path)"
		      ]
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
		  "command" : "graph",
		  "completeness" : "declarations",
		  "declarations" : [
		    {
		      "declarationKind" : "class",
		      "dependencies" : [
		        {
		          "filePath" : "\(path)/Feature.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "service",
		          "lifetime" : "eager",
		          "line" : 4,
		          "plainType" : "Service",
		          "source" : "instantiated",
		          "type" : "Service"
		        }
		      ],
		      "filePath" : "\(path)/Feature.swift",
		      "fulfills" : [
		        "Feature"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.Feature",
		      "isRoot" : true,
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "Feature"
		    },
		    {
		      "declarationKind" : "class",
		      "dependencies" : [

		      ],
		      "filePath" : "\(path)/Service.swift",
		      "fulfills" : [
		        "Service"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.Service",
		      "isRoot" : false,
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "Service"
		    },
		    {
		      "declarationKind" : "class",
		      "dependencies" : [

		      ],
		      "filePath" : "\(path)/Twin.swift",
		      "fulfills" : [
		        "Twin",
		        "Service"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.Twin",
		      "isRoot" : false,
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "Twin"
		    }
		  ],
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
		  "fulfillments" : [

		  ],
		  "modules" : [
		    {
		      "name" : "App",
		      "paths" : [
		        "\(path)"
		      ]
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
	mutating func graph_namesDeclarationsEnclosingFunctionsCallsPass_whenLazyCycleCallPassesParameterOfEnclosingFunction() async throws {
		// `B`'s builder function takes `theme`, which `Mid` declares before closing the cycle on it, and is declared in the body
		// of `A`'s, which takes `theme` too, since `X` declares it before closing the cycle on `A`: `A`'s function passes its
		// parameter on to `B`'s, so `B` is handed what `Shell` and `X`'s cycle-closing scope pass `A`'s, and what `Mid` passes.
		let report = try await graph(of: [
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: Instantiator<B>, xBuilder: Instantiator<X>) {
			        self.bBuilder = bBuilder
			        self.xBuilder = xBuilder
			    }

			    @Instantiated let bBuilder: Instantiator<B>
			    @Instantiated let xBuilder: Instantiator<X>
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(theme: Theme, midBuilder: Instantiator<Mid>) {
			        self.theme = theme
			        self.midBuilder = midBuilder
			    }

			    @Received let theme: Theme
			    @Instantiated let midBuilder: Instantiator<Mid>
			}
			""",
			"Mid.swift": """
			@Instantiable
			public final class Mid: Instantiable {
			    public init(theme: Theme, bBuilder: Instantiator<B>) {
			        self.theme = theme
			        self.bBuilder = bBuilder
			    }

			    @Forwarded let theme: Theme
			    @Instantiated let bBuilder: Instantiator<B>
			}
			""",
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(shellBuilder: Instantiator<Shell>) {
			        self.shellBuilder = shellBuilder
			    }

			    @Instantiated let shellBuilder: Instantiator<Shell>
			}
			""",
			"Shell.swift": """
			@Instantiable
			public final class Shell: Instantiable {
			    public init(theme: Theme, aBuilder: Instantiator<A>) {
			        self.theme = theme
			        self.aBuilder = aBuilder
			    }

			    @Forwarded let theme: Theme
			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
			"Theme.swift": """
			public struct Theme {}
			""",
			"X.swift": """
			@Instantiable
			public final class X: Instantiable {
			    public init(theme: Theme, aBuilder: Instantiator<A>) {
			        self.theme = theme
			        self.aBuilder = aBuilder
			    }

			    @Forwarded let theme: Theme
			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
		])

		#expect(Self.supplies(in: report) == [
			"App.B.theme": "App.Mid.theme, App.Shell.theme, App.X.theme",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_recordsNilProvenance_whenLazyCyclePassesNilFromOneCall() async throws {
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
			"App.Screen.session": "App.Step.session, nil(noProvidingDeclaration)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_recordsNilProvenance_whenSiblingThatDeclaresReceiveIsBuiltAfterReceiver() async throws {
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
			"App.B.c": "nil(providerNotYetBuilt)",
			"App.C.b": "App.Root.b",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesAliasInProvenance_whenReceiveReadsAliasDeclaredAbove() async throws {
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
	mutating func graph_namesDeclarationAboveInAliasProvenance_whenAliasKeepsLabelItRetypes() async throws {
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
	mutating func graph_leavesProvenanceOut_whenNoRootBuildsType() async throws {
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

		#expect(report.completeness == .trees)
		#expect(report.declarations.first { $0.typeName == "Unreached" }?.isReachedByRoot == false)
		#expect(report.declarations.flatMap(\.dependencies).filter { $0.source == .received }.map(\.provenance) == [nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksInstantiatedDependencyOnlyIfAvailable_whetherOrNotADeclarationFulfillsItsType() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(cache: Cache?, missing: Missing?, reader: Reader, service: Service) {
			        self.cache = cache
			        self.missing = missing
			        self.reader = reader
			        self.service = service
			    }

			    @Instantiated(onlyIfAvailable: true) let cache: Cache?
			    @Instantiated(onlyIfAvailable: true) let missing: Missing?
			    @Instantiated let reader: Reader
			    @Instantiated let service: Service
			}
			""",
			"Cache.swift": """
			@Instantiable
			public final class Cache: Instantiable {
			    public init() {}
			}
			""",
			"Missing.swift": """
			public protocol Missing {}
			""",
			"Reader.swift": """
			@Instantiable
			public final class Reader: Instantiable {
			    public init(cache: Cache?, missing: Missing?) {
			        self.cache = cache
			        self.missing = missing
			    }

			    @Received(onlyIfAvailable: true) let cache: Cache?
			    @Received(onlyIfAvailable: true) let missing: Missing?
			}
			""",
			"Service.swift": """
			@Instantiable
			public final class Service: Instantiable {
			    public init() {}
			}
			""",
		])

		let rootDependencies = try #require(report.declarations.first { $0.typeName == "Root" }).dependencies
		#expect(report.completeness == .trees)
		#expect(report.errors.isEmpty)
		#expect(rootDependencies.map(\.label) == ["cache", "missing", "reader", "service"])
		#expect(rootDependencies.map(\.isOnlyIfAvailable) == [true, true, false, false])
		#expect(rootDependencies.map(\.fulfilledBy) == ["App.Cache", nil, "App.Reader", "App.Service"])
		#expect(Self.supplies(in: report) == ["App.Reader.cache": "App.Root.cache", "App.Reader.missing": "App.Root.missing"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsTreeErrorWithoutProvenance_whenTreeInstantiatesTypeNoDeclarationFulfills() async throws {
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

		#expect(report.completeness == .fulfillment)
		#expect(report.errors.map(\.line) == [9])
		#expect(report.errors.map(\.message).allSatisfy { $0.hasPrefix("No @Instantiable type or extension fulfills `Missing`") })
		#expect(report.declarations.flatMap(\.dependencies).map(\.provenance) == [nil, nil, nil])
		#expect(report.declarations.map(\.isReachedByRoot) == [nil, nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_countsEdgesNotPaths_whenScreensOpenScreensOfTheNextLayer() async throws {
		// Layers of four screens, each holding instantiators of three screens of the next layer and receiving `service`,
		// under a root that declares `service` and builds the first layer, so the last layer is reached along
		// 4 × 3^(layers - 1) paths. The fold reads the per-type graph, where a node stands for every place of its
		// declaration: one pass over each edge, 1 + 4 + 12 × (layers - 1), and each declaration a screen's receive can read,
		// one root edge for each of the first layer, three for each of the second and four for each later one, so 24 + 32
		// more with each two layers. The walk it replaced entered every path: at four and six layers, 162 and 1,458 visits.
		let visits = try await supplyVisitsInLayersOfScreens()
		#expect(visits == [89, 145])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_handsEveryScreenRootsService_whenScreensOpenScreensOfTheNextLayer() async throws {
		// The layers of screens above, at four layers: a screen the fold reads once, as one node, still has the value
		// every place of it is handed.
		let report = try await graphOfLayersOfScreens(layerCount: 4)

		var expectedSupplies = [String: String]()
		for layer in 0..<4 {
			for position in 0..<4 {
				expectedSupplies["App.Screen\(layer)x\(position).service"] = "App.Root.service"
			}
		}
		#expect(report.completeness == .trees)
		#expect(Self.supplies(in: report) == expectedSupplies)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsPropertysPlainType_whenInstantiatedDependencyIsFulfilledByAnotherType() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(service: any Service, serviceBuilder: Instantiator<any Service>) {
			        self.service = service
			        self.serviceBuilder = serviceBuilder
			    }

			    @Instantiated(fulfilledByType: "DefaultService") let service: any Service
			    @Instantiated(fulfilledByType: "DefaultService") let serviceBuilder: Instantiator<any Service>
			}
			""",
			"DefaultService.swift": """
			public protocol Service {}

			@Instantiable(fulfillingAdditionalTypes: [Service.self])
			public final class DefaultService: Service, Instantiable {
			    public init() {}
			}
			""",
		])

		let dependencies = report.declarations.first { $0.typeName == "Root" }?.dependencies ?? []
		#expect(dependencies.map(\.plainType) == ["Service", "Service"])
		#expect(dependencies.map(\.fulfilledByType) == ["DefaultService", "DefaultService"])
		#expect(dependencies.map(\.fulfilledBy) == ["App.DefaultService", "App.DefaultService"])
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

		#expect(fromModuleInfo.declarations.map(\.id) == ["App.Cache", "App.Clock", "App.DefaultService", "App.Log", "App.Root"])
		#expect(fromModuleInfo.declarations.map(\.id) == fromDirectory.declarations.map(\.id))
		#expect(fromModuleInfo.fulfillments == fromDirectory.fulfillments)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_exportsEveryModule_whenManyModulesAreReadFromDirectoriesOrModuleInfo() async throws {
		// Forty modules, read in parallel both ways. Release builds of SafeDITool 2.3.1 by Swift 6.3 with `-Osize`, by
		// Swift 6.4.1 and 6.4.2 on Linux, and by Xcode 26.4 miscompiled the task groups that read them, and exported no
		// module or crashed. This build's compiler may not show that miscompile; the release binary's check in CI does.
		let directory = try temporaryDirectory()
		let moduleCount = 40
		var moduleDirectories = [URL]()
		var moduleInfoFiles = [URL]()
		for index in 0..<moduleCount {
			let moduleName = "Module\(index)"
			let moduleDirectory = directory.appendingPathComponent(moduleName)
			let fixtures = try createSwiftFixtureFiles(
				atFilePaths: ["Type\(index).swift": """
				@Instantiable
				public final class Type\(index): Instantiable {
				    public init() {}
				}
				"""],
				in: moduleDirectory,
				alongside: [],
			)
			let filePaths = Set(fixtures.map { NormalizedFilePath($0.path).path })
			let parsed = try await parseModule(filePaths: filePaths, configurationFilePaths: filePaths, activeCompilationConditions: [])
			let moduleInfoFile = directory.appendingPathComponent("\(moduleName).safedi")
			try ModuleInfoFile(module: parsed.module.moduleInfo, moduleName: moduleName, seamSignatures: [], view: .empty)
				.moduleInfoData
				.write(to: moduleInfoFile)
			moduleDirectories.append(moduleDirectory)
			moduleInfoFiles.append(moduleInfoFile)
		}
		let expectedIDs = (0..<moduleCount).map { "Module\($0).Type\($0)" }.sorted()

		let fromDirectories = try await QueryGraph.parse(["--include"] + moduleDirectories.map(\.path)).graph()
		let fromModuleInfo = try await QueryGraph.parse(["--module-info"] + moduleInfoFiles.map(\.path)).graph()

		#expect(fromDirectories.declarations.map(\.id).sorted() == expectedIDs)
		#expect(fromModuleInfo.declarations.map(\.id).sorted() == expectedIDs)
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

	/// The export of a module of `layerCount` layers of four screens, each holding instantiators of three screens of the
	/// next layer, with `screenDeclarations` of its layer and position, beside `otherTypes`, under a root that declares
	/// `rootDeclarations` and an instantiator of each screen of the first layer.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func graphOfLayersOfScreens(
		layerCount: Int,
		rootDeclarations: [FixtureProperty] = [FixtureProperty("@Instantiated", "service", "Service")],
		screenDeclarations: (_ layer: Int, _ position: Int) -> [FixtureProperty] = { _, _ in [FixtureProperty("@Received", "service", "Service")] },
		otherTypes: [String] = [Self.fixtureType(named: "Service", properties: [])],
	) async throws -> QueryGraphReport {
		var types = otherTypes
		types.append(Self.fixtureType(
			named: "Root",
			isRoot: true,
			properties: rootDeclarations + (0..<4).map { FixtureProperty("@Instantiated", "screen0x\($0)Builder", "Instantiator<Screen0x\($0)>") },
		))
		for layer in 0..<layerCount {
			for position in 0..<4 {
				var properties = screenDeclarations(layer, position)
				if layer + 1 < layerCount {
					properties += (0..<3).map { offset in
						FixtureProperty("@Instantiated", "screen\(layer + 1)x\((position + offset) % 4)Builder", "Instantiator<Screen\(layer + 1)x\((position + offset) % 4)>")
					}
				}
				types.append(Self.fixtureType(named: "Screen\(layer)x\(position)", properties: properties))
			}
		}
		return try await graph(of: ["Screens.swift": types.joined(separator: "\n\n")])
	}

	/// The work of the fold that reads the value each receive is handed (`GenerationWork.Step.findingReceivedValueSupplies`)
	/// as `query graph` exports `graphOfLayersOfScreens`, at four and at six layers.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func supplyVisitsInLayersOfScreens(
		rootDeclarations: [FixtureProperty] = [FixtureProperty("@Instantiated", "service", "Service")],
		screenDeclarations: (_ layer: Int, _ position: Int) -> [FixtureProperty] = { _, _ in [FixtureProperty("@Received", "service", "Service")] },
		otherTypes: [String] = [Self.fixtureType(named: "Service", properties: [])],
	) async throws -> [Int] {
		var visitsByLayerCount = [Int]()
		for layerCount in [4, 6] {
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
				_ = try await graphOfLayersOfScreens(layerCount: layerCount, rootDeclarations: rootDeclarations, screenDeclarations: screenDeclarations, otherTypes: otherTypes)
			}
			continuation.finish()
			var visits = 0
			for await work in stream where work.step == .findingReceivedValueSupplies {
				visits += work.elementCount
			}
			visitsByLayerCount.append(visits)
		}
		return visitsByLayerCount
	}

	/// A property of a fixture's type: its macro, as written, its label and its type.
	private struct FixtureProperty {
		init(_ attribute: String, _ label: String, _ type: String) {
			self.attribute = attribute
			self.label = label
			self.type = type
		}

		let attribute: String
		let label: String
		let type: String
	}

	/// The source of an `@Instantiable` class `name` that declares `properties`, with the initializer they need.
	private static func fixtureType(named name: String, isRoot: Bool = false, properties: [FixtureProperty]) -> String {
		"""
		@Instantiable\(isRoot ? "(isRoot: true)" : "")
		public final class \(name): Instantiable {
		    public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
		\(properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
		    }

		\(properties.map { "    \($0.attribute) let \($0.label): \($0.type)" }.joined(separator: "\n"))
		}
		"""
	}

	/// The provenance of each received dependency or alias of `report` that has one, by `<declaration id>.<label>`: each
	/// declaration as `<declaration id>.<label>`, then each `nil` as `nil(<reason kind>)`, joined.
	private static func supplies(in report: QueryGraphReport) -> [String: String] {
		var supplies = [String: String]()
		for declaration in report.declarations {
			for dependency in declaration.dependencies {
				guard let provenance = dependency.provenance else { continue }
				supplies["\(declaration.id).\(dependency.label)"] = provenance.map { entry in
					switch entry {
					case let .declaration(declaredBy, label):
						"\(declaredBy).\(label)"
					case let .passedNil(reason):
						"nil(\(reason.kind.rawValue))"
					}
				}.joined(separator: ", ")
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
