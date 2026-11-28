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

/// Which fills of a world's calls build their tree in a `@Sendable` function of their own: the per-type facts' column of
/// the tree's mark, `ScopeGenerator.buildsInSendableFunction(ofFill:)`.
///
/// The tree decides it once per call, bottom-up (`ScopeGenerator.fillReferences`): each fill and dispatcher of the call
/// is a node of a worklist that starts `@Sendable` where the seam takes the fill `@Sendable`, where it is a dispatcher of
/// the `@Sendable` family, or where a `@Sendable` function inside the call's fills that does not enclose the call refers to
/// it, and a node made `@Sendable` makes `@Sendable` every node it refers to. What the fills refer to of an enclosing
/// call's fills and dispatchers is the enclosing fill a call inside them passes, the enclosing dispatcher it passes by name
/// or a case of its own reuses, and each such reference is made inside a `@Sendable` function where the call passes it to a
/// builder that takes it `@Sendable` or a scope between the reference and the enclosing call builds in a `@Sendable`
/// function: a `Sendable` wrapper's, or one a cycle makes `@Sendable` (`ScopeGenerator.cycleClosings`).
///
/// The fold is one walk up the call nesting, over the world's graph, in which each node is finished once: each node's
/// summary is the set of keys of fills and dispatchers its subtree refers to (a key names a fill by its place, a
/// dispatcher by its enum, so it names the same fill or dispatcher wherever the node sits), each marked where some
/// reference to it is made inside a `@Sendable` function, and a call reads its fills' summaries, never their nodes. A key
/// is resolved at each call that has it: every call between a reference and the outermost call that has the key builds
/// that fill or dispatcher again in the tree, which passes the outermost's on, so a call keeps in its summary every key some
/// other call of the world also has, which a call further out may resolve, and drops the keys only it has. Which calls
/// enclose a node is so never an input: the summary's keys say what they refer to, not where it is declared.
///
/// A node shared by several paths is walked from the first that reaches it, and an edge to a node the walk is still
/// building is a back edge: one with no fill edge between the two closes a cycle, which refers to the builder function it
/// closes on and so to no fill, but makes that function `@Sendable` where a `@Sendable` function lies between; one with a
/// fill edge between builds its target again inside the fill, a call that hands on every fill of its own the enclosing
/// call already passes, and so refers to its keys alone. A fill edge of a call inside a call that passes the same key's
/// fill, one the walk has open, is that fill built again, so it takes the column of the outermost such call, decided
/// when that call is finished. Held only while the graph is built.
enum TypeFactsFillSendability {
	/// A fill a call passes: the edge it is passed along, its key, and whether the seam takes it `@Sendable`.
	struct Fill {
		let edge: Int32
		let key: Int32
		let holeIsSendable: Bool
	}

	/// A dispatcher a call declares, as the tree declares it where no enclosing call declares one of its enum: its key, its
	/// family, and the keys of the fills and dispatchers its cases hand on to.
	struct Dispatcher {
		let key: Int32
		let isSendableFamily: Bool
		let targets: [Int32]
	}

	/// A node that passes fills.
	struct Call {
		let node: Int32
		let fills: [Fill]
		let dispatchers: [Dispatcher]
	}

	/// What the fold finds: of each fill, and of each node.
	struct Columns {
		/// Whether each edge's fill builds its tree in a `@Sendable` function, by edge position; `false` for an edge that is
		/// no fill.
		let fillBuildsInSendableFunction: [Bool]
		/// Whether each node's builder function is `@Sendable` (`ScopeGenerator.buildsInSendableFunction`) where the walk
		/// first reaches the node: its property is a `Sendable` wrapper's, or a cycle closed beneath it from inside a
		/// `@Sendable` function that does not enclose it refers to it. `false` for the root, which no builder function builds.
		/// Two places of one node can differ, where a cycle is entered at another of its nodes, which a node's column cannot
		/// say; and an edge to a node already finished does not hand on the cycles closed beneath it, which the tree's place
		/// there closes again (check 40 of the per-type facts' checks counts both).
		let nodeBuildsInSendableFunction: [Bool]
	}

	/// Whether each fill and each node builds in a `@Sendable` function.
	/// - Parameters:
	///   - opensSendableFunction: Whether each node builds in a `@Sendable` function of its own by the kind of its property:
	///     a `Sendable` wrapper's.
	///   - keyCount: How many keys the calls' fills and dispatchers name.
	static func buildsInSendableFunction(
		in graph: OrderedGraph<TypeFactsDeclaration>,
		edgeIsFill: [Bool],
		opensSendableFunction: [Bool],
		calls: [Call],
		keyCount: Int,
	) -> Columns {
		let nodeCount = graph.nodes.count
		var callByNode = [Int32](repeating: -1, count: nodeCount)
		for (index, call) in calls.enumerated() {
			callByNode[Int(call.node)] = Int32(index)
		}
		// How many calls have each key: a key no other call has is dropped where its call resolves it.
		var callCountByKey = [Int32](repeating: 0, count: keyCount)
		for call in calls {
			var keys = Set<Int32>()
			for fill in call.fills {
				keys.insert(fill.key)
			}
			for dispatcher in call.dispatchers {
				keys.insert(dispatcher.key)
			}
			for key in keys {
				callCountByKey[Int(key)] += 1
			}
		}
		var column = [Bool](repeating: false, count: graph.edgeCount)
		// Each finished node's summary: the keys its subtree refers to, and those referred to inside a `@Sendable` function.
		var referenced = [Set<Int32>](repeating: [], count: nodeCount)
		var referencedFromSendableFunction = [Set<Int32>](repeating: [], count: nodeCount)
		// 0: not reached; 1: on the walk's stack; 2: finished.
		var state = [UInt8](repeating: 0, count: nodeCount)
		var fillEdgesAbove = [Int32](repeating: 0, count: nodeCount)
		// The cycles closed beneath each node that are not yet judged, as a list through `nextClosing`: each the node closed on.
		var closedOn = [Int32]()
		var nextClosing = [Int32]()
		var closingHead = [Int32](repeating: -1, count: nodeCount)
		var closingTail = [Int32](repeating: -1, count: nodeCount)
		var isMadeSendableByCycle = [Bool](repeating: false, count: nodeCount)
		// How many calls on the walk's stack pass each key's fill, and the fill edges of calls inside the outermost of them,
		// which build that call's fill again: each takes the column of the outermost call once it is decided.
		var openCallCountByKey = [Int32](repeating: 0, count: keyCount)
		var edgesAwaitingOutermostCallByKey = [[Int32]](repeating: [], count: keyCount)
		var work = 0

		struct Frame {
			let node: Int
			var nextEdge: Int
			var referenced = Set<Int32>()
			var referencedFromSendableFunction = Set<Int32>()
		}
		/// The keys a call refers to of its own: each fill's, marked where the seam takes it `@Sendable`, and each
		/// dispatcher's, marked where it is of the `@Sendable` family, as the call refers to them where it builds them again
		/// inside a fill of an enclosing call that has them.
		func addOwnKeys(of call: Call, to frame: inout Frame) {
			for fill in call.fills {
				frame.referenced.insert(fill.key)
				if fill.holeIsSendable {
					frame.referencedFromSendableFunction.insert(fill.key)
				}
			}
			for dispatcher in call.dispatchers {
				frame.referenced.insert(dispatcher.key)
				if dispatcher.isSendableFamily {
					frame.referencedFromSendableFunction.insert(dispatcher.key)
				}
			}
			work += call.fills.count + call.dispatchers.count
		}

		func open(_ node: Int) {
			state[node] = 1
			guard callByNode[node] >= 0 else { return }
			for fill in calls[Int(callByNode[node])].fills {
				openCallCountByKey[Int(fill.key)] += 1
			}
		}

		var frames = [Frame(node: 0, nextEdge: graph.edgeOffset(of: 0))]
		open(0)
		while let frame = frames.last {
			let node = frame.node
			let edges = graph.edgeIndices(from: node)
			if frame.nextEdge < edges.upperBound {
				let edge = frame.nextEdge
				frames[frames.count - 1].nextEdge += 1
				work += 1
				let target = Int(graph.edgeTargets[edge])
				switch state[target] {
				case 0:
					open(target)
					fillEdgesAbove[target] = fillEdgesAbove[node] + (edgeIsFill[edge] ? 1 : 0)
					frames.append(Frame(node: target, nextEdge: graph.edgeOffset(of: target)))
				case 1:
					if edgeIsFill[edge] {
						// A fill of the enclosing call, which this call passes on: its key is the call's own.
						continue
					} else if fillEdgesAbove[node] == fillEdgesAbove[target] {
						// A cycle closed on the target's builder function.
						let closing = Int32(closedOn.count)
						closedOn.append(Int32(target))
						nextClosing.append(-1)
						if closingTail[node] >= 0 {
							nextClosing[Int(closingTail[node])] = closing
						} else {
							closingHead[node] = closing
						}
						closingTail[node] = closing
					} else if callByNode[target] >= 0 {
						// The call built again inside a fill of its own, which passes on each fill it already passes.
						addOwnKeys(of: calls[Int(callByNode[target])], to: &frames[frames.count - 1])
					}
				default:
					frames[frames.count - 1].referenced.formUnion(referenced[target])
					frames[frames.count - 1].referencedFromSendableFunction.formUnion(referencedFromSendableFunction[target])
					work += referenced[target].count
				}
				continue
			}
			var finished = frames.removeLast()
			state[node] = 2
			let isSendable = opensSendableFunction[node] || isMadeSendableByCycle[node]
			// A `@Sendable` function refers to every builder function its subtree closes a cycle on above it.
			if isSendable {
				var closing = closingHead[node]
				while closing >= 0 {
					let closedOnNode = Int(closedOn[Int(closing)])
					if state[closedOnNode] == 1 {
						isMadeSendableByCycle[closedOnNode] = true
					}
					closing = nextClosing[Int(closing)]
					work += 1
				}
				closingHead[node] = -1
				closingTail[node] = -1
			}
			if callByNode[node] >= 0 {
				let call = calls[Int(callByNode[node])]
				addOwnKeys(of: call, to: &finished)
				// The call's own fills and dispatchers, as the tree's worklist sees them (`ScopeGenerator.sendableFills`).
				var referencesByKey = [Int32: Set<Int32>]()
				for fill in call.fills {
					let target = Int(graph.edgeTargets[Int(fill.edge)])
					if state[target] == 2 {
						referencesByKey[fill.key, default: []].formUnion(referenced[target])
					}
				}
				for dispatcher in call.dispatchers {
					referencesByKey[dispatcher.key, default: []].formUnion(dispatcher.targets)
				}
				var sendableKeys = Set<Int32>()
				var keysToVisit = [Int32]()
				for key in referencesByKey.keys where finished.referencedFromSendableFunction.contains(key) {
					sendableKeys.insert(key)
					keysToVisit.append(key)
				}
				while let key = keysToVisit.popLast() {
					for reference in referencesByKey[key] ?? [] {
						work += 1
						finished.referenced.insert(reference)
						finished.referencedFromSendableFunction.insert(reference)
						if referencesByKey[reference] != nil, sendableKeys.insert(reference).inserted {
							keysToVisit.append(reference)
						}
					}
				}
				for fill in call.fills {
					let key = Int(fill.key)
					openCallCountByKey[key] -= 1
					work += 1
					if openCallCountByKey[key] > 0 {
						edgesAwaitingOutermostCallByKey[key].append(fill.edge)
					} else {
						let buildsInSendableFunction = sendableKeys.contains(fill.key)
						column[Int(fill.edge)] = buildsInSendableFunction
						for edge in edgesAwaitingOutermostCallByKey[key] {
							column[Int(edge)] = buildsInSendableFunction
						}
						work += edgesAwaitingOutermostCallByKey[key].count
						edgesAwaitingOutermostCallByKey[key] = []
					}
				}
			}
			if isSendable {
				finished.referencedFromSendableFunction = finished.referenced
			}
			if callByNode[node] >= 0 {
				let call = calls[Int(callByNode[node])]
				for key in call.fills.map(\.key) + call.dispatchers.map(\.key) where callCountByKey[Int(key)] == 1 {
					finished.referenced.remove(key)
					finished.referencedFromSendableFunction.remove(key)
				}
			}
			referenced[node] = finished.referenced
			referencedFromSendableFunction[node] = finished.referencedFromSendableFunction
			guard let parent = frames.last?.node else { continue }
			frames[frames.count - 1].referenced.formUnion(finished.referenced)
			frames[frames.count - 1].referencedFromSendableFunction.formUnion(finished.referencedFromSendableFunction)
			work += finished.referenced.count
			// The cycles not yet judged go up with the node.
			if closingHead[node] >= 0 {
				if closingTail[parent] >= 0 {
					nextClosing[Int(closingTail[parent])] = closingHead[node]
				} else {
					closingHead[parent] = closingHead[node]
				}
				closingTail[parent] = closingTail[node]
			}
		}
		GenerationWork.record(work, by: .foldingFillSendability)
		let nodeColumn = (0..<nodeCount).map { node in
			node != 0 && (opensSendableFunction[node] || isMadeSendableByCycle[node])
		}
		return Columns(fillBuildsInSendableFunction: column, nodeBuildsInSendableFunction: nodeColumn)
	}
}
