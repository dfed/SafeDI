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

/// One question the mock writer asks of the module's cycle edges (`MockLowering.Walk.isPruned(_:beneath:)`): whether the
/// configuration of the node built for `parentConcreteType` (`nil` at the mock's root, whose `SafeDIOverrides` leaves
/// nothing out) has a field for a child built for `concreteType`.
public struct MockOverrideSourceDecision: Hashable, Sendable {
	/// The parent's concrete type, as `ScopeGenerator.CycleEdge` spells it, or `nil` at the mock's root.
	public let parentConcreteType: String?
	/// The child's concrete type, as `ScopeGenerator.CycleEdge` spells it.
	public let concreteType: String
	/// Whether the type edge is left out: the parent's configuration has no field for the child.
	public let isLeftOut: Bool
}

/// The questions the mock writer asks of the cycle edges as it lowers each mock root, handed with the mock root's type to
/// `observer`, which the tests set, never the tool, to compare with the per-type facts' edge column
/// (`TypeFactsOverrideSource`).
public enum MockOverrideSourceObservation {
	@TaskLocal public static var observer: (@Sendable (_ mockRoot: String, _ decision: MockOverrideSourceDecision) -> Void)?
}
