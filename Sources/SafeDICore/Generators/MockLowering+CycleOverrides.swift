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

/// Overrides around a cycle: a node a cycle builds again, whose parent's configuration has no field for it, reads the
/// overrides of the nearest node of its type around it, so a mock's overrides hold on every lap of the cycle, as a lazy
/// cycle's always did.
extension MockLowering {
	/// The override path a configured node read, with whether it read its configuration rather than a closure.
	struct AncestorOverridePath: Equatable {
		let path: String
		let hasConfiguration: Bool
		/// Whether the place is built with its type's hand-written mock, whose configuration has another shape than one
		/// built with its initializer: `validateConfigurationsAreBuiltOneWay` leaves out a place beneath a cycle edge.
		let builtWithHandWrittenMock: Bool

		/// The path a node reads its overrides at: its own field's, `path`, where `isReachable`, else the path the nearest
		/// node of its type around it read, `nearest`, where that node read the same kind of override, else none.
		static func own(path: String, hasConfiguration: Bool, builtWithHandWrittenMock: Bool, isReachable: Bool, nearest: AncestorOverridePath?) -> AncestorOverridePath? {
			if isReachable {
				AncestorOverridePath(path: path, hasConfiguration: hasConfiguration, builtWithHandWrittenMock: builtWithHandWrittenMock)
			} else if let nearest, nearest.hasConfiguration == hasConfiguration, nearest.builtWithHandWrittenMock == builtWithHandWrittenMock {
				nearest
			} else {
				nil
			}
		}
	}
}
