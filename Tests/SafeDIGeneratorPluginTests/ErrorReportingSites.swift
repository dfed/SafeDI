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

/// The code that reports an error type to the user: `code`, which must appear outside comments and strings in the
/// file at `path`, relative to the repository root, so that an entry naming code that moved or changed fails.
struct ErrorReportingSite {
	let path: String
	let code: String
}

extension ErrorReportingSite {
	/// Where each error type declared under `Sources/SafeDICore` is reported. An error that one root's validation
	/// throws must be caught where the roots are validated and joined with the other roots' errors, or which errors
	/// are reported depends on the order in which the roots are validated, which follows their names.
	static let byErrorType: [String: ErrorReportingSite] = [
		// Each loop over roots, mock roots, or trees catches it and joins what it caught.
		"DependencyTreeGenerator.DependencyTreeGeneratorError": .joinedWithTheErrorsOfOtherRoots,
		// Thrown while a root's generator is built: for production roots after every validation passed, and for mock
		// roots inside the mock-root loop, which it escapes, discarding the errors of the mock roots validated before it.
		// Nothing joins it, and `generate` prints it.
		"ErasedInstantiatorForwardedPropertiesMismatchError": ErrorReportingSite(
			path: "Sources/SafeDITool/GenerateCommand.swift",
			code: "catch let error as any SourceLocatedError",
		),
		// The macros attach them to the declaration as diagnostics; neither is thrown.
		"FixableInjectableError": .macroDiagnostic,
		"FixableInstantiableError": .macroDiagnostic,
		// The `@Instantiable` macro reports it as diagnostics. Generation builds a type only with an initializer that
		// fulfills its dependencies, so generation never throws it.
		"Initializer.GenerationError": ErrorReportingSite(
			path: "Sources/SafeDIMacros/Macros/InstantiableMacro.swift",
			code: "extension Initializer.GenerationError",
		),
	]

	/// Caught by each validation of roots and joined with the errors of the roots validated beside it.
	static let joinedWithTheErrorsOfOtherRoots = ErrorReportingSite(
		path: "Sources/SafeDICore/Generators/DependencyTreeGenerator.swift",
		code: "DependencyTreeGeneratorError.reportingAll(of:",
	)

	/// Attached by a macro to the declaration it diagnoses.
	static let macroDiagnostic = ErrorReportingSite(
		path: "Sources/SafeDICore/Extensions/DiagnosticExtensions.swift",
		code: "error: some DiagnosticError",
	)

	/// The problems with `reportingSitesByErrorType`, a registry of `errorTypes` – the error types declared in a set of
	/// files, by name, each with the path of a file that declares it – given `files`, the files that may hold a site:
	/// an error type the registry does not list, an entry that names no error type, and a site whose code is not in its
	/// file. In name order.
	static func problems(
		ofRegistry reportingSitesByErrorType: [String: ErrorReportingSite],
		errorTypes: [String: String],
		files: [RepositorySwiftFile],
	) -> [String] {
		var problems = [String]()
		for (errorType, path) in errorTypes.sorted(by: { $0.key < $1.key }) where reportingSitesByErrorType[errorType] == nil {
			problems.append("\(path): `\(errorType)` is an error type, so `ErrorReportingSite.byErrorType` lists it with the site that reports it")
		}
		let codeWithoutSpacesByPath = files.reduce(into: [String: String]()) { codeWithoutSpacesByPath, file in
			codeWithoutSpacesByPath[file.path] = stripSwiftCommentsAndStrings(from: file.source).withoutWhitespace
		}
		for (errorType, site) in reportingSitesByErrorType.sorted(by: { $0.key < $1.key }) {
			if errorTypes[errorType] == nil {
				problems.append("`ErrorReportingSite.byErrorType` lists `\(errorType)`, which is not an error type")
			} else if codeWithoutSpacesByPath[site.path]?.contains(site.code.withoutWhitespace) != true {
				problems.append("`ErrorReportingSite.byErrorType` reports `\(errorType)` with `\(site.code)`, which is not in \(site.path)")
			}
		}
		return problems
	}
}

enum ErrorTypeDeclarations {
	/// The types that `files` declare to conform to `Error`, directly or through the protocols, type aliases, and
	/// superclasses the files declare, by name – qualified by the types and extensions that enclose them – each with
	/// the path of a file that declares it or its conformance.
	static func errorTypes(in files: [RepositorySwiftFile]) -> [String: String] {
		let visitors = files.map { file in
			let visitor = ConformanceVisitor(path: file.path)
			visitor.walk(Parser.parse(source: file.source))
			return visitor
		}
		// The protocols and type aliases that refine or name an error protocol are error protocols too, and a class
		// that conforms to one passes its conformance to its subclasses, which a chain of declarations can make so in
		// any order. A type is named in a conformance by its last name component.
		var errorProtocolNames: Set = ["Error", "LocalizedError", "CustomNSError", "RecoverableError"]
		var foundErrorProtocol = true
		while foundErrorProtocol {
			foundErrorProtocol = false
			for visitor in visitors {
				let conformances = visitor.protocolConformances
					+ visitor.typeConformances.map { (name: String($0.typeName.split(separator: ".").last ?? ""), conformedNames: $0.conformedNames) }
				for (name, conformedNames) in conformances where !errorProtocolNames.contains(name) && !errorProtocolNames.isDisjoint(with: conformedNames) {
					errorProtocolNames.insert(name)
					foundErrorProtocol = true
				}
			}
		}
		var errorTypes = [String: String]()
		for visitor in visitors {
			for conformance in visitor.typeConformances where !errorProtocolNames.isDisjoint(with: conformance.conformedNames) {
				errorTypes[conformance.typeName] = errorTypes[conformance.typeName] ?? visitor.path
			}
		}
		return errorTypes
	}
}

/// Collects the conformances a file declares.
private final class ConformanceVisitor: SyntaxVisitor {
	init(path: String) {
		self.path = path
		super.init(viewMode: .sourceAccurate)
	}

	let path: String
	/// Each type, by qualified name, with the names of the types it conforms to, for each declaration of the type or
	/// an extension of it.
	private(set) var typeConformances = [(typeName: String, conformedNames: Set<String>)]()
	/// Each protocol, with the names of the protocols it refines, and each type alias, with the names of the types it
	/// stands for.
	private(set) var protocolConformances = [(name: String, conformedNames: Set<String>)]()

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(type: node.name.text, inheritanceClause: node.inheritanceClause)
	}

	override func visitPost(_: StructDeclSyntax) {
		enclosingTypeNames.removeLast()
	}

	override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(type: node.name.text, inheritanceClause: node.inheritanceClause)
	}

	override func visitPost(_: EnumDeclSyntax) {
		enclosingTypeNames.removeLast()
	}

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(type: node.name.text, inheritanceClause: node.inheritanceClause)
	}

	override func visitPost(_: ClassDeclSyntax) {
		enclosingTypeNames.removeLast()
	}

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(type: node.name.text, inheritanceClause: node.inheritanceClause)
	}

	override func visitPost(_: ActorDeclSyntax) {
		enclosingTypeNames.removeLast()
	}

	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(type: node.extendedType.trimmedDescription, inheritanceClause: node.inheritanceClause)
	}

	override func visitPost(_: ExtensionDeclSyntax) {
		enclosingTypeNames.removeLast()
	}

	override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
		protocolConformances.append((
			name: node.name.text,
			conformedNames: Set(node.inheritanceClause?.inheritedTypes.flatMap { Self.conformedNames(of: $0.type) } ?? []),
		))
		return .skipChildren
	}

	override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
		protocolConformances.append((name: node.name.text, conformedNames: Set(Self.conformedNames(of: node.initializer.value))))
		return .skipChildren
	}

	// MARK: Private

	private var enclosingTypeNames = [String]()

	private func enter(type name: String, inheritanceClause: InheritanceClauseSyntax?) -> SyntaxVisitorContinueKind {
		enclosingTypeNames.append(name)
		typeConformances.append((
			typeName: enclosingTypeNames.joined(separator: "."),
			conformedNames: Set(inheritanceClause?.inheritedTypes.flatMap { Self.conformedNames(of: $0.type) } ?? []),
		))
		return .visitChildren
	}

	/// The names of the types `type` conforms to: the last component of each type it names, apart from generic
	/// arguments, so `Swift.Error & Sendable` conforms to `Error` and `Sendable`.
	private static func conformedNames(of type: TypeSyntax) -> [String] {
		if let identifierType = type.as(IdentifierTypeSyntax.self) {
			[identifierType.name.text]
		} else if let memberType = type.as(MemberTypeSyntax.self) {
			[memberType.name.text]
		} else if let compositionType = type.as(CompositionTypeSyntax.self) {
			compositionType.elements.flatMap { conformedNames(of: $0.type) }
		} else if let attributedType = type.as(AttributedTypeSyntax.self) {
			conformedNames(of: attributedType.baseType)
		} else if let someOrAnyType = type.as(SomeOrAnyTypeSyntax.self) {
			conformedNames(of: someOrAnyType.constraint)
		} else {
			[]
		}
	}
}

extension String {
	/// This text without its spaces, tabs, and newlines.
	fileprivate var withoutWhitespace: String {
		String(filter { !$0.isWhitespace })
	}
}
