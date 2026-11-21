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

/// The value one receive is handed in one place of a dependency tree: a received dependency's, or an alias's, which
/// receives its fulfilling property.
public struct ReceivedValueSupply: Hashable, Sendable {
	/// The type that declares the receive.
	public let receivingType: TypeDescription
	/// The receive's label: a received dependency's, or an alias's own.
	public let label: String
	/// The declaration whose value the receive is handed, or `nil` where generated code hands it `nil`.
	public let supplier: Supplier?

	/// A declaration a type makes for the scopes it builds: a dependency it instantiates, forwards or aliases.
	public struct Supplier: Hashable, Sendable {
		/// The type that makes the declaration.
		public let declaringType: TypeDescription
		/// The declaration's label.
		public let label: String
	}
}
