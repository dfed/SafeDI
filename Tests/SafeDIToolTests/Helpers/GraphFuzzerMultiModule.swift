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
import Testing

// MARK: - Partition

/// A graph's files split into modules of one package, so that the graph can be run through the multi-module
/// integrations (`executeSafeDIToolMultiModuleTest`) as well as through `executeSafeDIToolTest`.
///
/// The partition is a pure function of the graph: it draws nothing from the seed, so every pin on the graphs a seed
/// names (`corpusFixtureHash`, the accepted-seed pins) is unchanged by it, and `corpusPartitionHash` pins the
/// partition itself. Each file names the types it refers to – what it instantiates, receives, forwards, aliases, erases
/// to, or fulfills with, the graph's `Value` and protocol types, and the extended class of the extension-based type –
/// and each name is declared in one file, so the files form a reference graph. Its strongly connected components are
/// found with Tarjan's algorithm, visiting the helper types' file first and then the files in their order, which lists
/// each component after every component it refers to: the helper types' file, which refers to nothing, is the first
/// component; a lazy cycle through instantiators is one component, so its types share a module; and a root's component
/// follows those of the types its tree names. The roots are the first files, so the types no root's file refers to,
/// directly or through other files, are visited after them and their components follow the roots', and a root need
/// not be in the last module. The components are then dealt out, in that order, to one to four modules
/// (`moduleNames`, in that order), as many as the graph's text chooses (`moduleCount(forComponentCount:of:)`, from
/// `GraphFuzzerHash` of the fixture's description, so single-module graphs stay in the corpus), each a contiguous run
/// of components, so every reference points into the same module or an earlier one. Every file keeps its name and its
/// content, with `import` lines for the modules it refers to added before it, except that the helper types `Value` and
/// `Unbuildable<n>`, which the generator declares in `Root0`'s file, move into a file of their own (`projectedFiles(of:)`),
/// so the renaming oracle's `rename` and `restore` apply unchanged (the module, package and helper file names hold no
/// digit but the seed's, and no index the renamings rewrite).
///
/// A module's `dependencies` are every module whose declarations its `generate` must read: the modules its files
/// refer to and, through them, the modules those refer to. That is what a Bazel user lists in `safedi_compile`'s
/// `deps`, since a `.safedi` holds only its own module's declarations, so a module whose tree reaches a declaration
/// two modules down must list that module too (`multiModuleTest_throwsErrorForGrandparentDeclaration_whenModuleInfoListsOnlyTheDirectDependency`
/// pins that). The plugin integration lists the transitive closure's files itself, so both integrations read exactly
/// the same declarations for each module. `referencedModuleNames` keeps the modules a module's files refer to
/// directly, which its files import.
struct GraphFuzzerPartition: Equatable, Sendable {
	struct Module: Equatable, Sendable {
		let name: String
		/// The indices of the module's files among the projected files (`projectedFiles(of:)`), increasing.
		let fileIndices: [Int]
		/// The modules whose declarations the module's files refer to, in module order.
		let referencedModuleNames: [String]
		/// Every module whose declarations the module's `generate` reads, in module order: the modules its files
		/// refer to, and the modules those refer to, through any chain.
		let dependencies: [String]
	}

	/// The modules, in dependency order: each depends only on modules before it.
	let modules: [Module]
	/// The modules each projected file refers to, in module order, by file index: the `import` lines the file is given.
	let importedModuleNamesByFileIndex: [[String]]
	/// The projected files' names: the fixture's files' names, as `executeSafeDIToolTest` and
	/// `executeSafeDIToolMultiModuleTest` name them, then `helperFileName` when the graph declares helper types.
	let fileNames: [String]

	/// A file of the graph as the partition projects it: the fixture's files, less the declarations of the helper types
	/// `Value` and `Unbuildable<n>`, which the generator writes into `Root0`'s file and which this projection moves into
	/// a file of their own. Left there, every type of `Root0`'s tree that names them, with the files between, would
	/// share `Root0`'s component, so `Root0` could never be split from a type of its tree that forwards `lazyValue`.
	struct ProjectedFile: Equatable, Sendable {
		let name: String
		let content: String
	}

	/// The name of the file the helper types are moved into. It refers to nothing and is visited first, so it is the
	/// first component and always lands in `Alpha`.
	static func helperFileName(of fixture: GraphFuzzerFixture) -> String {
		"\(fixture.typeNamePrefix)Helpers.swift"
	}

	/// `fixture`'s files as the partition projects them, each named as the harness names it, with the helper types'
	/// declarations – one-line `public final class` declarations of `<prefix>Value` and `<prefix>Unbuildable<n>`, under
	/// any letter a renaming moves the prefix to – moved out of the file declaring them, each with the blank line
	/// before it, into a last file named `helperFileName(of:)`. A fixture that declares none projects to its own files.
	static func projectedFiles(of fixture: GraphFuzzerFixture) -> [ProjectedFile] {
		let helperExpression = try! NSRegularExpression(
			pattern: "^public final class [A-Za-z]" + NSRegularExpression.escapedPattern(for: String(fixture.typeNamePrefix.dropFirst())) + "(?:Value|Unbuildable[0-9]+)(?::[^{]*)? \\{\\}$",
		)
		var projectedFiles = [ProjectedFile]()
		var helperDeclarations = [String]()
		for (fileName, content) in zip(fixture.fileNames, fixture.swiftFileContent) {
			var keptLines = [Substring]()
			for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
				let source = String(line)
				if helperExpression.firstMatch(in: source, range: NSRange(location: 0, length: (source as NSString).length)) != nil {
					helperDeclarations.append(source)
					if keptLines.last?.isEmpty == true {
						keptLines.removeLast()
					}
				} else {
					keptLines.append(line)
				}
			}
			projectedFiles.append(ProjectedFile(name: fileName, content: keptLines.joined(separator: "\n")))
		}
		if !helperDeclarations.isEmpty {
			projectedFiles.append(ProjectedFile(name: helperFileName(of: fixture), content: helperDeclarations.joined(separator: "\n\n") + "\n"))
		}
		return projectedFiles
	}

	/// The names the modules take, in dependency order. Each holds no digit, so no renaming rewrites it. The two
	/// integrations combine a module's declarations with its dependencies' in different orders: `generate` lists the
	/// dependencies' `.safedi` files, which the module-info integration reads in path order, before the module's own
	/// declarations, while the plugin integration parses every module's files in path order (`Sources/<Module>/…`),
	/// the module's own among them. The first three names sort in dependency order, so for one to three modules the
	/// orders agree; `Delta` sorts before `Gamma`, so in a four-module graph whose `Delta` depends on `Gamma` – otherwise
	/// `Gamma`'s files are not in `Delta`'s CSV and its `.safedi` is not read – the plugin combines `Delta`'s own
	/// declarations before `Gamma`'s where the module-info integration combines them after. That is deliberate: a real
	/// package's module directories sort arbitrarily against a Bazel build's `.safedi` paths, so those graphs (503 of
	/// the corpus's 5000, counted on the long run's `partitions` report line) check that nothing SafeDI generates or
	/// reports depends on that order.
	static let moduleNames = ["Alpha", "Beta", "Gamma", "Delta"]

	/// The one package every module belongs to: the plugin integration spells each file relative to it.
	static let packageName = "Graph"

	/// The partition of `fixture`'s files.
	///
	/// - Parameter moduleCount: How many modules to split the files into, as far as their components allow, or `nil`
	///   for the count `moduleCount(forComponentCount:of:)` chooses, which the oracle uses.
	static func partition(of fixture: GraphFuzzerFixture, moduleCount requestedModuleCount: Int? = nil) -> GraphFuzzerPartition {
		let prefix = NSRegularExpression.escapedPattern(for: fixture.typeNamePrefix)
		let declarationExpression = try! NSRegularExpression(pattern: "(?:class|protocol|extension)\\s+(" + prefix + "[A-Za-z0-9_]+)")
		let referenceExpression = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_])" + prefix + "[A-Za-z0-9_]+")
		func matches(of expression: NSRegularExpression, in content: String, group: Int) -> [String] {
			let source = content as NSString
			return expression.matches(in: content, range: NSRange(location: 0, length: source.length)).map {
				source.substring(with: $0.range(at: group))
			}
		}
		let projectedFiles = projectedFiles(of: fixture)
		let fileCount = projectedFiles.count
		var declaringFileIndexByName = [String: Int]()
		for (fileIndex, file) in projectedFiles.enumerated() {
			for name in matches(of: declarationExpression, in: file.content, group: 1) where declaringFileIndexByName[name] == nil {
				declaringFileIndexByName[name] = fileIndex
			}
		}
		// The files each file refers to, other than itself, increasing.
		let referencedFileIndices: [[Int]] = projectedFiles.enumerated().map { fileIndex, file in
			Set(matches(of: referenceExpression, in: file.content, group: 0).compactMap { declaringFileIndexByName[$0] })
				.subtracting([fileIndex])
				.sorted()
		}

		// The helper types' file is the last projected file, when there is one; visited first, it is the first component.
		let helperFileIndex = projectedFiles.count > fixture.swiftFileContent.count ? projectedFiles.count - 1 : nil
		let components = stronglyConnectedComponents(ofFileCount: fileCount, visitingFirst: helperFileIndex, referencedFileIndices: referencedFileIndices)
		let moduleCount = requestedModuleCount.map { min(components.count, $0) } ?? moduleCount(forComponentCount: components.count, of: fixture)
		var moduleIndexByFileIndex = [Int](repeating: 0, count: fileCount)
		var fileIndicesByModule = [[Int]](repeating: [], count: moduleCount)
		for (componentIndex, component) in components.enumerated() {
			let moduleIndex = componentIndex * moduleCount / components.count
			for fileIndex in component {
				moduleIndexByFileIndex[fileIndex] = moduleIndex
				fileIndicesByModule[moduleIndex].append(fileIndex)
			}
		}
		let importedModuleIndicesByFileIndex: [[Int]] = (0..<fileCount).map { fileIndex in
			Set(referencedFileIndices[fileIndex].map { moduleIndexByFileIndex[$0] }).subtracting([moduleIndexByFileIndex[fileIndex]]).sorted()
		}
		let referencedModuleIndicesByModule: [[Int]] = fileIndicesByModule.map { fileIndices in
			Set(fileIndices.flatMap { importedModuleIndicesByFileIndex[$0] }).sorted()
		}
		var dependenciesByModule = [[Int]]()
		for moduleIndex in 0..<moduleCount {
			// Each referenced module is earlier, so its dependencies are already known.
			var dependencies = Set(referencedModuleIndicesByModule[moduleIndex])
			for referencedModuleIndex in referencedModuleIndicesByModule[moduleIndex] {
				dependencies.formUnion(dependenciesByModule[referencedModuleIndex])
			}
			dependenciesByModule.append(dependencies.sorted())
		}
		return GraphFuzzerPartition(
			modules: (0..<moduleCount).map { moduleIndex in
				Module(
					name: moduleNames[moduleIndex],
					fileIndices: fileIndicesByModule[moduleIndex].sorted(),
					referencedModuleNames: referencedModuleIndicesByModule[moduleIndex].map { moduleNames[$0] },
					dependencies: dependenciesByModule[moduleIndex].map { moduleNames[$0] },
				)
			},
			importedModuleNamesByFileIndex: importedModuleIndicesByFileIndex.map { $0.map { moduleNames[$0] } },
			fileNames: projectedFiles.map(\.name),
		)
	}

	/// How many modules a graph with `componentCount` components is split into: one to four, as many as the
	/// components allow, chosen by the graph's text so that about a quarter of the graphs with enough components
	/// get each count.
	static func moduleCount(forComponentCount componentCount: Int, of fixture: GraphFuzzerFixture) -> Int {
		var hash = GraphFuzzerHash()
		hash.combine(fixture.description)
		return min(componentCount, 1 + Int(hash.value % UInt64(moduleNames.count)))
	}

	/// The module fixtures of `fixture` split by this partition, in dependency order, for
	/// `executeSafeDIToolMultiModuleTest`. Each file is its projected content with an `import` line for each module it
	/// refers to before it; the helper types' file is named `helperFileName(of:)` explicitly, the rest after the type
	/// each declares. With a `renaming`, the files are those of `fixture.renamed(by:)`, which lists the fixture's files
	/// in reverse order, named as `renaming.fileNames(of:)` names them.
	func moduleFixtures(of fixture: GraphFuzzerFixture, renamedBy renaming: GraphFuzzerRenaming? = nil) -> [ModuleFixture] {
		let renamedFixture = renaming.map(fixture.renamed(by:)) ?? fixture
		let renamedFileNames = renaming.flatMap { $0.fileNames(of: renamedFixture) }
		let renamedProjectedFiles = Self.projectedFiles(of: renamedFixture)
		let fixtureFileCount = fixture.swiftFileContent.count
		func renamedIndex(ofFileAt fileIndex: Int) -> Int {
			renaming == nil || fileIndex >= fixtureFileCount ? fileIndex : fixtureFileCount - 1 - fileIndex
		}
		return modules.map { module in
			var swiftFileContent = [String]()
			var swiftFileContentByFilePath = [String: String]()
			for fileIndex in module.fileIndices {
				let importLines = importedModuleNamesByFileIndex[fileIndex].map { "import \($0)\n" }.joined()
				let renamedFile = renamedProjectedFiles[renamedIndex(ofFileAt: fileIndex)]
				let content = (importLines.isEmpty ? "" : importLines + "\n") + renamedFile.content
				if fileIndex >= fixtureFileCount {
					swiftFileContentByFilePath[renamedFile.name] = content
				} else if let renamedFileNames {
					swiftFileContentByFilePath[renamedFileNames[renamedIndex(ofFileAt: fileIndex)]] = content
				} else {
					swiftFileContent.append(content)
				}
			}
			return ModuleFixture(
				name: module.name,
				packageName: Self.packageName,
				swiftFileContent: swiftFileContent,
				swiftFileContentByFilePath: swiftFileContentByFilePath,
				dependencies: module.dependencies,
			)
		}
	}

	/// The partition, one module per line: its name, the modules it depends on, and its files, each with the
	/// modules it imports.
	var description: String {
		modules.map { module in
			let dependencies = module.dependencies.isEmpty ? "" : " (depends on \(module.dependencies.joined(separator: ", ")))"
			let files = module.fileIndices.map { fileIndex in
				let imports = importedModuleNamesByFileIndex[fileIndex]
				return fileNames[fileIndex] + (imports.isEmpty ? "" : " importing \(imports.joined(separator: ", "))")
			}
			return "\(module.name)\(dependencies): \(files.joined(separator: ", "))"
		}.joined(separator: "\n")
	}

	/// The strongly connected components of the files' reference graph, each increasing, listed after every
	/// component they refer to, as Tarjan's algorithm lists them when it visits the file at `firstFile`, if any, and
	/// then the files in order.
	private static func stronglyConnectedComponents(ofFileCount fileCount: Int, visitingFirst firstFile: Int?, referencedFileIndices: [[Int]]) -> [[Int]] {
		var indexByFile = [Int?](repeating: nil, count: fileCount)
		var lowLinkByFile = [Int](repeating: 0, count: fileCount)
		var isOnStack = [Bool](repeating: false, count: fileCount)
		var stack = [Int]()
		var nextIndex = 0
		var components = [[Int]]()
		// A graph has at most a few dozen files, so the depth of the recursion is bounded by that.
		func visit(_ file: Int) {
			indexByFile[file] = nextIndex
			lowLinkByFile[file] = nextIndex
			nextIndex += 1
			stack.append(file)
			isOnStack[file] = true
			for referencedFile in referencedFileIndices[file] {
				if let referencedIndex = indexByFile[referencedFile] {
					if isOnStack[referencedFile] {
						lowLinkByFile[file] = min(lowLinkByFile[file], referencedIndex)
					}
				} else {
					visit(referencedFile)
					lowLinkByFile[file] = min(lowLinkByFile[file], lowLinkByFile[referencedFile])
				}
			}
			guard lowLinkByFile[file] == indexByFile[file] else { return }
			var component = [Int]()
			while let member = stack.popLast() {
				isOnStack[member] = false
				component.append(member)
				guard member != file else { break }
			}
			components.append(component.sorted())
		}
		for file in [firstFile].compactMap(\.self) + Array(0..<fileCount) where indexByFile[file] == nil {
			visit(file)
		}
		return components
	}
}

// MARK: - Generated units

/// The generated code of one module under one integration, reduced to what both integrations produce: each generated
/// extension, keyed as the plugin names the file it would write (`<Type>+SafeDI.swift` for a root's dependency tree,
/// `<Type>+SafeDIMock.swift` for a mock, and `<Type>+SafeDIMockConfiguration.swift` for a type's
/// `SafeDIMockConfiguration` struct, which the plugin writes in the type's own mock file when this module generates
/// its mock, else in `SafeDIMockConfiguration.swift`), with the `#if` the mock condition wraps it in; the `import` lines of the generated
/// files' headers; and the warnings `generate` reported. The plugin writes one file per root and per mock, each under
/// its own header, where the module-info integration writes one combined file under one header, with the bodies
/// joined; splitting both into extensions is what makes them comparable. Compile-time assertions, which the two
/// integrations place differently when a module has `#if` content, are kept as a unit of their own; the fuzzer emits
/// no `#if`, so none appear.
struct GraphFuzzerGeneratedModule: Equatable, Sendable {
	/// The generated extensions' code by unit name, each with every path under the fixture root reduced to
	/// `<fixture-directory>/…`, so that both integrations' `#sourceLocation` directives read the same.
	var units: [String: String]
	/// The `import` lines of each generated file's header, sorted and unique, by file name: the plugin's files each
	/// carry their own header, and the module-info integration's one combined file carries one.
	var importsByFileName: [String: [String]]
	var warnings: [String]

	/// The name of the unit `<Type>+SafeDI.swift` names, when it is one.
	static func rootTypeName(ofUnitNamed unitName: String) -> String? {
		guard unitName.hasSuffix(dependencyTreeUnitSuffix) else { return nil }
		return String(unitName.dropLast(dependencyTreeUnitSuffix.count))
	}

	/// Adds the units and the header imports of one generated file, which may be the combined file, named `fileName`.
	static func parsingGeneratedFile(_ code: String, named fileName: String, into module: inout GraphFuzzerGeneratedModule) {
		let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
		var imports = [String]()
		var index = 0
		var condition: String?
		var unparsedLines = [Substring]()
		/// Adds the unit under `name`, or under `name (2)`, `name (3)`, … when the name is taken: an extension emitted
		/// twice is a defect worth seeing. Each of the plugin's files repeats the module's compile-time assertions,
		/// which make one unit.
		func append(unitNamed name: String, code: String) {
			guard name != Self.assertionsUnitName || module.units[name] != code else { return }
			var unitName = name
			var repetition = 1
			while module.units[unitName] != nil {
				repetition += 1
				unitName = "\(name) (\(repetition))"
			}
			module.units[unitName] = code
		}
		while index < lines.count {
			let line = lines[index]
			if line.isEmpty || line.hasPrefix("//") {
				index += 1
			} else if line.hasPrefix("#if canImport(") {
				index += 1
				while index < lines.count, lines[index] != "#endif" {
					imports.append(String(lines[index]))
					index += 1
				}
				index += 1
			} else if line.hasPrefix("#if "), index + 1 < lines.count, lines[index + 1].hasPrefix("#error(") {
				var assertionLines = [line]
				index += 1
				while index < lines.count, lines[index] != "#endif" {
					assertionLines.append(lines[index])
					index += 1
				}
				assertionLines.append("#endif")
				index += 1
				append(unitNamed: Self.assertionsUnitName, code: assertionLines.joined(separator: "\n"))
			} else if line.hasPrefix("#if ") {
				condition = String(line.dropFirst("#if ".count))
				index += 1
			} else if line == "#endif" {
				condition = nil
				index += 1
			} else if line.hasPrefix("extension "), line.hasSuffix(" {") {
				let typeName = String(line.dropFirst("extension ".count).dropLast(" {".count))
				var extensionLines = [line]
				index += 1
				while index < lines.count {
					extensionLines.append(lines[index])
					index += 1
					guard extensionLines[extensionLines.count - 1] != "}" else { break }
				}
				let body = extensionLines.joined(separator: "\n")
				let unitName: String
				let unitCode: String
				if let condition {
					unitCode = "#if \(condition)\n\(body)\n#endif"
					unitName = if body.contains("static func mock(") {
						typeName + "+SafeDIMock.swift"
					} else if body.contains("struct SafeDIMockConfiguration") {
						typeName + "+SafeDIMockConfiguration.swift"
					} else {
						"\(typeName)+\(condition).swift"
					}
				} else {
					unitCode = body
					unitName = typeName + Self.dependencyTreeUnitSuffix
				}
				append(unitNamed: unitName, code: unitCode)
			} else {
				unparsedLines.append(line)
				index += 1
			}
		}
		if !unparsedLines.isEmpty {
			append(unitNamed: Self.unparsedUnitName, code: unparsedLines.joined(separator: "\n"))
		}
		module.importsByFileName[fileName] = Array(Set(imports)).sorted()
	}

	private static let dependencyTreeUnitSuffix = "+SafeDI.swift"
	private static let assertionsUnitName = "<compile-time assertions>"
	private static let unparsedUnitName = "<lines outside any extension>"
}

/// What one multi-module integration did with a partitioned graph: each module's verdict, in dependency order, up to
/// and including the first module whose `generate` failed, where the harness stops, as a build would.
struct GraphFuzzerMultiModuleOutcome: Equatable, Sendable {
	struct ModuleVerdict: Equatable, Sendable {
		enum Kind: Equatable, Sendable {
			/// The integration ran no `generate` for the module: the plugin adds a build command only for a module
			/// whose manifest plans an output, a dependency tree for a root in the module or in a module it depends on,
			/// or a mock for one of its own types.
			case skipped
			case accepted(GraphFuzzerGeneratedModule)
			case rejected(diagnostics: String)
		}

		let moduleName: String
		let kind: Kind
	}

	/// The modules' verdicts, in dependency order. A module after one the integration rejected has none.
	let verdicts: [ModuleVerdict]

	/// Whether the integration generated every module.
	var isAccepted: Bool {
		verdicts.allSatisfy { verdict in
			switch verdict.kind {
			case .skipped, .accepted:
				true
			case .rejected:
				false
			}
		}
	}

	/// The first aspect in which the module-info integration's outcome and the plugin's differ, or `nil` when
	/// they agree, module by module in dependency order: a module both generated must have the same generated units,
	/// each byte for byte, the imports of the combined file in each of the plugin's files (the plugin's dependency-tree
	/// and mock files import what each kind needs, which differs only through `#if`-guarded imports, which no fuzzer
	/// graph has, so one file lacking an import is not covered by another having it), and the same warnings; a module the plugin skipped
	/// must generate nothing under the module-info integration; and a module the module-info integration rejects must
	/// be rejected with the same diagnostics (compared as `GraphFuzzerToolOutcome.difference` compares them) by the
	/// plugin – at the module itself when the plugin runs `generate` for it, and otherwise at the first module after
	/// it, among those that depend on it, for which the plugin runs `generate`, whose inputs are the first to hold the
	/// module's files. When no such module runs, the plugin reports nothing: a defect a module's declarations alone
	/// reveal, such as two types fulfilling one protocol, goes undiagnosed by the plugin until a consumer generates,
	/// which is the plugin's design rather than a difference in the tool, so the outcomes agree. A module the plugin
	/// rejects for a reason of its own before that consumer, one that does not depend on the rejected module, is one
	/// the module-info integration never reached, so nothing is compared there either.
	///
	/// - Parameter modules: The partition's modules, in dependency order.
	static func difference(betweenModuleInfo moduleInfoOutcome: GraphFuzzerMultiModuleOutcome, andPlugin pluginOutcome: GraphFuzzerMultiModuleOutcome, modules: [GraphFuzzerPartition.Module]) -> String? {
		let pluginKindsByModuleName = Dictionary(uniqueKeysWithValues: pluginOutcome.verdicts.map { ($0.moduleName, $0.kind) })
		/// How the plugin's verdict on the module it first reads `moduleName`'s files in, among those depending on
		/// it, differs from the module-info integration's rejection of `moduleName` with `diagnostics`.
		func differenceAtConsumer(ofSkippedModuleNamed moduleName: String, rejectedWith diagnostics: String) -> String? {
			for consumer in modules where consumer.dependencies.contains(moduleName) {
				switch pluginKindsByModuleName[consumer.name] {
				case .skipped?:
					continue
				case let .rejected(otherDiagnostics)?:
					return difference(betweenDiagnostics: diagnostics, and: otherDiagnostics, inModuleNamed: moduleName).map { "\($0) (which .swiftPackagePlugin reports in module \(consumer.name))" }
				case .accepted?:
					return "its verdict for module \(moduleName) (.moduleInfo rejects it, while .swiftPackagePlugin plans no output for it and accepts module \(consumer.name), which depends on it)"
				case nil:
					// The plugin stopped before this consumer, at a module that does not depend on this one and
					// that the module-info integration never reached.
					return nil
				}
			}
			return nil
		}
		for verdict in moduleInfoOutcome.verdicts {
			let moduleName = verdict.moduleName
			let difference: String? = switch (verdict.kind, pluginKindsByModuleName[moduleName]) {
			case let (.accepted(module), .accepted(otherModule)?):
				difference(between: module, and: otherModule, inModuleNamed: moduleName)
			case let (.accepted(module), .skipped?):
				module.units.isEmpty
					? nil
					: "the generated units of module \(moduleName) (\(module.units.keys.sorted().joined(separator: ", ")) under .moduleInfo, while .swiftPackagePlugin plans no output for it)"
			case (.accepted, .rejected?):
				"its verdict for module \(moduleName) (.moduleInfo accepts it, .swiftPackagePlugin rejects it)"
			case (.accepted, nil):
				// The plugin stopped at an earlier module, which it rejected and the module-info integration accepted:
				// reported there.
				"its verdict for module \(moduleName) (.moduleInfo accepts it, .swiftPackagePlugin never reached it)"
			case let (.rejected(diagnostics), .rejected(otherDiagnostics)?):
				difference(betweenDiagnostics: diagnostics, and: otherDiagnostics, inModuleNamed: moduleName)
			case (.rejected, .accepted?):
				"its verdict for module \(moduleName) (.moduleInfo rejects it, .swiftPackagePlugin accepts it)"
			case let (.rejected(diagnostics), .skipped?):
				// The plugin reads the module's files first where a module that depends on it generates.
				differenceAtConsumer(ofSkippedModuleNamed: moduleName, rejectedWith: diagnostics)
			case (.rejected, nil):
				"its verdict for module \(moduleName) (.moduleInfo rejects it, .swiftPackagePlugin never reached it)"
			case (.skipped, .skipped?), (.skipped, .accepted?), (.skipped, .rejected?), (.skipped, nil):
				// The module-info integration runs `generate` for every module.
				"its verdict for module \(moduleName) (.moduleInfo ran no generate for it)"
			}
			if let difference {
				return difference
			} else {
				continue
			}
		}
		// The module-info integration runs `generate` for every module, so it reached them all unless it rejected one,
		// which is the last verdict it lists, and a module the plugin rejected was compared above too.
		return nil
	}

	private static func difference(between module: GraphFuzzerGeneratedModule, and otherModule: GraphFuzzerGeneratedModule, inModuleNamed moduleName: String) -> String? {
		guard Set(module.units.keys) == Set(otherModule.units.keys) else {
			return "the generated units of module \(moduleName) (\(module.units.keys.sorted().joined(separator: ", ")) under .moduleInfo, \(otherModule.units.keys.sorted().joined(separator: ", ")) under .swiftPackagePlugin)"
		}
		for unitName in module.units.keys.sorted() where module.units[unitName] != otherModule.units[unitName] {
			let kind = if unitName.hasSuffix("+SafeDIMock.swift") {
				"generated mock code"
			} else if unitName.hasSuffix("+SafeDIMockConfiguration.swift") {
				"generated mock configuration code"
			} else if GraphFuzzerGeneratedModule.rootTypeName(ofUnitNamed: unitName) != nil {
				"generated dependency tree code"
			} else {
				"generated code"
			}
			return "the \(kind) of module \(moduleName), in \(unitName)"
		}
		// The combined file imports what the dependency trees and the mocks need together, and the plugin's files
		// each import what their kind needs, which differs only through `#if`-guarded imports, which no fuzzer graph
		// has: so every one of the plugin's files must import exactly what the combined file imports.
		let expectedImports = module.importsByFileName.sorted { $0.key < $1.key }.first?.value ?? []
		for (fileName, imports) in otherModule.importsByFileName.sorted(by: { $0.key < $1.key }) where imports != expectedImports {
			return "the imports of module \(moduleName)'s generated file \(fileName) (\(imports.joined(separator: "; ")) under .swiftPackagePlugin, against \(expectedImports.joined(separator: "; ")) under .moduleInfo)"
		}
		guard module.warnings.sorted() == otherModule.warnings.sorted() else {
			return "the warnings of module \(moduleName)"
		}
		return nil
	}

	private static func difference(betweenDiagnostics diagnostics: String, and otherDiagnostics: String, inModuleNamed moduleName: String) -> String? {
		guard GraphFuzzerToolOutcome.difference(between: .rejected(diagnostics: diagnostics), and: .rejected(diagnostics: otherDiagnostics)) == nil else {
			return "the diagnostics of module \(moduleName)"
		}
		return nil
	}

	var description: String {
		verdicts.map { verdict in
			switch verdict.kind {
			case .skipped:
				"module \(verdict.moduleName): no generate run"
			case let .rejected(diagnostics):
				"module \(verdict.moduleName): rejected:\n\(diagnostics)"
			case let .accepted(module):
				"module \(verdict.moduleName), warnings \(module.warnings):\n"
					+ module.importsByFileName.keys.sorted().map { "// \($0) imports \(module.importsByFileName[$0, default: []].joined(separator: "; "))\n" }.joined()
					+ module.units.keys.sorted().map { "// \($0)\n\(module.units[$0, default: ""])" }.joined(separator: "\n")
			}
		}.joined(separator: "\n")
	}
}

// MARK: - Property

/// A partitioned graph with what each multi-module integration produced for it.
struct GraphFuzzerMultiModuleRuns: Sendable {
	let seed: UInt64
	let partition: GraphFuzzerPartition
	/// The renaming the graph was run under, or `nil` for the graph as generated.
	let renaming: GraphFuzzerRenaming?
	let moduleInfoOutcome: GraphFuzzerMultiModuleOutcome
	/// What the plugin produced, less the roots `regeneratedRoots` lists.
	let pluginOutcome: GraphFuzzerMultiModuleOutcome
	/// The roots the plugin wrote again in a module because a module it depends on declares them, in dependency
	/// order of the consuming module and then by root name, each with how its code differs from the declaring
	/// module's own, when it does.
	let regeneratedRoots: [GraphFuzzerRegeneratedRoot]

	/// Whether the module-info integration, which runs `generate` for every module, generated every module.
	var isAccepted: Bool {
		moduleInfoOutcome.isAccepted
	}

	/// The failure of a graph the two integrations give other results for, or `nil` when they agree: the plugin
	/// output writes a dependency's root again with other code than the dependency's own, or the outcomes differ in
	/// the first aspect `GraphFuzzerMultiModuleOutcome.difference` finds.
	var failure: GraphFuzzerFailure? {
		let graph = renaming.map { "\($0.description.prefix(1).uppercased())\($0.description.dropFirst()) and split into modules, the graph" } ?? "Split into modules, the graph"
		let summary: String
		if let regeneratedRootDifference = regeneratedRoots.compactMap(\.difference).first {
			summary = "\(graph) \(regeneratedRootDifference)"
		} else if let difference = GraphFuzzerMultiModuleOutcome.difference(betweenModuleInfo: moduleInfoOutcome, andPlugin: pluginOutcome, modules: partition.modules) {
			summary = "\(graph) differs between the .moduleInfo and .swiftPackagePlugin integrations in \(difference)."
		} else {
			return nil
		}
		return GraphFuzzerFailure(
			seed: seed,
			kind: .integrationsDiffer,
			details: "\(summary)\nModules:\n\(partition.description)\nUnder .moduleInfo:\n\(moduleInfoOutcome.description)\nUnder .swiftPackagePlugin:\n\(pluginOutcome.description)",
		)
	}
}

/// A root the plugin wrote again in a module's output because a module it depends on declares it: the plugin's
/// `scan` plans a dependency-tree file for every root in its CSV, which lists the files of the modules the module
/// depends on, where the module-info integration writes only the module's own roots.
struct GraphFuzzerRegeneratedRoot: Equatable, Sendable {
	let consumerModuleName: String
	let declaringModuleName: String
	let rootTypeName: String
	/// How the consumer's code for the root differs from the declaring module's own, or `nil` when it reads the same.
	let difference: String?
}

/// Runs a graph, split by its partition, through both multi-module integrations.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum GraphFuzzerMultiModuleProperty {
	/// Runs `fixture`, split by `partition` and renamed by `renaming`, through `executeSafeDIToolMultiModuleTest`
	/// under each integration, without compiling, and reduces what each produced to a `GraphFuzzerMultiModuleOutcome`.
	static func runs(of fixture: GraphFuzzerFixture, partition: GraphFuzzerPartition, renaming: GraphFuzzerRenaming? = nil) async throws -> GraphFuzzerMultiModuleRuns {
		let modules = partition.moduleFixtures(of: fixture, renamedBy: renaming)
		let moduleInfoOutcome = try await outcome(of: modules, integration: .moduleInfo, seed: fixture.seed)
		var pluginVerdicts = try await outcome(of: modules, integration: .swiftPackagePlugin, seed: fixture.seed).verdicts
		let regeneratedRoots = removingRegeneratedRoots(
			from: &pluginVerdicts,
			moduleNameByDeclaredTypeName: moduleNameByDeclaredTypeName(of: modules),
			dependenciesByModuleName: Dictionary(uniqueKeysWithValues: partition.modules.map { ($0.name, $0.dependencies) }),
		)
		return GraphFuzzerMultiModuleRuns(
			seed: fixture.seed,
			partition: partition,
			renaming: renaming,
			moduleInfoOutcome: moduleInfoOutcome,
			pluginOutcome: GraphFuzzerMultiModuleOutcome(verdicts: pluginVerdicts),
			regeneratedRoots: regeneratedRoots,
		)
	}

	/// Removes from the plugin's `verdicts` each root a module wrote again because a module it depends on declares it
	/// (`GraphFuzzerRegeneratedRoot`), and returns those roots, each compared with the declaring module's own code
	/// for it, which it must read exactly as. A root of a type declared in a module the consumer does not depend on
	/// is kept: the plugin's CSV holds no file of that module, so such a unit is the consumer's own.
	///
	/// - Parameters:
	///   - moduleNameByDeclaredTypeName: The module declaring each type, by the type's name
	///     (`moduleNameByDeclaredTypeName(of:)`).
	///   - dependenciesByModuleName: Every module each module depends on, directly or through another.
	static func removingRegeneratedRoots(
		from verdicts: inout [GraphFuzzerMultiModuleOutcome.ModuleVerdict],
		moduleNameByDeclaredTypeName: [String: String],
		dependenciesByModuleName: [String: [String]],
	) -> [GraphFuzzerRegeneratedRoot] {
		var regeneratedRoots = [GraphFuzzerRegeneratedRoot]()
		for (index, verdict) in verdicts.enumerated() {
			guard case var .accepted(generatedModule) = verdict.kind else { continue }
			for unitName in generatedModule.units.keys.sorted() {
				guard let rootTypeName = GraphFuzzerGeneratedModule.rootTypeName(ofUnitNamed: unitName),
				      let declaringModuleName = moduleNameByDeclaredTypeName[rootTypeName],
				      dependenciesByModuleName[verdict.moduleName, default: []].contains(declaringModuleName)
				else { continue }
				let regeneratedCode = generatedModule.units.removeValue(forKey: unitName)
				let declaringModuleCode: String? = verdicts.first { $0.moduleName == declaringModuleName }.flatMap { declaringVerdict in
					switch declaringVerdict.kind {
					case let .accepted(declaringModule):
						declaringModule.units[unitName]
					case .skipped, .rejected:
						nil
					}
				}
				regeneratedRoots.append(GraphFuzzerRegeneratedRoot(
					consumerModuleName: verdict.moduleName,
					declaringModuleName: declaringModuleName,
					rootTypeName: rootTypeName,
					difference: regeneratedCode == declaringModuleCode
						? nil
						: "has \(declaringModuleName)'s root \(rootTypeName) written again by the .swiftPackagePlugin integration in module \(verdict.moduleName) with other code than \(declaringModuleName)'s own:\n\(regeneratedCode ?? "")\nagainst\n\(declaringModuleCode ?? "nothing")",
				))
			}
			verdicts[index] = GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: verdict.moduleName, kind: .accepted(generatedModule))
		}
		return regeneratedRoots
	}

	/// The module declaring each type a module's files declare, by the type's name.
	static func moduleNameByDeclaredTypeName(of modules: [ModuleFixture]) -> [String: String] {
		let declarationExpression = try! NSRegularExpression(pattern: "(?:class|protocol|extension)\\s+([A-Za-z0-9_]+)")
		var moduleNameByDeclaredTypeName = [String: String]()
		for module in modules {
			for content in module.swiftFileContent + module.swiftFileContentByFilePath.keys.sorted().map({ module.swiftFileContentByFilePath[$0]! }) {
				let source = content as NSString
				for match in declarationExpression.matches(in: content, range: NSRange(location: 0, length: source.length)) {
					let typeName = source.substring(with: match.range(at: 1))
					if moduleNameByDeclaredTypeName[typeName] == nil {
						moduleNameByDeclaredTypeName[typeName] = module.name
					}
				}
			}
		}
		return moduleNameByDeclaredTypeName
	}

	/// `text` with each path under a fixture root – a directory named by a UUID under the temporary directory,
	/// however that directory is spelled: through `/private` or not – reduced to `<fixture-directory>/…`, so the
	/// paths both integrations cite in `#sourceLocation` directives and in diagnostics read the same. The harness
	/// spells the root two ways, as `FileManager.default.temporaryDirectory` spells it and resolved with `realpath(3)`,
	/// and both end in the UUID component, so one expression covers both without threading the root, which the
	/// harness's error does not carry, through to here; everything after the root is kept.
	static func reducingFixtureRootPaths(in text: String) -> String {
		text.replacingOccurrences(
			of: #"[^\s"'`(]*/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/"#,
			with: "<fixture-directory>/",
			options: .regularExpression,
		)
	}

	private static func outcome(of modules: [ModuleFixture], integration: MultiModuleIntegration, seed: UInt64) async throws -> GraphFuzzerMultiModuleOutcome {
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		let outputsByModuleName: [String: ModuleTestOutput]
		var rejection: GraphFuzzerMultiModuleOutcome.ModuleVerdict?
		do {
			outputsByModuleName = try await executeSafeDIToolMultiModuleTest(
				modules: modules,
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			).modules
		} catch let error as SafeDIToolMultiModuleTestError {
			outputsByModuleName = error.outputs
			rejection = GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: error.moduleName, kind: .rejected(diagnostics: reducingFixtureRootPaths(in: "\(error.underlyingError)")))
		} catch {
			throw GraphFuzzerInfrastructureError(description: "The multi-module test harness failed for seed \(seed) under \(integration) before or after SafeDITool ran: \(error)")
		}

		var verdicts = [GraphFuzzerMultiModuleOutcome.ModuleVerdict]()
		for module in modules {
			if let rejection, rejection.moduleName == module.name {
				verdicts.append(rejection)
				break
			}
			// The harness processes every module up to the one it rejects, so a module without an output before that
			// is a harness defect, not a verdict.
			guard let moduleOutput = outputsByModuleName[module.name] else {
				throw GraphFuzzerInfrastructureError(description: "The multi-module test harness produced no output for module \(module.name) of seed \(seed) under \(integration), and rejected no module before it.")
			}
			guard moduleOutput.generateRan else {
				verdicts.append(GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: module.name, kind: .skipped))
				continue
			}
			var generatedModule = GraphFuzzerGeneratedModule(units: [:], importsByFileName: [:], warnings: moduleOutput.warnings.map { reducingFixtureRootPaths(in: "\($0)") })
			for fileName in moduleOutput.generatedFiles.keys.sorted() {
				GraphFuzzerGeneratedModule.parsingGeneratedFile(reducingFixtureRootPaths(in: moduleOutput.generatedFiles[fileName, default: ""]), named: fileName, into: &generatedModule)
			}
			verdicts.append(GraphFuzzerMultiModuleOutcome.ModuleVerdict(moduleName: module.name, kind: .accepted(generatedModule)))
		}
		return GraphFuzzerMultiModuleOutcome(verdicts: verdicts)
	}
}
