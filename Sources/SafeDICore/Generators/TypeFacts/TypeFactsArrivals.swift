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

/// What can arrive at a read of a variant over every path of calls into it: `nil`, an answer a declaration gives, or
/// both.
struct TypeFactsArrivals: OptionSet, Hashable, Sendable {
	let rawValue: UInt8

	/// Some path passes `nil`: no declaration above binds the read there.
	static let `nil` = TypeFactsArrivals(rawValue: 1 << 0)
	/// Some path passes an answer a declaration binds.
	static let answer = TypeFactsArrivals(rawValue: 1 << 1)
}

/// For each read of each variant, what arrives there from every call into it (`TypeFactsArrivals`): a call's own source
/// where it binds the read or binds nothing for it, and what arrives at the caller's read where it passes that read
/// through. A fixed point over the calls, so neither call order nor cycles change it.
///
/// Rule 3's second stage: a variant keyed with a wrapper may be called with `nil` too, so its parameter for the read is
/// the optional wrapper where `nil` arrives (`nilArrives(at:of:)`), and is no parameter where only `nil` does
/// (`onlyNilArrives(at:of:)`).
///
/// Memory: one byte per read of each variant, for as long as a caller holds it.
struct TypeFactsReadArrivals: Sendable {
	init(world: some TypeFactsWorld) {
		var offsets = [Int32](repeating: 0, count: world.variantCount + 1)
		for variant in 0..<Int32(world.variantCount) {
			offsets[Int(variant) + 1] = offsets[Int(variant)] + Int32(world.keys(of: variant).count)
		}
		var arrivals = [UInt8](repeating: 0, count: Int(offsets[world.variantCount]))
		// A root's reads are bound by nothing in the world: what reaches them comes from outside it.
		for root in 0..<world.rootCount {
			let variant = world.rootVariant(root)
			for index in Int(offsets[Int(variant)])..<Int(offsets[Int(variant) + 1]) {
				arrivals[index] |= world.rootReadArrivals.rawValue
			}
		}
		// A worklist of callers whose arrivals changed, each once at a time; every variant starts on it, since a call
		// that binds or passes `nil` hands its callee something whatever arrives at its caller.
		var worklist = Array((0..<Int32(world.variantCount)).reversed())
		var isQueued = [Bool](repeating: true, count: world.variantCount)
		while let caller = worklist.popLast() {
			isQueued[Int(caller)] = false
			for (edgeIndex, callee) in world.calls(of: caller).enumerated() {
				var changed = false
				for (position, source) in world.sources(ofCall: edgeIndex, of: caller).enumerated() {
					let arrived: UInt8 = switch source.kind {
					case .none:
						TypeFactsArrivals.nil.rawValue
					case .bound:
						TypeFactsArrivals.answer.rawValue
					case .passedThrough:
						arrivals[Int(offsets[Int(caller)] + source.payload)]
					}
					let index = Int(offsets[Int(callee)]) + position
					if arrivals[index] | arrived != arrivals[index] {
						arrivals[index] |= arrived
						changed = true
					}
				}
				if changed, !isQueued[Int(callee)] {
					isQueued[Int(callee)] = true
					worklist.append(callee)
				}
			}
		}
		self.offsets = offsets
		self.arrivals = arrivals
	}

	/// What arrives at the read at `position` among `variant`'s keys.
	func arrivals(at position: Int, of variant: VariantID) -> TypeFactsArrivals {
		TypeFactsArrivals(rawValue: arrivals[Int(offsets[Int(variant)]) + position])
	}

	/// Whether some call into `variant` passes `nil` for the read at `position`, directly or through its caller's read.
	func nilArrives(at position: Int, of variant: VariantID) -> Bool {
		arrivals(at: position, of: variant).contains(.nil)
	}

	/// Whether every call into `variant` passes `nil` for the read at `position`: no path binds it.
	func onlyNilArrives(at position: Int, of variant: VariantID) -> Bool {
		arrivals(at: position, of: variant) == .nil
	}

	private let offsets: [Int32]
	private let arrivals: [UInt8]
}
