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

extension DependencyTreeGenerator {
	/// The value each receive is handed in each place the trees of the dependency tree's roots build its type, read from
	/// the trees `generate` builds and generates code from, validated as `generate` validates them, without generating
	/// their code, and the types those trees construct. A generator that holds no seam builds every type inline, a seam's
	/// tree included, as a module that declares no seam generates it. Each supply and each type is listed once, however
	/// many places hand or build it; the order is the trees'.
	/// - Throws: The error `generate` reports when the trees are not valid.
	public func receivedValueSupplies() async throws -> ReceivedValueSupplies {
		let roots = try await dependencyTrees(unreadTypeComment: nil, ownAccessProof: ownAccessProof(), readersOfEveryTree: [.reader(.receivedValueSupplies)]).roots
		var supplies = [ReceivedValueSupply]()
		var constructedTypes = [TypeDescription]()
		for root in roots.compactMap(\.tree) {
			let tree = await root.scopeGenerator.receivedValueSupplies(ofTreeRootedAt: root.instantiable)
			supplies.append(contentsOf: tree.supplies)
			constructedTypes.append(contentsOf: tree.constructedTypes)
		}
		return ReceivedValueSupplies(supplies: supplies.uniqued(), constructedTypes: constructedTypes.uniqued())
	}
}

/// What the trees of a dependency tree's roots hand each receive, and the types they construct.
public struct ReceivedValueSupplies: Sendable {
	/// The value each receive is handed in each place a tree builds its type, each listed once.
	public let supplies: [ReceivedValueSupply]
	/// The concrete type of each declaration a tree constructs, each listed once.
	public let constructedTypes: [TypeDescription]
}

/// The value one receive is handed in one place of a dependency tree: a received dependency's, or an alias's, which
/// receives its fulfilling property.
public struct ReceivedValueSupply: Hashable, Sendable {
	/// The type that declares the receive.
	public let receivingType: TypeDescription
	/// The receive's label: a received dependency's, or an alias's own.
	public let label: String
	/// The value the receive is handed.
	public let value: Value

	/// The value a receive is handed: a declaration's, or `nil`.
	public enum Value: Hashable, Sendable {
		/// The value of a declaration: a dependency a type instantiates, forwards or aliases.
		case declaration(Supplier)
		/// `nil`, which generated code passes a receive only if available, for the reason given.
		case passedNil(NilReason)
	}

	/// Why generated code hands a receive `nil`.
	public enum NilReason: Hashable, Sendable {
		/// No declaration of the receive's label in scope where its type is constructed provides the form it reads.
		case noProvidingDeclaration
		/// The nearest declaration that provides it is built after the receive's type, or is still being built where
		/// the receive's type is constructed inside it.
		case providerNotYetBuilt
	}

	/// A declaration a type makes for the scopes it builds: a dependency it instantiates, forwards or aliases.
	public struct Supplier: Hashable, Sendable {
		/// The type that makes the declaration.
		public let declaringType: TypeDescription
		/// The declaration's label.
		public let label: String
	}

	/// This supply with its value `nil`, for `reason`.
	func passingNil(because reason: NilReason) -> Self {
		Self(receivingType: receivingType, label: label, value: .passedNil(reason))
	}
}
