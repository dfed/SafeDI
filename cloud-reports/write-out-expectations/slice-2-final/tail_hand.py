F='Tests/SafeDIToolTests/SafeDIToolFulfillerImportTests.swift'
s=open(F).read()
KEY='integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift"'
IMPORTS=r'.map { "#if canImport(\($0))\nimport \($0)\n#endif" }.joined(separator: "\n")'
def r(a,b,count=1):
    global s
    b=b.replace('@KEY@',KEY).replace('@IMPORTS@',IMPORTS)
    assert s.count(a)==count,(s.count(a),a[:70])
    s=s.replace(a,b)
r(r'''		#expect(output.modules["App"]?.generatedFiles == Self.rootFiles(integration: integration, importing: property.expectedImports, property.expectedBody))
''',r'''		#expect(output.modules["App"]?.generatedFiles == [
			@KEY@: generatedFileHeader + """
			\(property.expectedImports@IMPORTS@)

			\(property.expectedBody)
			""",
		])
''')
r(r'''		#expect(output.modules["App"]?.generatedFiles == Self.files(integration: integration, moduleName: "App", rootFileName: "Root", header: """
		#if canImport(Contracts)
		import Contracts
		#endif
		\(facadeHeader)#if canImport(Impl)
		@_spi(Inside) import struct Impl.Secret
		#endif
		#if canImport(Impl)
		import Impl
		#endif
		""", body: """
		extension Root {''',r'''		#expect(output.modules["App"]?.generatedFiles == [@KEY@: generatedFileHeader + """
		#if canImport(Contracts)
		import Contracts
		#endif
		\(facadeHeader)#if canImport(Impl)
		@_spi(Inside) import struct Impl.Secret
		#endif
		#if canImport(Impl)
		import Impl
		#endif

		extension Root {''')
r(r'''		        self.init(thing: thing, childBuilder: childBuilder)
		    }
		}
		"""))
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsImportOfAnotherTypeThatTellsItFromTheTypeOfAnotherModule''',r'''		        self.init(thing: thing, childBuilder: childBuilder)
		    }
		}
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsImportOfAnotherTypeThatTellsItFromTheTypeOfAnotherModule''')
r(r'''		#expect(output.modules["App"]?.generatedFiles == Self.rootFiles(integration: integration, importing: ["Contracts", moduleNames[fulfillerModuleIndex]].sorted(), """
		extension Root {
		    public init() {
		        let thing = AnyThing(DefaultThing())
		        self.init(thing: thing)
		    }
		}
		"""))
''',r'''		#expect(output.modules["App"]?.generatedFiles == [@KEY@: generatedFileHeader + """
		\(["Contracts", moduleNames[fulfillerModuleIndex]].sorted()@IMPORTS@)

		extension Root {
		    public init() {
		        let thing = AnyThing(DefaultThing())
		        self.init(thing: thing)
		    }
		}
		"""])
''')
r(r'''		#expect(output.modules["App"]?.generatedFiles == Self.files(integration: integration, moduleName: "App", rootFileName: "Root", header: """
		#if canImport(Contracts)
		import Contracts
		#endif
		#if canImport(Impl)
		\(unreadFileImport.expectedGeneratedImport)
		#endif
		""", body: Self.rootBody))
''',r'''		#expect(output.modules["App"]?.generatedFiles == [@KEY@: generatedFileHeader + """
		#if canImport(Contracts)
		import Contracts
		#endif
		#if canImport(Impl)
		\(unreadFileImport.expectedGeneratedImport)
		#endif

		extension Root {
		    public init() {
		        let thing = AnyThing(DefaultThing())
		        self.init(thing: thing)
		    }
		}
		"""])
''')
open(F,'w').write(s)
G='Tests/SafeDIToolTests/SafeDIToolModuleInfoViewTests.swift'
s=open(G).read()
r(r'''		let fileName = integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift"
		let pluginComment = integration.seamCallComment(type: "MidScreen", declaringModule: "Mid")
		// `token` passes through''',r'''		// `token` passes through''')
r(r'''		#expect(viewOutput.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feed") + "\n\n" + """
		extension Root {''',r'''		#expect(viewOutput.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feed)
		import Feed
		#endif

		extension Root {''')
open(G,'w').write(s)
