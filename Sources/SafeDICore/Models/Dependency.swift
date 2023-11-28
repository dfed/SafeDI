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

/// A representation of a dependency.
/// e.g. `@singleton let mySingleton: MySingleton`
public struct Dependency: Codable, Equatable {
    public let property: Property
    public let source: Source

    public var isVariant: Bool {
        switch source {
        case .constructedInvariant, .providedInvariant, .singletonInvariant:
            return false
        case .propagatedVariant:
            return true
        }
    }

    public var isInvariant: Bool {
        switch source {
        case .constructedInvariant, .providedInvariant, .singletonInvariant:
            return true
        case .propagatedVariant:
            return false
        }
    }

    public enum Source: String, RawRepresentable, Codable, Equatable {
        case constructedInvariant = "constructed"
        case providedInvariant = "provided"
        case singletonInvariant = "singleton"
        case propagatedVariant = "propagated"
    }
}
