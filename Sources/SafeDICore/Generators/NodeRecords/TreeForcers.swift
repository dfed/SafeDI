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
/// - `validateFills` and `seamTierOmissions` judge seam calls and fills, which a module without seams has none of. In a
///   module with seams, node records refuse every fill (`.fill`), a world that holds one makes no records at
///   all (`SeamCallCheck.passesFill`), and they refuse a world whose seam call omits a value the world holds
///   (`NodeRecordRefusal.seamCallOmitsProvidedValue`, from `DeclarationsAnsweringReads`).
/// - `nonSendableWrapperCaptures` judges a `@Sendable` builder function, which only a `Sendable` wrapper or a cycle makes:
///   node records refuse a world in which one captures a wrapper (`NodeRecordRefusal.sendableFunctionCapturesWrapper`,
///   from `DeclarationsAnsweringReads`, which reads a seam call's `@Sendable` deferrals as one more such function), and
///   every cycle (`.cycle`), which `unpassableCycleLabelsInTree` judges too.
/// - `fulfillersOfTree`, the imports, is folded over the root's declarations (`TypeFactsImports`).
///
/// Where a test observes node records, the tree is built beside the records all the same, and each of these is checked
/// against it (`DependencyTreeGenerator.plannedRootCode(of:declaredTypeNames:)`).
public enum TreeForcer: Hashable, Sendable, CustomStringConvertible {
	/// The root is a seam's own, which node records do not lay out yet. Where the run names refusals
	/// (`GenerationRequest.namesNodeRecordRefusals`), the kind node records refuse the root's world with follows it.
	case seamWorld
	/// Node records refused the root's world, with this kind: a `NodeRecordRefusal`'s raw value, `notLaidOut` where the
	/// engine could not lay the records out.
	case nodeRecordKind(String)
	/// The run reads every root's tree beside its code.
	case reader(TreeReader)
	/// A check of the root's seam calls reads its tree, where no fact answers it yet.
	case seamCallCheck(SeamCallCheck)

	public var description: String {
		switch self {
		case .seamWorld:
			"seam world"
		case let .nodeRecordKind(kind):
			"kind \(kind)"
		case let .reader(reader):
			reader.rawValue
		case let .seamCallCheck(check):
			check.rawValue
		}
	}
}

/// What a check of a production root's seam calls reads of its tree before any code is generated, which no fact of its
/// world answers yet: a root of a module with seams whose world holds such a call keeps its tree, whatever its node
/// records make, so the check reports what it reports without them.
public enum SeamCallCheck: String, Hashable, Sendable {
	/// A seam call passes a fill, whose fills and dispatchers only the tree's fill pass makes, and which `validateFills`
	/// judges from the tree. Node records refuse such a world (`NodeRecordRefusal.fill`), so its root makes none.
	case passesFill = "seam call passes a fill"
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

	/// The layout of `instantiable`'s code from `nodeRecords`, which throws `NodeRecordRefusal.notLaidOut` where the
	/// engine cannot lay them out.
	init(of instantiable: Instantiable, nodeRecords: NodeRecords) throws {
		guard let code = try DependencyTreeGenerator.laidOutRootCode(of: instantiable, body: nodeRecords.rootBody) else {
			throw NodeRecordRefusal.notLaidOut
		}
		self.init(code: code, nodeRecords: nodeRecords)
	}

	/// The layout `code` writes, of a root whose records are `nodeRecords`.
	init(code: GeneratedCode, nodeRecords: NodeRecords) {
		self.code = code
		rootBody = nodeRecords.rootBody
		recordCount = nodeRecords.recordCount
	}
}
