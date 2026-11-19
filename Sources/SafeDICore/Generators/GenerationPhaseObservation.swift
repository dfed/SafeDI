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

/// The phases of a generation run whose time `SAFEDI_PHASE_TIMES_OUTPUT` records. Later pull requests may split a
/// span into these phases, never rename one.
public enum GenerationPhase: String, Sendable, CaseIterable {
	case validation = "validation"
	case signatures = "signatures"
	case productionConstruction = "production construction"
	case mockPlans = "mock plans"
	case mockConstruction = "mock construction"
	case wholeModuleGates = "whole-module gates"
	case productionOutput = "production output"
	case mockOutput = "mock output"
	case dot = "DOT"
}

/// Where the code that runs a generation's phases reports each span of them, as `CodeTaskStart` reports early code
/// starts. A span is bracketed as `let end = GenerationPhaseObservation.observer?(phases)` followed by
/// `defer { end?() }`, so a run without an observer pays one task-local read per span. Spans never nest.
public enum GenerationPhaseObservation {
	/// Called, when set, as a span of `phases` starts. The closure it returns is called as that span ends, whether
	/// the span returns or throws. Set by `generate` when `SAFEDI_PHASE_TIMES_OUTPUT` names a file, and by tests.
	@TaskLocal public static var observer: (@Sendable (_ phases: [GenerationPhase]) -> @Sendable () -> Void)?
}
