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
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The seam-world switch's attack on fills `validateFills` reports (`NodeRecordsObservation.recordsFilledCalls`): for each
/// kind of `FillFinding`, at least twenty graphs whose run reports it, made from the suite's own graphs of that kind
/// (`templates`) by calling their root from another: by value, through an `Instantiator`, a `LazilyInstantiated` or a lazy
/// cycle, once or twice (two fills of each place), beside a sibling or not. Each graph runs with the records of filled
/// calls off and on: the two report the same diagnostics, or both generate, and node records never lay out a root whose
/// fills `validateFills` reports (`checkingNodeRecords`' `acceptedRootWithFillFindings`), nor one whose records differ
/// from its tree's.
struct SafeDIToolSeamFillFindingAttackTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: Self.kinds)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsSameFindingsAndLaysOutNoRootItJudges_whenRecordsOfFilledCallsMeetFillFinding(kind: String) async throws {
		var graphsReportingKind = 0
		for graph in Self.graphs(ofKind: kind) {
			let off = try await outcome(of: graph.modules, recordsFilledCalls: false)
			let on = try await outcome(of: graph.modules, recordsFilledCalls: true)
			#expect(on.diagnostics == off.diagnostics, "\(graph.name)")
			// Each template as written reports its kind, as the test it is taken from expects.
			#expect(graph.isTemplate ? on.kinds.contains(kind) : true, "\(graph.name)")
			if on.kinds.contains(kind) {
				graphsReportingKind += 1
			}
		}
		#expect(graphsReportingKind >= 20, "\(kind)")
	}

	// MARK: Graphs

	/// How a graph's new root holds the template's root.
	enum Holding: CaseIterable {
		case value
		case instantiator
		case lazilyInstantiated
		/// Beneath a type that builds itself again through an `Instantiator`: the template's calls under a lazy cycle.
		case lazyCycle
	}

	struct Graph {
		let name: String
		let modules: [ModuleFixture]
		/// Whether the graph is a template as written, which no variant changes.
		let isTemplate: Bool
	}

	static var kinds: [String] {
		Array(Set(templates.map(\.kind))).sorted()
	}

	/// Thirty-two graphs of `kind`, or every one its templates make where they make fewer: each template as written, then
	/// its variants, the templates taken in turn.
	static func graphs(ofKind kind: String) -> [Graph] {
		let templatesOfKind = templates.filter { $0.kind == kind }
		var variants = [(holding: Holding?, callsTwice: Bool, sibling: Int)]()
		variants.append((nil, false, 0))
		for holding in Holding.allCases {
			for callsTwice in [false, true] {
				for sibling in 0..<3 {
					variants.append((holding, callsTwice, sibling))
				}
			}
		}
		var graphs = [Graph]()
		for (variantIndex, variant) in variants.enumerated() {
			for (templateIndex, template) in templatesOfKind.enumerated() where graphs.count < 32 {
				let name = "\(kind) template \(templateIndex) variant \(variantIndex)"
				if let holding = variant.holding {
					guard let modules = held(template.modules, holding: holding, callsTwice: variant.callsTwice, sibling: variant.sibling) else { continue }
					graphs.append(Graph(name: name, modules: modules, isTemplate: false))
				} else {
					graphs.append(Graph(name: name, modules: template.modules, isTemplate: true))
				}
			}
		}
		return graphs
	}

	/// `modules` with its root made a plain type that `AttackRoot`, a root declared beside it, builds as `holding` says,
	/// twice where `callsTwice`, after (`sibling` 1) or before (2) a plain sibling.
	static func held(_ modules: [ModuleFixture], holding: Holding, callsTwice: Bool, sibling: Int) -> [ModuleFixture]? {
		let rootAttribute = "@Instantiable(isRoot: true)"
		guard let moduleIndex = modules.firstIndex(where: { $0.swiftFileContent.contains { $0.contains(rootAttribute) } }) else { return nil }
		let module = modules[moduleIndex]
		guard let fileIndex = module.swiftFileContent.firstIndex(where: { $0.contains(rootAttribute) }),
		      case let file = module.swiftFileContent[fileIndex],
		      let attributeRange = file.range(of: rootAttribute),
		      case let words = file[attributeRange.upperBound...].split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }),
		      let kindIndex = words.firstIndex(where: { $0 == "struct" || $0 == "class" }),
		      kindIndex + 1 < words.endIndex
		else { return nil }
		let rootName = String(words[kindIndex + 1])
		// The file's imports, which the types the graph adds beside the root need, and none of the types it declares.
		let imports = file.split(separator: "\n", omittingEmptySubsequences: false).prefix { $0.hasPrefix("import ") || $0.isEmpty }.map { "\($0)\n" }.joined()
		var files = module.swiftFileContent
		files[fileIndex] = file.replacingOccurrences(of: rootAttribute, with: "@Instantiable")
		let heldType = switch holding {
		case .value, .lazyCycle: rootName
		case .instantiator: "Instantiator<\(rootName)>"
		case .lazilyInstantiated: "LazilyInstantiated<\(rootName)>"
		}
		var held = ["@Instantiated let attackHeld: \(heldType)"]
		if callsTwice {
			held.append("@Instantiated let attackHeldAgain: \(heldType)")
		}
		var rootDeclarations: [String]
		if holding == .lazyCycle {
			files.append(imports + seamFixtureType(named: "AttackLoop", declarations: held + ["@Instantiated let attackLoopBuilder: Instantiator<AttackLoop>"]))
			rootDeclarations = ["@Instantiated let attackLoop: AttackLoop"]
		} else {
			rootDeclarations = held
		}
		if sibling > 0 {
			files.append(imports + seamFixtureType(named: "AttackSibling", declarations: []))
			let siblingDeclaration = "@Instantiated let attackSibling: AttackSibling"
			rootDeclarations = sibling == 1 ? rootDeclarations + [siblingDeclaration] : [siblingDeclaration] + rootDeclarations
		}
		files.append(imports + seamFixtureType(named: "AttackRoot", isRoot: true, declarations: rootDeclarations))
		var heldModules = modules
		heldModules[moduleIndex] = ModuleFixture(name: module.name, packageName: module.packageName, swiftFileContent: files, swiftFileContentByFilePath: module.swiftFileContentByFilePath, dependencies: module.dependencies)
		return heldModules
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What a run of `modules` reports: its diagnostics with the run's own directories taken out, `nil` where every module
	/// generates, and the kinds of the fill findings among them.
	private mutating func outcome(of modules: [ModuleFixture], recordsFilledCalls: Bool) async throws -> (diagnostics: String?, kinds: Set<String>) {
		do {
			_ = try await NodeRecordsObservation.$recordsFilledCalls.withValue(recordsFilledCalls) {
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			}
			return (nil, [])
		} catch let error as SafeDIToolMultiModuleTestError {
			var kinds = Set<String>()
			if case let .fillFindings(findings) = error.underlyingError as? DependencyTreeGenerator.DependencyTreeGeneratorError {
				kinds = Set(findings.map(\.kindName))
			}
			let diagnostics = "\(error)".replacing(#/\/[^\s:]*\/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\//#, with: "/")
			return (diagnostics, kinds)
		}
	}
}
