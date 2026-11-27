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

extension NodeRecords {
	/// A term of production's chain that marks a node rather than making its record: what it discharges, the record that
	/// makes the node honors by reading the node, never by the term's kind. `mockDecoratedRecord` honors both, a public mock
	/// call's record an erasure (`publicMockCallRecord`).
	enum ProductionMark {
		/// `erasedClaim(of:in:)`: the record wraps what it builds in the property's type where the node is erased.
		case erased
		/// `lazyClaim(of:in:)`: the record makes the wrapper of the builder function the node's place declares.
		case lazy
	}

	/// `claim`, of the term that makes `declaration`'s record in a mock root's world, joined with each mark of `marks` that
	/// claims the node: their discharges unioned, their refusals joined, of `claim`'s kind. The order of the terms cannot
	/// matter: a union of discharges is the same in any order, the kind is that of the one term that makes the record, and
	/// no mark holds a refusal of its own, so the refusals are `claim`'s whatever the order
	/// (`NodeRecordsObservation.joinsMockWorldTermsInReverse`, which a test sets to show it). Where production's chain
	/// takes the first term that claims a node, so that a `LazilyInstantiated` its type receives only if available is
	/// refused for `lazy`, a mock root's world joins every term that applies. Each term discharges only what its own
	/// classifier finds of the node, so a mark that does not apply discharges nothing.
	static func joiningProductionMarks(
		_ marks: [ProductionMark],
		to claim: NodeRecordClaim,
		of declaration: DeclarationID,
		in world: some NodeRecordSources,
	) -> NodeRecordClaim {
		var terms = [claim]
		for mark in marks {
			let markClaim = switch mark {
			case .erased:
				erasedClaim(of: declaration, in: world)
			case .lazy:
				lazyClaim(of: declaration, in: world)
			}
			if let markClaim {
				terms.append(markClaim)
			}
		}
		if NodeRecordsObservation.joinsMockWorldTermsInReverse {
			terms.reverse()
		}
		return terms.reduce(NodeRecordClaim(kind: claim.kind, discharges: [])) { joined, term in
			NodeRecordClaim(kind: joined.kind, discharges: joined.discharges.union(term.discharges), refusals: joined.refusals + term.refusals)
		}
	}

	/// What the override of `declaration`, a node of a mock root's world, discharges of stage 1's refusals, and the
	/// refusals of shapes it does not make yet, which `refusals(in:)` lists as it lists a kind's: a hand-written mock builds
	/// the type with or without an initializer (a fake has none); a receive only if available is passed what the mock's
	/// walk passes it (`mockOnlyIfAvailableDischarges(of:)`); a rename the type declares is a node of its own
	/// (`mockRenameDischargesAndRefusals(of:in:)`); a node built in a `@Sendable` function of its own reads its override
	/// from a local bound before the function (`NodeRecords+MockSendable.swift`); a dependency the mock cannot build is a
	/// parameter of `mock()` (`NodeRecords+MockUncoveredDependency.swift`).
	static func mockOverrideDischargesAndRefusals(of declaration: DeclarationID, in world: some NodeRecordSources) -> (discharges: Set<NodeRecordRefusal>, refusals: [NodeRecordRefusal]) {
		let rename = mockRenameDischargesAndRefusals(of: declaration, in: world)
		var discharges: Set<NodeRecordRefusal> = world.construction(of: declaration) == .handWrittenMock ? [.construction, .noInitializer] : []
		discharges.formUnion(mockOnlyIfAvailableDischarges(of: declaration))
		discharges.formUnion(rename.discharges)
		discharges.formUnion(mockSendableDischarges(of: declaration, in: world))
		// A dependency the mock cannot build is a parameter of `mock()`, which the node's construction reads
		// (`NodeRecords+MockUncoveredDependency.swift`).
		discharges.formUnion(mockUncoveredDependencyDischarges(of: declaration, in: world))
		var refusals = rename.refusals + mockSendableRefusals(of: declaration, in: world) + mockActorWrapperRefusals(of: declaration, in: world)
		let instantiable = world.scope(of: declaration).instantiable
		// An actor is claimed as any node is. The closure that overrides it takes each argument `sending`
		// (`MockLowering.BuilderParameters`), and what it is sent is built by functions that are each handed their
		// configuration, the `Sendable` form beneath an actor (`ScopeGenerator.sendableConfigurationTypeNames(ofMockRootOf:)`),
		// so none captures `mock()`'s overrides, as the walk's read of them into a local before each function keeps its own
		// from doing.
		// A wrapper the actor builds calls its function in a closure, which would capture the configuration the actor's
		// function is handed, so its override is read into a local before it (`isWrapperSentToActor(_:in:)`).
		// The root's own default-valued parameters are parameters of `mock()`, which the root's lowering judges
		// (`ScopeGenerator.nodeRecordsMockStatements(of:worldRoot:bindsOnlyNodes:sendableConfigurationTypeNames:rootNames:outerDeclarations:)`).
		if declaration != 0, mockConstructionFunction(of: declaration, in: world).map({ passesValueNoRecordMakes($0, given: instantiable.dependencies) }) ?? false {
			refusals.append(.mockDefaultValuedParameter)
		}
		// A child the mock root names apart reads the root's field under that name, where every read of its label is one
		// the records make (`NodeRecords+MockOverrideNotParentField.swift`).
		if let refusal = refusalOfNamingApart(declaration, in: world) {
			refusals.append(refusal)
		}
		return (discharges, refusals)
	}

	/// The record of `declaration`'s place, a node of kind `mockConstruction`: the record production makes of it
	/// (`builtByInitializerRecord`'s), decorated with the node's override. The decoration hands the maker
	/// what it derives other fields from (the bound property, from which its function is named; a hand-written mock; the
	/// fields of its configuration its construction reads; the receives the node binds again before its children), and
	/// then sets the override's fields (`mockConstructionRecord`). An erased node's override returns the property's type
	/// (`mockErasedDecoration(of:)`). The local a `@Sendable` function reads its override from is a place before the node's,
	/// which the walk of the records puts there (`mockOverridesBindingPlace(of:record:in:)`).
	static func mockDecoratedRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		unavailableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		receivesBoundAgain: [MockReceiveBoundAgain],
		wrapperArgumentNames: [String: String] = [:],
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		let record = try mockConstructionRecord(
			of: declaration,
			variant: variant,
			in: world,
			unavailableProperties: unavailableProperties,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			receivesBoundAgain: receivesBoundAgain,
			wrapperArgumentNames: wrapperArgumentNames,
			typesDeclaredEscaping: typesDeclaredEscaping,
			children: children,
		)
		return isMockErased(declaration, in: world) ? mockErasedDecoration(of: record) : record
	}
}
