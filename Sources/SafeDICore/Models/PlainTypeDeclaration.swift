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

/// A declaration of a type that is not `@Instantiable` – a `struct`, `class`, `actor`, `enum`, or `protocol`, such as an
/// enum used as a namespace – whose access bounds the types an extension of it declares, and the type an
/// `@Instantiable` extension of it declares: code that names such a type names the extended type too. Its access is
/// also the access of the type, which proves the access of a parameter of a generated initializer or mock that names
/// it (`TypeAccessProof`).
///
/// Only a declaration outside every `#if` block and every extension is recorded. Its access is then the same whatever
/// the conditions, so a file's record needs no condition to be reused, and it is decided by the declaration's own
/// modifiers and those of the types enclosing it in its file: a declaration that spells no modifier directly inside an
/// extension takes the extension's level, which is not recorded.
public struct PlainTypeDeclaration: Codable, Hashable, Sendable {
	public init(
		typeDescription: TypeDescription,
		access: AccessDeclaration,
		enclosingTypeAccess: [AccessDeclaration],
		moduleName: String? = nil,
		packageName: String? = nil,
		sourceFilePath: String? = nil,
	) {
		self.typeDescription = typeDescription
		self.access = access
		self.enclosingTypeAccess = enclosingTypeAccess
		self.moduleName = moduleName
		self.packageName = packageName
		self.sourceFilePath = sourceFilePath
	}

	/// The type the declaration declares, with the types enclosing it in its file.
	public let typeDescription: TypeDescription
	/// The access the declaration spells.
	public let access: AccessDeclaration
	/// The access of each type declaration enclosing this one in its file, outermost first, as
	/// `Instantiable.enclosingTypeAccess` records it.
	public let enclosingTypeAccess: [AccessDeclaration]
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
	/// `public enum Outer { private enum Space {} }` is as invisible from another file as a file-scope `private` type.
	public var isVisibleOutsideItsFile: Bool {
		!(enclosingTypeAccess + [access]).contains { $0.level.isPrivateOrFilePrivate }
	}

	/// The access with which code outside the declaration can name the type: the level its declaration spells, or
	/// `internal` when it spells none, capped by the level of each type declaration enclosing it in its file. A recorded
	/// declaration is in no extension, so no extension gives it a level.
	public var effectiveAccessLevel: AccessLevel {
		(enclosingTypeAccess + [access]).reduce(AccessLevel.open) { effectiveLevel, declaration in
			effectiveLevel.capped(by: AccessLevel.ownLevel(of: declaration, directlyInside: nil))
		}
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
