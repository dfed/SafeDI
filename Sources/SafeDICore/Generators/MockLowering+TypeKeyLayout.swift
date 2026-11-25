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
		// Walk order starts a place before the places beneath it, so the reverse finishes them first.
		for path in placePathsInWalkOrder.reversed() {
			guard let call = builtPlaceCalls[path] else { continue }
			let children = call.inputs.hasFunction ? (childPathsByParent[path] ?? []).map(placeCode(at:)) : []
			// An erased place the mock can override is built from a closure that returns the erased type, where the type
			// key's function returns the concrete one: it keeps the walk's body.
			// So is a place built in a function whose property is another type than the one it builds (`fulfilledByType:`,
			// a protocol), whose override returns the property's type.
			let overrideReturnsAnotherType = !call.inputs.alternatives.isEmpty && (call.erasedToConcreteExistential || (call.inputs.hasFunction && call.property.typeDescription.asInstantiatedType != call.instantiable.concreteInstantiable))
			let isPlanned = call.isPlannedAtPlace && !overrideReturnsAnotherType
			if overrideReturnsAnotherType {
				unrecordedReasons[path] = "overrideReturnsAnotherType"
			} else if pathsWithUnplannedLines.contains(path) {
				unrecordedReasons[path] = "unplannedLines"
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
				// A public mock's configured place calls its type's construction function (`MockLowering+PublicRecords.swift`).
				builtRecords[path] = record.flatMap { publicRecord(of: $0, inputs: call.inputs) }
				relateConfiguration(ofBuiltPlaceAt: path, of: call.treeNode)
				if !call.inputs.hasFunction {
					readPassedConfigurationInPlace(ofBuiltPlaceAt: path)
				}
			} catch {
				unrecordedReasons[path] = "threw"
				unrecordedPlaceErrors[path] = error
			}
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
		} else {
			nil
		}
		guard let record else { return .text("") }
		return .place(PlacePlan(code: .empty, record: record))
	}

	/// The root's statements in the type key's layout, each line indented as the root's are, or `nil` where the root keeps
	/// the walk's: a place records nothing, a read names a value no record or root declaration binds, or the type key cannot
	/// lay the body out.
	func typeKeyRootLines(declaredAtRoot rootDeclarations: [Property]) -> (lines: [String]?, fallback: String) {
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
		return declarations
	}
}
