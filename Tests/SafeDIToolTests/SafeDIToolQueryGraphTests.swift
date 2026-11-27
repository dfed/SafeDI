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
		#expect(Self.supplies(in: report) == ["App.Reader.cache": "App.Root.cache", "App.Reader.missing": "nil(declarationNotInstantiated: App.Root.missing)"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsProvenanceFromTreesBuiltAroundUnfulfilledDependencies_whenTreeInstantiatesTypeNoDeclarationFulfills() async throws {
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

		#expect(report.completeness == .partialTrees)
		#expect(report.errors.map(\.line) == [9])
		#expect(report.errors.map(\.message).allSatisfy { $0.hasPrefix("No @Instantiable type or extension fulfills `Missing`") })
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, true, nil])
		#expect(Self.supplies(in: report) == ["App.Service.missing": "unfulfilled(App.Root.missing)"])
		#expect(report.declarations.map(\.isReachedByRoot) == [true, true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsProvenanceOfEveryOtherReceive_whenOneReceiveIsUnfulfilled() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(session: Session, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated let session: Session
			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			public final class Missing {}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(session: Session, missing: Missing) {
			        self.session = session
			        self.missing = missing
			    }

			    @Received let session: Session
			    @Received let missing: Missing
			}
			""",
			"Session.swift": """
			@Instantiable
			public final class Session: Instantiable {
			    public init() {}
			}
			""",
		])

		let screen = try #require(report.declarations.first { $0.typeName == "Screen" })
		#expect(report.completeness == .partialTrees)
		#expect(report.errors.count == 1)
		#expect(screen.dependencies.map(\.isUnfulfilled) == [nil, true])
		#expect(Self.supplies(in: report) == ["App.Screen.session": "App.Root.session", "App.Screen.missing": "unfulfilled"])
		#expect(screen.dependencies.last?.provenance?.first.map(Self.message(of:)) == "Nothing provides the `missing` that `Screen` receives.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_listsUnfulfilledProvenanceAfterDeclaration_whenReceiveIsProvidedUnderOneParentOnly() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(provider: Provider, bare: Bare) {
			        self.provider = provider
			        self.bare = bare
			    }

			    @Instantiated let provider: Provider
			    @Instantiated let bare: Bare
			}
			""",
			"Provider.swift": """
			@Instantiable
			public final class Provider: Instantiable {
			    public init(session: Session, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated let session: Session
			    @Instantiated let screen: Screen
			}
			""",
			"Bare.swift": """
			@Instantiable
			public final class Bare: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(session: Session) {
			        self.session = session
			    }

			    @Received let session: Session
			}
			""",
			"Session.swift": """
			@Instantiable
			public final class Session: Instantiable {
			    public init() {}
			}
			""",
		])

		let screen = try #require(report.declarations.first { $0.typeName == "Screen" })
		#expect(report.completeness == .partialTrees)
		#expect(screen.dependencies.map(\.isUnfulfilled) == [true])
		#expect(Self.supplies(in: report) == ["App.Screen.session": "App.Provider.session, unfulfilled"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksAliasUnfulfilled_whenNothingProvidesThePropertyItRenames() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(session: Session, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated let session: Session
			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			public final class User {}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(session: Session, account: User) {
			        self.session = session
			        self.account = account
			    }

			    @Received let session: Session
			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let account: User
			}
			""",
			"Session.swift": """
			@Instantiable
			public final class Session: Instantiable {
			    public init() {}
			}
			""",
		])

		let screen = try #require(report.declarations.first { $0.typeName == "Screen" })
		#expect(report.completeness == .partialTrees)
		#expect(screen.dependencies.map(\.isUnfulfilled) == [nil, true])
		#expect(Self.supplies(in: report) == ["App.Screen.session": "App.Root.session", "App.Screen.account": "unfulfilled"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksBuilderUnfulfilled_whenNoDeclarationFulfillsTypeItBuilds() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			public final class Missing {}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(missingBuilder: Instantiator<Missing>, screen: Screen) {
			        self.missingBuilder = missingBuilder
			        self.screen = screen
			    }

			    @Instantiated let missingBuilder: Instantiator<Missing>
			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(missingBuilder: Instantiator<Missing>?) {
			        self.missingBuilder = missingBuilder
			    }

			    @Received(onlyIfAvailable: true) let missingBuilder: Instantiator<Missing>?
			}
			""",
		])

		let root = try #require(report.declarations.first { $0.typeName == "Root" })
		#expect(report.completeness == .partialTrees)
		#expect(root.dependencies.map(\.isUnfulfilled) == [true, nil])
		#expect(Self.supplies(in: report) == ["App.Screen.missingBuilder": "unfulfilled(App.Root.missingBuilder)"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksOptionalReceiveUnfulfilled_whenNothingProvidesIt() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			public final class User {}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(user: User?) {
			        self.user = user
			    }

			    @Received let user: User?
			}
			""",
		])

		#expect(report.completeness == .partialTrees)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, true])
		#expect(Self.supplies(in: report) == ["App.Screen.user": "unfulfilled"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesNoProviderOfUnfulfilledReceive_whenOnlyOptionalDeclarationOfItsLabelIsAbove() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(user: User?, child: Child) {
			        self.user = user
			        self.child = child
			    }

			    @Instantiated(onlyIfAvailable: true) let user: User?
			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(user: User) {
			        self.user = user
			    }

			    @Received let user: User
			}
			""",
			"User.swift": """
			@Instantiable
			public final class User: Instantiable {
			    public init() {}
			}
			""",
		])

		let child = try #require(report.declarations.first { $0.typeName == "Child" })
		#expect(report.completeness == .partialTrees)
		#expect(child.dependencies.map(\.isUnfulfilled) == [true])
		#expect(Self.supplies(in: report) == ["App.Child.user": "unfulfilled"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsNoProvenance_whenSiblingsRequireEachOtherWhereUnfulfilledReceiveIsProvided() async throws {
		let report = try await graph(of: [
			"Alpha.swift": """
			@Instantiable(isRoot: true)
			public final class Alpha: Instantiable {
			    public init(aBuilder: Instantiator<A>, b: B) {
			        self.aBuilder = aBuilder
			        self.b = b
			    }

			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let b: B
			}
			""",
			"Beta.swift": """
			@Instantiable(isRoot: true)
			public final class Beta: Instantiable {
			    public init(b: B) {
			        self.b = b
			    }

			    @Instantiated let b: B
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(c: C) {
			        self.c = c
			    }

			    @Instantiated let c: C
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        self.aBuilder = aBuilder
			    }

			    @Received let aBuilder: Instantiator<A>
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

		// `generate` reports only the receive nothing provides beneath `Beta`. Built around it, `Alpha`'s children require
		// each other, which `generate` reports next, so the trees say nothing.
		#expect(report.completeness == .fulfillment)
		#expect(report.errors.count == 1)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, nil, nil, nil, nil, nil])
		#expect(Self.supplies(in: report) == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksOnlyDependencyGenerateReports_whenAliasRenamesValueOfTypeNoDeclarationFulfills() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			public final class Missing {}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(missing: Missing, service: Service) {
			        self.missing = missing
			        self.service = service
			    }

			    @Instantiated let missing: Missing
			    @Instantiated let service: Service
			}
			""",
			"Service.swift": """
			@Instantiable
			public final class Service: Instantiable {
			    public init(renamed: Missing) {
			        self.renamed = renamed
			    }

			    @Received(fulfilledByDependencyNamed: "missing", ofType: Missing.self) let renamed: Missing
			}
			""",
		])

		#expect(report.completeness == .partialTrees)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [true, nil, nil])
		#expect(Self.supplies(in: report) == ["App.Service.renamed": "unfulfilled(App.Root.missing)"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksEveryReceiveGenerateReports_whenTwoReceivesOfOneRootAreUnfulfilled() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}
			""",
			"First.swift": """
			public final class Missing {}

			@Instantiable
			public final class First: Instantiable {
			    public init(missing: Missing) {
			        self.missing = missing
			    }

			    @Received let missing: Missing
			}
			""",
			"Second.swift": """
			public final class Absent {}

			@Instantiable
			public final class Second: Instantiable {
			    public init(absent: Absent) {
			        self.absent = absent
			    }

			    @Received let absent: Absent
			}
			""",
		])

		#expect(report.completeness == .partialTrees)
		#expect(report.errors.count == 2)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [true, nil, nil, true])
		#expect(Self.supplies(in: report) == ["App.First.missing": "unfulfilled", "App.Second.absent": "unfulfilled"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksReceiveGenerateReportsOnceTypesAreDeclared_whenTreeAlsoInstantiatesTypeNoDeclarationFulfills() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			public final class Missing {}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(missing: Missing, service: Service) {
			        self.missing = missing
			        self.service = service
			    }

			    @Instantiated let missing: Missing
			    @Instantiated let service: Service
			}
			""",
			"Service.swift": """
			public final class Absent {}

			@Instantiable
			public final class Service: Instantiable {
			    public init(absent: Absent) {
			        self.absent = absent
			    }

			    @Received let absent: Absent
			}
			""",
		])

		// `generate` reports the type first, and the receive once the type is declared: both are marked, each with its error.
		#expect(report.completeness == .partialTrees)
		#expect(report.errors.map { String($0.message.prefix(40)) } == [
			"No @Instantiable type or extension fulfi",
			"@Received property `absent: Absent` is n",
		])
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [true, nil, true])
		#expect(Self.supplies(in: report) == ["App.Service.absent": "unfulfilled"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksReceiveOfUnfulfilledDependency_whenNothingProvidesItUnderAnotherRoot() async throws {
		let report = try await graph(of: [
			"Alpha.swift": """
			public final class Missing {}

			@Instantiable(isRoot: true)
			public final class Alpha: Instantiable {
			    public init(missing: Missing, service: Service) {
			        self.missing = missing
			        self.service = service
			    }

			    @Instantiated let missing: Missing
			    @Instantiated let service: Service
			}
			""",
			"Beta.swift": """
			@Instantiable(isRoot: true)
			public final class Beta: Instantiable {
			    public init(service: Service) {
			        self.service = service
			    }

			    @Instantiated let service: Service
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

		#expect(report.completeness == .partialTrees)
		#expect(report.errors.count == 2)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [true, nil, nil, true])
		#expect(Self.supplies(in: report) == ["App.Service.missing": "unfulfilled, unfulfilled(App.Alpha.missing)"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsNoProvenance_whenReceiveOfUnfulfilledDependencyReadsOptionalDeclarationBetween() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			public final class Missing {}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(missing: Missing, middleBuilder: Instantiator<Middle>) {
			        self.missing = missing
			        self.middleBuilder = middleBuilder
			    }

			    @Instantiated let missing: Missing
			    @Instantiated let middleBuilder: Instantiator<Middle>
			}
			""",
			"Middle.swift": """
			@Instantiable
			public final class Middle: Instantiable {
			    public init(missing: Missing?, service: Service) {
			        self.missing = missing
			        self.service = service
			    }

			    @Forwarded let missing: Missing?
			    @Instantiated let service: Service
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
		#expect(report.errors.count == 1)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, nil, nil, nil, nil])
		#expect(Self.supplies(in: report) == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesUnfulfilledDeclaration_whenReceiveReadsNearerDeclarationOfTypeNoDeclarationFulfills() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			public protocol Logger {}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(logger: Logger, section: Section) {
			        self.logger = logger
			        self.section = section
			    }

			    @Instantiated(fulfilledByType: "FileLogger") let logger: Logger
			    @Instantiated let section: Section
			}
			""",
			"Section.swift": """
			@Instantiable
			public final class Section: Instantiable {
			    public init(logger: Logger, row: Row) {
			        self.logger = logger
			        self.row = row
			    }

			    @Instantiated(fulfilledByType: "RemoteLogger") let logger: Logger
			    @Instantiated let row: Row
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(logger: Logger) {
			        self.logger = logger
			    }

			    @Received let logger: Logger
			}
			""",
			"FileLogger.swift": """
			@Instantiable
			public final class FileLogger: Instantiable, Logger {
			    public init() {}
			}
			""",
		])

		// The declaration stays as written, so the receive beneath it still reads it, never the root's.
		#expect(report.completeness == .partialTrees)
		#expect(report.errors.count == 1)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, nil, nil, true, nil])
		#expect(Self.supplies(in: report) == ["App.Row.logger": "unfulfilled(App.Section.logger)"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsTreeErrorWithoutProvenance_whenErrorIsNotOfUnfulfilledDependency() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(a: A) {
			        self.a = a
			    }

			    @Instantiated let a: A
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(b: B) {
			        self.b = b
			    }

			    @Instantiated let b: B
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(a: A) {
			        self.a = a
			    }

			    @Received let a: A
			}
			""",
		])

		#expect(report.completeness == .fulfillment)
		#expect(!report.errors.isEmpty)
		#expect(report.declarations.flatMap(\.dependencies).map(\.provenance) == [nil, nil, nil])
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, nil, nil])
		#expect(report.declarations.map(\.isReachedByRoot) == [nil, nil, nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsTreeErrorWithoutProvenance_whenUnfulfilledDependencyHidesAnotherError() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(a: A, missing: Missing) {
			        self.a = a
			        self.missing = missing
			    }

			    @Instantiated let a: A
			    @Instantiated let missing: Missing
			}
			""",
			"A.swift": """
			public final class Missing {}

			@Instantiable
			public final class A: Instantiable {
			    public init(b: B) {
			        self.b = b
			    }

			    @Instantiated let b: B
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(a: A) {
			        self.a = a
			    }

			    @Received let a: A
			}
			""",
		])

		#expect(report.completeness == .fulfillment)
		#expect(report.declarations.flatMap(\.dependencies).map(\.provenance) == [nil, nil, nil, nil])
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, nil, nil, nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_marksReceiveOfDependencyInstantiatedOnlyIfAvailable_whenNoDeclarationFulfillsIt() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			public protocol Tracker {}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(tracker: Tracker?, child: Child) {
			        self.tracker = tracker
			        self.child = child
			    }

			    @Instantiated(onlyIfAvailable: true) let tracker: Tracker?
			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(tracker: Tracker?) {
			        self.tracker = tracker
			    }

			    @Received(onlyIfAvailable: true) let tracker: Tracker?
			}
			""",
		])

		let child = try #require(report.declarations.first { $0.typeName == "Child" })
		#expect(report.completeness == .trees)
		#expect(Self.supplies(in: report) == ["App.Child.tracker": "nil(declarationNotInstantiated: App.Root.tracker)"])
		#expect(child.dependencies.first?.provenance?.first.map(Self.message(of:)) == "`App.Root` instantiates `tracker` only if available, and no declaration fulfills it.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesUnfulfilledReceiveAbove_whenTypeBeneathReceivesTheSameValue() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(session: Session, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated let session: Session
			    @Instantiated let screen: Screen
			}
			""",
			"Session.swift": """
			@Instantiable
			public final class Session: Instantiable {
			    public init() {}
			}
			""",
			"Screen.swift": """
			public final class Missing {}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(session: Session, missing: Missing, row: Row) {
			        self.session = session
			        self.missing = missing
			        self.row = row
			    }

			    @Received let session: Session
			    @Received let missing: Missing
			    @Instantiated let row: Row
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(missing: Missing, session: Session?) {
			        self.missing = missing
			        self.session = session
			    }

			    @Received let missing: Missing
			    @Received(onlyIfAvailable: true) let session: Session?
			}
			""",
		])

		let row = try #require(report.declarations.first { $0.typeName == "Row" })
		// `generate` reports the receive nearest the root alone: the one beneath it would be handed its value.
		#expect(report.completeness == .partialTrees)
		#expect(report.errors.count == 1)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, nil, nil, nil, nil, true, nil])
		#expect(Self.supplies(in: report) == [
			"App.Screen.session": "App.Root.session",
			"App.Screen.missing": "unfulfilled",
			"App.Row.missing": "unfulfilled(App.Screen.missing)",
			"App.Row.session": "App.Root.session",
		])
		#expect(row.dependencies.first?.provenance?.first.map(Self.message(of:)) == "`App.Screen` receives `missing`, which nothing provides.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesAliasInProvenance_whenNothingProvidesThePropertyItRenamesUnderOneParent() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(provider: Provider, bare: Bare) {
			        self.provider = provider
			        self.bare = bare
			    }

			    @Instantiated let provider: Provider
			    @Instantiated let bare: Bare
			}
			""",
			"Provider.swift": """
			@Instantiable
			public final class Provider: Instantiable {
			    public init(user: User, screen: Screen) {
			        self.user = user
			        self.screen = screen
			    }

			    @Instantiated let user: User
			    @Instantiated let screen: Screen
			}
			""",
			"Bare.swift": """
			@Instantiable
			public final class Bare: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"User.swift": """
			@Instantiable
			public final class User: Instantiable {
			    public init() {}
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(account: User, row: Row) {
			        self.account = account
			        self.row = row
			    }

			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let account: User
			    @Instantiated let row: Row
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(account: User) {
			        self.account = account
			    }

			    @Received let account: User
			}
			""",
		])

		let screen = try #require(report.declarations.first { $0.typeName == "Screen" })
		// The alias is a declaration wherever its type is built, so a receive of it names the alias, whose own provenance
		// says where it has a value.
		#expect(report.completeness == .partialTrees)
		#expect(screen.dependencies.map(\.isUnfulfilled) == [true, nil])
		#expect(Self.supplies(in: report) == [
			"App.Screen.account": "App.Provider.user, unfulfilled",
			"App.Row.account": "App.Screen.account",
		])
		#expect(screen.dependencies.first?.provenance?.last.map(Self.message(of:)) == "Nothing provides the `user` that `Screen` renames `account`.")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsValuesGenerateHandsUnderValidRoot_whenReceiveIsUnfulfilledUnderAnotherRoot() async throws {
		let report = try await graph(of: [
			"Alpha.swift": """
			@Instantiable(isRoot: true)
			public final class Alpha: Instantiable {
			    public init(b: B, a: A) {
			        self.b = b
			        self.a = a
			    }

			    @Instantiated let b: B
			    @Instantiated let a: A
			}
			""",
			"Beta.swift": """
			@Instantiable(isRoot: true)
			public final class Beta: Instantiable {
			    public init(a: A) {
			        self.a = a
			    }

			    @Instantiated let a: A
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(b: B) {
			        self.b = b
			    }

			    @Received let b: B
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(a: A?) {
			        self.a = a
			    }

			    @Received(onlyIfAvailable: true) let a: A?
			}
			""",
		])

		// Beneath `Alpha`, `a` requires `b`, so `b` is built first and handed no `a`, as `generate` builds them.
		#expect(report.completeness == .partialTrees)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [true, nil, nil, nil, nil])
		#expect(Self.supplies(in: report) == [
			"App.A.b": "App.Alpha.b, unfulfilled",
			"App.B.a": "nil(providerNotYetBuilt)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsNoProvenance_whenSiblingsRequireEachOtherBesideTypeNoDeclarationFulfills() async throws {
		let report = try await graph(of: [
			"Alpha.swift": """
			public protocol Detail {}

			public final class AnyDetail: Detail {
			    public init(_ detail: some Detail) {}
			}

			@Instantiable(isRoot: true)
			public final class Alpha: Instantiable {
			    public init(detailBuilder: ErasedInstantiator<(), AnyDetail>, row: Row) {
			        self.detailBuilder = detailBuilder
			        self.row = row
			    }

			    @Instantiated(fulfilledByType: "MissingDetail", erasedToConcreteExistential: true) let detailBuilder: ErasedInstantiator<(), AnyDetail>
			    @Instantiated let row: Row
			}
			""",
			"Beta.swift": """
			@Instantiable(isRoot: true)
			public final class Beta: Instantiable {
			    public init(detailBuilder: ErasedInstantiator<(), AnyDetail>, row: Row) {
			        self.detailBuilder = detailBuilder
			        self.row = row
			    }

			    @Instantiated(fulfilledByType: "RealDetail", erasedToConcreteExistential: true) let detailBuilder: ErasedInstantiator<(), AnyDetail>
			    @Instantiated let row: Row
			}
			""",
			"RealDetail.swift": """
			@Instantiable
			public final class RealDetail: Instantiable, Detail {
			    public init(c: C) {
			        self.c = c
			    }

			    @Instantiated let c: C
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(detailBuilder: ErasedInstantiator<(), AnyDetail>) {
			        self.detailBuilder = detailBuilder
			    }

			    @Received let detailBuilder: ErasedInstantiator<(), AnyDetail>
			}
			""",
			"C.swift": """
			@Instantiable
			public final class C: Instantiable {
			    public init(row: Row) {
			        self.row = row
			    }

			    @Received let row: Row
			}
			""",
		])

		// Beneath `Beta`, `detailBuilder`'s tree requires `row`, which requires `detailBuilder`: `generate` reports that
		// once `MissingDetail` is declared, so the trees say nothing.
		#expect(report.completeness == .fulfillment)
		#expect(report.errors.count == 1)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, nil, nil, nil, nil, nil, nil])
		#expect(Self.supplies(in: report) == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsValuesGenerateHandsUnderValidRoot_whenAnotherRootInstantiatesTypeNoDeclarationFulfills() async throws {
		let report = try await graph(of: [
			"Alpha.swift": """
			public protocol Detail {}

			public final class AnyDetail: Detail {
			    public init(_ detail: some Detail) {}
			}

			@Instantiable(isRoot: true)
			public final class Alpha: Instantiable {
			    public init(detailBuilder: ErasedInstantiator<(), AnyDetail>, row: Row) {
			        self.detailBuilder = detailBuilder
			        self.row = row
			    }

			    @Instantiated(fulfilledByType: "MissingDetail", erasedToConcreteExistential: true) let detailBuilder: ErasedInstantiator<(), AnyDetail>
			    @Instantiated let row: Row
			}
			""",
			"Beta.swift": """
			@Instantiable(isRoot: true)
			public final class Beta: Instantiable {
			    public init(detailBuilder: ErasedInstantiator<(), AnyDetail>, row: Row) {
			        self.detailBuilder = detailBuilder
			        self.row = row
			    }

			    @Instantiated(fulfilledByType: "RealDetail", erasedToConcreteExistential: true) let detailBuilder: ErasedInstantiator<(), AnyDetail>
			    @Instantiated let row: Row
			}
			""",
			"RealDetail.swift": """
			@Instantiable
			public final class RealDetail: Instantiable, Detail {
			    public init(c: C) {
			        self.c = c
			    }

			    @Instantiated let c: C
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(detailBuilder: ErasedInstantiator<(), AnyDetail>) {
			        self.detailBuilder = detailBuilder
			    }

			    @Received let detailBuilder: ErasedInstantiator<(), AnyDetail>
			}
			""",
			"C.swift": """
			@Instantiable
			public final class C: Instantiable {
			    public init(row: Row?) {
			        self.row = row
			    }

			    @Received(onlyIfAvailable: true) let row: Row?
			}
			""",
		])

		// Beneath `Beta`, `row` requires `detailBuilder`, whose tree is built first and handed no `row`, as `generate`
		// builds them once `MissingDetail` is declared.
		#expect(report.completeness == .partialTrees)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [true, nil, nil, nil, nil, nil, nil])
		#expect(Self.supplies(in: report) == [
			"App.C.row": "nil(providerNotYetBuilt)",
			"App.Row.detailBuilder": "App.Beta.detailBuilder, unfulfilled(App.Alpha.detailBuilder)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_leavesDependencyInstantiatedOnlyIfAvailableUnmarked_whenAnotherDependencyRequiresItsType() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			public final class Tracker {}

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(tracker: Tracker, feature: Feature) {
			        self.tracker = tracker
			        self.feature = feature
			    }

			    @Instantiated let tracker: Tracker
			    @Instantiated let feature: Feature
			}
			""",
			"Feature.swift": """
			@Instantiable
			public final class Feature: Instantiable {
			    public init(tracker: Tracker?, row: Row) {
			        self.tracker = tracker
			        self.row = row
			    }

			    @Instantiated(onlyIfAvailable: true) let tracker: Tracker?
			    @Instantiated let row: Row
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(tracker: Tracker?) {
			        self.tracker = tracker
			    }

			    @Received(onlyIfAvailable: true) let tracker: Tracker?
			}
			""",
		])

		// `generate`'s error lists both dependencies that instantiate `Tracker`, but only the required one keeps the trees
		// from being valid: the other is `nil` by design while no declaration fulfills it.
		#expect(report.completeness == .partialTrees)
		#expect(report.errors.count == 2)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, nil, true, nil, nil])
		#expect(Self.supplies(in: report) == ["App.Row.tracker": "nil(declarationNotInstantiated: App.Feature.tracker)"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_listsEachDeclarationNotInstantiatedByDeclaration_whenReceiveReadsTwo() async throws {
		let report = try await graph(of: [
			"RootB.swift": """
			public final class Tracker {}

			@Instantiable(isRoot: true)
			public final class RootB: Instantiable {
			    public init(tracker: Tracker?, child: Child) {
			        self.tracker = tracker
			        self.child = child
			    }

			    @Instantiated(onlyIfAvailable: true) let tracker: Tracker?
			    @Instantiated let child: Child
			}
			""",
			"RootA.swift": """
			@Instantiable(isRoot: true)
			public final class RootA: Instantiable {
			    public init(tracker: Tracker?, child: Child) {
			        self.tracker = tracker
			        self.child = child
			    }

			    @Instantiated(onlyIfAvailable: true) let tracker: Tracker?
			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(tracker: Tracker?) {
			        self.tracker = tracker
			    }

			    @Received(onlyIfAvailable: true) let tracker: Tracker?
			}
			""",
		])

		#expect(report.completeness == .trees)
		#expect(Self.supplies(in: report) == ["App.Child.tracker": "nil(declarationNotInstantiated: App.RootA.tracker), nil(declarationNotInstantiated: App.RootB.tracker)"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesAliasInProvenance_whenReceiveReadsInstanceOfLazilyInstantiatedAliasNothingProvides() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"User.swift": """
			@Instantiable
			public final class User: Instantiable {
			    public init() {}
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(user: LazilyInstantiated<User>, row: Row) {
			        self.user = user
			        self.row = row
			    }

			    @Received(fulfilledByDependencyNamed: "userLoader", ofType: LazilyInstantiated<User>.self) let user: LazilyInstantiated<User>
			    @Instantiated let row: Row
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(user: User) {
			        self.user = user
			    }

			    @Received let user: User
			}
			""",
		])

		#expect(report.completeness == .partialTrees)
		#expect(report.declarations.flatMap(\.dependencies).map(\.isUnfulfilled) == [nil, nil, true, nil])
		#expect(Self.supplies(in: report) == [
			"App.Screen.user": "unfulfilled",
			"App.Row.user": "App.Screen.user",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsNoProvenance_whenLazyCycleBuiltBeneathUnfulfilledReceiveTakesItsLabelAsParameter() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(missing: Missing, aBuilder: Instantiator<A>) {
			        self.missing = missing
			        self.aBuilder = aBuilder
			    }

			    @Received let missing: Missing
			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(b: B) {
			        self.b = b
			    }

			    @Instantiated let b: B
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(missing: Missing, inner: Inner) {
			        self.missing = missing
			        self.inner = inner
			    }

			    @Received let missing: Missing
			    @Instantiated let inner: Inner
			}
			""",
			"Inner.swift": """
			@Instantiable
			public final class Inner: Instantiable {
			    public init(missing: Missing, aBuilder: Instantiator<A>) {
			        self.missing = missing
			        self.aBuilder = aBuilder
			    }

			    @Instantiated let missing: Missing
			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
			"Missing.swift": """
			@Instantiable
			public final class Missing: Instantiable {
			    public init() {}
			}
			""",
		])

		// `generate` reports `Screen.missing` alone. The builder function the cycle closes on takes `missing`, which the
		// call beneath `Screen` would pass from the value nothing provides yet.
		#expect(report.completeness == .fulfillment)
		#expect(report.errors.count == 1)
		#expect(Self.unfulfilledDependencies(in: report) == [])
		#expect(Self.supplies(in: report) == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsNoProvenance_whenUnfulfilledReceiveReadsParameterOfFunctionLazyCycleClosesOn() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        self.aBuilder = aBuilder
			    }

			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(b: B) {
			        self.b = b
			    }

			    @Instantiated let b: B
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(missing: Missing, row: Row, inner: Inner) {
			        self.missing = missing
			        self.row = row
			        self.inner = inner
			    }

			    @Received let missing: Missing
			    @Instantiated let row: Row
			    @Instantiated let inner: Inner
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(missing: Missing) {
			        self.missing = missing
			    }

			    @Received let missing: Missing
			}
			""",
			"Inner.swift": """
			@Instantiable
			public final class Inner: Instantiable {
			    public init(missing: Missing, aBuilder: Instantiator<A>) {
			        self.missing = missing
			        self.aBuilder = aBuilder
			    }

			    @Instantiated let missing: Missing
			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
			"Missing.swift": """
			@Instantiable
			public final class Missing: Instantiable {
			    public init() {}
			}
			""",
		])

		// The cycle builds `B` again beneath `Inner`, whose `missing` that call passes; the root's call passes nothing.
		#expect(report.completeness == .fulfillment)
		#expect(report.errors.count == 1)
		#expect(Self.unfulfilledDependencies(in: report) == [])
		#expect(Self.supplies(in: report) == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesUnfulfilledReceiveAbove_whenLabelIsDeclaredAboveWithAnotherType() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(client: any NewClient, session: Session, screen: Screen) {
			        self.client = client
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated(fulfilledByType: "Client") let client: any NewClient
			    @Instantiated let session: Session
			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(client: Client, session: Session, row: Row) {
			        self.client = client
			        self.session = session
			        self.row = row
			    }

			    @Received let client: Client
			    @Received let session: Session
			    @Instantiated let row: Row
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(client: Client) {
			        self.client = client
			    }

			    @Received let client: Client
			}
			""",
			"Client.swift": """
			public protocol NewClient {}

			@Instantiable
			public final class Client: Instantiable, NewClient {
			    public init() {}
			}
			""",
			"Session.swift": """
			@Instantiable
			public final class Session: Instantiable {
			    public init() {}
			}
			""",
		])

		// The root's `client` was retyped while `Screen` and `Row` still receive the old type: `generate` reports `Screen`'s
		// receive alone, and no fix of it leaves `Row`'s hidden by the root's declaration.
		#expect(report.completeness == .partialTrees)
		#expect(Self.unfulfilledDependencies(in: report) == ["App.Screen.client"])
		#expect(Self.supplies(in: report) == [
			"App.Screen.client": "unfulfilled",
			"App.Screen.session": "App.Root.session",
			"App.Row.client": "unfulfilled(App.Screen.client)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesUnfulfilledReceiveAbove_whenLabelIsForwardedAboveAsOptional() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(middleBuilder: Instantiator<Middle>) {
			        self.middleBuilder = middleBuilder
			    }

			    @Instantiated let middleBuilder: Instantiator<Middle>
			}
			""",
			"Middle.swift": """
			public final class X {}

			@Instantiable
			public final class Middle: Instantiable {
			    public init(x: X?, screen: Screen) {
			        self.x = x
			        self.screen = screen
			    }

			    @Forwarded let x: X?
			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(x: X, row: Row) {
			        self.x = x
			        self.row = row
			    }

			    @Received let x: X
			    @Instantiated let row: Row
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(x: X) {
			        self.x = x
			    }

			    @Received let x: X
			}
			""",
		])

		// A required receive of `x: X` reads no `x: X?`, so `Row` reads what `Screen` will be handed.
		#expect(report.completeness == .partialTrees)
		#expect(Self.unfulfilledDependencies(in: report) == ["App.Screen.x"])
		#expect(Self.supplies(in: report) == [
			"App.Screen.x": "unfulfilled",
			"App.Row.x": "unfulfilled(App.Screen.x)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsNoProvenance_whenDeclarationBetweenUnfulfilledReceiveAndReceiveBeneathHidesIt() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			public final class X {}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(x: X, middle: Middle) {
			        self.x = x
			        self.middle = middle
			    }

			    @Received let x: X
			    @Instantiated let middle: Middle
			}
			""",
			"Middle.swift": """
			@Instantiable
			public final class Middle: Instantiable {
			    public init(x: Y, row: Row) {
			        self.x = x
			        self.row = row
			    }

			    @Instantiated let x: Y
			    @Instantiated let row: Row
			}
			""",
			"Y.swift": """
			@Instantiable
			public final class Y: Instantiable {
			    public init() {}
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(x: X) {
			        self.x = x
			    }

			    @Received let x: X
			}
			""",
		])

		// Once something provides `Screen`'s `x`, `generate` reports that `Middle`'s `x: Y` hides it from `Row`.
		#expect(report.completeness == .fulfillment)
		#expect(report.errors.count == 1)
		#expect(Self.unfulfilledDependencies(in: report) == [])
		#expect(Self.supplies(in: report) == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesUnfulfilledReceiveAbove_whenReceiveOnlyIfAvailableReadsInstanceOfLazilyInstantiatedReceive() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			@Instantiable
			public final class Screen: Instantiable {
			    public init(x: LazilyInstantiated<X>, row: Row) {
			        self.x = x
			        self.row = row
			    }

			    @Received let x: LazilyInstantiated<X>
			    @Instantiated let row: Row
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(x: X?) {
			        self.x = x
			    }

			    @Received(onlyIfAvailable: true) let x: X?
			}
			""",
			"X.swift": """
			@Instantiable
			public final class X: Instantiable {
			    public init() {}
			}
			""",
		])

		// Every declaration that provides `x: LazilyInstantiated<X>` provides its instance too.
		#expect(report.completeness == .partialTrees)
		#expect(Self.unfulfilledDependencies(in: report) == ["App.Screen.x"])
		#expect(Self.supplies(in: report) == [
			"App.Screen.x": "unfulfilled",
			"App.Row.x": "unfulfilled(App.Screen.x)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesUnfulfilledReceiveAbove_whenReceiveBeneathItIsOnlyIfAvailable() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			public final class X {}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(x: X, row: Row) {
			        self.x = x
			        self.row = row
			    }

			    @Received let x: X
			    @Instantiated let row: Row
			}
			""",
			"Row.swift": """
			@Instantiable
			public final class Row: Instantiable {
			    public init(x: X?) {
			        self.x = x
			    }

			    @Received(onlyIfAvailable: true) let x: X?
			}
			""",
		])

		#expect(report.completeness == .partialTrees)
		#expect(Self.unfulfilledDependencies(in: report) == ["App.Screen.x"])
		#expect(Self.supplies(in: report) == [
			"App.Screen.x": "unfulfilled",
			"App.Row.x": "unfulfilled(App.Screen.x)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_namesUnfulfilledReceiveOfEachBranch_whenTypeBeneathTwoUnfulfilledReceivesReadsBoth() async throws {
		let report = try await graph(of: [
			"Root.swift": """
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}
			""",
			"First.swift": """
			public final class X {}

			@Instantiable
			public final class First: Instantiable {
			    public init(x: X, reader: Reader) {
			        self.x = x
			        self.reader = reader
			    }

			    @Received let x: X
			    @Instantiated let reader: Reader
			}
			""",
			"Second.swift": """
			@Instantiable
			public final class Second: Instantiable {
			    public init(x: X, reader: Reader) {
			        self.x = x
			        self.reader = reader
			    }

			    @Received let x: X
			    @Instantiated let reader: Reader
			}
			""",
			"Reader.swift": """
			@Instantiable
			public final class Reader: Instantiable {
			    public init(x: X) {
			        self.x = x
			    }

			    @Received let x: X
			}
			""",
		])

		#expect(report.completeness == .partialTrees)
		#expect(Self.unfulfilledDependencies(in: report) == ["App.First.x", "App.Second.x"])
		#expect(Self.supplies(in: report) == [
			"App.First.x": "unfulfilled",
			"App.Second.x": "unfulfilled",
			"App.Reader.x": "unfulfilled(App.First.x), unfulfilled(App.Second.x)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_reportsNoProvenance_whenReceiveIsHiddenUnderOneRootAndAnotherIsUnfulfilledUnderAnotherRoot() async throws {
		let report = try await graph(of: [
			"Alpha.swift": """
			@Instantiable(isRoot: true)
			public final class Alpha: Instantiable {
			    public init(x: X, middleBuilder: Instantiator<Middle>) {
			        self.x = x
			        self.middleBuilder = middleBuilder
			    }

			    @Instantiated let x: X
			    @Instantiated let middleBuilder: Instantiator<Middle>
			}
			""",
			"Middle.swift": """
			@Instantiable
			public final class Middle: Instantiable {
			    public init(x: X?, child: Child) {
			        self.x = x
			        self.child = child
			    }

			    @Forwarded let x: X?
			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(x: X) {
			        self.x = x
			    }

			    @Received let x: X
			}
			""",
			"X.swift": """
			@Instantiable
			public final class X: Instantiable {
			    public init() {}
			}
			""",
			"Beta.swift": """
			@Instantiable(isRoot: true)
			public final class Beta: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"Screen.swift": """
			public final class Token {}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}
			""",
		])

		// `generate` reports `Screen.token` first, and `Child.x`, which `Middle` hides, once something provides it.
		#expect(report.completeness == .fulfillment)
		#expect(report.errors.count == 1)
		#expect(Self.unfulfilledDependencies(in: report) == [])
		#expect(Self.supplies(in: report) == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_exportsEveryKeyOfPartialTrees_whenTypeIsMissingAndReceiveAndAliasAreUnprovided() async throws {
		// One export that holds every key a partial tree adds, compared whole: `partialTrees`, `isUnfulfilled` on an
		// instantiated dependency, a receive and an alias, an `unfulfilled` value that names the instantiated dependency,
		// one that names the receive above, one that names nothing, an alias as a supplier, and a `nil` value whose reason
		// names the declaration that is not instantiated.
		let directory = try temporaryDirectory()
		let moduleDirectory = directory.appendingPathComponent("App")
		_ = try createSwiftFixtureFiles(
			atFilePaths: [
				"Root.swift": """
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(missing: Missing, gone: Gone?, child: Child) {}
				    @Instantiated let missing: Missing
				    @Instantiated(onlyIfAvailable: true) let gone: Gone?
				    @Instantiated let child: Child
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable {
				    public init(missing: Missing, gone: Gone?, token: Token, renamed: Token, leaf: Leaf) {}
				    @Received let missing: Missing
				    @Received(onlyIfAvailable: true) let gone: Gone?
				    @Received let token: Token
				    @Received(fulfilledByDependencyNamed: "source", ofType: Token.self) let renamed: Token
				    @Instantiated let leaf: Leaf
				}
				""",
				"Leaf.swift": """
				@Instantiable
				public final class Leaf: Instantiable {
				    public init(token: Token, renamed: Token) {}
				    @Received let token: Token
				    @Received let renamed: Token
				}
				""",
				"Token.swift": """
				@Instantiable
				public final class Token: Instantiable {
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
		  "completeness" : "partialTrees",
		  "declarations" : [
		    {
		      "constructedBy" : [
		        {
		          "declaredBy" : "App.Root",
		          "label" : "child"
		        }
		      ],
		      "declarationKind" : "class",
		      "dependencies" : [
		        {
		          "filePath" : "\(path)/Child.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "missing",
		          "line" : 4,
		          "plainType" : "Missing",
		          "provenance" : [
		            {
		              "declaredBy" : "App.Root",
		              "label" : "missing",
		              "message" : "`App.Root` instantiates `missing`, which no declaration fulfills.",
		              "source" : "unfulfilled"
		            }
		          ],
		          "source" : "received",
		          "type" : "Missing"
		        },
		        {
		          "filePath" : "\(path)/Child.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : true,
		          "label" : "gone",
		          "line" : 5,
		          "plainType" : "Gone",
		          "provenance" : [
		            {
		              "reason" : {
		                "declaredBy" : "App.Root",
		                "kind" : "declarationNotInstantiated",
		                "label" : "gone",
		                "message" : "`App.Root` instantiates `gone` only if available, and no declaration fulfills it."
		              },
		              "source" : "nil"
		            }
		          ],
		          "source" : "received",
		          "type" : "Gone?"
		        },
		        {
		          "filePath" : "\(path)/Child.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "isUnfulfilled" : true,
		          "label" : "token",
		          "line" : 6,
		          "plainType" : "Token",
		          "provenance" : [
		            {
		              "message" : "Nothing provides the `token` that `Child` receives.",
		              "source" : "unfulfilled"
		            }
		          ],
		          "source" : "received",
		          "type" : "Token"
		        },
		        {
		          "aliasOf" : {
		            "label" : "source",
		            "plainType" : "Token",
		            "type" : "Token"
		          },
		          "filePath" : "\(path)/Child.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "isUnfulfilled" : true,
		          "label" : "renamed",
		          "line" : 7,
		          "plainType" : "Token",
		          "provenance" : [
		            {
		              "message" : "Nothing provides the `source` that `Child` renames `renamed`.",
		              "source" : "unfulfilled"
		            }
		          ],
		          "source" : "received",
		          "type" : "Token"
		        },
		        {
		          "filePath" : "\(path)/Child.swift",
		          "fulfilledBy" : "App.Leaf",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "leaf",
		          "lifetime" : "eager",
		          "line" : 8,
		          "plainType" : "Leaf",
		          "source" : "instantiated",
		          "type" : "Leaf"
		        }
		      ],
		      "filePath" : "\(path)/Child.swift",
		      "fulfills" : [
		        "Child"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.Child",
		      "isReachedByRoot" : true,
		      "isRoot" : false,
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "Child"
		    },
		    {
		      "constructedBy" : [
		        {
		          "declaredBy" : "App.Child",
		          "label" : "leaf"
		        }
		      ],
		      "declarationKind" : "class",
		      "dependencies" : [
		        {
		          "filePath" : "\(path)/Leaf.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "token",
		          "line" : 4,
		          "plainType" : "Token",
		          "provenance" : [
		            {
		              "declaredBy" : "App.Child",
		              "label" : "token",
		              "message" : "`App.Child` receives `token`, which nothing provides.",
		              "source" : "unfulfilled"
		            }
		          ],
		          "source" : "received",
		          "type" : "Token"
		        },
		        {
		          "filePath" : "\(path)/Leaf.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "renamed",
		          "line" : 5,
		          "plainType" : "Token",
		          "provenance" : [
		            {
		              "declaredBy" : "App.Child",
		              "label" : "renamed",
		              "source" : "declaration"
		            }
		          ],
		          "source" : "received",
		          "type" : "Token"
		        }
		      ],
		      "filePath" : "\(path)/Leaf.swift",
		      "fulfills" : [
		        "Leaf"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.Leaf",
		      "isReachedByRoot" : true,
		      "isRoot" : false,
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "Leaf"
		    },
		    {
		      "constructedBy" : [

		      ],
		      "declarationKind" : "class",
		      "dependencies" : [
		        {
		          "filePath" : "\(path)/Root.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "isUnfulfilled" : true,
		          "label" : "missing",
		          "lifetime" : "eager",
		          "line" : 4,
		          "plainType" : "Missing",
		          "source" : "instantiated",
		          "type" : "Missing"
		        },
		        {
		          "filePath" : "\(path)/Root.swift",
		          "isErased" : false,
		          "isOnlyIfAvailable" : true,
		          "label" : "gone",
		          "lifetime" : "eager",
		          "line" : 5,
		          "plainType" : "Gone",
		          "source" : "instantiated",
		          "type" : "Gone?"
		        },
		        {
		          "filePath" : "\(path)/Root.swift",
		          "fulfilledBy" : "App.Child",
		          "isErased" : false,
		          "isOnlyIfAvailable" : false,
		          "label" : "child",
		          "lifetime" : "eager",
		          "line" : 6,
		          "plainType" : "Child",
		          "source" : "instantiated",
		          "type" : "Child"
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
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "Root"
		    },
		    {
		      "constructedBy" : [

		      ],
		      "declarationKind" : "class",
		      "dependencies" : [

		      ],
		      "filePath" : "\(path)/Token.swift",
		      "fulfills" : [
		        "Token"
		      ],
		      "generatesDependencyTree" : false,
		      "id" : "App.Token",
		      "isReachedByRoot" : false,
		      "isRoot" : false,
		      "line" : 1,
		      "module" : "App",
		      "typeName" : "Token"
		    }
		  ],
		  "errors" : [
		    {
		      "filePath" : "\(path)/Root.swift",
		      "line" : 4,
		      "message" : "No @Instantiable type or extension fulfills `Missing`, which @Instantiated property `missing: Missing` instantiates. Decorate `Missing`, or an extension of it, with @Instantiable, or list `Missing` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it. If a declaration that fulfills `Missing` is in another target, add that target’s folder to `additionalDirectoriesToInclude` in this target’s `#SafeDIConfiguration`, or, in a SafeDITool run by hand, list the `.safedi` file of its module in the file you pass to `--dependent-module-info-file-path`."
		    },
		    {
		      "filePath" : "\(path)/Child.swift",
		      "line" : 6,
		      "message" : "@Received property `token: Token` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let token: Token` on `Root` or on another type in the chain to fix."
		    },
		    {
		      "filePath" : "\(path)/Child.swift",
		      "line" : 7,
		      "message" : "@Received property `source: Token` is not @Instantiated or @Forwarded in chain: Root -> Child. Declare `@Instantiated let source: Token` on `Root` or on another type in the chain to fix."
		    }
		  ],
		  "formatVersion" : 0,
		  "fulfillments" : [
		    {
		      "fulfilledBy" : "App.Child",
		      "plainType" : "Child"
		    },
		    {
		      "fulfilledBy" : "App.Leaf",
		      "plainType" : "Leaf"
		    },
		    {
		      "fulfilledBy" : "App.Root",
		      "plainType" : "Root"
		    },
		    {
		      "fulfilledBy" : "App.Token",
		      "plainType" : "Token"
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
	mutating func graph_countsEdgesNotPaths_whenScreensOpenScreensOfTheNextLayer() async throws {
		// Layers of four screens, each holding instantiators of three screens of the next layer and receiving `service`,
		// under a root that declares `service` and builds the first layer, so the last layer is reached along
		// 4 × 3^(layers - 1) paths. The fold reads the per-type graph, where a node stands for every place of its
		// declaration, so each later layer adds the same work: its 12 edges, the four declarations of `service` (one per
		// screen of the first layer) that the second and third edge into each of its four screens read, 32, and the four
		// each screen's receive judges, 16, which is 60. The walk it replaced entered every path: at four and six layers,
		// 162 and 1,458 visits.
		let visits = try await supplyVisitsInLayersOfScreens()
		#expect(visits == [169, 289])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func graph_countsEachDeclarationOnce_whenParentsDeclaringLabelShareChainThatReceivesIt() async throws {
		// k parents under the root each declare `theme` and build the first of a chain of n links, whose last receives
		// `theme`. The fold visits each of the 3k + n - 1 edges once and judges the k declarations at the reader, 4k + n - 1
		// in all: the links share the first link's set of k declarations rather than copying it, which would move n × k.
		var visits = [Int]()
		for (parentCount, linkCount) in [(4, 8), (8, 16)] {
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
				var types = [Self.fixtureType(named: "Theme", properties: [])]
				types.append(Self.fixtureType(named: "Root", isRoot: true, properties: (0..<parentCount).map { FixtureProperty("@Instantiated", "parent\($0)", "Parent\($0)") }))
				for parent in 0..<parentCount {
					types.append(Self.fixtureType(named: "Parent\(parent)", properties: [FixtureProperty("@Instantiated", "theme", "Theme"), FixtureProperty("@Instantiated", "link0", "Link0")]))
				}
				for link in 0..<linkCount {
					let properties = if link + 1 < linkCount {
						[FixtureProperty("@Instantiated", "link\(link + 1)", "Link\(link + 1)")]
					} else {
						[FixtureProperty("@Received", "theme", "Theme")]
					}
					types.append(Self.fixtureType(named: "Link\(link)", properties: properties))
				}
				_ = try await graph(of: ["Chain.swift": types.joined(separator: "\n\n")])
			}
			continuation.finish()
			var visitsOfThisSize = 0
			for await work in stream where work.step == .findingReceivedValueSupplies {
				visitsOfThisSize += work.elementCount
			}
			visits.append(visitsOfThisSize)
		}
		#expect(visits == [23, 47])
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
	/// declaration as `<declaration id>.<label>`, then each `nil` as `nil(<reason kind>)`, with the declaration its reason
	/// names, then each entry of what cannot be fulfilled, with the declaration it names, joined.
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
						reason.declaredBy.map { "nil(\(reason.kind.rawValue): \($0).\(reason.label ?? ""))" } ?? "nil(\(reason.kind.rawValue))"
					case let .unfulfilled(unfulfilled):
						unfulfilled.declaredBy.map { "unfulfilled(\($0).\(unfulfilled.label ?? ""))" } ?? "unfulfilled"
					}
				}.joined(separator: ", ")
			}
		}
		return supplies
	}

	/// Each dependency `report` marks `isUnfulfilled`, as `<declaration id>.<label>`, sorted.
	private static func unfulfilledDependencies(in report: QueryGraphReport) -> [String] {
		report.declarations.flatMap { declaration in
			declaration.dependencies.filter { $0.isUnfulfilled == true }.map { "\(declaration.id).\($0.label)" }
		}.sorted()
	}

	private static func message(of provenance: GraphDependency.Provenance) -> String? {
		switch provenance {
		case .declaration:
			nil
		case let .passedNil(reason):
			reason.message
		case let .unfulfilled(unfulfilled):
			unfulfilled.message
		}
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
