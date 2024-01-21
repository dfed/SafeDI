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

    public init(_ value: Element, next: List? = nil) {
        self.value = value
        self.next = next
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
        let itemToInsert = List(value, next: next)
        next = itemToInsert
        return itemToInsert
    }

    /// Prepends the value before the current element.
    /// This method does not modify previous elements in the list.
    /// - Parameter value: The value to prepend into the list.
    /// - Returns: The inserted element in the list.
    ///
    /// - Warning: Only call this method on the head of a list.
    @discardableResult
    public func prepend(_ value: Element) -> List<Element> {
        List(value, next: self)
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
}
