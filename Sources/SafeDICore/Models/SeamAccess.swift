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

// The access helpers only a seam's generated initializers read. They are kept apart from AccessReachability.swift,
// whose helpers the access-enforcement work shares, so that file can be replaced whole.

extension AccessLevel: Comparable {
	/// Orders the levels by how widely they expose a declaration: `private` least, `open` most, which is the order
	/// `capped(by:)` chooses by.
	public static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
		lhs != rhs && lhs.capped(by: rhs) == lhs
	}

	/// How generated code spells this level on a declaration it generates, which is never `open` – an initializer
	/// cannot be overridden – nor `fileprivate` or `private`: a seam's parameters and tiers are counted `internal` at
	/// those levels, so only `public`, `package` and `internal` reach it from generation.
	public var spelledOnGeneratedDeclaration: String {
		switch self {
		case .open, .public:
			"public"
		case .package:
			"package"
		case .internal:
			"internal"
		case .fileprivate:
			"fileprivate"
		case .private:
			"private"
		}
	}
}

extension Instantiable {
	/// The effective access of the type this declaration declares. See `AccessLevel.effective(ofTypeDeclaredBy:)`.
	public var effectiveTypeAccess: AccessLevel {
		AccessLevel.effective(ofTypeDeclaredBy: self)
	}

	/// The effective access of the initializer, or `instantiate(…)` method, SafeDI constructs the type with, or `nil`
	/// when the declaration has none. A type's unspelled initializer is `internal`; an extension's unspelled
	/// `instantiate(…)` defaults to the extension's level. See `AccessLevel.effective(ofMember:declaredIn:ofTypeWithEffectiveAccess:)`.
	public var effectiveInitializerAccess: AccessLevel? {
		initializer.map { initializer in
			AccessLevel.effective(ofMember: initializer, declaredIn: access, ofTypeWithEffectiveAccess: effectiveTypeAccess)
		}
	}
}
