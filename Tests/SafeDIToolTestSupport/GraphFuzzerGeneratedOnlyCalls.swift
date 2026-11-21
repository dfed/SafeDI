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

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerOracle {
	/// Each call in `generatedFiles` – generated code, by file name – of a function SafeDI generates for code people write:
	/// a generated `mock()`, which every public mock's tier pairs with the function only generated code calls,
	/// `__safeDI_mock`, and a seam's plain initializer, which a module that sets `generatePlainDependencyTreeInitializers`
	/// declares beside the initializer only generated code calls. Generated code reaches another type's generated entry
	/// only through the function or initializer only generated code calls, whose forms SafeDI can change in any release, so
	/// what a person calls never builds a tree for generated code. A call of a hand-written `mock()` or `customMockName`
	/// method, of a type's own initializer, and of a seam's initializer that takes no argument, which both kinds of code
	/// call, is no finding. Each finding names the file and the line, in file order.
	static func callsOfEntriesMeantForPeople(in generatedFiles: [String: String]) -> [String] {
		var generatedMockTypeNames = Set<String>()
		var plainInitializerLabelsByTypeName = [String: Set<[String]>]()
		for contents in generatedFiles.values {
			var extendedType: String?
			for line in contents.split(separator: "\n") {
				if line.hasPrefix("extension "), line.hasSuffix(" {") {
					extendedType = String(line.dropFirst("extension ".count).dropLast(2))
				} else if line.hasPrefix("}") {
					extendedType = nil
				} else if let extendedType, line.hasPrefix("    "), !line.hasPrefix("     "), line.contains("static func mock(") {
					generatedMockTypeNames.insert(unqualifiedName(of: extendedType))
				}
			}
			for tier in readableInitializerTiers(inGeneratedFile: contents) where !tier.readableParameters.isEmpty {
				plainInitializerLabelsByTypeName[unqualifiedName(of: tier.seamTypeName), default: []].insert(tier.readableParameters.map { parameter in
					String(parameter.prefix { $0 != ":" }).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "`", with: "")
				})
			}
		}
		var findings = [String]()
		// A public mock caller's file holds the call a person writes (`addingPublicMockCallers(to:of:)`).
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where !fileName.hasSuffix(publicMockCallerFileSuffix) {
			for line in contents.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.hasPrefix("//") && !line.contains("func mock(") {
				for typeName in generatedMockTypeNames.sorted() where callsMock(of: typeName, in: line) {
					findings.append("`\(fileName)` calls `\(typeName).mock(`, which code people write calls, not `\(typeName).__safeDI_mock(`: \(line)")
				}
				for (typeName, labelLists) in plainInitializerLabelsByTypeName.sorted(by: { $0.key < $1.key }) {
					for call in initializerCalls(of: typeName, in: line) where labelLists.contains(call.map { $0.label.replacingOccurrences(of: "`", with: "") }) {
						findings.append("`\(fileName)` calls `\(typeName)`’s plain initializer, which code people write calls, not the one only generated code calls: \(line)")
					}
				}
			}
		}
		return findings
	}

	/// Whether `line` calls `typeName.mock(`: `typeName` not part of a longer name, possibly after the types that enclose
	/// it or its module.
	private static func callsMock(of typeName: String, in line: String) -> Bool {
		var searchStart = line.startIndex
		while let range = line.range(of: "\(typeName).mock(", range: searchStart..<line.endIndex) {
			searchStart = range.upperBound
			guard range.lowerBound > line.startIndex else { return true }
			let previous = line[line.index(before: range.lowerBound)]
			if !(previous.isLetter || previous.isNumber || previous == "_") {
				return true
			}
		}
		return false
	}

	/// `typeName` without the types that enclose it.
	private static func unqualifiedName(of typeName: String) -> String {
		String(typeName.split(separator: ".").last ?? Substring(typeName))
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph whose generated code calls a function SafeDI generates for code people write
	/// (`GraphFuzzerOracle.callsOfEntriesMeantForPeople(in:)`), in one module or under the module-info integration of a
	/// split of it, or `nil`.
	var generatedCodeCallsEntryMeantForPeopleFailure: GraphFuzzerFailure? {
		for (description, files) in judgedGeneratedFiles {
			let findings = GraphFuzzerOracle.callsOfEntriesMeantForPeople(in: files)
			guard !findings.isEmpty else { continue }
			return GraphFuzzerFailure(
				seed: fixture.seed,
				kind: .generatedCodeCallsEntryMeantForPeople,
				details: "\(findings.joined(separator: "\n"))\n\(description):\n\(files.keys.sorted().map { "// \($0)\n\(files[$0, default: ""])" }.joined(separator: "\n"))",
			)
		}
		return nil
	}

	/// The generated code of an accepted graph in one module, then of each split of it under the module-info
	/// integration, each file keyed by its module and unit there, which the oracles of generated-only entries judge.
	var judgedGeneratedFiles: [(description: String, files: [String: String])] {
		var judged = [(description: String, files: [String: String])]()
		if case let .accepted(generatedFiles, _) = firstOutcome {
			judged.append(("This graph", generatedFiles))
		}
		for runs in multiModuleRuns {
			var files = [String: String]()
			for verdict in runs.moduleInfoOutcome.verdicts {
				guard case let .accepted(module) = verdict.kind else { continue }
				for (unitName, code) in module.units {
					files["\(verdict.moduleName)/\(unitName)"] = code
				}
			}
			judged.append(("Split into modules (\(runs.partition.description))", files))
		}
		return judged
	}
}
