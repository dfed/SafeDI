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

/// The decisions that select the clauses of an `#if` block that holds nothing else SafeDI reads but declares a plain type
/// (`PlainTypeDeclaration`) in some clause, the conditions the selection consulted, and the types the block declares in
/// any clause. A module keeps the plain declarations of some types only (`FileScan.keepingPlainTypeDeclarations`): the
/// block's conditions decide what the module reads only when it declares one of those, and its decisions are asserted in
/// the module's generated files (`ConditionalCompilationDecision.compileTimeAssertions`) only when a read the access
/// check makes can resolve to a declaration the block could hold.
public struct GuardedPlainTypeNames: Codable, Hashable, Sendable {
	/// - Parameters:
	///   - decisions: How the block's bare conditions were evaluated, in source order.
	///   - consultedConditions: Every bare condition the selection of the block's clauses depended on, sorted.
	///   - declaredTypes: Each type the block declares, in any clause, sorted and without duplicates.
	public init(decisions: [ConditionalCompilationDecision], consultedConditions: [String], declaredTypes: [DeclaredType]) {
		self.decisions = decisions
		self.consultedConditions = consultedConditions
		self.declaredTypes = declaredTypes
	}

	/// A type an `#if` block declares in some clause, as far as deciding whether a read resolves to it needs.
	public struct DeclaredType: Codable, Hashable, Comparable, Sendable {
		/// - Parameters:
		///   - name: The type's own name, the last of its chain, without the backticks it was written with.
		///   - outermostName: The name of the outermost type enclosing it, or its own when nothing encloses it, without
		///     the backticks it was written with.
		///   - level: The level its declaration gives it before the type an enclosing extension extends caps it
		///     (`PlainTypeDeclaration.levelBeforeExtendedTypeCap`), normalized (`AccessLevel.normalized(_:)`).
		public init(name: String, outermostName: String, level: AccessLevel) {
			self.name = name
			self.outermostName = outermostName
			self.level = level
		}

		/// The type's own name, the last of its chain: the name a member of a type enclosing it can mention it by.
		public let name: String
		/// The name of the outermost type enclosing it, or its own when nothing encloses it.
		public let outermostName: String
		/// The level its declaration gives it, normalized: `public`, `package` or `internal`. A mention in another module
		/// names the type only when it is `package` or wider.
		public let level: AccessLevel

		public static func < (lhs: DeclaredType, rhs: DeclaredType) -> Bool {
			(lhs.name, lhs.outermostName, lhs.level) < (rhs.name, rhs.outermostName, rhs.level)
		}
	}

	/// How the block's bare conditions were evaluated, in source order.
	public let decisions: [ConditionalCompilationDecision]
	/// Every bare condition the selection of the block's clauses depended on, sorted: walking the file with an evaluator
	/// that gives each the same value records the same declarations from the block.
	public let consultedConditions: [String]
	/// Each type the block declares, in any clause of it or of a block nested in it, sorted and without duplicates. They
	/// are read from every clause, so they are the same whatever the conditions.
	public let declaredTypes: [DeclaredType]
}
