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

/// What still makes `generate` build a production root's place tree (`ScopeGenerator`): a kind node records do not make
/// yet, or a reader of the tree that has no fold over the per-type facts yet. A root that none holds builds no tree. Its
/// code is laid out from its node records (`NodeRecordsLayout`), and each check that reads a root's tree reads them:
///
/// - `validateFills` and `seamTierOmissions` judge seam calls and fills, which a module without seams has none of.
/// - `nonSendableWrapperCaptures` judges a `@Sendable` builder function, which only a `Sendable` wrapper or a cycle makes:
///   node records refuse a world in which one captures a wrapper (`NodeRecordRefusal.sendableFunctionCapturesWrapper`,
///   from `DeclarationsAnsweringReads`), and every cycle (`.cycle`), which `unpassableCycleLabelsInTree` judges too.
/// - `fulfillersOfTree`, the imports, is folded over the root's world (`NodeRecordsLayout.fulfillers`).
///
/// Where a test observes node records, the tree is built beside the records all the same, and each of these is checked
/// against it (`DependencyTreeGenerator.plannedRootCode(of:declaredTypeNames:)`).
public enum TreeForcer: Hashable, Sendable, CustomStringConvertible {
	/// The module holds a seam, whose roots node records do not lay out yet. Where the run names refusals
	/// (`GenerationRequest.namesNodeRecordRefusals`), the kind node records refuse the root's world with follows it.
	case seamWorld
	/// Node records refused the root's world, with this kind: a `NodeRecordRefusal`'s raw value, `notLaidOut` where the
	/// engine could not lay the records out.
	case nodeRecordKind(String)
	/// The run reads every root's tree beside its code.
	case reader(TreeReader)

	public var description: String {
		switch self {
		case .seamWorld:
			"seam world"
		case let .nodeRecordKind(kind):
			"kind \(kind)"
		case let .reader(reader):
			reader.rawValue
		}
	}
}

/// What a run can read of every root's tree beside its code, which no root's node records stand in for yet.
public enum TreeReader: String, Hashable, Sendable {
	/// The DOT graph, whose columns are read from the tree's places (`TypeFactsDOT`).
	case dotGraph = "DOT graph"
	/// What each tree hands each receive (`DependencyTreeGenerator.receivedValueSupplies()`).
	case receivedValueSupplies = "received value supplies"
}

/// The trees one run of `generate` built, and what forced each (`TreeForcer`), for each production root in type order.
public struct TreeForcerReport: Sendable {
	/// Each root's concrete type, and what forced its tree: empty where it built none.
	public let forcersByRoot: [(root: String, forcers: [TreeForcer])]

	/// How many roots built a tree. The gate of row 7 is 0.
	public var forcedRootCount: Int {
		forcersByRoot.count { !$0.forcers.isEmpty }
	}

	/// A line per root, `<root>\t<forcers, or none>`, then the count of roots that built a tree.
	public var lines: [String] {
		forcersByRoot.map { root in
			"\(root.root)\t\(root.forcers.isEmpty ? "none" : root.forcers.map(\.description).joined(separator: ", "))"
		} + ["roots that built a tree: \(forcedRootCount) of \(forcersByRoot.count)"]
	}
}

/// A production root's code laid out from its node records, and the facts the checks of its tree read instead of it.
struct NodeRecordsLayout: Sendable {
	/// The extension that declares the root's generated initializer.
	let code: GeneratedCode
	/// The root's body as node records make it, which a test compares with the tree's.
	let rootBody: [GeneratedCode]
	/// How many records node records made.
	let recordCount: Int
	/// What the generated file imports for the root: each declaration the world builds as a property, as
	/// `ScopeGenerator.fulfillersOfTree(buildingMock:)` collects them from the tree's places.
	let fulfillers: Set<FulfillerImports.Fulfiller>

	/// The layout of `instantiable`'s code from `world`'s node records, which throws `NodeRecordRefusal.notLaidOut` where the
	/// engine cannot lay them out.
	init(of instantiable: Instantiable, world: some NodeRecordSources, nodeRecords: NodeRecords) throws {
		guard let code = try DependencyTreeGenerator.laidOutRootCode(of: instantiable, body: nodeRecords.rootBody) else {
			throw NodeRecordRefusal.notLaidOut
		}
		self.code = code
		rootBody = nodeRecords.rootBody
		recordCount = nodeRecords.recordCount
		var fulfillers = Set<FulfillerImports.Fulfiller>()
		// The root is built as no property, so it adds none, as the tree's root place adds none; nor does a rename or a hole,
		// which builds nothing.
		for declaration in 0..<Int32(world.declarationCount) where world.kind(of: declaration) != .alias && world.kind(of: declaration) != .hole {
			fulfillers.formUnion(world.property(of: declaration).map { property in
				FulfillerImports.Fulfiller.fulfillers(
					building: world.scope(of: declaration).instantiable,
					forPropertyOfType: property.typeDescription.asInstantiatedType,
					callingHandWrittenMock: false,
				)
			} ?? [])
		}
		self.fulfillers = fulfillers
	}
}
