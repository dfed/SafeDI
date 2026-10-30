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

/// A module, as far as SafeDITool knows it: the name the compiler gives it, and the package it is compiled in, as
/// `-package-name` names it (under SwiftPM, the package's identity, of which `-package-name` carries the C99-mangled
/// form). Either is `nil` when SafeDITool does not know it.
public struct ModuleIdentity: Hashable, Sendable {
	public init(moduleName: String?, packageName: String?) {
		self.moduleName = moduleName
		self.packageName = packageName
	}

	public let moduleName: String?
	public let packageName: String?
}

/// The access a declaration needs for the code SafeDI generates in one module to use it.
public enum AccessRequirement: Hashable, Sendable {
	/// The code is in the declaration's own module: `internal` access suffices.
	case `internal`
	/// The code is in another module of the declaration's package: `package` access suffices.
	case package
	/// The code is in a module of another package: only `public` or `open` access suffices.
	case `public`
	/// The code is in another module, and SafeDITool does not know whether that module is in the declaration's package,
	/// because it does not know the package of one of the two. `package` access is assumed to suffice.
	case packageUnverified
}

extension AccessLevel {
	/// The access with which code outside the declaration can use the type an `@Instantiable` declaration declares:
	/// the level the declaration spells, capped by the level of each type declaration enclosing it in its file.
	///
	/// A declaration that spells no access modifier is `internal`, unless it is directly inside an extension, whose
	/// level is the default of the declarations directly inside it (`fileprivate` for a `private` extension). The
	/// outermost enclosing type declaration follows the same rule. An extension caps nothing, and the type it extends
	/// is declared elsewhere, so its access is unknown and caps nothing either.
	///
	/// The type an extension-based `@Instantiable` declares is declared elsewhere too, so its access is unknown. For
	/// such a declaration this returns the best bound SafeDITool has: the level the extension spells
	/// (`fileprivate` for a `private` extension), which its `instantiate()` and mock methods are taken to be capped
	/// by, or `open`, which caps nothing, when the extension spells none. Swift does not cap a member of an extension
	/// that spells a more permissive level than its extension, though it warns about it, so this bound can reject
	/// such a member.
	public static func effective(ofTypeDeclaredBy instantiable: Instantiable) -> AccessLevel {
		if instantiable.declarationType.isExtension {
			instantiable.access.spellsAccessModifier ? instantiable.access.level.asDefaultOfExtensionMembers : .open
		} else {
			(instantiable.enclosingTypeAccess + [instantiable.access])
				.enumerated()
				.reduce(AccessLevel.open) { effectiveLevel, enclosingDeclaration in
					effectiveLevel.capped(by: ownLevel(
						of: enclosingDeclaration.element,
						directlyInside: enclosingDeclaration.offset == 0 ? instantiable.enclosingExtensionAccess : nil,
					))
				}
		}
	}

	/// The access with which code outside the declaration can use `member` – a construction initializer, an
	/// `instantiate()` method, or a hand-written mock method: the level the member spells, or, when it spells none,
	/// `internal` for a member of a type declaration, whatever the type's level, and the extension's level for a
	/// member of an extension (`fileprivate` for a `private` extension), capped by `typeAccess`.
	/// - Parameters:
	///   - declaration: The declaration `member` is declared in: `Instantiable.access` for the construction
	///     initializer or `instantiate()` method, and `Instantiable.mockDeclarationAccess` for the hand-written mock.
	///   - typeAccess: The effective access of the type `member` constructs, as
	///     `effective(ofTypeDeclaredBy:)` returns it.
	public static func effective(ofMember member: Initializer, declaredIn declaration: AccessDeclaration, ofTypeWithEffectiveAccess typeAccess: AccessLevel) -> AccessLevel {
		ownLevel(of: member.access, declaredIn: declaration).capped(by: typeAccess)
	}

	/// The access a declaration needs for the code SafeDI generates in `emitter` to construct the type it declares.
	/// - Parameters:
	///   - emitter: The module the generated code compiles in.
	///   - declarer: The module that declares the declaration.
	///   - isOwnFile: Whether the declaration is in one of `emitter`'s own files, which decides that the two modules
	///     are one whatever their recorded names say.
	public static func required(toConstructFrom emitter: ModuleIdentity, declaredIn declarer: ModuleIdentity, isOwnFile: Bool) -> AccessRequirement {
		if isOwnFile {
			.internal
		} else if let emitterModuleName = emitter.moduleName, emitterModuleName == declarer.moduleName {
			.internal
		} else if let emitterPackageName = emitter.packageName, let declarerPackageName = declarer.packageName {
			emitterPackageName == declarerPackageName ? .package : .public
		} else {
			.packageUnverified
		}
	}

	/// Whether code that needs `requirement` can use a declaration with this level: `open` and `public` satisfy every
	/// requirement, `package` every one but `public`, `internal` only `internal`, and `fileprivate` and `private` none,
	/// since SafeDI generates code in files of its own.
	public func satisfies(_ requirement: AccessRequirement) -> Bool {
		switch requirement {
		case .internal:
			rank >= AccessLevel.internal.rank
		case .package, .packageUnverified:
			rank >= AccessLevel.package.rank
		case .public:
			rank >= AccessLevel.public.rank
		}
	}

	/// The less permissive of this level and `other`.
	public func capped(by other: AccessLevel) -> AccessLevel {
		rank <= other.rank ? self : other
	}

	/// The level of a member of an extension at this level that spells no access modifier: this level, but
	/// `fileprivate` for a `private` extension, whose members its whole file can use.
	public var asDefaultOfExtensionMembers: AccessLevel {
		switch self {
		case .private:
			.fileprivate
		case .open, .public, .package, .internal, .fileprivate:
			self
		}
	}

	/// The level a type declaration has by itself, before the declarations enclosing it cap it: the level it spells,
	/// or, when it spells none, the default of `enclosingExtension` it is directly inside, if any, and `internal`
	/// otherwise.
	static func ownLevel(of declaration: AccessDeclaration, directlyInside enclosingExtension: AccessDeclaration?) -> AccessLevel {
		if declaration.spellsAccessModifier {
			declaration.level
		} else {
			enclosingExtension?.level.asDefaultOfExtensionMembers ?? .internal
		}
	}

	/// The level a member has by itself, before its type caps it: the level it spells, or, when it spells none, the
	/// default of the declaration it is declared in.
	static func ownLevel(of member: AccessDeclaration, declaredIn declaration: AccessDeclaration) -> AccessLevel {
		if member.spellsAccessModifier {
			member.level
		} else if declaration.isExtension {
			declaration.level.asDefaultOfExtensionMembers
		} else {
			.internal
		}
	}

	/// The order of the levels, from the least permissive.
	private var rank: Int {
		switch self {
		case .private:
			0
		case .fileprivate:
			1
		case .internal:
			2
		case .package:
			3
		case .public:
			4
		case .open:
			5
		}
	}
}
