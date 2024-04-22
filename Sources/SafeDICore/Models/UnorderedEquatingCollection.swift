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

public struct UnorderedEquatingCollection<Element: Hashable>: Hashable, Collection, ExpressibleByArrayLiteral {
    // MARK: Initialization

    public init(_ array: [Element]) {
        self.array = array
        set = Set(array)
    }

    // MARK: Equatable

    public static func == (lhs: UnorderedEquatingCollection, rhs: UnorderedEquatingCollection) -> Bool {
        lhs.set == rhs.set
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(set)
    }

    // MARK: Collection

    public func makeIterator() -> IndexingIterator<[Element]> { array.makeIterator() }
    public var startIndex: Int { array.startIndex }
    public var endIndex: Int { array.endIndex }
    public func index(after i: Int) -> Int {
        array.index(after: i)
    }

    public subscript(position: Int) -> Element {
        array[position]
    }

    // MARK: ExpressibleByArrayLiteral

    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }

    public typealias ArrayLiteralElement = Element

    // MARK: Private

    private let array: [Element]
    private let set: Set<Element>
}

// MARK: - Encodable

extension UnorderedEquatingCollection: Encodable where Element: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(array)
    }
}

// MARK: - Decodable

extension UnorderedEquatingCollection: Decodable where Element: Decodable {
    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode([Element].self))
    }
}

// MARK: - Sendable

extension UnorderedEquatingCollection: Sendable where Element: Sendable {}
