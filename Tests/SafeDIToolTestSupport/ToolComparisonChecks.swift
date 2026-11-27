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

/// The comparisons the test helpers make around every `generate()` they run: each compares two computations of the tool
/// (a tree built with the construction memo and without it, a reused seam tree and one built anew, a fact and the walk
/// it replaces, the fold and the fulfillment walk, a run over whole module info files and over split ones), so each
/// makes the tool do part of its work twice. They test the tool’s logic against itself, not a compiler, so they run
/// where the suite runs in full on Linux, and not on macOS, where the suite exists to compile generated code with
/// Xcode’s Swift: with them, the Xcode 26 test job’s tests took 1,955 seconds in a run that compiled nothing (run
/// 45865538303), and 2,624 a day and three more comparisons later (run 45990228538).
enum ToolComparisonChecks {
	/// Whether the helpers make their comparisons around a run started here. A value in `forced` decides, as the fuzzer’s
	/// long run sets it for the seeds it leaves the comparisons out of. Else they are made where a test counts the run’s
	/// work (`GenerationWork.observer`), because the counts such a test pins include the work the comparisons make the
	/// tool do; where a test observes the validation walk (`ValidationWalkObservation.observer`), because the walk
	/// runs only where the comparison of it with the fold is set; and otherwise wherever `areMadeByDefault` says.
	static var areMade: Bool {
		forced ?? (areMadeByDefault || GenerationWork.observer != nil || ValidationWalkObservation.observer != nil)
	}

	/// Set around runs that make the comparisons, or leave them out, whatever the host.
	@TaskLocal static var forced: Bool?

	/// `SAFEDI_TOOL_COMPARISON_CHECKS` set to `0` or `1` decides; unset, the comparisons are made everywhere but on
	/// macOS. A Linux run with `0` is the macOS suite’s run, less Xcode’s compiler.
	static let areMadeByDefault: Bool = {
		switch ProcessInfo.processInfo.environment["SAFEDI_TOOL_COMPARISON_CHECKS"] {
		case "0":
			return false
		case "1":
			return true
		default:
			#if os(macOS)
				return false
			#else
				return true
			#endif
		}
	}()

	/// Runs `generate` with every comparison set around it, or, where none is made, with only the mode a run generates
	/// in (`ConstructionInternerOrder`). An observer a test set around its own run stays set either way: each comparison
	/// hands on what it observes, and where none is made nothing replaces the test’s.
	static func aroundGenerate<Result>(_ generate: () async throws -> Result) async throws -> Result {
		guard areMade else {
			return try await ConstructionInternerOrder.applying(.fromEnvironment) {
				try await generate()
			}
		}
		// Every place's levels must hold its scope struct's fields (`SeamPlaceLevels.pathStructMismatches`), and every tree
		// the same data on every path with the construction memo and without it (`ConstructionMemoChecks`).
		// Every seam settled without its confirming signature pass must have the signature that pass finds (`SkippedConfirmingPassChecks`).
		// Every seam tree made again from its first signature pass must generate what a tree built anew does (`ReusedSeamTreeChecks`).
		return try await HoleSiteRecordObservation.$observer.withValue(HoleSiteRecordObservation.checkingRecords(handingOn: HoleSiteRecordObservation.observer)) {
			try await SeamPlaceLevels.$observer.withValue(SeamPlaceLevels.checkingPathStructs(handingOn: SeamPlaceLevels.observer)) {
				try await ConstructionMemoOracle.$observer.withValue(ConstructionMemoChecks.recordingDifferences(handingOn: ConstructionMemoOracle.observer)) {
					try await SeamSignatureObservation.$confirmsSkippedPasses.withValue(SkippedConfirmingPassChecks.recordingDifferences(handingOn: SeamSignatureObservation.confirmsSkippedPasses)) {
						// Interned in the order `SAFEDI_INTERNER_ORDER` names, if any: the output must not change (`ConstructionInternerOrder`).
						// Every value a freeze interns must be one the interner is designed to meet there (`ConstructionInternerClosure`).
						try await ConstructionInternerObservation.$missObserver.withValue(ConstructionInternerClosure.recordingMissesNotExcluded(handingOn: ConstructionInternerObservation.missObserver)) {
							try await ConstructionInternerOrder.applying(.fromEnvironment) {
								try await ReusedSeamTreeChecks.comparing(handingOn: SeamTreeReuseObservation.comparesBuiltTrees) {
									// Every root’s imports from its union fact must equal the walk of its generator tree’s (`TypeFactsImportsChecks`).
									try await TypeFactsImportsChecks.comparing(handingOn: TypeFactsImportsObservation.comparesWalk) {
										// Every root’s received values from its per-type graph must equal the walk of its generator tree’s
										// (`TypeFactsReceivedValueSuppliesChecks`).
										try await TypeFactsReceivedValueSuppliesChecks.comparing(handingOn: TypeFactsReceivedValueSuppliesObservation.comparesWalk) {
											// The fold that decides whether any route is walked must send every graph the walk rejects to the walk (`FulfillmentFoldChecks`).
											try await ValidationWalkObservation.$foldComparison.withValue(FulfillmentFoldChecks.comparison(handingOn: ValidationWalkObservation.foldComparison)) {
												try await generate()
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
