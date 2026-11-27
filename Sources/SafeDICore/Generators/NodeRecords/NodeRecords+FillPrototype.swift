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

// PROTOTYPE, not for review: step 3's timing prototype (`lanes/node-records-fills/step3-interface.md`). With
// `SAFEDI_FILL_PROTOTYPE_REPORT` naming a file, `generate` appends, per production root, the fills, carrier fills and
// dispatchers node records make of the root's filled seam calls from the world alone, each as distinct keys beside the
// tree's, the filled calls refused by reason, and the time the records took.

/// What the prototype made of one root's filled seam calls, beside the tree's.
struct FillPrototypeReport: Sendable {
	let root: String
	let filledCalls: Int
	let fillKeys: [String]
	let carrierFillKeys: [String]
	let dispatcherKeys: [String]
	let refusedCallsByReason: [(reason: String, count: Int)]
	let worldRefusals: [String]
	let nanoseconds: Int64
	var treeFillKeys: [String] = []
	var treeCarrierFillKeys: [String] = []
	var treeDispatcherKeys: [String] = []

	var lines: String {
		func comparison(_ name: String, _ records: [String], _ tree: [String]) -> String {
			let missing = Set(tree).subtracting(records).sorted()
			let extra = Set(records).subtracting(tree).sorted()
			return "  \(name): records \(records.count), tree \(tree.count)\(missing.isEmpty && extra.isEmpty ? ", agree" : ", missing \(missing.prefix(5)), extra \(extra.prefix(5))")"
		}
		return ([
			"root \(root): filled calls made \(filledCalls), \(Double(nanoseconds) / 1_000_000) ms",
			comparison("fills", fillKeys, treeFillKeys),
			comparison("carrier fills", carrierFillKeys, treeCarrierFillKeys),
			comparison("dispatchers", dispatcherKeys, treeDispatcherKeys),
			"  refused filled calls: \(refusedCallsByReason.isEmpty ? "none" : refusedCallsByReason.map { "\($0.reason) \($0.count)" }.joined(separator: ", "))",
			"  world refusals: \(worldRefusals.isEmpty ? "none" : worldRefusals.joined(separator: ", "))",
		] + [""]).joined(separator: "\n")
	}
}

enum FillPrototype {
	/// The file the report is appended to, where set.
	static let reportPath = ProcessInfo.processInfo.environment["SAFEDI_FILL_PROTOTYPE_REPORT"]

	/// What node records make of the filled seam calls of `world`, a production root's.
	static func report(ofRoot root: String, world: TypeFactsGraph) -> FillPrototypeReport {
		let start = DispatchTime.now().uptimeNanoseconds
		var variantCounts = [Int](repeating: 0, count: world.declarationCount)
		for variant in 0..<Int32(world.variantCount) {
			variantCounts[Int(world.declaration(of: variant))] += 1
		}
		var refused = [String: Int]()
		var fillKeys = Set<String>()
		var carrierFillKeys = Set<String>()
		var dispatcherKeys = Set<String>()
		var filledCalls = 0
		for declaration in 0..<Int32(world.declarationCount) where world.construction(of: declaration) == .seamCall {
			let scope = world.scope(of: declaration)
			let fillsAPlace = scope.holeArguments.contains { argument in
				if case .fill = argument {
					true
				} else {
					false
				}
			}
			guard fillsAPlace else { continue }
			let reason: String? = if world.isMockWorld {
				"fillMockWorld"
			} else if scope.publicMockCall != nil {
				"fillPublicMockCall"
			} else if world.firstRoute(to: declaration).dropLast().contains(where: { world.construction(of: $0) == .fill }) {
				"fillInsideFill"
			} else if world.isOnCycle(declaration) {
				"fillCycleMember"
			} else if variantCounts[Int(declaration)] > 1 {
				"fillCallSeveralVariants"
			} else {
				nil
			}
			if let reason {
				refused[reason, default: 0] += 1
				continue
			}
			filledCalls += 1
			var log = ConstructionLog(recording: false)
			let callFills = ScopeGeneratorUnderConstruction.callFills(
				of: scope,
				holeArguments: scope.holeArguments,
				callPath: [],
				enclosingFills: [:],
				enclosingFillNames: .init([]),
				enclosingCarriedInnerScopes: [:],
				seamHoles: SeamHoles(),
				childNearestDeclarations: NearestDeclarations(),
				fillLabelsReadOnlyAsPlaceField: { _ in [] },
				fillSendableWrapperReads: { _ in [:] },
				log: &log,
			)
			for (fill, _, _) in callFills.fills where fill.emitsCode {
				fillKeys.insert(fill.key)
				if fill.carrierUse != nil {
					carrierFillKeys.insert(fill.key)
				}
			}
			for dispatcher in callFills.dispatchers {
				dispatcherKeys.insert(dispatcher.key)
			}
		}
		let nanoseconds = Int64(DispatchTime.now().uptimeNanoseconds - start)
		return FillPrototypeReport(
			root: root,
			filledCalls: filledCalls,
			fillKeys: fillKeys.sorted(),
			carrierFillKeys: carrierFillKeys.sorted(),
			dispatcherKeys: dispatcherKeys.sorted(),
			refusedCallsByReason: refused.sorted { $0.key < $1.key }.map { (reason: $0.key, count: $0.value) },
			worldRefusals: NodeRecords.refusals(in: world, declaredTypeNames: nil).map(\.rawValue),
			nanoseconds: nanoseconds,
		)
	}

	/// The tree's fills, carrier fills and dispatchers of seam calls, as distinct keys, from the generators beneath `root`.
	static func treeKeys(beneath root: ScopeGenerator) -> (fills: [String], carrierFills: [String], dispatchers: [String]) {
		var fills = Set<String>()
		var carrierFills = Set<String>()
		var dispatchers = Set<String>()
		var pending = [root]
		while let generator = pending.popLast() {
			if generator.publicMockLevelFunctions == nil {
				for dispatcher in generator.fillDispatchers {
					dispatchers.insert(dispatcher.key)
				}
			}
			for child in generator.propertiesToGenerate {
				if let key = child.fillKey, child.fillEmitsCode {
					fills.insert(key)
					if child.fillCarrierUse != nil {
						carrierFills.insert(key)
					}
				}
				pending.append(child)
			}
		}
		return (fills.sorted(), carrierFills.sorted(), dispatchers.sorted())
	}

	/// Appends `report` to the report file.
	static func append(_ report: FillPrototypeReport) {
		guard let reportPath, let data = report.lines.data(using: .utf8) else { return }
		if let handle = FileHandle(forWritingAtPath: reportPath) {
			handle.seekToEndOfFile()
			handle.write(data)
			handle.closeFile()
		} else {
			FileManager.default.createFile(atPath: reportPath, contents: data)
		}
	}
}
