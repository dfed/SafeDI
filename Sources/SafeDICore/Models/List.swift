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

@dynamicMemberLookup
public final class List<Element>: Sequence {

    // MARK: Initialization

    public init(value: Element, previous: List? = nil, next: List? = nil) {
        self.value = value
        self.previous = previous
        self.next = next
    }

    public convenience init?(_ collection: some Collection<Element>) {
        guard let first = collection.first else { return nil }
        self.init(first: first, remaining: collection.dropFirst())
    }

    public convenience init(first: Element, remaining: some Collection<Element>) {
        self.init(value: first)
        var next = self
        for element in remaining {
            next = next.insert(element)
        }
    }

    // MARK: Public

    public let value: Element

    public subscript<T>(dynamicMember keyPath: KeyPath<Element, T>) -> T {
        value[keyPath: keyPath]
    }

    /// Inserts the value after the current element.
    /// - Parameter value: The value to insert into the list.
    /// - Returns: The inserted element in the list.
    @discardableResult
    public func insert(_ value: Element) -> List<Element> {
        let next = next

        let nextToInsert = List(value: value)
        self.next = nextToInsert

        nextToInsert.next = next
        nextToInsert.previous = self

        next?.previous = nextToInsert

        return nextToInsert
    }

    /// Removes the receiver from the list.
    /// - Returns: The next element in the list, if the current element is the head of the list.
    @discardableResult
    public func remove() -> List<Element>? {
        previous?.next = next
        next?.previous = previous
        return previous == nil ? next : nil
    }

    // MARK: Sequence

    public func makeIterator() -> Iterator {
        Iterator(node: self)
    }

    public struct Iterator: IteratorProtocol {
        init(node: List?) {
            self.node = node
        }

        public mutating func next() -> List? {
            defer { node = node?.next }
            return node
        }

        private var node: List?
    }

    // MARK: Private

    private var next: List? = nil
    private var previous: List? = nil
}
