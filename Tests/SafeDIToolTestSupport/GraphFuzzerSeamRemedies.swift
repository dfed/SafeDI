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

// MARK: - Remedy oracle of the seam corpus

/// Follows the advice of the error a seam reports when a fill of a builder it passes up to its own caller receives a value
/// it builds before the call (`boundByPassingUpSeam`): "Declare `@Received let x: X` on `Inner`, so the builder’s scope
/// carries it", which, where the inner seam's module is not the outer seam's, goes on "(if module `M` cannot see a type
/// `x: X` names, first declare that type in module `M` or a module it depends on, with an initializer module `O` can
/// call)". The remedy moves the file of each type the property's type names that is declared in neither `M` nor a module
/// beneath it into `M`, with a `public` initializer, and declares the receive on the inner seam (`receiveOnInnerSeam`).
/// The remedied graph must leave no error at the reader's declaration and, where the tool accepts it, every module must
/// compile with no warning in generated code: the advice must give a graph that builds. Errors elsewhere are allowed, as
/// the base corpus's remedy oracle allows them, and such a graph is not compiled.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum GraphFuzzerSeamRemedies {
	/// The remedy an error states, read from its message.
	struct StatedRemedy: Equatable {
		/// The property the error says to receive on the inner seam.
		let property: GraphFuzzerRemedyProperty
		/// The inner seam the error names.
		let innerSeam: String
		/// The module the error says each type the property names must be declared in or beneath, or `nil` where the error
		/// says to receive the property alone.
		let innerSeamModule: String?

		init?(message: String) {
			guard message.contains(GraphFuzzerSeamRemedies.passedUpBuilderMarker),
			      let match = GraphFuzzerSeamRemedies.remedyExpression?.firstMatch(in: message, range: NSRange(message.startIndex..., in: message))
			else { return nil }
			func group(_ index: Int) -> String? {
				Range(match.range(at: index), in: message).map { String(message[$0]) }
			}
			guard let label = group(1), let type = group(2), let innerSeam = group(3) else { return nil }
			property = GraphFuzzerRemedyProperty(attribute: "@Received", label: label, type: type)
			self.innerSeam = innerSeam
			innerSeamModule = group(4)
		}
	}

	/// What the errors of a passed-up builder's fill say, which no other error says.
	static let passedUpBuilderMarker = "on from its own caller, which cannot hand it"

	private static let remedyExpression = try? NSRegularExpression(pattern: #"Declare `@Received let ([^:`]+): ([^`]+)` on `([^`]+)`, so the builder’s scope carries it(?: \(if module `([^`]+)` cannot see a type)?"#)

	/// The remedy each site of `fixture`, a split graph the tool rejects with `diagnostics`, states, or `nil` for a site
	/// whose errors state such a remedy that cannot be applied as stated: the errors state different remedies, a type to
	/// move is not declared in the fuzzer's form, or a type to move names a type declared only where the inner seam's
	/// module cannot see it, whose declaration the remedy would have to move too.
	static func remedies(of fixture: GraphFuzzerFixture, diagnostics: String) -> [GraphFuzzerRemedy?] {
		guard let modules = fixture.modules, let files = GraphFuzzerRemedies.Files(fixture) else { return [] }
		var sites = [GraphFuzzerRemedy.Site]()
		var errorsBySite = [GraphFuzzerRemedy.Site: [(message: String, remedy: StatedRemedy)]]()
		for diagnosticLine in diagnostics.split(separator: "\n") {
			guard let error = GraphFuzzerRemedies.ReportedError(diagnosticLine),
			      let statedRemedy = StatedRemedy(message: error.message),
			      let site = files.site(of: error)
			else { continue }
			if errorsBySite[site] == nil {
				sites.append(site)
			}
			errorsBySite[site, default: []].append((error.message, statedRemedy))
		}
		return sites.map { site in
			let errors = errorsBySite[site] ?? []
			guard let statedRemedy = errors.first?.remedy, errors.allSatisfy({ $0.remedy == statedRemedy }) else { return nil }
			return remedy(statedRemedy, at: site, answering: errors.map(\.message), in: files, of: fixture, modules: modules)
		}
	}

	/// The sites of `fixture` whose errors state a remedy `remedies(of:diagnostics:)` cannot apply.
	static func unremediedSiteCount(of fixture: GraphFuzzerFixture, diagnostics: String) -> Int {
		remedies(of: fixture, diagnostics: diagnostics).count { $0 == nil }
	}

	private static func remedy(_ statedRemedy: StatedRemedy, at site: GraphFuzzerRemedy.Site, answering errors: [String], in files: GraphFuzzerRemedies.Files, of fixture: GraphFuzzerFixture, modules: [GraphFuzzerModule]) -> GraphFuzzerRemedy? {
		var editedFiles = files
		let property = statedRemedy.property
		guard editedFiles.edit(typeNamed: statedRemedy.innerSeam, { properties in
			properties.contains { $0.label == property.label } ? nil : properties + [property]
		}) else { return nil }
		var contents = editedFiles.contents
		var description = "receives `\(property.label): \(property.type)` on `\(statedRemedy.innerSeam)`"
		if let innerSeamModuleName = statedRemedy.innerSeamModule {
			guard let innerSeamModule = GraphFuzzerModule(rawValue: innerSeamModuleName) else { return nil }
			let visibleModules = Set([innerSeamModule] + innerSeamModule.transitiveDependencies)
			let declaredNames = contents.map { declaredTypeNames(in: $0, prefix: fixture.typeNamePrefix) }
			var movedNames = [String]()
			for name in typeNames(in: property.type, prefix: fixture.typeNamePrefix) {
				let declaringIndices = contents.indices.filter { declaredNames[$0].contains(name) }
				guard declaringIndices.count == 1, let fileIndex = declaringIndices.first else { return nil }
				guard !visibleModules.contains(modules[fileIndex]) else { continue }
				// Every type the moved file names must be one the inner seam's module sees: one the file declares, or one
				// declared in that module or beneath it.
				let namesTheFileNeeds = typeNames(in: contents[fileIndex], prefix: fixture.typeNamePrefix).subtracting(declaredNames[fileIndex])
				guard namesTheFileNeeds.allSatisfy({ neededName in
				      	contents.indices.contains { declaredNames[$0].contains(neededName) && visibleModules.contains(modules[$0]) }
				      }),
				      let movedContent = moving(contents[fileIndex], to: innerSeamModule, of: fixture, presentModules: Set(modules))
				else { return nil }
				contents[fileIndex] = movedContent
				movedNames.append(name)
			}
			if !movedNames.isEmpty {
				description += ", declaring \(movedNames.map { "`\($0)`" }.joined(separator: ", ")) in module `\(innerSeamModuleName)` with a `public` initializer"
			}
		}
		return GraphFuzzerRemedy(
			kind: .receiveOnInnerSeam,
			site: site,
			answeredErrors: errors,
			description: description,
			fixture: GraphFuzzerFixture(seed: fixture.seed, swiftFileContent: contents),
		)
	}

	/// `content`, a file of a split graph, as a file of `module`: its first lines, the module's marker and the imports of
	/// its header, replaced by `module`'s, and each initializer `public`. `nil` for a file without that header.
	private static func moving(_ content: String, to module: GraphFuzzerModule, of fixture: GraphFuzzerFixture, presentModules: Set<GraphFuzzerModule>) -> String? {
		guard GraphFuzzerModule(declaredIn: content) != nil, let headerEnd = content.range(of: "\n\n") else { return nil }
		let body = content[headerEnd.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).map { line in
			let indentation = line.prefix { $0 == "\t" || $0 == " " }
			var declaration = line.dropFirst(indentation.count)
			for modifier in ["public ", "package ", "internal "] where declaration.hasPrefix(modifier) {
				declaration = declaration.dropFirst(modifier.count)
			}
			return declaration.hasPrefix("init(") ? "\(indentation)public \(declaration)" : String(line)
		}
		return module.fileHeader(omitsPackageName: fixture.modulesOmittingPackageName.contains(module), presentModules: presentModules) + body.joined(separator: "\n")
	}

	/// The type names of the graph that `source` names: each word that begins with the graph's type-name prefix.
	private static func typeNames(in source: String, prefix: String) -> Set<String> {
		var names = Set<String>()
		var remaining = Substring(source)
		while let range = remaining.range(of: prefix) {
			let isWordStart = range.lowerBound == remaining.startIndex || !isIdentifierCharacter(remaining[remaining.index(before: range.lowerBound)])
			let name = remaining[range.lowerBound...].prefix(while: isIdentifierCharacter)
			if isWordStart, name.count > prefix.count {
				names.insert(String(name))
			}
			remaining = remaining[range.upperBound...]
		}
		return names
	}

	/// The type names of the graph `source` declares: classes, structs, enums, protocols and typealiases.
	private static func declaredTypeNames(in source: String, prefix: String) -> Set<String> {
		var names = Set<String>()
		for line in source.split(separator: "\n") {
			let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == ":" || $0 == "{" || $0 == "<" || $0 == "=" })
			for (index, word) in words.enumerated().dropLast() where ["class", "struct", "enum", "protocol", "typealias", "actor"].contains(word) && words[index + 1].hasPrefix(prefix) {
				names.insert(String(words[index + 1]))
			}
		}
		return names
	}

	private static func isIdentifierCharacter(_ character: Character) -> Bool {
		character.isLetter || character.isNumber || character == "_"
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerOracle {
	/// Runs SafeDITool over each remedy the errors of `outcome` state for `fixture` (`GraphFuzzerSeamRemedies`), when the
	/// tool rejects a split graph of the seam corpus with a passed-up builder's fill error, as Bazel runs it, and compiles
	/// every module of a remedied graph the tool accepts.
	static func seamRemedyRuns(of fixture: GraphFuzzerFixture, outcome: GraphFuzzerToolOutcome) async throws -> [GraphFuzzerRemedyRun] {
		guard fixture.modules != nil, case let .rejected(diagnostics) = outcome, diagnostics.contains(GraphFuzzerSeamRemedies.passedUpBuilderMarker) else { return [] }
		var runs = [GraphFuzzerRemedyRun]()
		for remedy in GraphFuzzerSeamRemedies.remedies(of: fixture, diagnostics: diagnostics).compactMap(\.self) {
			try await runs.append(compiledRemedyRun(of: remedy))
		}
		return runs
	}

	private static func compiledRemedyRun(of remedy: GraphFuzzerRemedy) async throws -> GraphFuzzerRemedyRun {
		let fixture = remedy.fixture
		guard let modules = fixture.modules else {
			return try await GraphFuzzerRemedyRun(remedy: remedy, outcome: toolOutcome(of: fixture))
		}
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		let fileNames = fixture.fileNames
		let presentModules = Set(modules)
		let moduleFixtures = GraphFuzzerModule.allCases.filter(presentModules.contains).map { module in
			ModuleFixture(
				name: module.name,
				packageName: module.packageName,
				swiftFileContentByFilePath: Dictionary(uniqueKeysWithValues: modules.indices.filter { modules[$0] == module }.map { (fileNames[$0], fixture.swiftFileContent[$0]) }),
				dependencies: fixture.listedDependencies(of: module, modules: modules, listsTransitiveDependencies: false),
				omitsPackageName: fixture.modulesOmittingPackageName.contains(module),
			)
		}
		do {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: moduleFixtures,
				integration: .moduleInfo,
				compileVerification: compileVerificationIsEnabled ? .returningOutcomeOnly : .skipped,
				filesToDelete: &filesToDelete,
			)
			let normalize = normalizer(fixtureDirectory: output.fixtureRoot.path)
			var generatedFiles = [String: String]()
			for moduleName in output.moduleNames {
				for (fileName, contents) in output.modules[moduleName]?.generatedFiles ?? [:] {
					generatedFiles["\(moduleName)/\(fileName)"] = normalize(contents)
				}
			}
			var run = GraphFuzzerRemedyRun(remedy: remedy, outcome: .accepted(generatedFiles: generatedFiles, warnings: []))
			if let compilation = output.compilation {
				if let failure = compilation.failure {
					// The compiler's error lines, each from its file's name on, since the files are staged in a directory of their own.
					let errorLines = failure.standardError.split(separator: "\n").filter { $0.contains("error: ") }.map { $0.split(separator: "/").last ?? $0 }
					run.compilationFailure = "module \(failure.moduleName) does not compile: \(errorLines.prefix(4).joined(separator: " | "))"
				} else if let warnings = compilation.modules.first(where: { !$0.generatedCodeWarnings.isEmpty }) {
					run.compilationFailure = "the generated code of module \(warnings.moduleName) draws warnings: \(warnings.generatedCodeWarnings.map(normalize).joined(separator: " | "))"
				} else {
					run.isCompiled = true
				}
			}
			return run
		} catch let error as SafeDIToolMultiModuleTestError {
			let normalize = normalizer(fixtureDirectory: filesToDelete.first?.path ?? "")
			return GraphFuzzerRemedyRun(remedy: remedy, outcome: .rejected(diagnostics: normalize("\(error.underlyingError)")))
		} catch {
			throw GraphFuzzerInfrastructureError(description: "The test harness failed for seed \(fixture.seed) before or after SafeDITool ran a remedied graph: \(error)")
		}
	}
}

extension GraphFuzzerFixture {
	/// The names of the modules a run of `module`, one of `modules` (the module of each file), lists as its dependencies:
	/// the modules it imports (`GraphFuzzerModule.dependencies`), or with `listsTransitiveDependencies` every module beneath
	/// it, and each module of the graph a file of `module` imports beyond its header (`TypeDeclaration.imports`), as a
	/// Bazel user lists every module a module's roots reach: `HoleCartImpl`, which fills the hole of `HoleCheckout`, two
	/// modules beneath the roots' module, imports `HoleCheckout`'s module, which the roots' module must then list. No
	/// other file imports a module of the graph beyond its header, so every other graph's runs list what they did.
	func listedDependencies(of module: GraphFuzzerModule, modules: [GraphFuzzerModule], listsTransitiveDependencies: Bool) -> [String] {
		let presentModules = Set(modules)
		var listed = Set(listsTransitiveDependencies ? module.transitiveDependencies : module.dependencies)
		for index in modules.indices where modules[index] == module {
			for line in swiftFileContent[index].split(separator: "\n") where line.hasPrefix("import ") {
				if let imported = GraphFuzzerModule(rawValue: String(line.dropFirst("import ".count))), imported != module {
					listed.insert(imported)
				}
			}
		}
		return listed.filter(presentModules.contains).sorted().map(\.name)
	}
}
