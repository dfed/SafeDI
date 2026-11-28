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

/// The work a step of generation did: how many elements it read, wrote or compared. Each step counted here once did work
/// that grew with the square of a seam's places – it copied or scanned every place's names, or every fill of a call, once
/// for each place, fill or scope – and is counted so that a test can check that its work grows no faster than the paths
/// to the places. Handed to `observer`, which the tests set, never the tool.
///
/// Work is counted where each scope, fill, builder or name takes the collection it consults (`taking(_:by:)`), not where
/// the collection is built: a collection taken as a plain value counts every element, as if built or scanned for the taker,
/// so a step that builds or scans its collection again for each taker counts that work whatever its own code reports. A
/// collection built once is taken as `Shared`, which counts its building where it is built; names kept in several sets
/// are taken as `NamesConsultedInTurn`, which counts each membership test.
///
/// `observer` is task-local. It sees every step `generate` runs: building each tree and computing each seam's signature in
/// `generate`'s own task and its children, and emitting each scope's code on the task `ScopeGenerator.generateCode`
/// creates for it, which inherits the observer of the task that asks for the code. A step passes no `Step` (`taking(_:by:)` with `nil`) where its work is not counted:
/// `identifierSafeNames` counts only for a seam's signature.
public struct GenerationWork: Sendable {
	/// A step of generation whose work is counted.
	public enum Step: String, Sendable, Hashable, CaseIterable {
		/// Naming entries that share a label apart by their suffix types
		/// (`ScopeGenerator.identifierSafeNames(for:besideEntriesKeepingTheirNames:reservedNames:countingWorkAs:)`), for a
		/// seam's signature: each entry, at each suffix position it tries, takes what it must differ from there, the entries
		/// sharing its label and suffix.
		case namingEntriesApart
		/// Naming each of a seam's builders apart from the names bound in its initializer: each builder of a place takes the
		/// names it must avoid (`DependencyTreeGenerator.holes`), and the builders of each hole type the names the initializer
		/// declares before them (`DependencyTreeGenerator.shapedBuilders`).
		case namingSeamBuilders
		/// Gathering the fills and dispatchers of a seam call, which every fill inside the call takes, as does the call.
		case gatheringFillsOfACall
		/// Joining the names a seam's tree binds for its builders and its deferred parameters, which every scope of the tree
		/// takes.
		case joiningNamesBoundBySeam
		/// Naming the scope value each call of an inner seam hands a fill (`DependencyTreeGenerator.innerScopeNames`): each
		/// call and builder takes the names it must avoid.
		case namingInnerScopes
		/// Naming the struct each member call on the routes to a seam's places returns (`DependencyTreeGenerator.memberBindingNames`):
		/// each binding takes the names it must avoid.
		case namingValuesBindings
		/// Reserving the names a seam call's fills and dispatchers avoid: the enclosing calls' fills and the names the seam
		/// whose tree holds the call binds, which each call takes.
		case reservingNamesOfACall
		/// Laying a production root's body out by the type key (`TypeKeyBody`): each view of the plan, one for all of a
		/// plan node's places that agree on what they read outside it, is laid out once, so the views count, not the places.
		case layingOutTypeKeyViews
		/// Finding the root functions a root's body holds (`RootFunctionHoisting`): each level of the plan the walk reads.
		/// A place records whether a root function is beneath it, so the walk reads no tree of a place that holds none,
		/// and its levels do not grow with the paths through the tree.
		case findingRootFunctions
		/// Looking a place up in the construction memo (`ConstructionMemo.reuse(of:in:besideCallGenerators:drawing:)`): each
		/// candidate of the place's key whose log the lookup asks. The candidates are found by what their reads of the
		/// declaration a cycle closes on were answered, so a lookup asks the ones its context answers alike, not every
		/// candidate a tree with cycles stored for the key.
		case askingMemoCandidates
		/// Filing an entry of the construction memo under its cycle reads (`ConstructionMemo`'s `Candidates`): each cycle read
		/// of the entry's subtree. A key files its entries once it holds two, so a chain of places with one entry each
		/// files none; filing every entry listed the reads of a chain of n places n² times.
		case filingMemoEntryReads
		/// Asking whether a read of a type key class's statement is `nil` in every member of the class
		/// (`TypeKeyLayout.checkEveryRead`): each member's statement read. The answer is the class's, so each read is asked
		/// once per class and reads each member once; asked for every member, it read the members of a class of n members
		/// n² times.
		case checkingReadsAtEveryMember
		/// Collecting the types a tree builds: for the imports of a root's file, each declaration its world reaches
		/// (`TypeFactsImports`); for the imports of a mock's file (`ScopeGenerator.fulfillersOfTree(buildingMock:)`) and the
		/// public mocks a mock tree reaches (`concreteTypesOfTree()`), each generator the walk visits. A declaration stands
		/// for every place of it, and a walk visits a generator once, so neither counts the places that share them; entered
		/// at every place, a tree of n layers of screens that each build every screen of the next layer was visited once per
		/// path.
		case collectingTypesOfATree
		/// Finding the value each receive in a root's tree is handed (`TypeFactsReceivedValueSupplies`), for `query graph`:
		/// each edge into a node, in each pass over its component, for each label a receive reads, and each declaration a
		/// receive can read. A node stands for every place of its declaration, so a tree of n layers of screens that each
		/// open screens of the next layer counts its edges, not its paths, which the walk it replaced entered each of.
		case findingReceivedValueSupplies
		/// Collecting what the scopes of a lazy cycle in a seam's tree declare between the builder function the cycle closes
		/// on and the scopes that call it again (`DependencyTreeGenerator.declarationsBetween(closedOnScope:closedOnDeclaration:)`):
		/// each generator a walk reads. A walk reads a generator once, so the generators count, not the paths through
		/// them; walked along every path, layers of screens that each build every screen of the next layer were read
		/// once per path.
		case collectingDeclarationsOfACycle
		/// Finding, for a child a scope on a site's path builds after the property that leads to the site, the first carrier
		/// among its siblings that it requires (`DependencyTreeGenerator.fields(of:)`): the properties the child
		/// requires, where they are fewer than the scope's carriers and each is looked up, or else the carriers compared
		/// until one is found. Scanned for in every case, every carrier of the scope was compared for every later
		/// child of every site, so a seam whose own type builds n children that each hold a place compared n carriers n²
		/// times.
		case findingCarrierASiblingRequires
		/// Finding the fill of a seam call that stands for a place (`ScopeGenerator.FillStoodFor`): each place of a call
		/// and each set of fills of the place's case with one tree's reads that its lookup asks (`Scope.nextFill()`), and,
		/// where the capture walk reaches the call, each place stood for that it gathers under its fill and each that a
		/// fill then takes. Scanned for, the fills of a case were compared for every place of it, and the places stood
		/// for for every fill.
		case findingFillThatStandsForPlace
		/// Collecting the names of the builder functions of a seam's tree (`DependencyTreeGenerator.builderFunctionNamesOfProperties(in:includingHoleSites:)`):
		/// each generator the walk visits. A walk visits a generator once, so the generators count, not the places that
		/// share them.
		case collectingBuilderFunctionNames
		/// Finding a seam's receivers and the reads of its parameters (`DependencyTreeGenerator.receivers(in:of:instantiables:)`):
		/// each place of the seam's tree the walk reaches, a place it then skips included. A place whose generator the walk
		/// already visited with the same context, as far as the generator's subtree reads it, is skipped and its children
		/// are not reached, so the generators and the contexts their parents are visited in count, not the paths to them.
		case findingSeamReceivers
		/// Finding the values a seam tier a tree calls omits (`ScopeGenerator.seamTierOmissions(ofTreeRootedAt:isOwnFile:)`):
		/// each place the walk visits. The walk enters no tree that holds no call of a seam tier that omits a parameter, and
		/// in a tree that holds one only a place whose subtree holds such a call or a scope that closes a lazy cycle.
		case findingSeamTierOmissions
		/// Finding the facts producers still owe each declaration of a world (`TypeFactsGraph.owedFactsByNode`): each
		/// declaration, each edge, and each declaration a walk down from the fills reaches, once per world. Asked of each
		/// declaration with a walk up its parents, a chain of n declarations walked n² parents.
		case findingOwedFacts
	}

	/// The step that did the work.
	public let step: Step
	/// The elements it read, wrote or compared.
	public let elementCount: Int

	/// Called with the work of a counted step each time the step runs, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (GenerationWork) -> Void>?

	/// Hands `observer`, when set, the work `step` did, when `step` is not `nil`.
	static func record(_ elementCount: Int, by step: Step?) {
		if let observer, let step {
			observer(GenerationWork(step: step, elementCount: elementCount))
		}
	}

	/// `collection`, which a scope, fill, builder or name of `step` takes: as a plain value, it was built or is scanned for
	/// the taker, so each of its elements counts.
	static func taking<Taken: Collection>(_ collection: Taken, by step: Step?) -> Taken {
		record(collection.count, by: step)
		return collection
	}

	/// The value of `shared`, built once for every taker and counted where it was built, so taking it counts nothing.
	static func taking<Value>(_ shared: Shared<Value>, by _: Step?) -> Value {
		shared.value
	}

	/// `names`, which a builder, name or call of `step` takes: taking it copies none of their names, and each membership test
	/// it is asked then counts as one.
	static func taking(_ names: NamesConsultedInTurn, by step: Step?) -> NamesConsultedInTurn {
		var names = names
		names.step = step
		return names
	}

	/// A collection built once and handed to each scope, fill or builder that takes it, which costs the taker nothing:
	/// its building is counted where it is built.
	struct Shared<Value: Sendable>: Sendable {
		init(_ value: Value) {
			self.value = value
		}

		fileprivate let value: Value
	}
}

/// Names a builder, a name or a call must avoid, held as the sets they are in and asked of each in turn: joining the sets
/// would copy every name of each for every builder, name or call that asks, where the sets grow with a seam's places.
/// Each test asks as many sets as there are calls or paths enclosing the asker, which the code generated there spells too.
///
/// A set handed here shares its storage with the collection it came from, so the holder releases this value before it
/// inserts into that collection: inserting while both hold the storage copies it.
struct NamesConsultedInTurn: Sendable {
	/// Names in `sets`, each asked in turn, apart from `exception`, which the last set does not hold for this asker.
	init(_ sets: [Set<String>], exceptFromTheLast exception: String? = nil) {
		self.sets = sets
		self.exception = exception
	}

	/// Whether any set holds `name`: one membership test of the step that took these names (`GenerationWork.taking(_:by:)`).
	func contains(_ name: String) -> Bool {
		GenerationWork.record(1, by: step)
		return sets.indices.contains { index in
			sets[index].contains(name) && (index != sets.count - 1 || name != exception)
		}
	}

	/// The step whose membership tests these are, once taken.
	fileprivate(set) var step: GenerationWork.Step?

	private let sets: [Set<String>]
	private let exception: String?
}
