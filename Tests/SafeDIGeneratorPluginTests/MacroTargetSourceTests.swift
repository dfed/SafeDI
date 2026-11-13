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
import SwiftParser
import SwiftSyntax
import Testing

/// The SafeDIMacros target compiles SafeDICore's sources through a symbolic link, but leaves out the ones only
/// SafeDITool uses: every adopter compiles the macros from source, and the generators are most of SafeDICore. Package.swift
/// lists what the target leaves out in its `exclude` argument, and Sources/SafeDICore/BUILD.bazel in the `exclude` of the
/// `SafeDICoreSources` filegroup. A file the macros need but the lists leave out fails the build; these tests catch the
/// rest: two lists that disagree, a new SafeDICore file that the macros would compile without anyone deciding they
/// should, and an exclusion that no longer names a file.
struct MacroTargetSourceTests {
	@Test
	func macroTarget_leavesOutTheSameSafeDICoreSources_inPackageManifestAndBazel() throws {
		let packageManifestExclusions = try Self.packageManifestExclusions()
		#expect(packageManifestExclusions.contains("Generators/"))
		#expect(try packageManifestExclusions == Self.bazelExclusions())
	}

	@Test
	func macroTarget_compilesTheSafeDICoreSourcesTheMacrosUse() throws {
		let exclusions = try Self.packageManifestExclusions()
		let compiledSources = try Self.safeDICoreSources().filter { source in
			!exclusions.contains { Self.exclusion($0, leavesOut: source) }
		}
		#expect(
			compiledSources == Self.safeDICoreSourcesTheMacrosUse,
			"""
			Each Swift file under Sources/SafeDICore is either compiled into the SafeDIMacros target, and listed in \
			`safeDICoreSourcesTheMacrosUse`, or left out of it by the `exclude` argument of the SafeDIMacros target in \
			Package.swift and the `exclude` of the `SafeDICoreSources` filegroup in Sources/SafeDICore/BUILD.bazel. \
			Leave out a file the macros do not use: a file under Generators/ or Utilities/ is left out already.
			""",
		)
	}

	@Test
	func macroTarget_exclusionsEachLeaveOutASafeDICoreSource() throws {
		let sources = try Self.safeDICoreSources()
		let exclusionsLeavingOutNothing = try Self.packageManifestExclusions().filter { exclusion in
			!sources.contains { Self.exclusion(exclusion, leavesOut: $0) }
		}
		#expect(exclusionsLeavingOutNothing == [])
	}

	// MARK: Private

	/// The Swift files under Sources/SafeDICore that the macros use, relative to that directory, in path order.
	private static let safeDICoreSourcesTheMacrosUse = [
		"Errors/DiagnosticError.swift",
		"Errors/FixableInjectableError.swift",
		"Errors/FixableInstantiableError.swift",
		"Extensions/AttributeListSyntaxElementExtensions.swift",
		"Extensions/AttributeListSyntaxExtensions.swift",
		"Extensions/AttributeSyntaxExtensions.swift",
		"Extensions/CollectionExtensions.swift",
		"Extensions/DeclModifierListSyntaxExtensions.swift",
		"Extensions/DiagnosticExtensions.swift",
		"Extensions/IdentifierSpellingExtensions.swift",
		"Extensions/PatternBindingSyntaxExtensions.swift",
		"Models/AccessDeclaration.swift",
		"Models/AccessLevel.swift",
		"Models/AccessReachability.swift",
		"Models/ConcreteDeclSyntaxProtocol.swift",
		"Models/ConcreteDeclType.swift",
		"Models/ConditionalCompilationDecision.swift",
		"Models/DeclaredTypeNames.swift",
		"Models/Dependency.swift",
		"Models/GuardedPlainTypeNames.swift",
		"Models/Initializer.swift",
		"Models/InstantiableStruct.swift",
		"Models/MockGeneration.swift",
		"Models/OutputFileDeclarations.swift",
		"Models/PlainTypeDeclaration.swift",
		"Models/Property.swift",
		"Models/ReservedName.swift",
		"Models/SafeDIConfiguration.swift",
		"Models/SeamAccess.swift",
		"Models/TypeDescription.swift",
		"Models/UnorderedEquatingCollection.swift",
		"Visitors/ConditionalCompilationEvaluator.swift",
		"Visitors/InstantiableVisitor.swift",
		"Visitors/SafeDIConfigurationVisitor.swift",
		"Visitors/SafeDIContentDetector.swift",
	]

	private static let safeDICoreDirectory = "Sources/SafeDICore"

	/// The Swift files under Sources/SafeDICore, relative to that directory, in path order.
	private static func safeDICoreSources() throws -> [String] {
		try RepositorySwiftFile.files(under: [safeDICoreDirectory]).map {
			String($0.path.dropFirst(safeDICoreDirectory.count + 1))
		}
	}

	/// Whether `exclusion`, a file or a directory that ends in `/`, leaves out `source`.
	private static func exclusion(_ exclusion: String, leavesOut source: String) -> Bool {
		exclusion.hasSuffix("/") ? source.hasPrefix(exclusion) : source == exclusion
	}

	/// The SafeDICore files and directories the SafeDIMacros target in Package.swift leaves out, relative to
	/// Sources/SafeDICore, a directory ending in `/`.
	private static func packageManifestExclusions() throws -> [String] {
		let manifest = try String(
			contentsOf: RepositorySwiftFile.repositoryRoot.appendingPathComponent("Package.swift"),
			encoding: .utf8,
		)
		let finder = MacroTargetExclusionFinder(viewMode: .sourceAccurate)
		finder.walk(Parser.parse(source: manifest))
		guard let exclusions = finder.exclusions else {
			throw MissingExclusionsError(file: "Package.swift")
		}
		let linkedDirectory = "SafeDICore/"
		return exclusions.map { exclusion in
			let path = exclusion.hasPrefix(linkedDirectory) ? String(exclusion.dropFirst(linkedDirectory.count)) : exclusion
			return path.hasSuffix(".swift") ? path : path + "/"
		}
	}

	/// The SafeDICore files and directories the `SafeDICoreSources` filegroup in Sources/SafeDICore/BUILD.bazel leaves
	/// out, a directory ending in `/`.
	private static func bazelExclusions() throws -> [String] {
		let buildFile = try String(
			contentsOf: RepositorySwiftFile.repositoryRoot.appendingPathComponent("\(safeDICoreDirectory)/BUILD.bazel"),
			encoding: .utf8,
		)
		guard let filegroup = buildFile.range(of: #"name = "SafeDICoreSources""#),
		      let exclude = buildFile.range(of: "exclude = [", range: filegroup.upperBound..<buildFile.endIndex),
		      let end = buildFile.range(of: "]", range: exclude.upperBound..<buildFile.endIndex)
		else {
			throw MissingExclusionsError(file: "\(safeDICoreDirectory)/BUILD.bazel")
		}
		return buildFile[exclude.upperBound..<end.lowerBound].matches(of: #/"([^"]+)"/#).map { match in
			let pattern = String(match.output.1)
			return pattern.hasSuffix("/**") ? String(pattern.dropLast("**".count)) : pattern
		}
	}

	private struct MissingExclusionsError: Error {
		let file: String
	}
}

/// Finds the `exclude` argument of the `.macro(name: "SafeDIMacros", …)` target in a package manifest.
private final class MacroTargetExclusionFinder: SyntaxVisitor {
	/// The string literals of the argument, or `nil` when the manifest declares no such target with one.
	private(set) var exclusions: [String]?

	override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
		guard node.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "macro",
		      node.arguments.contains(where: { argument in
		      	argument.label?.text == "name" && Self.text(of: argument.expression) == "SafeDIMacros"
		      }),
		      let exclude = node.arguments.first(where: { $0.label?.text == "exclude" })?.expression.as(ArrayExprSyntax.self)
		else {
			return .visitChildren
		}
		exclusions = exclude.elements.compactMap { Self.text(of: $0.expression) }
		return .skipChildren
	}

	private static func text(of expression: ExprSyntax) -> String? {
		expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
	}
}
