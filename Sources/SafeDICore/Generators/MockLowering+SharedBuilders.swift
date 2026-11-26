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

/// Builders shared by every mock of a module that builds a type: a place of a type whose internal mock the module generates
/// is built by a static function in the type's extension, `__safeDI_build_<hash>`, which each mock that builds the place
/// alike calls, rather than by a builder function of its own in each mock. Each function is the type key's layout of the
/// place on its own (`TypeKeyBody.staticFunction(building:parameters:attributes:)`), named by the hash of its declaration
/// (`ReservedName.sharedBuilder(named:)`), so mocks whose places build alike declare one function between them, which the
/// mocked type's file declares beside its mock.
///
/// A place is built so where the walk found it can be (`Walk.sharedBuilderAttributes(of:instantiable:isLoopMember:)`), its
/// function reads only what is visible where the place is built and what it is handed, and its attributes are the
/// caller's or none: the mock's, or the attributes of the shared builder the place is built in. Anything else keeps the
/// place in the mock's body, as before.
extension MockLowering {
	/// A static function in the extension of the type it builds, which every mock of the module that builds the type alike
	/// calls.
	struct SharedBuilder: Sendable, Equatable {
		/// The function's name, `__safeDI_build_<hash>`.
		let name: String
		/// The type whose extension declares the function.
		let builtType: TypeDescription
		/// The function's declaration, indented as a member of an extension, with no line ending it.
		let declaration: String
	}

	/// The lifting of a root's places into shared builders. It holds the builders it made, and, for the root it lifts, the
	/// function each place's plan node lifts to and the plan nodes of the places it rebuilt around lifted ones; it lives
	/// while the root is laid out.
	struct SharedBuilderLifting {
		init(rootAttributes: String) {
			self.rootAttributes = rootAttributes
		}

		/// The builders made, by the type whose extension declares them, then by name.
		private(set) var buildersByTypeAndName = [SharedBuilderKey: SharedBuilder]()

		/// `rootBody`, whose first `declarationCount` statements are the root's declarations, with each place it can build
		/// through a shared builder replaced by a call of it, or `nil` where no place is.
		mutating func lifting(_ rootBody: [GeneratedCode], declarationCount: Int) async -> [GeneratedCode]? {
			var visible = [String: TypeDescription]()
			for code in rootBody.prefix(declarationCount) {
				guard case let .alias(alias)? = TypeKeyLayout.record(of: code) else { return nil }
				visible[alias.property.label] = alias.property.typeDescription
			}
			let lifted = await lifting(rootBody, from: declarationCount, visible: visible, attributes: rootAttributes)
			return lifted.changed ? lifted.codes : nil
		}

		// MARK: Private

		/// The function a lifted place calls.
		private struct Lifted {
			let name: String
			let builtType: TypeDescription
		}

		/// What a place lifts alike for: its plan node, the parameters its function takes, and its attributes.
		private struct LiftKey: Hashable {
			let node: ObjectIdentifier
			let parameters: [Property]
			let typesSpelled: [String]
			let attributes: String
		}

		/// What a place rebuilt around lifted places is alike for: its plan node and what each of its children became.
		private struct RebuildKey: Hashable {
			let node: ObjectIdentifier
			let children: [ChildIdentity]
		}

		private enum ChildIdentity: Hashable {
			case node(ObjectIdentifier)
			case text(String)
			case other
		}

		private let rootAttributes: String
		/// The function each place lifted to, or `nil` where it stays in place, by what it lifts alike for.
		private var liftedByKey = [LiftKey: Lifted?]()
		/// The labels each place's plan node reads from outside its function (`labelsReadFromOutside(of:)`), which every
		/// place of the node reads alike.
		private var labelsReadFromOutsideByNode = [ObjectIdentifier: [String]?]()
		/// What each place's plan node and the functions in it are handed and read (`readsOnlyWhatItIsHanded(_:)`).
		private var handedReadsByNode = [ObjectIdentifier: HandedReads?]()
		/// The plan node of each place rebuilt around lifted places, which every alike place takes.
		private var rebuiltNodesByKey = [RebuildKey: PlanNode]()
		/// Each place rebuilt around lifted places, or `nil` where none is, by what it rebuilds alike for, so a node
		/// reached along many paths is rebuilt once per context rather than once per path.
		private var rebuiltByKey = [RebuildContextKey: BuiltPlaceRecord?]()

		/// What a place's rebuilding is alike for: its plan node, its attributes, and how each label it reads from outside
		/// its function is declared where it is built (`nil` where not), or, where it reads what no record lists, every
		/// declaration visible there.
		private struct RebuildContextKey: Hashable {
			let node: ObjectIdentifier
			let attributes: String
			let declarations: [VisibleDeclaration]
		}

		private struct VisibleDeclaration: Hashable {
			let label: String
			let typeSpelled: String?
		}

		/// What a function and the functions in it are handed (`handedNames`), what the values they read take as handed
		/// (`readNames`), and whether a value reads a root's declaration.
		private struct HandedReads {
			var handedNames = Set<String>()
			var readNames = Set<String>()
			var readsRootDeclaration = false

			mutating func read(_ path: ValuePath) {
				readsRootDeclaration = readsRootDeclaration || path.readsRootDeclaration
				readNames.formUnion(path.passedArgumentNames)
			}

			mutating func formUnion(_ other: HandedReads) {
				handedNames.formUnion(other.handedNames)
				readNames.formUnion(other.readNames)
				readsRootDeclaration = readsRootDeclaration || other.readsRootDeclaration
			}
		}

		/// `body` from `start` on, where `visible` declares what is visible before `start`, with each place it can build
		/// through a shared builder replaced by a call of it, inside functions `attributes` isolates.
		/// Each place's function body is lifted by a call nested in this one, `async` so that the task, not the thread's
		/// stack, holds a frame per level of a deep tree.
		private mutating func lifting(_ body: [GeneratedCode], from start: Int, visible: [String: TypeDescription], attributes: String) async -> (codes: [GeneratedCode], changed: Bool) {
			var visible = visible
			var codes = body
			var changed = false
			for index in body.indices where index >= start {
				guard let record = TypeKeyLayout.record(of: body[index]) else { continue }
				switch record {
				case let .built(built):
					if let call = await call(lifting: built, visible: visible, attributes: attributes) {
						codes[index] = call
						changed = true
					} else if let rebuilt = await rebuilding(built, visible: visible, attributes: attributes) {
						codes[index] = .place(PlacePlan(code: .empty, record: .built(rebuilt)))
						changed = true
					}
					visible[built.property.label] = built.property.typeDescription
				case let .closer(closer):
					visible[closer.property.label] = closer.property.typeDescription
				case let .alias(alias):
					visible[alias.property.label] = alias.property.typeDescription
					for binding in alias.otherBindings {
						visible[binding.label] = binding.typeDescription
					}
				}
			}
			return (codes, changed)
		}

		/// `built`, whose function's body holds places lifted, or `nil` where none is.
		private mutating func rebuilding(_ built: BuiltPlaceRecord, visible: [String: TypeDescription], attributes: String) async -> BuiltPlaceRecord? {
			guard built.hasFunction, built.cycleParameters.isEmpty else { return nil }
			let contextKey = rebuildContextKey(of: built, visible: visible, attributes: attributes)
			if let rebuilt = rebuiltByKey[contextKey] {
				return rebuilt
			}
			let rebuilt = await rebuildingAfresh(built, visible: visible, attributes: attributes)
			rebuiltByKey[contextKey] = .some(rebuilt)
			return rebuilt
		}

		/// The key of `built`'s rebuilding where `visible` declares what is visible: the labels its function reads from
		/// outside it are all of `visible` it can read, since what it binds inside it declares there itself.
		private mutating func rebuildContextKey(of built: BuiltPlaceRecord, visible: [String: TypeDescription], attributes: String) -> RebuildContextKey {
			let declarations: [VisibleDeclaration] = if let labels = labelsReadFromOutside(of: built) {
				labels.map { VisibleDeclaration(label: $0, typeSpelled: visible[$0]?.asSource) }
			} else {
				visible.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { VisibleDeclaration(label: $0, typeSpelled: visible[$0]?.asSource) }
			}
			return RebuildContextKey(node: ObjectIdentifier(built.node), attributes: attributes, declarations: declarations)
		}

		private mutating func rebuildingAfresh(_ built: BuiltPlaceRecord, visible: [String: TypeDescription], attributes: String) async -> BuiltPlaceRecord? {
			var inner = visible
			for property in built.parameterProperties {
				inner[property.label] = property.typeDescription
			}
			let children = await lifting(built.children, from: 0, visible: inner, attributes: attributes)
			guard children.changed else { return nil }
			let key = RebuildKey(node: ObjectIdentifier(built.node), children: children.codes.map { code in
				switch TypeKeyLayout.record(of: code) {
				case let .built(child)?:
					.node(ObjectIdentifier(child.node))
				case let .alias(alias)?:
					.text(alias.text)
				case .closer?,
				     nil:
					.other
				}
			})
			let node = rebuiltNodesByKey[key] ?? PlanNode()
			rebuiltNodesByKey[key] = node
			return built.with(children: children.codes, node: node)
		}

		/// The call of the shared builder that builds `built`'s place, written where the place is, or `nil` where the
		/// place stays.
		private mutating func call(lifting built: BuiltPlaceRecord, visible: [String: TypeDescription], attributes callerAttributes: String) async -> GeneratedCode? {
			guard let attributes = built.staticBuilderAttributes,
			      attributes.isEmpty || attributes == callerAttributes,
			      built.hasFunction,
			      !built.passedArguments.contains(where: \.bindsBeforeCall),
			      let labels = labelsReadFromOutside(of: built)
			else { return nil }
			var parameters = [Property]()
			for label in labels {
				guard let type = visible[label] else { return nil }
				parameters.append(Property(label: label, typeDescription: type))
			}
			let key = LiftKey(node: ObjectIdentifier(built.node), parameters: parameters, typesSpelled: parameters.map(\.typeDescription.asSource), attributes: attributes)
			let lifted: Lifted
			if let memoized = liftedByKey[key] {
				guard let memoized else { return nil }
				lifted = memoized
			} else {
				let made = await function(building: built, parameters: parameters, attributes: attributes)
				liftedByKey[key] = .some(made)
				guard let made else { return nil }
				lifted = made
			}
			// The call hands the function what the place's function was handed, spelled where the place is.
			var arguments = parameters.map { "\($0.label.spelledAsArgumentLabel): \($0.label)" }
			var reads = parameters.map { PlaceRead(argumentLabel: $0.label, label: $0.label, property: $0, source: .binding(label: $0.label)) }
			for argument in built.passedArguments {
				guard let value = Self.spelled(argument.value, visible: visible) else { return nil }
				arguments.append("\(argument.parameterName.spelledAsArgumentLabel): \(value)")
				reads.append(contentsOf: argument.value.reads.filter { $0.source != .nil })
			}
			let text = TypeKeyLayout.spelledCall(
				ofFunctionNamed: "\(lifted.builtType.asSource).\(lifted.name)",
				binding: built.property,
				isErased: built.isErased && built.functionReturnType == nil,
				isExtension: built.isExtension,
				handing: arguments,
				forwardedProperties: built.forwardedProperties,
				returnedType: built.functionReturnType ?? built.concreteType,
			)
			var record = AliasPlaceRecord(property: built.property, fulfillingProperty: nil, text: text)
			record.reads = reads
			return .place(PlacePlan(code: .empty, record: .alias(record)))
		}

		/// The shared builder of `built`'s place, which takes `parameters` besides what the place's function takes, or
		/// `nil` where its place stays: its function reads a value the shared builder cannot take, closes a cycle, or is
		/// `@Sendable`, or the type key cannot lay it out on its own, or another builder takes its name.
		private mutating func function(building built: BuiltPlaceRecord, parameters: [Property], attributes: String) async -> Lifted? {
			guard readsOnlyWhatItIsHanded(built) else { return nil }
			var visible = [String: TypeDescription]()
			for property in parameters + built.parameterProperties {
				visible[property.label] = property.typeDescription
			}
			// The places inside lift too, as the function's own: its attributes are theirs.
			let children = await lifting(built.children, from: 0, visible: visible, attributes: attributes)
			var place = built.with(children: children.codes, node: built.node)
			// The function is laid out as a root's only place, whose call is never written.
			place.passedArguments = built.passedArguments.map { argument in
				PassedArgument(parameterName: argument.parameterName, type: argument.type, value: .rootDeclaration(argument.parameterName), staysOutsideSendableFunctions: argument.staysOutsideSendableFunctions)
			}
			guard let declaration = TypeKeyBody.staticFunction(building: place, parameters: parameters, attributes: attributes) else { return nil }
			let (name, namedDeclaration) = ReservedName.sharedBuilder(named: declaration)
			let key = SharedBuilderKey(builtType: built.concreteType.asSource, name: name)
			if let existing = buildersByTypeAndName[key] {
				// Two declarations of one hash: the place stays rather than calling the other.
				guard existing.declaration == namedDeclaration else { return nil }
			} else {
				buildersByTypeAndName[key] = SharedBuilder(name: name, builtType: built.concreteType, declaration: namedDeclaration)
			}
			return Lifted(name: name, builtType: built.concreteType)
		}

		/// The labels the place `built`'s function reads from outside it, in the order it first reads them, other than reads
		/// of `nil`; `nil` where a place in it closes a cycle or records no reads. Each function's labels are found once
		/// per plan node, children before parents on an explicit stack, and a function's are its own reads and those of the
		/// functions in it, less what it binds before each: a tree can be deep, and reached along many paths.
		private mutating func labelsReadFromOutside(of built: BuiltPlaceRecord) -> [String]? {
			var stack = [(record: built, childrenVisited: false)]
			while let (record, childrenVisited) = stack.popLast() {
				let key = ObjectIdentifier(record.node)
				guard labelsReadFromOutsideByNode[key] == nil else { continue }
				if childrenVisited {
					labelsReadFromOutsideByNode[key] = .some(labelsReadFromOutside(ofFunctionOf: record))
				} else {
					stack.append((record, true))
					for child in record.children {
						if case let .built(childRecord)? = TypeKeyLayout.record(of: child), childRecord.hasFunction, labelsReadFromOutsideByNode[ObjectIdentifier(childRecord.node)] == nil {
							stack.append((childRecord, false))
						}
					}
				}
			}
			return labelsReadFromOutsideByNode[ObjectIdentifier(built.node)] ?? nil
		}

		/// `record`'s labels, where those of each function in it are found.
		private func labelsReadFromOutside(ofFunctionOf record: BuiltPlaceRecord) -> [String]? {
			var labels = [String]()
			var seen = Set<String>()
			var bound = Set(record.parameterProperties.map(\.label)).union(record.cycleParameters.map(\.label))
			func read(_ readLabels: [String]) {
				for label in readLabels where !bound.contains(label) && seen.insert(label).inserted {
					labels.append(label)
				}
			}
			func labelsRead(by reads: [PlaceRead]) -> [String] {
				reads.filter { $0.source != .nil }.map(\.label)
			}
			for child in record.children {
				switch TypeKeyLayout.record(of: child) {
				case let .built(childRecord)?:
					read(labelsRead(by: childRecord.callSiteReads))
					if childRecord.hasFunction {
						guard let childLabels = labelsReadFromOutsideByNode[ObjectIdentifier(childRecord.node)] ?? nil else { return nil }
						read(childLabels)
					} else {
						read(labelsRead(by: childRecord.constructionReads))
					}
					bound.insert(childRecord.property.label)
				case let .alias(alias)?:
					guard alias.listsItsReads else { return nil }
					if let fulfillingProperty = alias.fulfillingProperty {
						read([fulfillingProperty.label])
					}
					read(labelsRead(by: alias.listedReads))
					bound.insert(alias.property.label)
					bound.formUnion(alias.otherBindings.map(\.label))
				case .closer?,
				     nil:
					return nil
				}
			}
			read(labelsRead(by: record.constructionReads))
			return labels
		}

		/// Whether the function of `built`'s place, and every function in it, reads only what it binds, what it is handed and
		/// what the place reads from outside it: no place in it closes a cycle, takes a cycle's parameters, is `@Sendable`,
		/// calls a function by name, reads a root's declaration, or reads a value handed to a function outside it. What each
		/// place in it is handed and reads is found once per plan node, children before parents on an explicit stack.
		private mutating func readsOnlyWhatItIsHanded(_ built: BuiltPlaceRecord) -> Bool {
			guard built.cycleParameters.isEmpty, built.callCycleArguments.isEmpty, !built.isSendable else { return false }
			// The place's own handed values are read where it is called, outside its function.
			var placeReads = HandedReads()
			placeReads.handedNames.formUnion(built.passedArguments.map(\.parameterName))
			readValues(of: built, into: &placeReads)
			for child in built.children {
				switch TypeKeyLayout.record(of: child) {
				case let .built(childRecord)?:
					guard let childReads = handedReads(ofPlace: childRecord) else { return false }
					placeReads.formUnion(childReads)
				case let .alias(alias)?:
					guard alias.calledFunctionNames.isEmpty, alias.calledRootFunctionNames.isEmpty else { return false }
				case .closer?,
				     nil:
					return false
				}
			}
			return !placeReads.readsRootDeclaration && placeReads.readNames.isSubset(of: placeReads.handedNames)
		}

		/// What the place `record`, the values it is handed included, and every place in it are handed and read, or `nil`
		/// where one closes a cycle, takes a cycle's parameters, is `@Sendable` or calls a function by name.
		private mutating func handedReads(ofPlace record: BuiltPlaceRecord) -> HandedReads? {
			var stack = [(record: record, childrenVisited: false)]
			while let (current, childrenVisited) = stack.popLast() {
				let key = ObjectIdentifier(current.node)
				guard handedReadsByNode[key] == nil else { continue }
				if childrenVisited {
					handedReadsByNode[key] = .some(handedReadsOfPlaceAfterItsChildren(current))
				} else {
					stack.append((current, true))
					for child in current.children {
						if case let .built(childRecord)? = TypeKeyLayout.record(of: child), handedReadsByNode[ObjectIdentifier(childRecord.node)] == nil {
							stack.append((childRecord, false))
						}
					}
				}
			}
			return handedReadsByNode[ObjectIdentifier(record.node)] ?? nil
		}

		/// `record`'s handed values and reads, where those of each place in it are found.
		private func handedReadsOfPlaceAfterItsChildren(_ record: BuiltPlaceRecord) -> HandedReads? {
			guard record.cycleParameters.isEmpty, record.callCycleArguments.isEmpty, !record.isSendable else { return nil }
			var handedReads = HandedReads()
			handedReads.handedNames.formUnion(record.passedArguments.map(\.parameterName))
			for argument in record.passedArguments {
				handedReads.read(argument.value)
			}
			readValues(of: record, into: &handedReads)
			for child in record.children {
				switch TypeKeyLayout.record(of: child) {
				case let .built(childRecord)?:
					guard let childReads = handedReadsByNode[ObjectIdentifier(childRecord.node)] ?? nil else { return nil }
					handedReads.formUnion(childReads)
				case let .alias(alias)?:
					guard alias.calledFunctionNames.isEmpty, alias.calledRootFunctionNames.isEmpty else { return nil }
				case .closer?,
				     nil:
					return nil
				}
			}
			return handedReads
		}

		/// Reads into `handedReads` the values `record`'s construction reads, other than those it is handed.
		private func readValues(of record: BuiltPlaceRecord, into handedReads: inout HandedReads) {
			for alternative in record.alternatives {
				handedReads.read(alternative.closure)
				for path in alternative.requiresAbsent {
					handedReads.read(path)
				}
			}
			for path in record.argumentValues.values {
				handedReads.read(path)
			}
			if let constructionValue = record.constructionValue {
				handedReads.read(constructionValue.value)
			}
		}

		/// `path` spelled where `visible` declares what is visible, or `nil` where a read in it reads a declaration as no
		/// receiver declares it.
		private static func spelled(_ path: ValuePath, visible: [String: TypeDescription]) -> String? {
			func spelled(_ read: PlaceRead) -> String? {
				guard read.source != .nil, let declaredType = visible[read.label] else { return "nil" }
				return TypeKeyLayout.spelledRead(read, declaredAs: declaredType)
			}
			switch path {
			case let .rootDeclaration(name),
			     let .passedArgument(name):
				return name
			case let .read(read):
				return spelled(read)
			case let .emptyInitialization(type):
				return "\(type.asSource)()"
			case let .memberRead(name, base):
				return Self.spelled(base.value, visible: visible).map { "\($0).\(name)" }
			case let .optionalMemberRead(name, base):
				return Self.spelled(base.value, visible: visible).map { "\($0)?.\(name)" }
			case let .call(name, value, arguments, argumentsWrapper):
				guard let receiver = Self.spelled(value, visible: visible) else { return nil }
				var spelledArguments = [String]()
				for argument in arguments {
					guard let value = spelled(argument) else { return nil }
					spelledArguments.append("\(argument.argumentLabel.spelledAsArgumentLabel): \(value)")
				}
				let joined = spelledArguments.joined(separator: ", ")
				if let argumentsWrapper {
					return "\(receiver).\(name)(\(argumentsWrapper.asSource)(\(joined)))"
				} else {
					return "\(receiver).\(name)(\(joined))"
				}
			case let .spliced(segments):
				var text = ""
				for segment in segments {
					switch segment {
					case let .text(segmentText):
						text += segmentText
					case let .value(value):
						guard let value = Self.spelled(value, visible: visible) else { return nil }
						text += value
					case let .declaredFunction(name):
						text += name
					}
				}
				return text
			}
		}
	}

	/// What tells two shared builders apart: the type whose extension declares them, and the name.
	struct SharedBuilderKey: Hashable, Comparable {
		let builtType: String
		let name: String

		static func < (lhs: SharedBuilderKey, rhs: SharedBuilderKey) -> Bool {
			(lhs.builtType, lhs.name) < (rhs.builtType, rhs.name)
		}
	}

	/// The declarations of the shared builders `roots` made, by the type whose extension declares them, each type's in
	/// name order, one per name. Roots whose places build alike made one declaration of a name, which their hash names.
	static func sharedBuilderDeclarations(of roots: [LoweredRoot]) -> [String: [String]] {
		var buildersByKey = [SharedBuilderKey: SharedBuilder]()
		for root in roots {
			// Two declarations of one name differ at most in their `#sourceLocation` lines, which the name leaves out: the
			// first by their UTF-8 is kept, whichever root lowered it first.
			for builder in root.lowered.sharedBuilders {
				let key = SharedBuilderKey(builtType: builder.builtType.asSource, name: builder.name)
				if let kept = buildersByKey[key], kept.declaration.utf8.lexicographicallyPrecedes(builder.declaration.utf8) || kept.declaration == builder.declaration {
					continue
				}
				buildersByKey[key] = builder
			}
		}
		var declarationsByType = [String: [String]]()
		for key in buildersByKey.keys.sorted() {
			if let builder = buildersByKey[key] {
				declarationsByType[key.builtType, default: []].append(builder.declaration)
			}
		}
		return declarationsByType
	}
}

extension BuiltPlaceRecord {
	/// This record, holding the places `children` beneath it, as the plan node `node`.
	func with(children: [GeneratedCode], node: PlanNode) -> BuiltPlaceRecord {
		var record = BuiltPlaceRecord(
			property: property,
			isErased: isErased,
			concreteType: concreteType,
			isExtension: isExtension,
			target: target,
			arguments: arguments,
			forwardedProperties: forwardedProperties,
			cycleParameters: cycleParameters,
			callCycleArguments: callCycleArguments,
			functionName: functionName,
			isSendable: isSendable,
			typesDeclaredEscaping: typesDeclaredEscaping,
			lineEnd: lineEnd,
			hasFunction: hasFunction,
			children: children,
			node: node,
		)
		record.sharingFields = sharingFields
		return record
	}
}

extension ValuePath {
	/// Whether the path reads a declaration at the root's top.
	fileprivate var readsRootDeclaration: Bool {
		switch self {
		case .rootDeclaration:
			true
		case .read,
		     .passedArgument,
		     .emptyInitialization:
			false
		case let .memberRead(_, base),
		     let .optionalMemberRead(_, base):
			base.value.readsRootDeclaration
		case let .call(_, value, _, _):
			value.readsRootDeclaration
		case let .spliced(segments):
			segments.contains { segment in
				guard case let .value(value) = segment else { return false }
				return value.readsRootDeclaration
			}
		}
	}
}

extension TypeDescription {
	/// Whether the type is a name with no generic arguments, at any depth of its nesting, which a static function of the
	/// type's extension can name without generic parameters of its own.
	var namesNoGenericType: Bool {
		switch self {
		case let .simple(_, generics):
			generics.isEmpty
		case let .nested(_, parentType, generics):
			generics.isEmpty && parentType.namesNoGenericType
		case .void,
		     .composition,
		     .optional,
		     .implicitlyUnwrappedOptional,
		     .some,
		     .any,
		     .metatype,
		     .attributed,
		     .array,
		     .dictionary,
		     .tuple,
		     .closure,
		     .variadic,
		     .unknown:
			false
		}
	}
}

extension Initializer {
	/// Whether the declaration is `nonisolated`, which a function of its type's isolation could not call as code outside
	/// that isolation does.
	var isNonisolated: Bool {
		guard let spelledAttributes else { return false }
		return spelledAttributes.split(separator: " ").contains { $0 == "nonisolated" || $0.hasPrefix("nonisolated(") }
	}
}
