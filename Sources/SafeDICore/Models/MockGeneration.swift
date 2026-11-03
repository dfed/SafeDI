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

/// Whether, and with what access, SafeDI generates a `mock()` method for an `@Instantiable` type: the
/// `generateMock:` argument of `@Instantiable`, which the runtime declares as an enum of the same name.
public enum MockGeneration: String, Codable, Hashable, Sendable, ExpressibleByBooleanLiteral {
	/// No `mock()` is generated (`false`, `.none`, or no argument).
	case none
	/// A `mock()` the type's own module calls is generated (`true` or `.internal`).
	case `internal`
	/// A `public` `mock()` is generated, which modules of other packages call (`.public`).
	case `public`

	/// `true` is `.internal` and `false` is `.none`, as the macro reads a boolean literal.
	public init(booleanLiteral value: Bool) {
		self = value ? .internal : .none
	}

	/// Whether a `mock()` is generated at all.
	public var generatesMock: Bool {
		switch self {
		case .none:
			false
		case .internal, .public:
			true
		}
	}
}
