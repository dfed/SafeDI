// SPIKE (throwaway): writes each internal mock root's body through the production emitter with a construction hook, and
// compares it with the body MockLowering writes.
#if canImport(Glibc)
	import Glibc
#elseif canImport(Darwin)
	import Darwin
#endif
import Foundation

enum SpikeShadow {
	static let logPath: String? = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_LOG"]
	/// Whether the mock walk feeds production's record function at each place.
	static let feeds: Bool = logPath != nil || ProcessInfo.processInfo.environment["SAFEDI_SPIKE_FEED"] != nil

	static func append(_ line: String) {
		guard let logPath, let file = fopen(logPath, "a") else { return }
		fputs(line + "\n", file)
		fclose(file)
	}
}

extension ScopeGenerator {
	func spikeCompare(instantiable: Instantiable, mockLines: [String], hooks: [[Int]: ConstructionHook], indent: String, flatRenames: Bool, walk: MockLowering.Walk) async {
		var tree = PlaceHooks()
		for (path, hook) in hooks {
			func insert(_ node: inout PlaceHooks, _ rest: ArraySlice<Int>) {
				guard let first = rest.first else {
					node.construction = hook
					return
				}
				var child = node.children[first] ?? PlaceHooks()
				insert(&child, rest.dropFirst())
				node.children[first] = child
			}
			insert(&tree, path[...])
		}
		var features = Set<String>()
		if instantiable.generateMock == .public { features.insert("public") }
		if flatRenames { features.insert("flatRenames") }
		let instantiated = Set(instantiable.dependencies.filter { if case .instantiated = $0.source { true } else { false } }.map(\.property.label))
		for child in children {
			if let property = child.property, !instantiated.contains(property.label) { features.insert("promoted") }
		}
		var stack = children
		var depth = 0
		while let generator = stack.popLast() {
			depth += 1
			switch generator.scopeData {
			case let .property(_, property, _, _, isPropertyCycle, seamCall):
				if isPropertyCycle { features.insert("cycle") }
				if seamCall != nil { features.insert("seamCall") }
				if !property.propertyType.isConstant { features.insert("wrapper") }
			case .alias: features.insert("alias")
			case .fill: features.insert("fill")
			case .hole: features.insert("hole")
			case .root: break
			}
			if await !generator.cycleParameters.isEmpty { features.insert("cycleParameters") }
			if !generator.receivedBuilderLoops.loopByChildIndex.isEmpty { features.insert("loop") }
			if generator.publicMockCall != nil { features.insert("publicMockCall") }
			if await generator.buildsInSendableFunction { features.insert("sendable") }
			stack += generator.children
		}
		let mockBody = mockLines.joined(separator: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.allSatisfy(\.isWhitespace) }
		let outcome: String
		var detail = ""
		do {
			let code = try await generateProperties(
				codeGeneration: .configurable(tree),
				propertiesGeneratedLater: [],
				enclosingFunctionNames: [:],
				leadingMemberWhitespace: indent,
				fillPlaceBindings: .none,
			)
			let productionBody = GeneratedCode.lines(code).spelled().split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.allSatisfy(\.isWhitespace) }
			SpikeShadow.append(SpikeRecords.compare(production: SpikeRecords.collect(code), walk: walk, hooks: hooks, root: instantiable.concreteInstantiable.asSource))
			if productionBody == mockBody {
				outcome = "SAME"
			} else {
				outcome = "DIFF"
				let index = (0..<min(productionBody.count, mockBody.count)).first { productionBody[$0] != mockBody[$0] } ?? min(productionBody.count, mockBody.count)
				let p = index < productionBody.count ? productionBody[index] : "<end>"
				let m = index < mockBody.count ? mockBody[index] : "<end>"
				detail = "\tline=\(index)\tprod=\(p.trimmingCharacters(in: .whitespaces))\tmock=\(m.trimmingCharacters(in: .whitespaces))\tprodLines=\(productionBody.count)\tmockLines=\(mockBody.count)"
			}
		} catch {
			outcome = "THREW"
			detail = "\t\(error)"
		}
		let test = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_TEST"] ?? ""
		SpikeShadow.append("\(outcome)\t\(instantiable.concreteInstantiable.asSource)\t\(features.sorted().joined(separator: ","))\tnodes=\(depth)\thooks=\(hooks.count)\(detail)\t\(test)")
	}
}

extension MockLowering.Walk {
	/// SPIKE: production's record function, fed what this walk holds at the place it just lowered.
	mutating func spikeFeed(generator: ScopeGenerator, node: MockLowering.TreeNode, isLoopMember: Bool, unavailableAtPlace: Set<Property>) {
		guard case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, _, seamCall) = generator.scopeData else { return }
		let path = childIndexPath
		switch node {
		case let .built(constant):
			do {
				if let record = try generator.builtPlaceRecord(
					property: constant.property,
					isErased: constant.isErased,
					instantiable: constant.instantiable,
					forwardedProperties: Set(constant.forwardedProperties),
					unavailableProperties: unavailableAtPlace,
					functionName: constant.functionName,
					hasFunction: spikeHasFunction[path] ?? true,
					children: [],
					isPlannedAtPlace: seamCall == nil && !isLoopMember,
					spikePath: path,
				) {
					spikeMockRecords[path] = record
				}
			} catch {
				spikeFeedError[path] = "\(error)"
			}
		case .cycleClosing:
			if let record = generator.closingPlaceRecord(
				of: property,
				instantiable: instantiable,
				forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted { $0.label < $1.label },
				erasedToConcreteExistential: erasedToConcreteExistential,
				closedOnFunctionName: spikeClosedOn[path] ?? "",
				unavailableProperties: unavailableAtPlace,
				isPlannedAtPlace: seamCall == nil && !isLoopMember,
				spikePath: path,
			) {
				spikeMockRecords[path] = record
			}
		case .alias, .publicMockCall:
			_ = forwardedProperties
		}
	}
}

enum SpikeRecords {
	/// The records of a configurable body, by path.
	static func collect(_ codes: [GeneratedCode]) -> [[Int]: PlaceRecord] {
		var records = [[Int]: PlaceRecord]()
		var stack = codes
		while let code = stack.popLast() {
			switch code.node {
			case .text, .spelled:
				break
			case let .sequence(children), let .lines(children):
				stack += children
			case let .indented(child, _):
				stack.append(child)
			case let .place(plan):
				stack.append(plan.code)
				switch plan.record {
				case let .built(record)?:
					stack += record.children
					if let path = record.spikePath { records[path] = .built(record) }
				case let .closer(record)?:
					if let path = record.spikePath { records[path] = .closer(record) }
				case .alias?, nil:
					break
				}
			}
		}
		return records
	}

	static func spelled(_ reads: [PlaceRead]) -> [String] {
		reads.map { CallArgument(label: $0.argumentLabel, source: $0.source).spelled }
	}

	static func readKey(_ reads: [PlaceRead]) -> [String] {
		reads.map { "\($0.argumentLabel)|\($0.label)|\($0.property.asSource)|\($0.source.spelled)" }
	}

	/// One line per root: how many places each walk records, the plan nodes, and every field on which the record the mock
	/// walk feeds differs from the record production's writer makes at the same place, or from what the mock's statement
	/// reads.
	static func compare(production: [[Int]: PlaceRecord], walk: MockLowering.Walk, hooks: [[Int]: ConstructionHook], root: String) -> String {
		let mock = walk.spikeMockRecords
		var differences = [String: Int]()
		var examples = [String: String]()
		func differ(_ field: String, _ example: @autoclosure () -> String) {
			differences[field, default: 0] += 1
			if examples[field] == nil { examples[field] = example() }
		}
		var builtProduction = 0
		var builtMock = 0
		var closers = 0
		var productionGenerators = Set<ObjectIdentifier>()
		var overridden = 0
		for path in Set(production.keys).union(mock.keys) {
			if hooks[path] != nil { overridden += 1 }
			switch (production[path], mock[path]) {
			case let (.built(p)?, .built(m)?):
				builtProduction += 1
				builtMock += 1
				if let generator = p.spikeGenerator { productionGenerators.insert(generator) }
				if p.property != m.property || p.property.typeDescription.asSource != m.property.typeDescription.asSource { differ("property", "\(p.property.asSource) vs \(m.property.asSource)") }
				if p.isErased != m.isErased { differ("isErased", p.property.asSource) }
				if p.target != m.target { differ("target", "\(p.target.callee) vs \(m.target.callee)") }
				if readKey(p.arguments) != readKey(m.arguments) { differ("arguments", "\(readKey(p.arguments)) vs \(readKey(m.arguments))") }
				if p.forwardedProperties.map(\.asSource) != m.forwardedProperties.map(\.asSource) { differ("forwarded", p.property.asSource) }
				if p.cycleParameters.map(\.asSource) != m.cycleParameters.map(\.asSource) { differ("cycleParameters", p.property.asSource) }
				if readKey(p.callCycleArguments) != readKey(m.callCycleArguments) { differ("callCycleArguments", "\(readKey(p.callCycleArguments)) vs \(readKey(m.callCycleArguments))") }
				if p.functionName != m.functionName { differ("functionName", "\(p.functionName) vs \(m.functionName)") }
				if p.isSendable != m.isSendable { differ("isSendable", p.property.asSource) }
				if p.typesDeclaredEscaping != m.typesDeclaredEscaping { differ("typesDeclaredEscaping", p.property.asSource) }
				if p.lineEnd != m.lineEnd { differ("lineEnd", p.property.asSource) }
				if p.hasFunction != m.hasFunction { differ("hasFunction", "\(p.property.asSource) prod=\(p.hasFunction) mock=\(m.hasFunction)") }
				// What the mock's own statement reads, against what the record says the place reads.
				if let statement = walk.spikeDependencyArguments[path], statement != spelled(m.arguments) { differ("statementArguments", "\(spelled(m.arguments)) vs \(statement)") }
				if let statement = walk.spikeCycleArguments[path], statement != spelled(m.callCycleArguments) { differ("statementCycleArguments", "\(spelled(m.callCycleArguments)) vs \(statement)") }
			case let (.closer(p)?, .closer(m)?):
				closers += 1
				if p.closedOnFunctionName != m.closedOnFunctionName { differ("closedOnFunctionName", "\(p.closedOnFunctionName) vs \(m.closedOnFunctionName)") }
				if p.forwardedProperties.map(\.asSource) != m.forwardedProperties.map(\.asSource) { differ("closerForwarded", p.property.asSource) }
				if readKey(p.cycleArguments) != readKey(m.cycleArguments) { differ("closerCycleArguments", "\(readKey(p.cycleArguments)) vs \(readKey(m.cycleArguments))") }
				if p.isErased != m.isErased || p.isExtension != m.isExtension { differ("closerKind", p.property.asSource) }
				if let statement = walk.spikeCycleArguments[path], statement != spelled(m.cycleArguments) { differ("statementCloserCycleArguments", "\(spelled(m.cycleArguments)) vs \(statement)") }
			case let (p, m):
				func kind(_ record: PlaceRecord?) -> String {
					switch record {
					case .built?: "built"
					case .closer?: "closer"
					case .alias?: "alias"
					case nil: walk.spikeFeedError[path].map { "threw(\($0))" } ?? "none"
					}
				}
				differ("presence:\(kind(p))->\(kind(m))", "\(path)")
			}
		}
		let differenceText = differences.keys.sorted().map { "\($0)=\(differences[$0, default: 0])" }.joined(separator: ",")
		let exampleText = examples.keys.sorted().map { "\($0): \(examples[$0, default: ""])" }.joined(separator: " || ")
		return "RECORDS\t\(root)\tbuilt=\(builtProduction)/\(builtMock)\tclosers=\(closers)\tprodPlaces=\(production.count)\tmockPlaces=\(mock.count)\tgenerators=\(productionGenerators.count)\toverridden=\(overridden)\tdiff=\(differenceText.isEmpty ? "none" : differenceText)\t\(exampleText)"
	}
}
