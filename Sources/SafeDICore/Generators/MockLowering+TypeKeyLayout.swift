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

#if canImport(Glibc)
	import Glibc
#elseif canImport(Darwin)
	import Darwin
#endif
import Foundation

/// The type key's layout of an internal mock's body (`TypeKeyBody`), behind a switch tests turn on: the walk's places, each
/// with the record production's record function makes of it, laid out as production's are. A root any place of which has
/// no record, or reads a value the records cannot name, keeps the walk's body.
extension MockLowering {
	/// Whether internal mocks' bodies are laid out by the type key: set by a test, or by `SAFEDI_MOCK_TYPE_KEY=1` for a run
	/// of the graph fuzzer's corpora.
	@TaskLocal static var laysOutWithTypeKey = ProcessInfo.processInfo.environment["SAFEDI_MOCK_TYPE_KEY"] == "1"

	/// SPIKE: appends whether the type key laid `instantiable`'s mock out, or why not, to `SAFEDI_MOCK_TYPE_KEY_LOG`.
	static func logTypeKeyLayout(of instantiable: Instantiable, outcome: String) {
		guard let logPath = ProcessInfo.processInfo.environment["SAFEDI_MOCK_TYPE_KEY_LOG"], let file = fopen(logPath, "a") else { return }
		fputs("TYPEKEY\t\(instantiable.concreteInstantiable.asSource)\t\(outcome)\n", file)
		fclose(file)
	}

	/// What the walk hands production's record function at a built place.
	struct BuiltPlaceCall {
		let generator: ScopeGenerator
		let property: Property
		let instantiable: Instantiable
		let forwardedProperties: Set<Property>
		let erasedToConcreteExistential: Bool
		let unavailableProperties: Set<Property>
		let inputs: BuiltPlaceInputs
		let node: PlanNode
		/// The node the walk lowered the place to, whose configuration the record reads (`relateConfiguration(ofBuiltPlaceAt:…)`).
		let treeNode: TreeNode
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
		let nearest: MockLowering.NearestConfigurations? = buildsPublicMock ? nil : nearestConfigurations(childPathsByParent: childPathsByParent)
		var parentFieldsReadByBuiltPlaces = Set<ParentFieldRead>()
		for context in builtPlaceConfigurationContexts.values {
			if let parentConfiguration = context.parentConfiguration {
				parentFieldsReadByBuiltPlaces.insert(ParentFieldRead(parentConfiguration: parentConfiguration, fieldName: context.fieldName))
			}
		}
		if let nearest {
			for path in placePathsInWalkOrder {
				guard case var .closer(record)? = closerAndDefaultRecords[path], let argument = record.passedArguments.first else { continue }
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
					+ nearest.nearestArguments(ofCallTo: closedOn, at: path)
				closerAndDefaultRecords[path] = .closer(record)
			}
		}
		// Walk order starts a place before the places beneath it, so the reverse finishes them first.
		for path in placePathsInWalkOrder.reversed() {
			defer {
				if builtRecords[path] == nil, closerAndDefaultRecords[path] == nil {
					for depth in 1..<max(path.count, 1) {
						pathsAboveUnrecordedPlace.insert(Array(path.prefix(depth)))
					}
				}
			}
			guard let call = builtPlaceCalls[path] else { continue }
			let children = call.inputs.hasFunction ? (leadingBodyPlaces[path] ?? []) + (childPathsByParent[path] ?? []).map(placeCode(at:)) : []
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
			} else if !call.isPlannedAtPlace {
				unrecordedReasons[path] = "notPlannedAtPlace"
			}
			do {
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
				)
				// A construction that reads defaults or calls a hand-written mock records it in place of production's call
				// (`MockLowering+ClosersAndDefaults.swift`).
				let record = if let configuredConstruction = call.inputs.configuredConstruction {
					productionRecord.flatMap { configuring($0, with: configuredConstruction, instantiable: call.instantiable) }
				} else {
					productionRecord
				}
				// A record whose construction passes `nil` where the walk passes a value, or the other way, as for an
				// `@Instantiated` dependency the mock takes as a parameter where production builds nothing, keeps the walk's
				// body.
				if case let .built(built)? = record, built.arguments.contains(where: { argument in
					argument.source == .nil ? call.inputs.labelsPassedValue.contains(argument.argumentLabel) : call.inputs.labelsPassedNil.contains(argument.argumentLabel)
				}) {
					unrecordedReasons[path] = "nilDisagrees"
					continue
				}
				if record == nil, unrecordedReasons[path] == nil {
					unrecordedReasons[path] = "noRecord"
				}
				builtRecords[path] = record
				relateConfiguration(ofBuiltPlaceAt: path, of: call.treeNode)
				if overrideCanReturnAnotherType, case var .built(built)? = builtRecords[path], !built.alternatives.isEmpty {
					built.functionReturnType = call.property.typeDescription.asInstantiatedTypeSpelledAsDeclared
					builtRecords[path] = .built(built)
				}
				if let nearest, let own = nearest.ownParameterByPath[path], case var .built(built)? = builtRecords[path] {
					// A place that reads its parent's field of it, or a configuration of its own, reads the nearest place of
					// its type's configuration first, as a closer of its type hands it, where its parent's function takes
					// that nearest one: it is set exactly where a place of its type is above, which no built place has.
					if let first = built.passedArguments.first, first.parameterName == own.name,
					   let nearestRead = nearest.nearestRead(of: own, calledFrom: Array(path.dropLast())),
					   let value = Self.nearestFirst(nearestRead, orElse: first.value, context: builtPlaceConfigurationContexts[path])
					{
						var handed = PassedArgument(parameterName: first.parameterName, type: first.type, value: value, staysOutsideSendableFunctions: first.staysOutsideSendableFunctions)
						handed.bindsBeforeCall = first.bindsBeforeCall
						built.passedArguments[0] = handed
					}
					built.passedArguments += nearest.nearestArguments(ofCallTo: own, at: path)
					builtRecords[path] = .built(built)
				}
				if !call.inputs.hasFunction {
					readPassedConfigurationInPlace(ofBuiltPlaceAt: path)
				}
			} catch {
				unrecordedReasons[path] = "threw"
				unrecordedPlaceErrors[path] = error
			}
		}
	}

	/// What a built place hands its configuration parameter where its parent's function takes the nearest configuration of
	/// its type, `nearestRead`: that, else what it hands now, a field of its parent's or a configuration built afresh, or
	/// that alone where it hands `nil`; `nil` where it hands anything else, which it keeps.
	static func nearestFirst(_ nearestRead: ValuePath, orElse value: ValuePath, context: MockLowering.BuiltPlaceConfigurationContext?) -> ValuePath? {
		switch value {
		case .emptyInitialization:
			return .spliced([.value(nearestRead), .text(" ?? "), .value(value)])
		case .member:
			guard let context, let parentConfiguration = context.parentConfiguration, value == .member(context.fieldName, of: parentConfiguration) else { return nil }
			return .spliced([.value(nearestRead), .text(" ?? "), .value(value)])
		case let .read(read):
			guard case .nil = read.source else { return nil }
			return nearestRead
		case .rootDeclaration, .passedArgument, .optionalMember, .call, .spliced:
			return nil
		}
	}

	/// The code of the place at `path` as the type key reads it: its record, or text, which keeps the root's walk body.
	/// Puts the configuration a built place with no function of its own would be handed into the reads of its alternatives:
	/// such a place is built in its parent's body, where no parameter takes what `relateConfiguration(ofBuiltPlaceAt:of:)`
	/// passes it, so it reads that value where it is built.
	mutating func readPassedConfigurationInPlace(ofBuiltPlaceAt path: [Int]) {
		guard case var .built(record) = builtRecords[path], !record.passedArguments.isEmpty else { return }
		let valueByName = Dictionary(record.passedArguments.map { ($0.parameterName, $0.value) }, uniquingKeysWith: { first, _ in first })
		func substituting(_ value: ValuePath) -> ValuePath {
			switch value {
			case let .passedArgument(name):
				valueByName[name] ?? value
			case let .member(member, of: base):
				.member(member, of: substituting(base))
			case let .optionalMember(member, of: base):
				.optionalMember(member, of: substituting(base))
			case let .call(member, of: base, arguments: arguments, argumentsWrapper: wrapper):
				.call(member, of: substituting(base), arguments: arguments, argumentsWrapper: wrapper)
			case let .spliced(segments):
				.spliced(segments.map { segment in
					switch segment {
					case let .value(value):
						.value(substituting(value))
					case .text, .declaredFunction:
						segment
					}
				})
			case .rootDeclaration, .read, .emptyInitialization:
				value
			}
		}
		record.alternatives = record.alternatives.map { alternative in
			ConstructionAlternative(closure: substituting(alternative.closure), bindingName: alternative.bindingName, requiresAbsent: alternative.requiresAbsent.map(substituting), use: alternative.use, resultWrapper: alternative.resultWrapper)
		}
		record.argumentValues = record.argumentValues.mapValues(substituting)
		record.constructionValue = record.constructionValue.map { ConstructionValue(value: substituting($0.value), resultWrapper: $0.resultWrapper) }
		record.passedArguments = []
		builtRecords[path] = .built(record)
	}

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
	/// the walk's: the walk entered a cycle with a cycle edge, a place records nothing, a read names a value no record or
	/// root declaration binds, or the type key cannot lay the body out.
	func typeKeyRootLines(declaredAtRoot rootDeclarations: [Property]) -> (lines: [String]?, fallback: String) {
		guard ProcessInfo.processInfo.environment["SCRATCH_NO_GUARD"] == "1" || !entersCycleWithEdge else { return (nil, "entersCycleWithEdge") }
		var rootBody = [GeneratedCode]()
		// The values `mock()` declares before the tree, as renames the type key copies as empty text, which it drops below.
		for property in rootDeclarations {
			rootBody.append(.place(PlacePlan(code: .empty, record: .alias(AliasPlaceRecord(property: property, fulfillingProperty: nil, text: "")))))
		}
		for path in placePathsInWalkOrder where path.count == 1 {
			rootBody.append(placeCode(at: path))
		}
		if let path = placePathsInWalkOrder.first(where: { builtRecords[$0] == nil && closerAndDefaultRecords[$0] == nil }) {
			return (nil, "unrecorded:\(unrecordedReasons[path] ?? "closerOrOther")")
		}
		if let label = Self.unresolvedRead(in: rootBody, declaredAtRoot: Set(rootDeclarations.map(\.label))) {
			return (nil, "readUnresolved:\(label)")
		}
		guard let statements = TypeKeyBody.statements(ofRootBody: rootBody) else { return (nil, "engineRefused") }
		var lines = [String]()
		for statement in statements {
			let spelled = statement.spelled()
			guard !spelled.allSatisfy(\.isWhitespace) else { continue }
			lines.append(contentsOf: spelled.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
		}
		return (lines, "laidOut")
	}

	/// The label of the first read the places of `rootBody` make, other than of `nil`, that no declaration visible where it
	/// is made binds (a statement before it in its body or one enclosing it, a function's parameter, or a root declaration):
	/// a value the records do not see, such as one `mock()` binds under a name of its own, keeps the walk's body, since the
	/// type key would read it as `nil`.
	static func unresolvedRead(in rootBody: [GeneratedCode], declaredAtRoot rootLabels: Set<String>) -> String? {
		// Each frame is a body: the labels visible in it so far, the frames around it holding theirs.
		var frames: [(children: [GeneratedCode], next: Int, visible: Set<String>, functionReads: [PlaceRead])] = [(rootBody, 0, rootLabels, [])]
		func resolves(_ reads: [PlaceRead], in visible: Set<String>) -> String? {
			reads.first { $0.source != .nil && !visible.contains($0.label) }.map(\.label)
		}
		while let frame = frames.last {
			guard frame.next < frame.children.count else {
				// A function's construction reads what its body binds.
				if let label = resolves(frame.functionReads, in: frame.visible) {
					return label
				}
				frames.removeLast()
				continue
			}
			frames[frames.count - 1].next += 1
			guard let record = TypeKeyLayout.record(of: frame.children[frame.next]) else { return "" }
			let visible = frame.visible
			switch record {
			case let .built(built):
				if let label = resolves(built.callSiteReads, in: visible) {
					return label
				}
				if built.hasFunction {
					var inner = visible
					inner.formUnion(built.parameterProperties.map(\.label))
					inner.formUnion(built.cycleParameters.map(\.label))
					frames[frames.count - 1].visible.insert(built.property.label)
					frames.append((built.children, 0, inner, built.constructionReads))
				} else {
					if let label = resolves(built.constructionReads, in: visible) {
						return label
					}
					frames[frames.count - 1].visible.insert(built.property.label)
				}
			case let .closer(closer):
				if let label = resolves(closer.callSiteReads, in: visible) {
					return label
				}
				frames[frames.count - 1].visible.insert(closer.property.label)
			case let .alias(alias):
				// A rename of a name `mock()` binds apart, such as a sibling its root names apart, reads no declaration the
				// records name.
				if let fulfillingProperty = alias.fulfillingProperty, !visible.contains(fulfillingProperty.label) {
					return fulfillingProperty.label
				}
				frames[frames.count - 1].visible.insert(alias.property.label)
			}
		}
		return nil
	}
}

extension MockLowering.RootSignature {
	/// The values `mock()` binds under names its tree reads before the tree, each as its places read it: its parameters taken
	/// as their properties' types, and its overrides of what the tree receives only if available.
	var typeKeyRootDeclarations: [Property] {
		var declarations = [Property]()
		// A parameter `mock()` takes as another type than its property's, a builder or an autoclosure, is no declaration
		// the records read.
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
