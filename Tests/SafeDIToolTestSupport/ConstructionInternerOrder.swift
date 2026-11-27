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
import SafeDICore
import Testing

/// An order in which `generate` interns what it builds, other than its own, so that a run shows that no ID's value, which
/// the order assigns, reaches what SafeDI produces: the generator's declarations
/// (`ConstructionInternerObservation.declarationOrder`) and each freeze's entries (`ScopeTableObservation.entryOrder`),
/// which decide the IDs everything else is given, both reversed or both permuted by a seed.
public enum ConstructionInternerOrder: Equatable, Sendable {
	case reversed
	case permuted(seed: UInt64)

	/// The order `SAFEDI_INTERNER_ORDER` names: `reverse`, or `permute:<seed>`; `nil` when it names none.
	public static var fromEnvironment: Self? {
		guard let value = ProcessInfo.processInfo.environment["SAFEDI_INTERNER_ORDER"] else { return nil }
		if value == "reverse" {
			return .reversed
		} else if value.hasPrefix("permute:"), let seed = UInt64(value.dropFirst("permute:".count)) {
			return .permuted(seed: seed)
		} else {
			return nil
		}
	}

	/// The order the graph fuzzer's second run interns in for the graph of `seed`: reversed for an even seed, and
	/// otherwise permuted by the seed.
	public static func secondRun(forGraphSeed seed: UInt64) -> Self {
		seed.isMultiple(of: 2) ? .reversed : .permuted(seed: seed)
	}

	/// The positions of `count` items in this order.
	public func positions(count: Int) -> [Int] {
		switch self {
		case .reversed:
			return Array((0..<count).reversed())
		case let .permuted(seed):
			var positions = Array(0..<count)
			var random = GraphFuzzerRandomNumberGenerator(seed: seed)
			for index in positions.indices.dropLast().reversed() {
				positions.swapAt(index, random.integer(in: index...(count - 1)))
			}
			return positions
		}
	}

	/// The value of `body`, run with what `generate` interns ordered so; a freeze order a test already set is kept.
	public func applying<Value>(_ body: () async throws -> Value) async rethrows -> Value {
		let order: @Sendable (Int) -> [Int] = { count in positions(count: count) }
		return try await ConstructionInternerObservation.$declarationOrder.withValue(order) {
			try await ScopeTableObservation.$entryOrder.withValue(ScopeTableObservation.entryOrder ?? order) {
				try await body()
			}
		}
	}

	/// The value of `body`, run in `order` when there is one, and as it is otherwise.
	public static func applying<Value>(_ order: Self?, _ body: () async throws -> Value) async rethrows -> Value {
		if let order {
			try await order.applying(body)
		} else {
			try await body()
		}
	}
}

/// The closure test: every value a freeze interns that the generator's declarations did not give its interner is read
/// only by excluded places or is one the freezes are designed to intern (`ConstructionInternerMiss`).
public enum ConstructionInternerClosure {
	/// An observer that records an issue for each miss that is `notExcluded`, and hands each miss to `enclosingObserver`.
	public static func recordingMissesNotExcluded(
		handingOn enclosingObserver: (@Sendable (ConstructionInternerMiss, String) -> Void)?,
	) -> @Sendable (ConstructionInternerMiss, String) -> Void {
		{ bucket, value in
			switch bucket {
			case .notExcluded:
				Issue.record("A freeze interned `\(value)`, which the generator’s declarations did not give its interner, for a place a memo entry can key: a construction site the interner does not cover.")
			case .excluded, .internedAtFreeze, .internedForTypeFacts:
				break
			}
			enclosingObserver?(bucket, value)
		}
	}
}
