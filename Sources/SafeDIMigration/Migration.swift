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

import SwiftParser
import SwiftSyntax

/// Rewrites a SafeDI 2.x project's sources to the 3.0 mock API in one pass: the fake rename, the mocked type's own
/// defaults moved into `safeDIOverrides`, received dependencies the mock builds into `.instance(…)` and `.built(…)`,
/// created dependencies the mock cannot build into builders, and the opt-in setting in every `#SafeDIConfiguration`.
/// It edits only what syntax and the role file decide, and reports every site that needs type information or a person.
public enum Migration {
	/// Rewrites `sources` with `roles`. Files are visited in path order, and the result lists findings in source
	/// order, so two runs over the same input agree byte for byte.
	public static func migrate(
		sources: [SourceFile],
		roles: MigrationRoles,
		options: MigrationOptions = .init(),
	) -> MigrationResult {
		let orderedSources = sources.sorted { $0.path < $1.path }
		let trees = orderedSources.map { ($0, Parser.parse(source: $0.text)) }
		let declarations = SourceDeclarations(trees: trees.map(\.1))
		let typeIndex = MockedTypeIndex(roles: roles, handWrittenMockTypes: declarations.handWrittenMockTypes)
		var log = MigrationLog()
		var rewrittenFiles = [SourceFile]()
		for (source, tree) in trees {
			let rewriter = MigrationRewriter(
				path: source.path,
				tree: tree,
				typeIndex: typeIndex,
				declarations: declarations,
				options: options,
				log: log,
			)
			let rewritten = rewriter.rewrite(tree)
			log = rewriter.log
			let text = rewritten.description
			if text != source.text {
				rewrittenFiles.append(SourceFile(path: source.path, text: text))
			}
		}
		for site in roles.labelRedeclarations {
			log.report(.labelRedeclaredBeneathItself, at: site)
		}
		for path in options.modulesWithoutConfiguration.sorted() {
			rewrittenFiles.append(SourceFile(path: path, text: MigrationRewriter.newConfigurationFile(options: options)))
			log.count(.configurationFileCreated)
		}
		return MigrationResult(
			rewrittenFiles: rewrittenFiles,
			editCounts: log.editCounts,
			findings: log.findings.sorted { ($0.site, $0.kind.rawValue) < ($1.site, $1.kind.rawValue) },
		)
	}
}

/// One Swift source file.
public struct SourceFile: Equatable, Sendable {
	public init(path: String, text: String) {
		self.path = path
		self.text = text
	}

	public let path: String
	public let text: String
}

/// How the rewriter applies what is not decided yet.
public struct MigrationOptions: Equatable, Sendable {
	public init(
		modulesWithoutConfiguration: [String] = [],
		ordersArgumentsByRoleFile: Bool = false,
	) {
		self.modulesWithoutConfiguration = modulesWithoutConfiguration
		self.ordersArgumentsByRoleFile = ordersArgumentsByRoleFile
	}

	/// The `#SafeDIConfiguration` argument that opts a module into the 3.0 shape, added to or updated in every
	/// configuration (Dan, 2026-11-23: one app-wide switch, which 3.0 removes).
	public static let optInArgumentLabel = "apiVersion"
	public static let optInArgumentValue = ".v3Unstable"
	/// The path of a configuration file to create for each module that declares no `#SafeDIConfiguration`.
	public let modulesWithoutConfiguration: [String]
	/// THREE-ZERO 2.1, a candidate: orders each `mock()` call's arguments, and those of its `safeDIOverrides: .init(…)`,
	/// as the role file lists the parameters, rather than keeping the order written.
	public let ordersArgumentsByRoleFile: Bool
}

/// What a migration rewrote and found.
public struct MigrationResult: Equatable, Sendable {
	/// Each file whose text changed, with its new text, in path order, and each configuration file created.
	public let rewrittenFiles: [SourceFile]
	/// How many edits of each kind were made.
	public let editCounts: [MigrationEdit: Int]
	/// Every site left for a person, in source order.
	public let findings: [MigrationFinding]
}

/// A kind of edit the rewriter makes.
public enum MigrationEdit: String, CaseIterable, Sendable {
	case attributeLabelRenamed = "@Instantiable label renamed"
	case configurationLabelRenamed = "#SafeDIConfiguration label renamed"
	case optInSettingAdded = "#SafeDIConfiguration opt-in setting added"
	case optInSettingUpdated = "#SafeDIConfiguration opt-in setting updated"
	case configurationFileCreated = "#SafeDIConfiguration file created with the opt-in setting"
	case mockGenerationRenamed = "MockGeneration renamed FakeGeneration"
	case configurationTypeRenamed = "SafeDIMockConfiguration renamed SafeDIFakeConfiguration"
	case handWrittenMockDeclarationRenamed = "hand-written mock declaration renamed fake"
	case generatedMockCallRenamed = "generated mock call renamed .fake("
	case handWrittenMockCallRenamed = "hand-written mock call renamed .fake("
	case implicitMemberResolvedFromWrittenType = "implicit .mock( resolved from a written type"
	case createdDependencyWrappedLocalName = "D12: local name wrapped as { name }"
	case createdDependencyWrappedCapturedExpression = "D12: expression captured once, as { [label = expression] in label }"
	case sendableAutoclosureWrapped = "D12: @Sendable autoclosure argument wrapped (already one value per creation)"
	case ownDefaultMovedIntoNewOverrides = "B: own default moved into a new safeDIOverrides: .init(…)"
	case ownDefaultMergedIntoOverrides = "B: own default appended to an existing safeDIOverrides: .init(…)"
	case publicNilDefaultDropped = "B: public mock nil (use the default) argument dropped"
	case receivedValueWrappedAsInstance = "received dependency passed as .instance(…)"
	case receivedNilDropped = "received dependency nil (build it) argument dropped"
	case receivedOverrideMovedToBuilt = "received dependency override moved to a .built(…) argument"
	case receivedOverrideClosureMovedToBuilt = "of which an override closure, as .built(.init(closure))"
	case receivedWithoutConfigurationKept = "received dependency with nothing to configure kept as a plain value"
	case receivedOverrideClosureCalled = "received dependency override closure called once in place (nothing to configure)"
	case builderRelabeled = "builder argument relabeled to the property’s label (3.0 sub-decision 1)"
	case argumentsReordered = "arguments reordered by the role file (THREE-ZERO 2.1)"
}

/// A site the rewriter leaves for a person.
public struct MigrationFinding: Equatable, Sendable {
	public let kind: Kind
	public let site: SourceSite
	/// The call or declaration as written, trimmed.
	public let text: String

	public enum Kind: String, CaseIterable, Sendable {
		case implicitMemberUnresolved = "implicit .mock( whose type is not written: needs the contextual type"
		case typealiasOrGenericBase = ".mock( through a typealias or generic parameter: needs the type it stands for"
		case mockReferencedAsValue = ".mock referenced as a value, not called"
		case ownDefaultBesideNonLiteralOverrides = "own default beside a safeDIOverrides that is not written as .init(…): move it into that value"
		case trailingClosure = "mock call with a trailing closure: its label is not written"
		case unknownLabel = "argument label the 2.x mock() does not take"
		case ambiguousType = "two modules generate a mock for this type name: qualify the call with its module"
		case receivedBuildablePassedTwice = "received dependency passed both as a value and as an override: 2.x ignored one, keep the one the test means"
		case receivedBuildableOverrideNotLiteral = "received dependency override that is not a .init(…) configuration: write it as .instance(…) or .built(…)"
		case closureTypedDependencyWrapped = "dependency whose own type is a closure: the argument is now the builder that returns it, check the rewrite"
		case configurationFieldRead = "configuration field read: child fields are optional in 3.0 (field?.member)"
		case forwardedWrapper = "@Forwarded SafeDI wrapper, an error in 3.0: declare it @Instantiated here, receive it from an ancestor, or forward the value it builds"
		case labelRedeclaredBeneathItself = "label redeclared beneath itself on one branch, an error in 3.0: rename one of the two"
	}
}

/// What one migration has done so far, carried from file to file.
struct MigrationLog: Sendable {
	private(set) var editCounts = [MigrationEdit: Int]()
	private(set) var findings = [MigrationFinding]()

	mutating func count(_ edit: MigrationEdit) {
		editCounts[edit, default: 0] += 1
	}

	mutating func report(_ kind: MigrationFinding.Kind, at site: SourceSite, text: String = "") {
		findings.append(MigrationFinding(kind: kind, site: site, text: text))
	}
}
