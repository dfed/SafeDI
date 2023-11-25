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

struct Dependency: Codable, Equatable {
    let variableName: String
    let type: String
    let source: Source

    var isVariant: Bool {
        switch source {
        case .constructedInvariant, .providedInvariant, .singletonInvariant:
            return false
        case .variant:
            return true
        }
    }

    var isInvariant: Bool {
        switch source {
        case .constructedInvariant, .providedInvariant, .singletonInvariant:
            return true
        case .variant:
            return false
        }
    }

    enum Source: Codable, Equatable {
        case constructedInvariant
        case providedInvariant
        case singletonInvariant
        case variant

        init?(_ attributeText: String) {
            if attributeText == ConstructedMacro.name {
                self = .constructedInvariant
            } else if attributeText == SingletonMacro.name {
                self = .singletonInvariant
            } else {
                return nil
            }
        }
    }
}
