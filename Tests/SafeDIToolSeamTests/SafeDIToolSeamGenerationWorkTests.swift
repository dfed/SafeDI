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
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// How the work of generating a seam grows with the paths to its places. Each step `GenerationWork` counts once did work
/// that grew with the square of a seam's places, so that a seam reached along thousands of paths took minutes to
/// generate; the work is counted, not timed, so that the check is the same on every machine and every run. Each step
/// counts its work where a scope, fill, builder or name takes what it consults, so a step that builds or scans a
/// collection again for each of them counts that work, whatever the step's own code reports.
struct SafeDIToolSeamGenerationWorkTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_growsEachCountedStepNoFasterThanThePathsToThePlaces_whenSeamReachesItsPlacesAlongManyPaths() async throws {
		// Shape E (`SafeDIToolSeamScopeByTypeTests.shapeEModules`) triples the paths to the places with each layer of screens,
		// whether the places are the models' own or in the fills of a seam each model calls. A step whose work grew with the
		// square of the places grew nine times with each layer where its names grow with the paths, as they do when every
		// path reaches screens of its own; where its names grow with the layers instead, it grew only a little faster than
		// the paths.
		// The type key lays out production roots, not seams: `SafeDIToolTypeKeyViewTests` counts its views. The search for
		// root functions runs while code is emitted, where a seam whose signature takes more than one pass starts code it
		// then discards, which records or not as tasks are scheduled; `SafeDIToolTypeKeyViewTests` counts it on production
		// roots, which take one pass.
		let seamSteps = Set(GenerationWork.Step.allCases).subtracting([.layingOutTypeKeyViews, .findingRootFunctions])
		var countedSteps = Set<GenerationWork.Step>()
		for shape in Shape.allCases {
			var measures = [Measure]()
			for screenCount in Self.screenCounts {
				let shapeMeasure = try await measure(screenCount: screenCount, shape: shape)
				measures.append(shapeMeasure)
			}
			for (smaller, larger) in zip(measures, measures.dropFirst()) {
				let pathGrowth = Double(larger.pathCount) / Double(smaller.pathCount)
				for step in GenerationWork.Step.allCases where seamSteps.contains(step) {
					let smallerWork = smaller.workByStep[step, default: 0]
					let largerWork = larger.workByStep[step, default: 0]
					guard smallerWork > 0 else {
						#expect(largerWork == 0, "\(shape) counts no work for \(step.rawValue) along \(smaller.pathCount) paths, and \(largerWork) along \(larger.pathCount)")
						continue
					}
					countedSteps.insert(step)
					let workGrowth = Double(largerWork) / Double(smallerWork)
					#expect(
						workGrowth <= pathGrowth * Self.maximumWorkGrowthPerPathGrowth,
						"\(shape): \(step.rawValue) does \(smallerWork) units of work along \(smaller.pathCount) paths and \(largerWork) along \(larger.pathCount): \(String(format: "%.2f", workGrowth))× the work for \(String(format: "%.2f", pathGrowth))× the paths",
					)
				}
			}
		}
		#expect(seamSteps.subtracting(countedSteps).isEmpty, "No shape counts work for \(seamSteps.subtracting(countedSteps).map(\.rawValue).sorted())")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A shape measured: shape E, its places in the fills of an inner seam, and both with every path's screens its own.
	private enum Shape: String, CaseIterable, CustomStringConvertible {
		case shapeE = "Shape E"
		case placesInFillsOfInnerSeam = "Shape E with its places in the fills of an inner seam"
		case placesInFillsOfInnerSeamAlongPathsOfTheirOwn = "Shape E with its places in the fills of an inner seam, every path opening screens of its own"

		var description: String {
			rawValue
		}

		var modulesHavePlacesInFillsOfInnerSeam: Bool {
			switch self {
			case .shapeE:
				false
			case .placesInFillsOfInnerSeam,
			     .placesInFillsOfInnerSeamAlongPathsOfTheirOwn:
				true
			}
		}

		var opensScreensOfItsOwn: Bool {
			switch self {
			case .shapeE,
			     .placesInFillsOfInnerSeam:
				false
			case .placesInFillsOfInnerSeamAlongPathsOfTheirOwn:
				true
			}
		}
	}

	/// The work of every counted step for a shape with `screenCount / 4` layers, and the paths to its places.
	private struct Measure {
		let pathCount: Int
		let workByStep: [GenerationWork.Step: Int]
	}

	/// The screens of each shape measured: three, four and five layers of four, whose last layers' screens are reached
	/// along 36, 108 and 324 paths.
	private static let screenCounts = [12, 16, 20]

	/// How much faster than the paths to the places a step's work may grow from one shape to the next. A step whose work
	/// grows with the places grows as fast as the paths, or slower where part of its work is the same for every shape; a
	/// step whose work grows with the square of the places grows three times as fast.
	private static let maximumWorkGrowthPerPathGrowth = 1.1

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func measure(screenCount: Int, shape: Shape) async throws -> Measure {
		let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
		try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamScopeByTypeTests.shapeEModules(
					screenCount: screenCount,
					placesInFillsOfInnerSeam: shape.modulesHavePlacesInFillsOfInnerSeam,
					opensScreensOfItsOwn: shape.opensScreensOfItsOwn,
				),
				integration: .moduleInfo,
				// The smallest shape is compiled, so that the work the check measures is that of code that compiles.
				compileVerification: screenCount == Self.screenCounts.first ? .recordingIssues : .skipped,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var workByStep = [GenerationWork.Step: Int]()
		for await work in stream {
			workByStep[work.step, default: 0] += work.elementCount
		}
		// Each screen of a layer but the last opens three of the next layer's screens, and the first layer's four are `Home`'s,
		// whether the screens are shared or every path's own.
		let pathCount = 4 * Int(pow(3, Double(screenCount / 4 - 1)))
		return Measure(pathCount: pathCount, workByStep: workByStep)
	}
}
