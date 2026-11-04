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

/// A declaration of a type that is not `@Instantiable` – a `struct`, `class`, `actor`, `enum`, `protocol`, or
/// `typealias`, such as an enum used as a namespace – whose access bounds the types an extension of it declares, and the
/// type an `@Instantiable` extension of it declares: code that names such a type names the extended type too. Its access
/// is also the access of the type, which proves the access of a parameter of a generated initializer or mock that names
/// it (`TypeAccessProof`).
///
/// A declaration outside every `#if` block is recorded with the access its chain spells, directly inside an extension or
/// not: its access is then the same whatever the conditions, so a file's record needs no condition to be reused. A
/// declaration inside an `#if` block is recorded from every clause, with its spelled chain, and marked
/// `isInsideConditionalBlock`: the clause the compiler selects decides whether it exists, so SafeDI takes no access level
/// from it, and records it so that a mention of its name is not taken for a type SafeDI reads no declaration of.
public struct PlainTypeDeclaration: Codable, Hashable, Sendable {
	public init(
		typeDescription: TypeDescription,
		access: AccessDeclaration,
		enclosingTypeAccess: [AccessDeclaration],
		enclosingExtensionAccess: AccessDeclaration? = nil,
		isInsideConditionalBlock: Bool = false,
		moduleName: String? = nil,
		packageName: String? = nil,
		sourceFilePath: String? = nil,
	) {
		self.typeDescription = typeDescription
		self.access = access
		self.enclosingTypeAccess = enclosingTypeAccess
		self.enclosingExtensionAccess = enclosingExtensionAccess
		self.isInsideConditionalBlock = isInsideConditionalBlock
		self.moduleName = moduleName
		self.packageName = packageName
		self.sourceFilePath = sourceFilePath
	}

	/// The type the declaration declares, with the types enclosing it in its file, and, for a declaration inside an
	/// extension, the type the extension extends before them.
	public let typeDescription: TypeDescription
	/// The access the declaration spells.
	public let access: AccessDeclaration
	/// The access of each type declaration enclosing this one in its file, outermost first, as
	/// `Instantiable.enclosingTypeAccess` records it.
	public let enclosingTypeAccess: [AccessDeclaration]
	/// The access of the extension the outermost of those declarations is directly inside, or `nil` outside every
	/// extension, as `Instantiable.enclosingExtensionAccess` records it.
	public let enclosingExtensionAccess: AccessDeclaration?
	/// Whether the declaration is inside an `#if` block, in any clause. SafeDI takes no access level from such a
	/// declaration (`TypeAccessProof`), but records its spelled chain so that its access can be read later.
	public let isInsideConditionalBlock: Bool
	/// The module that declares the declaration's file, or `nil` when SafeDITool does not know it.
	public var moduleName: String?
	/// The package of the module that declares the declaration's file, or `nil` when SafeDITool does not know it.
	public var packageName: String?
	/// The file that holds the declaration.
	public var sourceFilePath: String?

	/// Whether code in another file than the declaration's can name the type: a `private` or `fileprivate` level
	/// anywhere in its chain – its own, or that of a type enclosing it in its file – keeps code in any other file from
	/// naming it, so an extension in another file cannot extend it, and such a declaration can be the type an extension
	/// extends only when it is in the extension's own file. Every level counts, not only the outermost:
	/// `public enum Outer { private enum Space {} }` is as invisible from another file as a file-scope `private` type. A
	/// declaration directly inside a `private` or `fileprivate` extension takes its level when it spells none.
	public var isVisibleOutsideItsFile: Bool {
		!(enclosingTypeAccess + [access]).enumerated().contains { index, declaration in
			AccessLevel.ownLevel(of: declaration, directlyInside: index == 0 ? enclosingExtensionAccess : nil).isPrivateOrFilePrivate
		}
	}

	/// The access with which code outside the declaration can name the type, before the type an enclosing extension
	/// extends caps it: the level its declaration spells – or, when it spells none, `internal`, or the default of the
	/// extension it is directly inside – capped by the level of each type declaration enclosing it in its file, the
	/// outermost of which follows the same rule. The extended type is declared elsewhere, so it is not part of this.
	public var levelBeforeExtendedTypeCap: AccessLevel {
		(enclosingTypeAccess + [access]).enumerated().reduce(AccessLevel.open) { effectiveLevel, enclosingDeclaration in
			effectiveLevel.capped(by: AccessLevel.ownLevel(
				of: enclosingDeclaration.element,
				directlyInside: enclosingDeclaration.offset == 0 ? enclosingExtensionAccess : nil,
			))
		}
	}

	/// The type the extension the declaration is inside extends, or `nil` for a declaration outside every extension.
	public var extendedType: TypeDescription? {
		guard enclosingExtensionAccess != nil else { return nil }
		var extendedType: TypeDescription? = typeDescription
		for _ in 0...enclosingTypeAccess.count {
			extendedType = extendedType?.popNested
		}
		return extendedType
	}
}

extension [PlainTypeDeclaration] {
	/// Orders declarations by source file path while keeping each file's declarations in the order they appear in it,
	/// as `[Instantiable].sortedByDeclaration()` orders instantiables.
	public func sortedByDeclaration() -> [PlainTypeDeclaration] {
		enumerated()
			.sorted { lhs, rhs in
				(lhs.element.sourceFilePath ?? "", lhs.offset) < (rhs.element.sourceFilePath ?? "", rhs.offset)
			}
			.map(\.element)
	}
}
