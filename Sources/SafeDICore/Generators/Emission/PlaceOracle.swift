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

/// One place of a body's walk, in the order the walk first reaches it.
struct WalkedPlace: Sendable {
	/// The index at which the walk first reaches the place, which keys its builder functions (`BuilderKey.place`).
	let identity: PlaceIdentity
	let kind: PlaceKind
	let functionNames: [String]
	let closedOnFunctionName: String?
	/// The names of the builder functions the places enclosing this one declare, outermost first.
	let enclosingFunctionNames: [String]
	/// The number of places beneath this one.
	let placeCountBeneath: Int
}

extension GeneratedCode {
	/// The places of the body's ordered walk, depth first, each numbered by the index at which the walk first reaches it.
	/// A scope's code, cached and held by every place that builds the scope again, is reached once per such place, so each
	/// is a place of its own: the key is the path, never the scope.
	func places() -> [WalkedPlace] {
		enum Work {
			case code(GeneratedCode)
			/// Leaves the place at `index` among the places walked, whose functions are the last `functionCount` enclosing
			/// names.
			case leavePlace(index: Int, functionCount: Int)
		}
		var places = [WalkedPlace]()
		var enclosingFunctionNames = [String]()
		var work = [Work.code(self)]
		while let next = work.popLast() {
			switch next {
			case let .code(code):
				switch code {
				case .text:
					break
				case let .sequence(pieces), let .lines(pieces):
					for piece in pieces.reversed() {
						work.append(.code(piece))
					}
				case let .indented(code, _):
					work.append(.code(code))
				case let .laidOut(_, places):
					work.append(.code(places))
				case let .place(plan):
					work.append(.leavePlace(index: places.count, functionCount: plan.functionNames.count))
					work.append(.code(plan.code))
					places.append(WalkedPlace(
						identity: PlaceIdentity(firstReachIndex: places.count),
						kind: plan.kind,
						functionNames: plan.functionNames,
						closedOnFunctionName: plan.closedOnFunctionName,
						enclosingFunctionNames: enclosingFunctionNames,
						placeCountBeneath: 0,
					))
					enclosingFunctionNames += plan.functionNames
				}
			case let .leavePlace(index, functionCount):
				enclosingFunctionNames.removeLast(functionCount)
				let place = places[index]
				places[index] = WalkedPlace(
					identity: place.identity,
					kind: place.kind,
					functionNames: place.functionNames,
					closedOnFunctionName: place.closedOnFunctionName,
					enclosingFunctionNames: place.enclosingFunctionNames,
					placeCountBeneath: places.count - index - 1,
				)
			}
		}
		return places
	}
}

/// What a production body's plan holds for each place, checked against what each kind of place holds: one builder
/// function for a place built by one, two for a loop member whose function takes a lazy cycle's parameters, none and one
/// closing edge to an enclosing place's function for a scope that closes a cycle, none for an alias or a constant built in
/// place, and none, with no place beneath it, for a seam's hosted code. Handed to `observer`, which the tests and the
/// graph fuzzer set, never the tool.
public struct PlaceObservation: Sendable {
	/// One place of the body's walk.
	public struct Place: Equatable, Sendable {
		/// The index at which the walk first reaches the place.
		public let index: Int
		public let kind: PlaceKind
		/// The builder functions the place declares.
		public let functionNames: [String]

		public init(index: Int, kind: PlaceKind, functionNames: [String]) {
			self.index = index
			self.kind = kind
			self.functionNames = functionNames
		}
	}

	/// The places of the body's walk, in walk order.
	public let places: [Place]
	/// The number of places of each kind the body's walk reaches.
	public let placeCountByKind: [PlaceKind: Int]
	/// Each place whose plan does not hold what its kind holds, described, in walk order.
	public let violations: [String]

	/// Called with each production root's body, when set: by the tests and the graph fuzzer, never by the tool.
	@TaskLocal public static var observer: (@Sendable (PlaceObservation) -> Void)?

	/// Tells `observer`, when set, what `code`'s places hold.
	static func record(_ code: GeneratedCode) {
		if let observer {
			observer(PlaceObservation(of: code.places()))
		}
	}

	init(of places: [WalkedPlace]) {
		var placeCountByKind = [PlaceKind: Int]()
		var violations = [String]()
		for place in places {
			placeCountByKind[place.kind, default: 0] += 1
			let expectedFunctionCount = switch place.kind {
			case .builtByFunction, .loopMemberClosingCycle: 1
			case .loopMemberWithCycleParameters: 2
			case .constantBuiltInPlace, .closesCycle, .alias, .hostedSeamCode: 0
			}
			let description = "Place \(place.identity.firstReachIndex) (\(place.kind))"
			if place.functionNames.count != expectedFunctionCount {
				violations.append("\(description) declares \(place.functionNames.count) builder functions \(place.functionNames), not \(expectedFunctionCount)")
			}
			switch place.kind {
			case .closesCycle, .loopMemberClosingCycle:
				if let closedOnFunctionName = place.closedOnFunctionName {
					if !place.enclosingFunctionNames.contains(closedOnFunctionName) {
						violations.append("\(description) closes on \(closedOnFunctionName), which no enclosing place declares")
					}
				} else {
					violations.append("\(description) closes on no function")
				}
			case .builtByFunction, .loopMemberWithCycleParameters, .constantBuiltInPlace, .alias, .hostedSeamCode:
				if let closedOnFunctionName = place.closedOnFunctionName {
					violations.append("\(description) closes on \(closedOnFunctionName), but only a cycle-closing place does")
				}
			}
			if place.kind == .hostedSeamCode, place.placeCountBeneath > 0 {
				violations.append("\(description) holds \(place.placeCountBeneath) places beneath it")
			}
		}
		self.places = places.map { Place(index: $0.identity.firstReachIndex, kind: $0.kind, functionNames: $0.functionNames) }
		self.placeCountByKind = placeCountByKind
		self.violations = violations
	}
}
