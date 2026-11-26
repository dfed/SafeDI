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

extension TypeKeyLayout {
	// MARK: Reads

	/// The labels each place's function reads and does not bind, and where its reads escape it; `false` where they do not
	/// settle.
	mutating func computeReads() -> Bool {
		// Each pass recomputes, in reverse order, only a body one of whose children or closed-on targets changed since the
		// body was last computed: recomputing any other gives what it holds, so every pass ends as a pass over every body
		// would, at a cost that follows what changes.
		let dependents = dependentsOfBodies()
		postOrder = postOrderOfViews()
		reads = Array(repeating: [], count: bodies.count)
		guard settle(dependents: dependents, recompute: { layout, body in
			let bodyReads = layout.readsOfBody(body)
			guard bodyReads != layout.reads[body] else { return false }
			layout.reads[body] = bodyReads
			return true
		}) else { return false }
		escapingReads = Array(repeating: [:], count: bodies.count)
		for body in postOrder {
			escapingReads[body] = escapingReadsOfBody(body)
		}
		requiredReads = Array(repeating: [], count: bodies.count)
		return settle(dependents: dependents, recompute: { layout, body in
			let required = layout.requiredReadsOfBody(body)
			guard required != layout.requiredReads[body] else { return false }
			layout.requiredReads[body] = required
			return true
		})
	}

	/// The bodies whose reads read each body's: the body holding it as a child, and each body holding a closer on it.
	func dependentsOfBodies() -> [[Int]] {
		var dependents = [[Int]](repeating: [], count: bodies.count)
		for body in bodies.indices.dropFirst() {
			for statement in bodies[body].statements {
				switch statement {
				case let .built(child):
					dependents[child].append(body)
				case let .closer(_, target):
					dependents[target].append(body)
				case .inline, .alias:
					break
				}
			}
		}
		return dependents
	}

	/// The views other than the root's, each after every view its body builds: post-order of the view DAG.
	func postOrderOfViews() -> [Int] {
		var order = [Int]()
		var isVisited = [Bool](repeating: false, count: bodies.count)
		var frames = [(body: 0, next: 0)]
		isVisited[0] = true
		while let frame = frames.last {
			let statements = bodies[frame.body].statements
			guard frame.next < statements.count else {
				frames.removeLast()
				if frame.body != 0 {
					order.append(frame.body)
				}
				continue
			}
			frames[frames.count - 1].next += 1
			if case let .built(child) = statements[frame.next], !isVisited[child] {
				isVisited[child] = true
				frames.append((body: child, next: 0))
			}
		}
		return order
	}

	/// How many places the views stand for, saturating at `Int.max`: each view stands for one place at each place of each
	/// body holding it.
	func placeCount() -> Int {
		Self.saturatingSum(placesByBody().dropFirst())
	}

	/// How many places each view stands for, saturating at `Int.max`; the root's body stands for one.
	func placesByBody() -> [Int] {
		var placesByBody = [Int](repeating: 0, count: bodies.count)
		placesByBody[0] = 1
		for body in postOrder.reversed() {
			placesByBody[body] = Self.saturatingSum(bodies[body].edges.map { placesByBody[$0.parent] })
		}
		return placesByBody
	}

	/// Whether the root lays out the loops of builders it holds: it holds none, or a class holding a member's view that wraps
	/// another member again stands for several places, which the path key would write once per path. A class's places do not
	/// depend on which places the walk keyed into one view, only on the path key's tree.
	func laysOutLoops() -> Bool {
		guard !loopRebindingBodies.isEmpty else { return true }
		let places = placesByBody()
		return loopRebindingBodies.contains { body in
			Self.saturatingSum(membersByClass[classByBody[body]].map { places[$0] }) > 1
		}
	}

	static func saturatingSum(_ counts: some Sequence<Int>) -> Int {
		var total = 0
		for count in counts {
			let (sum, overflow) = total.addingReportingOverflow(count)
			total = overflow ? Int.max : sum
		}
		return total
	}

	/// Runs passes over the views in post-order until no view changes, recomputing a view only where it is dirty: never
	/// computed, or a view it reads changed since. `recompute` returns whether the view changed. `false` where the passes
	/// do not settle within one pass per place, as many as the path key's per-place passes could take.
	mutating func settle(dependents: [[Int]], recompute: (inout TypeKeyLayout, Int) -> Bool) -> Bool {
		var dirty = [Bool](repeating: true, count: bodies.count)
		var anyDirty = true
		var passes = 0
		let (bound, overflow) = placeCount().addingReportingOverflow(2)
		let passBound = overflow ? Int.max : bound
		while anyDirty {
			anyDirty = false
			passes += 1
			guard passes <= passBound else { return false }
			for body in postOrder where dirty[body] {
				dirty[body] = false
				guard recompute(&self, body) else { continue }
				for dependent in dependents[body] {
					dirty[dependent] = true
					anyDirty = true
				}
			}
		}
		return true
	}

	/// The labels of `body`'s reads that some read inside it requires a value of, as a non-optional receive does.
	func requiredReadsOfBody(_ body: Int) -> Set<String> {
		var required = Set<String>()
		func note(_ read: PlaceRead) {
			if !read.property.typeDescription.isOptional {
				required.insert(read.label)
			}
		}
		bodies[body].record?.constructionReads.forEach(note)
		for statement in bodies[body].statements {
			switch statement {
			case let .built(child):
				required.formUnion(requiredReads[child])
				bodies[child].record?.callSiteReads.forEach(note)
			case let .inline(record):
				record.constructionReads.forEach(note)
			case let .closer(record, target):
				record.callSiteReads.forEach(note)
				required.formUnion(requiredReads[target])
			case let .alias(record):
				if let fulfillingProperty = record.fulfillingProperty, !fulfillingProperty.typeDescription.isOptional {
					required.insert(fulfillingProperty.label)
				}
				record.listedReads.forEach(note)
			}
		}
		return required.intersection(reads[body])
	}

	func readsOfBody(_ body: Int) -> [String] {
		var seen = Set<String>()
		var list = [String]()
		func add(_ label: String) {
			if seen.insert(label).inserted {
				list.append(label)
			}
		}
		for argument in bodies[body].record?.constructionReads ?? [] {
			add(argument.label)
		}
		for statement in bodies[body].statements {
			switch statement {
			case let .built(child):
				reads[child].forEach(add)
				for argument in bodies[child].record?.callSiteReads ?? [] {
					add(argument.label)
				}
			case let .inline(record):
				record.constructionReads.forEach { add($0.label) }
			case let .closer(record, target):
				record.callSiteReads.forEach { add($0.label) }
				reads[target].forEach(add)
			case let .alias(record):
				if let fulfillingProperty = record.fulfillingProperty {
					add(fulfillingProperty.label)
				}
				record.listedReads.forEach { add($0.label) }
			}
		}
		return list.filter { !bodies[body].forwardedLabels.contains($0) && bodies[body].positionsByLabel[$0] == nil }
	}

	func escapingReadsOfBody(_ body: Int) -> [String: PathValue] {
		var escaping = [String: PathValue]()
		func note(_ label: String, _ value: PathValue) {
			switch value {
			case .none:
				if escaping[label] == nil {
					escaping[label] = PathValue.none
				}
			case let .statement(declaringBody, _),
			     let .forwarded(declaringBody, _),
			     let .cycleParameter(declaringBody, _):
				if declaringBody != body, escaping[label] == nil || escaping[label] == PathValue.none {
					escaping[label] = value
				}
			}
		}
		let statements = bodies[body].statements
		for argument in bodies[body].record?.constructionReads ?? [] {
			note(argument.label, pathValue(of: argument, inBody: body, before: statements.count))
		}
		for (index, statement) in statements.enumerated() {
			switch statement {
			case let .built(child):
				for (label, value) in escapingReads[child].sorted(by: { $0.key < $1.key }) {
					note(label, value)
				}
				for argument in bodies[child].record?.callSiteReads ?? [] {
					note(argument.label, pathValue(of: argument, inBody: body, before: index))
				}
			case let .inline(record):
				for argument in record.constructionReads {
					note(argument.label, pathValue(of: argument, inBody: body, before: index))
				}
			case let .closer(record, _):
				for argument in record.callSiteReads {
					note(argument.label, pathValue(of: argument, inBody: body, before: index))
				}
			case let .alias(record):
				if let fulfillingProperty = record.fulfillingProperty {
					note(fulfillingProperty.label, lookUp(fulfillingProperty.label, inBody: body, before: index))
				}
				for read in record.listedReads {
					note(read.label, pathValue(of: read, inBody: body, before: index))
				}
			}
		}
		return escaping.filter { !bodies[body].forwardedLabels.contains($0.key) && !bodies[body].cycleParameterLabels.contains($0.key) && bodies[body].positionsByLabel[$0.key] == nil }
	}
}
