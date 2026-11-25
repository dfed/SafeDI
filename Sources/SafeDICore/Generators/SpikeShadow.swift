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
		if instantiable.generateMock == .public {
			features.insert("public")
		}
		if flatRenames {
			features.insert("flatRenames")
		}
		let instantiated = Set(instantiable.dependencies.filter {
			if case .instantiated = $0.source {
				true
			} else {
				false
			}
		}.map(\.property.label))
		for child in children {
			if let property = child.property, !instantiated.contains(property.label) {
				features.insert("promoted")
			}
		}
		var stack = children
		var depth = 0
		while let generator = stack.popLast() {
			depth += 1
			switch generator.scopeData {
			case let .property(_, property, _, _, isPropertyCycle, seamCall):
				if isPropertyCycle {
					features.insert("cycle")
				}
				if seamCall != nil {
					features.insert("seamCall")
				}
				if !property.propertyType.isConstant {
					features.insert("wrapper")
				}
			case .alias: features.insert("alias")
			case .fill: features.insert("fill")
			case .hole: features.insert("hole")
			case .root: break
			}
			if await !generator.cycleParameters.isEmpty {
				features.insert("cycleParameters")
			}
			if !generator.receivedBuilderLoops.loopByChildIndex.isEmpty {
				features.insert("loop")
			}
			if generator.publicMockCall != nil {
				features.insert("publicMockCall")
			}
			if await generator.buildsInSendableFunction {
				features.insert("sendable")
			}
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
			detail += "\t" + Self.recordCounts(of: code)
			SpikeShadow.append(Self.compareRecords(production: Self.builtRecordsInDocumentOrder(of: code), walk: walk, root: instantiable.concreteInstantiable.asSource))
			if walk.buildsPublicMock {
				SpikeShadow.append("PUBLICRECORDS\t\(instantiable.concreteInstantiable.asSource)\t\(walk.publicRecordCounts.reportField)")
			}
			let productionBody = GeneratedCode.lines(code).spelled().split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.allSatisfy(\.isWhitespace) }
			if productionBody == mockBody {
				outcome = "SAME"
			} else {
				outcome = "DIFF"
				let index = (0..<min(productionBody.count, mockBody.count)).first { productionBody[$0] != mockBody[$0] } ?? min(productionBody.count, mockBody.count)
				let p = index < productionBody.count ? productionBody[index] : "<end>"
				let m = index < mockBody.count ? mockBody[index] : "<end>"
				detail += "\tline=\(index)\tprod=\(p.trimmingCharacters(in: .whitespaces))\tmock=\(m.trimmingCharacters(in: .whitespaces))\tprodLines=\(productionBody.count)\tmockLines=\(mockBody.count)"
			}
		} catch {
			outcome = "THREW"
			detail = "\t\(error)"
		}
		let test = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_TEST"] ?? ""
		SpikeShadow.append("\(outcome)\t\(instantiable.concreteInstantiable.asSource)\t\(features.sorted().joined(separator: ","))\tnodes=\(depth)\thooks=\(hooks.count)\(detail)\t\(test)")
	}

	/// SPIKE: how many places of `code` record what, and how many plan nodes and types the built ones name.
	static func recordCounts(of code: [GeneratedCode]) -> String {
		var places = 0, built = 0, builtWithAlternative = 0, closers = 0, aliases = 0, unrecorded = 0
		var nodes = Set<PlanNode>()
		var types = Set<String>()
		var stack = code
		while let next = stack.popLast() {
			switch next.node {
			case .text:
				break
			case let .sequence(codes), let .lines(codes):
				stack += codes
			case let .indented(inner, _), let .rootFunction(_, inner), let .sendableFunction(inner), let .omittingRootFunctions(inner, _):
				stack.append(inner)
			case let .place(plan):
				places += 1
				stack.append(plan.code)
				switch plan.record {
				case let .built(record):
					built += 1
					if !record.alternatives.isEmpty {
						builtWithAlternative += 1
					}
					nodes.insert(record.node)
					types.insert(record.concreteType.asSource)
				case .closer:
					closers += 1
				case .alias:
					aliases += 1
				case nil:
					unrecorded += 1
				}
			}
		}
		return "places=\(places)\tbuilt=\(built)\tbuiltWithOverride=\(builtWithAlternative)\tclosers=\(closers)\taliases=\(aliases)\tunrecorded=\(unrecorded)\tnodes=\(nodes.count)\ttypes=\(types.count)"
	}

	/// SPIKE: the built records of `code`'s places, in document order.
	static func builtRecordsInDocumentOrder(of code: [GeneratedCode]) -> [BuiltPlaceRecord] {
		var records = [BuiltPlaceRecord]()
		var stack = Array(code.reversed())
		while let next = stack.popLast() {
			switch next.node {
			case .text:
				break
			case let .sequence(codes), let .lines(codes):
				stack += codes.reversed()
			case let .indented(inner, _), let .rootFunction(_, inner), let .sendableFunction(inner), let .omittingRootFunctions(inner, _):
				stack.append(inner)
			case let .place(plan):
				if case let .built(record) = plan.record {
					records.append(record)
				}
				stack.append(plan.code)
			}
		}
		return records
	}

	static func readKey(_ reads: [PlaceRead]) -> [String] {
		reads.map { "\($0.argumentLabel)|\($0.label)|\($0.property.asSource)|\($0.source.spelled)" }
	}

	static func alternativeKey(_ alternatives: [ConstructionAlternative]) -> [String] {
		alternatives.map { "\($0.closure)|\($0.bindingName ?? "-")|\($0.resultWrapper?.asSource ?? "-")" }
	}

	/// SPIKE: one line per root comparing, place by place in order, the records the mock walk fed production's record
	/// function with the records the configurable path wrote, and counting the walk's plan nodes.
	static func compareRecords(production: [BuiltPlaceRecord], walk: MockLowering.Walk, root: String) -> String {
		let walkRecords = walk.placePathsInWalkOrder.compactMap { path -> BuiltPlaceRecord? in
			if case let .built(record) = walk.builtRecords[path] {
				record
			} else {
				nil
			}
		}
		var differences = [String: Int]()
		var examples = [String: String]()
		func differ(_ field: String, _ example: @autoclosure () -> String) {
			differences[field, default: 0] += 1
			if examples[field] == nil {
				examples[field] = example()
			}
		}
		if production.count != walkRecords.count {
			func key(_ record: BuiltPlaceRecord) -> String {
				"\(record.property.asSource)@\(record.concreteType.asSource)/\(record.target)/fn=\(record.hasFunction)"
			}
			var remaining = [String: Int]()
			for record in production {
				remaining[key(record), default: 0] += 1
			}
			var walkOnly = [String]()
			for record in walkRecords {
				if let count = remaining[key(record)], count > 0 {
					remaining[key(record)] = count - 1
				} else {
					walkOnly.append(key(record))
				}
			}
			let productionOnly = remaining.filter { $0.value > 0 }.keys.sorted()
			differ("count", "prod=\(production.count) walk=\(walkRecords.count) walkOnly=\(walkOnly.prefix(3)) prodOnly=\(productionOnly.prefix(3))")
			SpikeShadow.append("WALKONLY\t\(root)\t" + walkOnly.joined(separator: "\t"))
		}
		let walkPaths = walk.placePathsInWalkOrder.filter {
			if case .built = walk.builtRecords[$0] {
				true
			} else {
				false
			}
		}
		let configurationReads = walk.absoluteConfigurationReads()
		for ((p, m), walkPath) in zip(zip(production, walkRecords), walkPaths) {
			guard p.property == m.property, p.concreteType == m.concreteType else {
				differ("place", "\(p.property.asSource) vs \(m.property.asSource)")
				continue
			}
			if p.isErased != m.isErased {
				differ("isErased", p.property.asSource)
			}
			if p.target != m.target {
				differ("target", p.property.asSource)
			}
			if readKey(p.arguments) != readKey(m.arguments) {
				differ("arguments", "\(readKey(p.arguments)) vs \(readKey(m.arguments))")
			}
			if p.forwardedProperties != m.forwardedProperties {
				differ("forwarded", p.property.asSource)
			}
			if p.cycleParameters != m.cycleParameters {
				differ("cycleParameters", p.property.asSource)
			}
			if readKey(p.callCycleArguments) != readKey(m.callCycleArguments) {
				differ("callCycleArguments", "\(readKey(p.callCycleArguments)) vs \(readKey(m.callCycleArguments))")
			}
			if p.functionName != m.functionName {
				differ("functionName", "\(p.functionName) vs \(m.functionName)")
			}
			if p.isSendable != m.isSendable {
				differ("isSendable", p.property.asSource)
			}
			if p.lineEnd != m.lineEnd {
				differ("lineEnd", p.property.asSource)
			}
			if p.hasFunction != m.hasFunction {
				differ("hasFunction", "\(p.property.asSource) prod=\(p.hasFunction) walk=\(m.hasFunction)")
			}
			// The walk records the type key's relative reads, which must resolve to the path key's absolute ones.
			let walkAlternatives = walk.alternativesReadAbsolutely(at: walkPath, configurationReads: configurationReads)
			if alternativeKey(p.alternatives) != alternativeKey(walkAlternatives) {
				differ("alternatives", "\(alternativeKey(p.alternatives)) vs \(alternativeKey(walkAlternatives))")
			}
		}
		let differenceText = differences.keys.sorted().map { "\($0)=\(differences[$0, default: 0])" }.joined(separator: ",")
		let exampleText = examples.keys.sorted().map { "\($0): \(examples[$0, default: ""])" }.joined(separator: " || ")
		return "WALKRECORDS\t\(root)\tprod=\(production.count)\twalk=\(walkRecords.count)\twalkNodes=\(Set(walkRecords.map(\.node)).count)\tprodNodes=\(Set(production.map(\.node)).count)\twalkThrew=\(walk.unrecordedPlaceErrors.count)\tdiff=\(differenceText.isEmpty ? "none" : differenceText)\t\(exampleText)"
	}
}
