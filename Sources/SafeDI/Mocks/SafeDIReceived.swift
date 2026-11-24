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
/// A dependency a generated `mock()` receives and can also build: either an instance to use, or the configuration the
/// mock builds one with. One case at a time, so no setting is silently ignored.
///
/// Mocks take it only in a module that sets `#SafeDIConfiguration(apiVersion: .v3Unstable)`.
///
/// It is `@frozen` so that code switching over it compiles without `@unknown default` when SafeDI is built with
/// library evolution (Swift 6.2: "switch covers known cases, but … may have additional unknown values").
@frozen
public enum SafeDIReceived<Value, Configuration> {
	/// Use this instance.
	case instance(Value)
	/// Build an instance with this configuration.
	case built(Configuration)
}

extension SafeDIReceived: Sendable where Value: Sendable, Configuration: Sendable {}
