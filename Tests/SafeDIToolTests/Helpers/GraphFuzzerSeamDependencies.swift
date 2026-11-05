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

/// The draw that moves declarations of a graph split across modules from the seam's module
/// (`GraphFuzzerModule.seamModule`) into `GraphFuzzerModule.seamDependency`, which only the seam's module lists, and
/// draws a chain of seams or public mocks through it and the modules beneath it, `GraphFuzzerModule.seamDependencyBase`
/// and `GraphFuzzerModule.seamDependencyLeaf`, each listed only by the one above it (`chainPercent`). The callers still
/// list the seam's module alone, so under the module-info flow they compute each seam's and public mock's signature from
/// the declarations the seam's module's `.safedi` carries in its view, and under the SwiftPM plugin flow from the target
/// graph; the oracle's comparison of the two flows checks that both compute the same.
///
/// The draw reads each file's source as written without its header (`Unit`), so that the seam corpus and the public mock
/// corpus share it. A declaration moves only where the fixture still compiles and every caller still reads it through
/// the seam's module (`Analysis`): it spells `public` or `package` on every declaration another module of its package
/// can need; no caller, configuration, or hand-written caller comment names it, and no caller or caller's mock builds
/// it, so that a caller only computes from the view what the seam's module builds; it names no type a caller declares,
/// and no type the read twin renames; and each type it names moves with it. Drawn from a stream of its own, after every
/// other pass, so a graph without the draw is the graph it was before; the inline build and the known-right path list
/// every module beneath them, as 2.2.0 asked, since they build what the seam's module would have.
enum GraphFuzzerSeamDependencyDraw {
	/// A file of the graph: the module it is in, its source without the lines that name its module and import others, and
	/// whether anything beyond its source keeps it where it is.
	struct Unit {
		let module: GraphFuzzerModule
		let source: String
		/// Whether the draw may move the file: `false` for a file whose module or name another file finds it by, such as a
		/// file in no SafeDI marker that another declaration's file is matched with.
		let mayMove: Bool
	}

	/// The stream the seam corpus draws from.
	static let seamRandomSeedMask: UInt64 = 0x7365616D44657073
	/// The stream the public mock corpus draws from.
	static let publicMockRandomSeedMask: UInt64 = 0x7075624D6B446570
	/// The share of eligible graphs whose declarations of the seam's module may move beneath it, in percent.
	static let drawPercent = 30
	/// The share of eligible graphs that gain a chain of seams or public mocks beneath the seam's module, in percent:
	/// `ChainLink`, in `seamDependency`, which a seam or public mock of the seam's module instantiates; `ChainBase`, in
	/// `seamDependencyBase`, which `ChainLink` instantiates; and `ChainLeaf`, in `seamDependencyLeaf`, which `ChainBase`
	/// instantiates and whose tree receives the plain `ChainToken` only if available. `ChainLink` and `ChainBase` are each
	/// a seam in the seam corpus and a public mock with an `internal` initializer in the public mock corpus, so each module
	/// calls the one beneath it, and a caller computes each level's signature from the view of the module that calls it.
	/// The bottom level reads a module the level above it does not list, which is what a computation from the wrong
	/// module's view gets wrong (cell 5b of the module info view's design: with one module fewer, the chain passes with or
	/// without that defect). A type of the seam's module moves only one module down
	/// (`destinations(of:typeNamePrefix:random:)`), since the seam's module builds what a seam's or public mock's tree names
	/// and lists only the module beneath it, so the chain is drawn on purpose, beneath a seam or public mock that each
	/// module calls rather than builds.
	static let chainPercent = 20
	static let chainLinkSuffix = "ChainLink"
	static let chainBaseSuffix = "ChainBase"
	static let chainLeafSuffix = "ChainLeaf"
	static let chainTokenSuffix = "ChainToken"

	/// What the draw reads of a graph's files: the type names each declares and names, and the names that must stay in
	/// the seam's module.
	struct Analysis {
		init(units: [Unit], typeNamePrefix prefix: String) {
			let declaredNames = units.map { GraphFuzzerSeamDependencyDraw.declaredTypeNames(in: $0.source, prefix: prefix) }
			let referencedNames = units.indices.map { GraphFuzzerSeamDependencyDraw.typeNames(in: units[$0].source, prefix: prefix).subtracting(declaredNames[$0]) }
			var declaringUnitIndices = [String: [Int]]()
			for (index, names) in declaredNames.enumerated() {
				for name in names {
					declaringUnitIndices[name, default: []].append(index)
				}
			}
			// A caller calls a seam's generated initializer or a public mock where it instantiates the type, so what only such
			// a type's tree names may move: that is what a caller computes from the view. A type whose mock is hand-written
			// (`customMockName`) has its dependencies built by the caller that calls that mock.
			let boundaryUnits = Set(units.indices.filter { index in
				let source = units[index].source
				return source.contains("generateDependencyTree: true") || source.contains("generateMock: .public") && !source.contains("customMockName")
			})
			/// Whether a type built in `module`'s generated code calls the seam's generated initializer or the public mock of
			/// `name` rather than build its tree: a seam's always, and a public mock's when `module` cannot call the type's own
			/// initializer – `internal`, or `package` and `module` in another package. A type the seam's module declares is
			/// built inline only by a caller, so it is judged as the caller in the seam's package would build it.
			func callsRatherThanBuilds(_ name: String, from module: GraphFuzzerModule) -> Bool {
				guard let declaringIndex = (declaringUnitIndices[name] ?? []).first(where: boundaryUnits.contains) else { return false }
				let source = units[declaringIndex].source
				guard source.contains("generateMock: .public") else { return true }
				let initializerLine = source.split(separator: "\n").first { $0.contains("init(") && !$0.contains(".init(") } ?? ""
				let modifiers = initializerLine.prefix { $0 != "(" }.split(whereSeparator: { $0 == " " || $0 == "\t" })
				if modifiers.contains("public") {
					return false
				} else if modifiers.contains("package") {
					return module.packageName != GraphFuzzerModule.seamModule.packageName
				} else {
					return true
				}
			}
			/// The names the file at `index` names, less each seam or public mock type it names only where it instantiates it
			/// – on the property's line, and as the initializer's or a mock method's parameter – and calls rather than builds.
			func namesBuiltInline(by index: Int) -> Set<String> {
				let module = units[index].module.isCaller ? units[index].module : .samePackageCaller
				var names = Set<String>()
				for line in units[index].source.split(separator: "\n") {
					let lineNames = GraphFuzzerSeamDependencyDraw.typeNames(in: String(line), prefix: prefix).subtracting(declaredNames[index])
					let namesInstantiation = line.contains("@Instantiated") || line.contains("init(") || line.contains("func ")
					names.formUnion(namesInstantiation ? lineNames.filter { !callsRatherThanBuilds($0, from: module) } : lineNames)
				}
				return names
			}
			var pinnedNames = Set<String>()
			var inlineNames = Set<String>()
			for (index, unit) in units.enumerated() where unit.module.isCaller || unit.source.contains("#SafeDIConfiguration") || unit.source.contains(GraphFuzzerPublicMockDraw.publicMockCallerMarker) {
				pinnedNames.formUnion(referencedNames[index])
				inlineNames.formUnion(namesBuiltInline(by: index))
			}
			// A seam or public mock type a caller instantiates is what the caller hands a receiver of it beneath, so a receive of
			// one is built inline only where a caller receives it itself, which `namesBuiltInline` has already counted.
			var namesCallersInstantiate = Set<String>()
			for unit in units where unit.module.isCaller {
				for line in unit.source.split(separator: "\n") where line.contains("@Instantiated") {
					namesCallersInstantiate.formUnion(GraphFuzzerSeamDependencyDraw.typeNames(in: String(line), prefix: prefix))
				}
			}
			for unit in units {
				for line in unit.source.split(separator: "\n") where line.contains("@Received") || line.contains("@Forwarded") {
					inlineNames.formUnion(GraphFuzzerSeamDependencyDraw.typeNames(in: String(line), prefix: prefix).filter { name in
						!namesCallersInstantiate.contains(name) || !callsRatherThanBuilds(name, from: .samePackageCaller)
					})
				}
			}
			// A mock builds a seam's tree itself, and calls a public mock only where `callsRatherThanBuilds` says, so what a
			// mock reaches through seams is built where the mock is: by a caller's mock, in the caller; by a mock of the seam's
			// module, there, which reads the module beneath it but no module further down.
			func namesReached(fromMocksIn modules: (GraphFuzzerModule) -> Bool) -> Set<String> {
				var reached = Set<String>()
				var pending = units.indices.filter { modules(units[$0].module) && units[$0].source.contains("generateMock: ") }.flatMap { declaredNames[$0].sorted() }
				while let name = pending.popLast() {
					for index in declaringUnitIndices[name] ?? [] {
						for referencedName in namesBuiltInline(by: index).union(referencedNames[index].filter { name in
							(declaringUnitIndices[name] ?? []).contains { units[$0].source.contains("generateDependencyTree: true") }
						}).sorted() where reached.insert(referencedName).inserted {
							pending.append(referencedName)
						}
					}
				}
				return reached
			}
			inlineNames.formUnion(namesReached(fromMocksIn: \.isCaller))
			var pendingNames = Array(inlineNames.sorted())
			while let name = pendingNames.popLast() {
				pinnedNames.insert(name)
				for index in declaringUnitIndices[name] ?? [] {
					for builtName in namesBuiltInline(by: index).sorted() where inlineNames.insert(builtName).inserted {
						pendingNames.append(builtName)
					}
					pinnedNames.formUnion(referencedNames[index])
				}
			}
			self.declaredNames = declaredNames
			self.referencedNames = referencedNames
			self.declaringUnitIndices = declaringUnitIndices
			self.pinnedNames = pinnedNames
			self.inlineNames = inlineNames
			namesMocksReach = namesReached(fromMocksIn: { _ in true })
		}

		/// The type names each file declares.
		let declaredNames: [Set<String>]
		/// The type names each file names and does not declare.
		let referencedNames: [Set<String>]
		/// The files that declare each type name.
		let declaringUnitIndices: [String: [Int]]
		/// The names a caller can build or name itself, which must stay in the seam's module, where a caller that lists
		/// it alone reads them under the module-info flow as it reads them under the plugin flow, which reads every module
		/// beneath it: what a caller, a configuration, or the caller the oracle writes for a hand-written caller's comment
		/// names, and everything a type in `inlineNames` names.
		let pinnedNames: Set<String>
		/// The types a caller may build itself, rather than call a seam's generated initializer or a public mock for:
		/// what a caller, a configuration, or the oracle's caller names other than by instantiating a seam or public mock;
		/// the types of the values a tree receives or is handed, which a caller provides – a mock by building them; and,
		/// transitively, everything such a type names the same way.
		let inlineNames: Set<String>
		/// The types any mock builds itself: those its tree names, through seams, which a mock builds, and not through a
		/// public mock it calls (`inlineNames` counts those of callers' mocks).
		let namesMocksReach: Set<String>
	}

	/// The module each of `units` moves to, in the order given, or `nil` for one that stays. Empty when the draw
	/// moves nothing: the roll against `drawPercent` fails, or no file can move.
	static func destinations(of units: [Unit], typeNamePrefix prefix: String, random: inout GraphFuzzerRandomNumberGenerator) -> [GraphFuzzerModule?] {
		guard random.percentChance(drawPercent) else { return [] }
		let analysis = Analysis(units: units, typeNamePrefix: prefix)
		let declaredNames = analysis.declaredNames
		let referencedNames = analysis.referencedNames
		let declaringUnitIndices = analysis.declaringUnitIndices
		let pinnedNames = analysis.pinnedNames
		let candidates = units.indices.filter { index in
			let unit = units[index]
			return unit.module == .seamModule
				&& unit.mayMove
				&& !declaredNames[index].isEmpty
				&& declaredNames[index].isDisjoint(with: pinnedNames)
				&& !unit.source.contains(GraphFuzzerPublicMockDraw.publicMockCallerMarker)
				&& !GraphFuzzerReadTwin.UnreadType.all.contains(where: { $0.isNamed(in: unit.source) })
				&& referencedNames[index].allSatisfy { name in
					(declaringUnitIndices[name] ?? []).allSatisfy { units[$0].module == .seamModule }
				}
				&& spellsAccessEveryModuleOfItsPackageReads(unit.source)
		}
		// Half the candidates, less those that name a declaration of the seam's module that stays.
		var moved = Set(candidates.filter { _ in random.percentChance(50) })
		func removeUnitsNamingDeclarations(notIn kept: inout Set<Int>, among scope: Set<Int>) {
			var removedAny = true
			while removedAny {
				removedAny = false
				for index in kept.sorted() where referencedNames[index].contains(where: { name in
					(declaringUnitIndices[name] ?? []).contains { !kept.contains($0) && scope.contains($0) }
				}) {
					kept.remove(index)
					removedAny = true
				}
			}
		}
		removeUnitsNamingDeclarations(notIn: &moved, among: Set(units.indices.filter { units[$0].module == .seamModule }))
		guard !moved.isEmpty else { return [] }
		return units.indices.map { moved.contains($0) ? .seamDependency : nil }
	}

	/// What `fixture` draws beneath its seam's module: whether a file there declares something other than the chain
	/// (`movesDeclaration`), and whether it holds the chain (`drawsChain`).
	static func drawn(in fixture: GraphFuzzerFixture) -> (movesDeclaration: Bool, drawsChain: Bool) {
		var drawn = (movesDeclaration: false, drawsChain: false)
		let chainNames = [chainLinkSuffix, chainBaseSuffix, chainLeafSuffix].map { fixture.typeNamePrefix + $0 }
		for content in fixture.swiftFileContent {
			guard let module = GraphFuzzerModule(declaredIn: content), module < .seamModule else { continue }
			if declaredTypeNames(in: content, prefix: fixture.typeNamePrefix).contains(where: chainNames.contains) {
				drawn.drawsChain = true
			} else {
				drawn.movesDeclaration = true
			}
		}
		return drawn
	}

	/// The index of the file of `sources` that declares the creation stamps' counter
	/// (`DifferentialValueCreationStamp`): the first file of the lowest module every module above it imports, the seam's
	/// module or one beneath it, in a graph split across modules, and otherwise the first file.
	static func creationStampCounterIndex(in sources: [String]) -> Int {
		let modules = sources.map(GraphFuzzerModule.init(declaredIn:))
		guard let lowestModule = modules.compactMap(\.self).filter({ !$0.isCaller }).min() else { return 0 }
		return modules.firstIndex(of: lowestModule) ?? 0
	}

	/// `sources`, a graph split across modules, with the files of every module above the one that declares the creation
	/// stamps' counter (`creationStampCounterIndex(in:)`) importing that module when they do not already: a module beneath
	/// the seam's module, which only the module right above it lists. Only the rendering that stores every parameter
	/// stamps its classes, so only it imports the module that way.
	static func addingCreationStampCounterImports(to sources: [String]) -> [String] {
		guard !sources.isEmpty,
		      let counterModule = GraphFuzzerModule(declaredIn: sources[creationStampCounterIndex(in: sources)]),
		      counterModule < .seamModule
		else { return sources }
		return sources.map { source in
			guard let module = GraphFuzzerModule(declaredIn: source),
			      module != counterModule,
			      !module.dependencies.contains(counterModule),
			      let headerEnd = source.range(of: "\n\n")
			else { return source }
			// After the header, which `GraphFuzzerFixture.withoutHoles` replaces when it moves a file into the seam's module.
			return source[..<headerEnd.upperBound] + "import \(counterModule.name)\n\n" + source[headerEnd.upperBound...]
		}
	}

	/// The names beginning with `prefix` that `source` declares as a type: after `class`, `struct`, `enum`, `protocol`,
	/// `typealias` or `actor`.
	static func declaredTypeNames(in source: String, prefix: String) -> Set<String> {
		var names = Set<String>()
		for line in source.split(separator: "\n") {
			let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
			for (keyword, name) in zip(tokens, tokens.dropFirst()) where ["class", "struct", "enum", "protocol", "typealias", "actor"].contains(keyword) {
				let typeName = String(name.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
				if typeName.hasPrefix(prefix) {
					names.insert(typeName)
				}
			}
		}
		return names
	}

	/// The names beginning with `prefix` that `source` spells anywhere, each as a whole identifier.
	static func typeNames(in source: String, prefix: String) -> Set<String> {
		var names = Set<String>()
		var identifier = ""
		for character in source + " " {
			if character.isLetter || character.isNumber || character == "_" {
				identifier.append(character)
			} else {
				if identifier.hasPrefix(prefix) {
					names.insert(identifier)
				}
				identifier = ""
			}
		}
		return names
	}

	/// Whether every declaration in `source` that another module of its package can need – a type, an initializer, a
	/// method, a static member – spells `public` or `package`. A stored instance property, an enum case and an extension
	/// need neither; a protocol's requirements spell nothing, so a file that declares one stays.
	static func spellsAccessEveryModuleOfItsPackageReads(_ source: String) -> Bool {
		for line in source.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
			let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.hasPrefix("@") }
			guard let keywordIndex = tokens.firstIndex(where: { token in
				["class", "struct", "enum", "protocol", "typealias", "actor", "func", "let", "var", "case", "extension"].contains(token)
					|| token == "init" || token.hasPrefix("init(") || token.hasPrefix("init<")
			}) else { continue }
			let keyword = tokens[keywordIndex]
			let modifiers = tokens[..<keywordIndex]
			switch keyword {
			case "extension", "case":
				continue
			case "let", "var":
				guard modifiers.contains("static") else { continue }
			default:
				break
			}
			guard modifiers.contains("public") || modifiers.contains("package") else { return false }
		}
		return true
	}
}
