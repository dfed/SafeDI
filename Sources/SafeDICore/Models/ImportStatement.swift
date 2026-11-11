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

public struct ImportStatement: Codable, Hashable, Sendable {
	// MARK: Initialization

	public init(
		attribute: String = "",
		kind: String = "",
		moduleName: String,
		type: String = "",
		accessLevel: AccessLevel? = nil,
		sourceFilePath: String? = nil,
	) {
		self.attribute = attribute
		self.kind = kind
		self.moduleName = moduleName
		self.type = type
		self.accessLevel = accessLevel
		self.sourceFilePath = sourceFilePath
	}

	// MARK: Public

	/// Attributes on the import (i.e. `@testable`)
	public let attribute: String
	/// The kind of import, if specified (i.e. `class`, `struct`, etc).
	public let kind: String
	/// The name of the module.
	public let moduleName: String
	/// The type imported from the module.
	public let type: String
	/// The access level the import spells (`internal import Foundation`), or `nil` when it spells none.
	public let accessLevel: AccessLevel?
	/// The file whose import spells `accessLevel`: `generate` keeps the levels the module's own files spell apart from
	/// those a dependency's file spells, which say nothing of the module's own imports. `nil` when the import spells no
	/// level, so that such imports of one module in many files stay one import (`spelled(in:)`), or when the file is not
	/// yet known.
	public let sourceFilePath: String?

	/// This import as the file at `sourceFilePath` spells it, which it records when the import spells an access level.
	public func spelled(in sourceFilePath: String) -> ImportStatement {
		ImportStatement(
			attribute: attribute,
			kind: kind,
			moduleName: moduleName,
			type: type,
			accessLevel: accessLevel,
			sourceFilePath: accessLevel == nil ? nil : sourceFilePath,
		)
	}

	/// This import as source code, spelling the access level `accessLevel`, or none when it is `nil`. A generated file
	/// decides the level of each of its imports itself (`GeneratedImportAccess`).
	public func asSource(spelling accessLevel: AccessLevel?) -> String {
		let accessModifier = accessLevel.map { "\($0.spelling) " } ?? ""
		return "\(attributeStatement)\(accessModifier)import \(kind.isEmpty ? "" : kind + " ")\(moduleName)\(type.isEmpty ? "" : "." + type)"
	}

	// MARK: Internal

	/// The attributes `asSource(spelling:)` writes.
	var attributeToGenerate: String {
		if Self.attributesToFilterOut.contains(attribute) {
			""
		} else {
			attribute
		}
	}

	/// Whether the import re-exports its module, which only a `public` import can.
	var isExported: Bool {
		attributeToGenerate.contains("@_exported")
	}

	/// Whether the import keeps its module out of the module's interface, which the compiler warns about unless every
	/// import of the module in the module's files does.
	var isImplementationOnly: Bool {
		attributeToGenerate.contains(Self.implementationOnlyAttribute)
	}

	/// The attribute that makes an import implementation-only.
	static let implementationOnlyAttribute = "@_implementationOnly"

	/// This import without its access level and the file that spells it: what a generated file's import of the module is
	/// written from, with the level the generated file decides.
	var withoutAccessLevel: ImportStatement {
		ImportStatement(attribute: attribute, kind: kind, moduleName: moduleName, type: type)
	}

	// MARK: Private

	private var attributeStatement: String {
		let attributeToGenerate = attributeToGenerate
		return if attributeToGenerate.isEmpty {
			""
		} else {
			attributeToGenerate + " "
		}
	}

	private static let attributesToFilterOut = Set([
		// We don't use concurrency in generated code, so including this attribute leads to a warning:
		//     '@preconcurrency' attribute on module 'ImportedModule' is unused
		"@preconcurrency",
	])
}
