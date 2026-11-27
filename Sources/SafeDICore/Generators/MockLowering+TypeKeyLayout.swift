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

import Foundation

/// The type key's layout of an internal mock's body (`TypeKeyBody`): the walk's places, each with the record production's
/// record function makes of it, laid out as production's are. A root any place of which has
/// no record, or reads a value the records cannot name, keeps the walk's body.
extension MockLowering {
	/// Whether internal mocks' bodies are laid out by the type key. A test that compares the walk's body sets it off.
	@TaskLocal static var laysOutWithTypeKey = true

	/// Whether public mocks' bodies are laid out by the type key too. Off, because a public mock's records do not yet carry
	/// everything its body reads: each place whose record cannot say what the walk writes refuses its root where the record
	/// is made (`recordInputs(of:…)`), and a public mock's root shares no subtree (`sharesSubtrees(of:)`), so a root that
	/// reports `laidOut` under this switch is one whose records carried its whole body. Set by the tests of those refusals;
	/// never by the tool.
	@TaskLocal static var laysOutPublicMocksWithTypeKey = false

	/// Called, where set, with how many places each check of the reads of a root's laid-out body (`unresolvedRead(in:declaredAtRoot:)`)
	/// read. Set by the tests that check the check grows with the places of the plan, never with the paths; never by the tool.
	@TaskLocal public static var unresolvedReadObserver: (@Sendable (_ readPlaces: Int) -> Void)?

	/// Called with each internal mock root's layout outcome while the switch is on: `laidOut`, or why the root keeps the walk's
	/// body, as `unrecorded:threw:<error case>` where production's record function threw at one of its places. Set by the
	/// tests and the graph fuzzer, which fails a graph that falls back on an error case it does not expect; never by the
	/// tool.
	@TaskLocal public static var typeKeyLayoutObserver: (@Sendable (_ mockedType: String, _ outcome: String) -> Void)?

	/// Called after each walk of a mock root's tree with how many statements the walk wrote to the root's body: none where
	/// the type key may lay the root out, whose body the layout writes from the walk's records, and every one where the root
	/// is walked again because its layout fell back, or is never laid out (`MockLowering.Walk.writesText`). Set by the tests,
	/// which fail when a walk the layout follows writes a statement; never by the tool.
	@TaskLocal static var rootWalkObserver: (@Sendable (_ mockedType: String, _ statementCount: Int) -> Void)?

	/// What the walk hands production's record function at a built place.
	///
	/// A class, so that the walk's table of them holds a reference per place: the table has a slot for up to twice the
	/// places it holds, and copies them all as it grows, which for a mock of tens of thousands of places was the largest
	/// thing the walk held. Each is released as its place is recorded.
	final class BuiltPlaceCall {
		init(
			generator: ScopeGenerator,
			property: Property,
			instantiable: Instantiable,
			forwardedProperties: Set<Property>,
			erasedToConcreteExistential: Bool,
			unavailableProperties: Set<Property>,
			inputs: BuiltPlaceInputs,
			node: PlanNode,
			nodeConfiguration: NodeConfiguration,
			isPlannedAtPlace: Bool,
		) {
			self.generator = generator
			self.property = property
			self.instantiable = instantiable
			self.forwardedProperties = forwardedProperties
			self.erasedToConcreteExistential = erasedToConcreteExistential
			self.unavailableProperties = unavailableProperties
			self.inputs = inputs
			self.node = node
			self.nodeConfiguration = nodeConfiguration
			self.isPlannedAtPlace = isPlannedAtPlace
		}

		let generator: ScopeGenerator
		let property: Property
		let instantiable: Instantiable
		let forwardedProperties: Set<Property>
		let erasedToConcreteExistential: Bool
		let unavailableProperties: Set<Property>
		let inputs: BuiltPlaceInputs
		let node: PlanNode
		/// How the node the walk lowered the place to is configured, which the record reads (`relateConfiguration(ofBuiltPlaceAt:…)`).
		let nodeConfiguration: NodeConfiguration
		let isPlannedAtPlace: Bool
	}
}

extension MockLowering.Walk {
	/// Makes the record of each built place the walk lowered, the places in its builder function first, so each record holds
	/// its children's.
	mutating func recordBuiltPlaces() {
		var childPathsByParent = [[Int]: [[Int]]]()
		for path in placePathsInWalkOrder {
			childPathsByParent[Array(path.dropLast()), default: []].append(path)
		}
		// The places with a place beneath them left unrecorded, which a place whose function reads overrides into locals
		// keeps the walk's body for.
		var pathsAboveUnrecordedPlace = Set<[Int]>()
		// Every function of a type takes the nearest configurations of the places closers beneath it close on, one list
		// for the type, so no function's parameters follow the path that reaches it.
		// A tree no closer closes hands no nearest configuration: a place a cycle builds again has a closer beneath it.
		var closesCycle = false
		for case .closer in closerAndDefaultRecords.values {
			closesCycle = true
			break
		}
		let nearest: MockLowering.NearestConfigurations? = buildsPublicMock || !closesCycle ? nil : nearestConfigurations(childPathsByParent: childPathsByParent)
		var parentFieldsReadByBuiltPlaces = Set<ParentFieldRead>()
		if nearest != nil {
			for context in builtPlaceConfigurationContexts.values {
				if let parentConfiguration = context.parentConfiguration {
					parentFieldsReadByBuiltPlaces.insert(ParentFieldRead(parentConfiguration: parentConfiguration, fieldName: context.fieldName))
				}
			}
		}
		// What a call hands the nearest configurations its callee's function takes is the same at every call of that
		// function made in a function of one type, so each list is made once and every such call's record shares it.
		struct NearestCall: Hashable {
			let calleeName: String
			let callerName: String?
		}
		var nearestArgumentsByCall = [NearestCall: [PassedArgument]]()
		func nearestArguments(_ nearest: MockLowering.NearestConfigurations, ofCallTo callee: MockLowering.ConfigurationParameter, at path: [Int]) -> [PassedArgument] {
			let call = NearestCall(calleeName: callee.name, callerName: nearest.ownParameterByPath[Array(path.dropLast())]?.name)
			if let arguments = nearestArgumentsByCall[call] {
				return arguments
			} else {
				let arguments = nearest.nearestArguments(ofCallTo: callee, at: path)
				nearestArgumentsByCall[call] = arguments
				return arguments
			}
		}
		// What each generator's construction reads in each context it is written in, which reads only the generator and its
		// unavailable properties (`ScopeGenerator.constructionReads(of:unavailableProperties:)`), computed once for the places
		// that share them, many thousands in a wide mock, and kept only while the records are made. A plan node is no such
		// context: it also keys what the walk reads at the place, such as the override's path, which differs at every place.
		struct ConstructionContext: Hashable {
			let generator: ObjectIdentifier
			let unavailableProperties: Set<Property>
		}
		var constructionReadsByContext = [ConstructionContext: Result<[PlaceRead]?, Initializer.GenerationError>]()
		// The configurations the functions of the members of the root's loops of builders take, read while every member's
		// call is known.
		let loopConfigurations = loopMemberConfigurations()
		for call in builtPlaceCalls.values where call.isPlannedAtPlace {
			let context = ConstructionContext(generator: ObjectIdentifier(call.generator), unavailableProperties: call.unavailableProperties)
			if constructionReadsByContext[context] == nil {
				// A member of a loop of builders writes its rebindings as places of their own, its closers, or keeps the walk's body
				// (`unplannedLines:rebindings`).
				constructionReadsByContext[context] = call.generator.isPlannedByGenerator(plansRebindings: true)
					? Result { () throws(Initializer.GenerationError) in try call.generator.constructionReads(of: call.instantiable, unavailableProperties: call.unavailableProperties) }
					: .success(nil)
			}
		}
		// The first record made of each key, whose node every alike place takes (`sharingNode(ofBuiltPlaceAt:nodesByKey:)`).
		var sharedRecordsByKey = [MockLowering.SharedRecordKey: BuiltPlaceRecord]()
		// Walk order starts a place before the places beneath it, so the reverse finishes them first. Where the walk shared a
		// subtree, the place that holds its records is recorded before the meetings that take them, depth first.
		let subtreeSharing = subtreeSharing.flatMap { $0.sharedMeetings > 0 ? $0 : nil }
		let recordingOrder = subtreeSharing == nil ? Array(placePathsInWalkOrder.reversed()) : placePathsRecordingSharedSubtreesFirst()
		// The first unrecorded place in walk order, whatever order the places are recorded in.
		var walkIndexByPath = [[Int]: Int]()
		if subtreeSharing != nil {
			for (index, path) in placePathsInWalkOrder.enumerated() {
				walkIndexByPath[path] = index
			}
		}
		for path in recordingOrder {
			defer {
				builtPlaceCalls[path] = nil
				builtPlaceConfigurationContexts[path] = nil
				if builtRecords[path] == nil, closerAndDefaultRecords[path] == nil {
					if firstUnrecordedPath.map({ (walkIndexByPath[$0] ?? 0) < (walkIndexByPath[path] ?? 0) }) != true {
						firstUnrecordedPath = path
					}
					for depth in 1..<max(path.count, 1) {
						pathsAboveUnrecordedPlace.insert(Array(path.prefix(depth)))
					}
				}
			}
			// A closer hands the configuration of the place it closes on when its turn comes, so that its record holds what it
			// hands only until its parent's record takes it: a mock that enters a lazy cycle has thousands of closers, each
			// handed a nearest configuration per type the cycle closes on.
			if let nearest, case var .closer(record)? = closerAndDefaultRecords[path], let argument = record.passedArguments.first {
				let closedOn = MockLowering.ConfigurationParameter(name: argument.parameterName, type: argument.type)
				// Where a built place of the closed-on type and the closer's label reads its parent's field, the closer hands
				// the same expression that place hands, `nearest ?? parent.field`: the nearest is set exactly where a place
				// of its type is above, so both read what they read before, and both are one call of the type's function.
				let parentField = closerParentFieldReads[path].flatMap { read in
					parentFieldsReadByBuiltPlaces.contains(ParentFieldRead(parentConfiguration: read.parentConfiguration, fieldName: read.fieldName))
						? ValuePath.member(read.fieldName, of: read.parentConfiguration)
						: nil
				}
				let value = nearest.closedOnValue(of: closedOn, at: path, parentField: parentField) ?? argument.value
				record.passedArguments = [PassedArgument(parameterName: argument.parameterName, type: argument.type, value: value, staysOutsideSendableFunctions: argument.staysOutsideSendableFunctions)]
					+ nearestArguments(nearest, ofCallTo: closedOn, at: path)
				closerAndDefaultRecords[path] = .closer(record)
				closerParentFieldReads[path] = nil
			}
			guard let call = builtPlaceCalls[path] else { continue }
			guard !pathsNamedApart.contains(path) else {
				unrecordedReasons[path] = "namedApart"
				continue
			}
			// A member of a loop of builders whose function rebinds another member hands each closer that member's
			// configuration and its level's, as the level hands them (`MockLowering+LoopPlaces.swift`).
			var rebindingCodes = [GeneratedCode]()
			if let rebindings = loopRebindings.removeValue(forKey: path) {
				guard let configuration = loopConfigurations[path] else {
					unrecordedReasons[path] = "loopMemberUnrecorded"
					continue
				}
				var nearestArgumentsByMember = [[Int]: [PassedArgument]]()
				if let nearest {
					for rebinding in rebindings {
						if let callee = loopConfigurations[rebinding.memberPath] {
							nearestArgumentsByMember[rebinding.memberPath] = nearestArguments(nearest, ofCallTo: MockLowering.ConfigurationParameter(name: callee.own.parameterName, type: callee.own.type), at: path + [0])
						}
					}
				}
				rebindingCodes = Self.rebindingCodes(of: rebindings, at: path, configuration: configuration, among: loopConfigurations, nearestArguments: nearestArgumentsByMember)
			}
			// A meeting of a subtree met before takes that meeting's child records.
			let childCodes = subtreeSharing?.sourcePathByPath[path].flatMap { subtreeSharing?.childCodesBySourcePath[$0] }
				?? (childPathsByParent[path] ?? []).map(placeCode(at:))
			if let subtreeSharing, subtreeSharing.sourcePaths.contains(path) {
				subtreeSharing.childCodesBySourcePath[path] = childCodes
			}
			let children = call.inputs.hasFunction ? rebindingCodes + (leadingBodyPlaces[path] ?? []) + childCodes : []
			// The record made below holds its children's, so the walk's tables let go of them, and of what the walk kept to
			// record this place, as soon as they are read: the tables then hold the places still waiting for their parents,
			// never every place of the tree at once.
			if call.inputs.hasFunction {
				leadingBodyPlaces[path] = nil
				for child in childPathsByParent[path] ?? [] {
					builtRecords[child] = nil
					closerAndDefaultRecords[child] = nil
				}
			}
			// An erased place the mock can override is built from a closure that returns the erased type, and a place built in
			// a function whose property is another type than the one it builds (`fulfilledByType:`, a protocol) from an
			// override that returns the property's type: its function returns the property's type (`functionReturnType`).
			// It is decided once the record holds every alternative it tries, the one `relateConfiguration(ofBuiltPlaceAt:of:)`
			// adds beneath the left-out edge of a mocked lazy cycle included.
			let overrideCanReturnAnotherType = call.erasedToConcreteExistential || (call.inputs.hasFunction && call.property.typeDescription.asInstantiatedType != call.instantiable.concreteInstantiable)
			// A function that reads the overrides beneath it into locals keeps them where a place beneath it keeps the walk's
			// body, which reads those locals.
			let keepsOverrideLocals = pathsStartingExtraction.contains(path) && pathsAboveUnrecordedPlace.contains(path)
			let isPlanned = call.isPlannedAtPlace && !keepsOverrideLocals
			if pathsWithUnplannedLines.contains(path) {
				unrecordedReasons[path] = "unplannedLines:" + ([unplannedLineKinds[path]] + (keepsOverrideLocals ? ["overrideExtraction"] : [])).compactMap(\.self).joined(separator: "+")
			} else if keepsOverrideLocals {
				unrecordedReasons[path] = "unplannedLines:overrideExtraction"
			}
			do throws(Initializer.GenerationError) {
				let productionRecord = try call.generator.builtPlaceRecord(
					of: call.property,
					instantiable: call.instantiable,
					forwardedProperties: call.forwardedProperties,
					erasedToConcreteExistential: call.erasedToConcreteExistential,
					unavailableProperties: call.unavailableProperties,
					functionName: call.inputs.functionName,
					hasFunction: call.inputs.hasFunction,
					children: children,
					node: call.node,
					isPlannedAtPlace: isPlanned,
					readNames: call.inputs.readNames,
					alternatives: call.inputs.alternatives,
					constructionReads: constructionReadsByContext[ConstructionContext(generator: ObjectIdentifier(call.generator), unavailableProperties: call.unavailableProperties)],
					plansRebindings: true,
				)
				// A construction that reads defaults or calls a hand-written mock records it in place of production's call
				// (`MockLowering+ClosersAndDefaults.swift`).
				let record = if let configuredConstruction = call.inputs.configuredConstruction {
					productionRecord.flatMap { configuring($0, with: configuredConstruction, instantiable: call.instantiable) }
				} else {
					productionRecord
				}
				// A record whose construction passes `nil` where the walk passes a value, or the other way, is no record of
				// the walk's place, which keeps the walk's body.
				let passesWhatTheWalkPasses = if case let .built(built)? = record {
					built.arguments.allSatisfy { argument in
						argument.source == .nil ? !call.inputs.labelsPassedValue.contains(argument.argumentLabel) : !call.inputs.labelsPassedNil.contains(argument.argumentLabel)
					}
				} else {
					true
				}
				let recordOfWalksPlace = passesWhatTheWalkPasses ? record : nil
				if recordOfWalksPlace == nil, unrecordedReasons[path] == nil {
					unrecordedReasons[path] = "noRecord"
				}
				builtRecords[path] = recordOfWalksPlace
				relateConfiguration(ofBuiltPlaceAt: path, of: call.nodeConfiguration)
				if let configuration = loopConfigurations[path] {
					handLevelConfiguration(of: configuration, toBuiltPlaceAt: path, among: loopConfigurations)
				}
				if overrideCanReturnAnotherType, case var .built(built)? = builtRecords[path], !built.alternatives.isEmpty {
					built.functionReturnType = call.property.typeDescription.asInstantiatedTypeSpelledAsDeclared
					builtRecords[path] = .built(built)
				}
				if let nearest, let own = nearest.ownParameterByPath[path], case var .built(built)? = builtRecords[path] {
					// A place that reads its parent's field of it, or a configuration of its own, reads the nearest place of
					// its type's configuration first, as a closer of its type hands it, where its parent's function takes
					// that nearest one: it is set exactly where a place of its type is above, which no built place has.
					if let first = built.passedArguments.first, first.parameterName == own.name,
					   let nearestRead = nearest.nearestRead(of: own, calledFrom: Array(path.dropLast()))
					{
						let value = Self.nearestFirst(nearestRead, orElse: first.value, own: own)
						var handed = PassedArgument(parameterName: first.parameterName, type: first.type, value: value, staysOutsideSendableFunctions: first.staysOutsideSendableFunctions)
						handed.bindsBeforeCall = first.bindsBeforeCall
						built.passedArguments[0] = handed
					}
					built.passedArguments += nearestArguments(nearest, ofCallTo: own, at: path)
					builtRecords[path] = .built(built)
				}
				if !call.inputs.hasFunction {
					readPassedConfigurationInPlace(ofBuiltPlaceAt: path)
				}
				// A place bound as `nil` where its entry says so reads the entry where it is bound, before anything of it.
				if let nilAlternative = nilAlternatives.removeValue(forKey: path), case var .built(built)? = builtRecords[path] {
					built.nilAlternative = nilAlternative
					builtRecords[path] = .built(built)
				}
				sharingNode(ofBuiltPlaceAt: path, nodesByKey: &sharedRecordsByKey)
			} catch {
				// The error is named by its case alone (`unexpectedArgument`), and by whether the place calls its type's hand-written
				// mock or reads its configuration's defaults, whose arguments production's initializer need not take: the tests and
				// the graph fuzzer judge the name (`typeKeyLayoutObserver`).
				let configured = call.inputs.configuredConstruction == nil ? "" : ":configuredConstruction"
				unrecordedReasons[path] = "threw:" + String(describing: error).prefix { $0 != "(" } + configured
			}
		}
		// The calls hold each place's tree node and inputs, which the layout reads no more.
		builtPlaceCalls = [:]
		builtPlaceInputs = [:]
	}

	/// Drops what the walk kept to record and lay out its places once the root's lines are written, so that the rest of the
	/// mock's assembly does not hold it beside the body.
	mutating func dropRecords() {
		closerAndDefaultRecords = [:]
		builtPlaceInputs = [:]
		builtRecords = [:]
		placePathsInWalkOrder = []
		builtPlaceCalls = [:]
		pathsWithUnplannedLines = []
		unplannedLineKinds = [:]
		pathsStartingExtraction = []
		nilAlternatives = [:]
		leadingBodyPlaces = [:]
		loopRebindings = [:]
		unrecordedReasons = [:]
		closedOnPlacesByLabel = [:]
		builtPlaceConfigurationContexts = [:]
		closerParentFieldReads = [:]
		publicMockCallPlanNodes = [:]
		subtreeSharing?.releaseTables()
	}

	/// What a built place hands its configuration parameter where its parent's function takes the nearest configuration of
	/// its type, `nearestRead`: that, else what it hands now. `value` is what `MockLowering.passedArguments(ofBuiltPlaceTaking:…)`
	/// hands, one of four forms: its parent's field of it, a configuration built afresh, a read of its own type's parameter,
	/// or `nil`.
	static func nearestFirst(_ nearestRead: ValuePath, orElse value: ValuePath, own: MockLowering.ConfigurationParameter) -> ValuePath {
		switch value {
		case .read:
			// A read of the nearest place of its type above, which the function it is called in was handed, or `nil`.
			// A configuration struct is taken non-optional, and the nearest is set wherever a read of it resolved.
			own.readsConfigurationStruct ? .spliced([.value(nearestRead), .text(" ?? "), .value(.emptyInitialization(own.type))]) : nearestRead
		case .emptyInitialization, .memberRead, .rootDeclaration, .passedArgument, .optionalMemberRead, .call, .spliced:
			.spliced([.value(nearestRead), .text(" ?? "), .value(value)])
		}
	}

	/// Puts the configuration a built place with no function of its own would be handed into the reads of its alternatives:
	/// such a place is built in its parent's body, where no parameter takes what `relateConfiguration(ofBuiltPlaceAt:of:)`
	/// passes it, so it reads that value where it is built.
	mutating func readPassedConfigurationInPlace(ofBuiltPlaceAt path: [Int]) {
		guard case var .built(record) = builtRecords[path], let handed = record.passedArguments.first else { return }
		// A place with no function is handed one argument, its own configuration parameter
		// (`MockLowering.relativeConfiguration(of:…)`), which each alternative it tries reads. Such a place has no default
		// field, so no value its construction passes reads the parameter, but for a parameter of its type's hand-written mock
		// that only a clause the build leaves out declares a dependency for, which the walk's text reads as a member of the
		// parameter (`defaultArgumentReads(of:…)`), in a mock that build never compiles.
		func readInPlace(_ value: ValuePath) -> ValuePath {
			if case let .memberRead(member, of: base) = value {
				.member(member, of: readInPlace(base.value))
			} else {
				handed.value
			}
		}
		record.alternatives = record.alternatives.map { alternative in
			ConstructionAlternative(closure: readInPlace(alternative.closure), bindingName: alternative.bindingName, requiresAbsent: alternative.requiresAbsent, use: alternative.use, resultWrapper: alternative.resultWrapper)
		}
		record.argumentValues = record.argumentValues.mapValues(readInPlace)
		record.passedArguments = []
		builtRecords[path] = .built(record)
	}

	/// The code of the place at `path` as the type key reads it: its record, or text, which keeps the root's walk body.
	func placeCode(at path: [Int]) -> GeneratedCode {
		let record: PlaceRecord? = if let built = builtRecords[path] {
			built
		} else if case let .closer(closer) = closerAndDefaultRecords[path] {
			.closer(closer)
		} else if case let .alias(alias) = closerAndDefaultRecords[path] {
			.alias(alias)
		} else {
			nil
		}
		guard let record else { return .text("") }
		return .place(PlacePlan(code: .empty, record: record))
	}

	/// The root's statements in the type key's layout, each line indented as the root's are, or `nil` where the root keeps
	/// the walk's: a place records nothing, a read names a value no record or root declaration binds, or the type key
	/// cannot lay the body out.
	func typeKeyRootLines(declaredAtRoot rootDeclarations: [Property]) -> (lines: [String]?, fallback: String) {
		var rootBody = [GeneratedCode]()
		// The values `mock()` declares before the tree, as renames the type key copies as empty text, which it drops below.
		for property in rootDeclarations {
			rootBody.append(.place(PlacePlan(code: .empty, record: .alias(AliasPlaceRecord(property: property, fulfillingProperty: nil, text: "")))))
		}
		for path in placePathsInWalkOrder where path.count == 1 {
			rootBody.append(placeCode(at: path))
		}
		if let path = firstUnrecordedPath {
			return (nil, "unrecorded:\(unrecordedReasons[path] ?? "closerOrOther")")
		}
		if let label = Self.unresolvedRead(in: rootBody, declaredAtRoot: Set(rootDeclarations.map(\.label))) {
			return (nil, "readUnresolved:\(label)")
		}
		guard let statements = TypeKeyBody.statements(ofRootBody: rootBody, laysOutEveryLoop: true) else { return (nil, "engineRefused") }
		var lines = [String]()
		for statement in statements {
			let spelled = statement.spelled()
			guard !spelled.allSatisfy(\.isWhitespace) else { continue }
			// A root's body is its largest text, so its lines are found over bytes (`generator-design.md`).
			lines.append(contentsOf: GeneratedCodeText.lines(of: spelled))
		}
		return (lines, "laidOut")
	}

	/// The label of the first read the places of `rootBody` make, other than of `nil`, that no declaration visible where it
	/// is made binds (a statement before it in its body or one enclosing it, a function's parameter, or a root declaration):
	/// a value the records do not see, such as one `mock()` binds under a name of its own, keeps the walk's body, since the
	/// type key would read it as `nil`.
	///
	/// A subtree the walk met on several paths is one plan node, which every meeting's record holds, as the type key reads
	/// it (`TypeKeyBody`'s `domain(of:)`), so each function's reads are found once per node (`unresolvedLabels(ofFunctionOf:)`)
	/// and the check grows with the plan's nodes, never with its paths.
	static func unresolvedRead(in rootBody: [GeneratedCode], declaredAtRoot rootLabels: Set<String>) -> String? {
		var reads = UnresolvedReads()
		defer { MockLowering.unresolvedReadObserver?(reads.readPlaces) }
		return reads.unresolvedLabels(of: rootBody, declaredAbove: rootLabels).labels.first
	}

	/// The reads of a laid-out body that no declaration inside it binds, found once per function's plan node.
	private struct UnresolvedReads {
		/// What each function's body and construction read that the function does not bind, in the order the walk meets them.
		var labelsByFunction = [PlanNode: [String]]()
		/// The places read, which a test reads through `unresolvedReadObserver`.
		var readPlaces = 0

		/// The labels the places of `body` read, other than of `nil`, that neither `declaredAbove` nor a place before the
		/// read in `body` binds, each once, in the order the walk meets them; and the labels `body` binds. Every place of a
		/// body read here holds a record: a root with a place that records nothing keeps the walk's body before its reads
		/// are checked (`firstUnrecordedPath`, in `typeKeyRootLines(declaredAtRoot:)`), and a place's code is text only
		/// where it records nothing (`placeCode(at:)`).
		mutating func unresolvedLabels(of body: [GeneratedCode], declaredAbove: Set<String>) -> (labels: [String], bound: Set<String>) {
			var labels = OrderedLabels()
			var visible = declaredAbove
			for record in body.compactMap(TypeKeyLayout.record(of:)) {
				readPlaces += 1
				switch record {
				case let .built(built):
					labels.append(contentsOf: built.callSiteReads, unless: visible)
					if built.hasFunction {
						labels.append(contentsOf: unresolvedLabels(ofFunctionOf: built), unless: visible)
					} else {
						labels.append(contentsOf: built.constructionReads, unless: visible)
					}
					visible.insert(built.property.label)
				case let .closer(closer):
					// A call reads what is declared where it is made, a closer's as a built place's.
					labels.append(contentsOf: closer.callSiteReads, unless: visible)
					visible.insert(closer.property.label)
				case let .alias(alias):
					// A rename of a name `mock()` binds apart, such as a sibling its root names apart, reads no declaration the
					// records name.
					if let fulfillingProperty = alias.fulfillingProperty, !visible.contains(fulfillingProperty.label) {
						labels.append(fulfillingProperty.label)
					}
					visible.insert(alias.property.label)
					visible.formUnion(alias.otherBindings.map(\.label))
				}
			}
			return (labels.labels, visible)
		}

		/// What `built`'s function reads that its parameters and its body do not bind: its body's places' reads, then its
		/// construction's, which reads what its body binds. The functions beneath it are found first, each once, with a stack,
		/// since a plan can be as deep as the module has types.
		mutating func unresolvedLabels(ofFunctionOf built: BuiltPlaceRecord) -> [String] {
			var stack = [built]
			while let current = stack.last {
				guard labelsByFunction[current.node] == nil else {
					stack.removeLast()
					continue
				}
				let pending = current.children.compactMap { code -> BuiltPlaceRecord? in
					guard case let .built(child)? = TypeKeyLayout.record(of: code), child.hasFunction, labelsByFunction[child.node] == nil else { return nil }
					return child
				}
				guard pending.isEmpty else {
					stack.append(contentsOf: pending)
					continue
				}
				stack.removeLast()
				let parameters = Set(current.parameterProperties.map(\.label)).union(current.cycleParameters.map(\.label))
				let body = unresolvedLabels(of: current.children, declaredAbove: parameters)
				var labels = OrderedLabels(body.labels)
				// A function's construction reads what its body binds.
				labels.append(contentsOf: current.constructionReads, unless: body.bound)
				labelsByFunction[current.node] = labels.labels
			}
			return labelsByFunction[built.node] ?? []
		}
	}

	/// Labels in the order they are first added, each once.
	private struct OrderedLabels {
		private(set) var labels: [String]
		private var added: Set<String>

		init(_ labels: [String] = []) {
			self.labels = labels
			added = Set(labels)
		}

		mutating func append(_ label: String) {
			if added.insert(label).inserted {
				labels.append(label)
			}
		}

		mutating func append(contentsOf labels: [String], unless bound: Set<String>) {
			for label in labels where !bound.contains(label) {
				append(label)
			}
		}

		mutating func append(contentsOf reads: [PlaceRead], unless bound: Set<String>) {
			for read in reads where read.source != .nil && !bound.contains(read.label) {
				append(read.label)
			}
		}
	}
}

extension MockLowering.RootSignature {
	/// The values `mock()` binds under names its tree reads before the tree, each as its places read it: its parameters taken
	/// as their properties' types, and its overrides of what the tree receives only if available.
	var typeKeyRootDeclarations: [Property] {
		var declarations = [Property]()
		// A parameter `mock()` takes as another type than its property's, a builder or an autoclosure, is no declaration
		// the records read.
		// safedi-source-rule: allow stringScan — once per parameter of one `mock()`, over that parameter’s type as spelled.
		for parameter in forwardedParameters + flatReceivedParameters + uncoveredParameters where parameter.typeSource.map({ $0.replacingOccurrences(of: "@escaping ", with: "") == parameter.property.typeDescription.asSource }) ?? true {
			declarations.append(Property(label: parameter.name, typeDescription: parameter.property.typeDescription))
		}
		for override in onlyIfAvailableOverrides {
			declarations.append(Property(label: override.name, typeDescription: override.typeDescription))
		}
		// The local `mock()` reads each `@Sendable` autoclosure parameter into, which the bindings of its value read.
		for (property, parameter) in sendableAutoclosureBindings.sorted(by: { $0.value.localName < $1.value.localName }) {
			declarations.append(MockLowering.sendableAutoclosureLocalProperty(of: parameter, builds: property))
		}
		return declarations
	}
}

/// A field of a parent's configuration a place reads, by the parent's configuration read and the field's name.
struct ParentFieldRead: Hashable {
	let parentConfiguration: ValuePath
	let fieldName: String
}
