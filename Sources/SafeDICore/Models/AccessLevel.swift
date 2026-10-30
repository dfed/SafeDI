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

/// The access level of a declaration, as its modifiers spell it.
public enum AccessLevel: Codable, Hashable, Sendable {
	case open
	case `public`
	case package
	case `internal`
	case `fileprivate`
	case `private`

	/// Whether code in any module can use the declaration.
	public var isPublicOrOpen: Bool {
		switch self {
		case .open, .public:
			true
		case .package, .internal, .fileprivate, .private:
			false
		}
	}

	/// Whether only code in the declaration's own file can use it. SafeDI generates code in files of its own, so
	/// that code can never use such a declaration.
	public var isPrivateOrFilePrivate: Bool {
		switch self {
		case .fileprivate, .private:
			true
		case .open, .public, .package, .internal:
			false
		}
	}

	/// The modifier that sets this level, as source spells it, which is the name of its case.
	public var spelling: String {
		"\(self)"
	}
}
