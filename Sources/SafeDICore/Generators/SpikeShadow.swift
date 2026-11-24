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
	func spikeCompare(instantiable: Instantiable, mockLines: [String], hooks: [[Int]: ConstructionHook], indent: String, flatRenames: Bool) async {
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
			let productionBody = GeneratedCode.lines(code).spelled().split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.allSatisfy(\.isWhitespace) }
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
