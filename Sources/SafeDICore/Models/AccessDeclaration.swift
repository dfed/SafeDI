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

/// The access level a declaration spells, with where a fix-it that changes it would edit the declaration.
public struct AccessDeclaration: Codable, Hashable, Sendable {
	/// - Parameter spellsAccessModifier: Whether the declaration spells an access modifier, or `nil` for a declaration
	///   SafeDI constructs rather than parses, which spells one when it has a modifier range or a level other than
	///   `internal`.
	public init(
		level: AccessLevel,
		spellsAccessModifier: Bool? = nil,
		modifierRange: Dependency.SourceRange? = nil,
		declarationStartLocation: Dependency.DeclarationLocation? = nil,
		isExtension: Bool = false,
	) {
		self.level = level
		self.spellsAccessModifier = spellsAccessModifier ?? (modifierRange != nil || level != .internal)
		self.modifierRange = modifierRange
		self.declarationStartLocation = declarationStartLocation
		self.isExtension = isExtension
	}

	/// The access level the declaration's modifiers spell: `internal` when none of them sets one.
	public let level: AccessLevel
	/// Whether the declaration spells an access modifier, which a declaration that spells none – and so has the
	/// `internal` level – does not. Stored rather than read from `modifierRange`, which is a position: a module info's
	/// view of another module holds no positions, and a declaration parsed without a file context records none.
	public let spellsAccessModifier: Bool
	/// The source range of the modifier that sets `level`, in the file of `declarationStartLocation`, which a fix-it
	/// can replace. `nil` when the declaration spells no access modifier, when it was parsed without a file context –
	/// macro expansion walks a detached declaration – and in a module info's view of another module.
	public let modifierRange: Dependency.SourceRange?
	/// Where the declaration begins after its attributes – its first modifier, or the keyword that introduces it when
	/// it has none – which is where a fix-it inserts an access modifier. `nil` when the declaration was parsed without
	/// a file context – macro expansion walks a detached declaration.
	public let declarationStartLocation: Dependency.DeclarationLocation?
	/// Whether the declaration is an extension. A member of an extension that spells no access modifier defaults to
	/// the extension's level (`fileprivate` for a `private` extension), and a member of a type declaration to
	/// `internal`, whatever the type's level. Always `false` in `Instantiable.enclosingTypeAccess`, and always `true` in
	/// `Instantiable.enclosingExtensionAccess`.
	public let isExtension: Bool
}
