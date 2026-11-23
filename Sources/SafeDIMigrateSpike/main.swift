// SPIKE (3.0 migrate rewriter, spike branch only, never to land as is): runs the SafeDIMigration rewriter over a
// directory of sources, the prototype of `SafeDITool migrate`.
//
// Usage: SafeDIMigrateSpike (--roles FILE | --generated DIR…) --sources DIR [--sources DIR…] [--write] [--report-json FILE]
//
// `--generated` reads the `// safedi-migrate-roles:` lines the spike hook in `ScopeGenerator` writes into 2.x generated
// code when SAFEDI_MIGRATE_ROLES is set, and builds the role file from them.

import Foundation
import SafeDIMigration
import SwiftParser

func swiftFiles(in directory: String) -> [String] {
	guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
	return enumerator.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.sorted().map { "\(directory)/\($0)" }
}

var rolesPath: String?
var generatedDirectories = [String]()
var sourceDirectories = [String]()
var write = false
var reportPath: String?
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
	switch argument {
	case "--roles": rolesPath = arguments.next()
	case "--generated": generatedDirectories.append(arguments.next() ?? "")
	case "--sources": sourceDirectories.append(arguments.next() ?? "")
	case "--write": write = true
	case "--report-json": reportPath = arguments.next()
	default:
		FileHandle.standardError.write(Data("unknown argument \(argument)\n".utf8))
		exit(2)
	}
}

let roles: MigrationRoles
if let rolesPath {
	roles = try MigrationRoles(contentsOf: Data(contentsOf: URL(fileURLWithPath: rolesPath)))
} else {
	let marker = "// safedi-migrate-roles: "
	var mockedTypes = [MigrationRoles.MockedType]()
	var seen = Set<String>()
	for directory in generatedDirectories {
		for path in swiftFiles(in: directory) {
			let text = try String(contentsOfFile: path, encoding: .utf8)
			for line in text.split(separator: "\n") {
				guard let range = line.range(of: marker) else { continue }
				let json = String(line[range.upperBound...])
				guard seen.insert(json).inserted else { continue }
				mockedTypes.append(try JSONDecoder().decode(MigrationRoles.MockedType.self, from: Data(json.utf8)))
			}
		}
	}
	roles = MigrationRoles(mockedTypes: mockedTypes)
}

let sources = try sourceDirectories.flatMap(swiftFiles(in:)).map { path in
	SourceFile(path: path, text: try String(contentsOfFile: path, encoding: .utf8))
}

let result = Migration.migrate(sources: sources, roles: roles)
for file in result.rewrittenFiles where Parser.parse(source: file.text).hasError {
	print("PARSE ERROR after rewrite: \(file.path)")
}

if write {
	for file in result.rewrittenFiles {
		try file.text.write(toFile: file.path, atomically: true, encoding: .utf8)
	}
}

print("mocked types: \(roles.mockedTypes.count), files: \(sources.count), rewritten: \(result.rewrittenFiles.count)")
for edit in MigrationEdit.allCases {
	guard let count = result.editCounts[edit] else { continue }
	print(String(format: "%7d  ", count) + edit.rawValue)
}

var findingCounts = [MigrationFinding.Kind: Int]()
for finding in result.findings {
	findingCounts[finding.kind, default: 0] += 1
}

for kind in MigrationFinding.Kind.allCases {
	guard let count = findingCounts[kind] else { continue }
	print(String(format: "%7d  REPORTED: ", count) + kind.rawValue)
}

if let reportPath {
	var json = [String: Int]()
	for (edit, count) in result.editCounts {
		json["edit." + String(describing: edit)] = count
	}
	for (kind, count) in findingCounts {
		json["finding." + String(describing: kind)] = count
	}
	try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: reportPath))
}
