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

/// Two lazy cycles that share a type: `W` builds `U`, which builds `W` again and also `P`, which builds `U` again. A
/// label `P` declares is the nearest declaration for everything `U` builds beneath `P`, the `W` that `U` builds again
/// included, although on `W`'s own path to the scope that builds it again (`W` -> `U` -> `W`) nothing declares the
/// label. So the labels declared between `U` and the scope that builds `U` again are also declared between `W` and the
/// scope that builds `W` again, and each builder function on the way takes the label as a parameter. Each generated tree
/// is compared by value with a tree built by hand to the Manual's rule: a `@Received` property takes the nearest
/// declaration above it.
struct SafeDIToolNestedLazyCycleNearestDeclarationTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Production

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclaration_whenReceiverIsReachedOnlyThroughSecondCycleClosedInsideFirst() async throws {
		try await expectGeneratedTree(of: Self.fixture(), root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let l = L()
		        func __safeDI_wBuilder(l: L) -> W {
		            let uBuilder = Instantiator<U> {
		                __safeDI_uBuilder(l: l)
		            }
		            let vBuilder = Instantiator<V> {
		                __safeDI_vBuilder(l: l)
		            }
		            return W(uBuilder: uBuilder, vBuilder: vBuilder)
		        }
		        func __safeDI_uBuilder(l: L) -> U {
		            let pBuilder = Instantiator<P>(__safeDI_pBuilder)
		            let wBuilder = Instantiator<W> {
		                __safeDI_wBuilder(l: l)
		            }
		            return U(pBuilder: pBuilder, wBuilder: wBuilder)
		        }
		        func __safeDI_pBuilder() -> P {
		            let l = L()
		            let uBuilder = Instantiator<U> {
		                __safeDI_uBuilder(l: l)
		            }
		            return P(l: l, uBuilder: uBuilder)
		        }
		        func __safeDI_vBuilder(l: L) -> V {
		            V(l: l)
		        }
		        let wBuilder = Instantiator<W> {
		            __safeDI_wBuilder(l: l)
		        }
		        self.init(l: l, wBuilder: wBuilder)
		    }
		}
		""", buildsTheSameValuesAs: Self.handBuiltTree)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Root` instantiates `l` and `W`; `W` instantiates `U` and `V`, which receives `l`; `U` instantiates `P` and `W`
	/// again; `P` instantiates its own `l` and `U` again.
	private static func fixture(
		rootDeclares: [String] = ["@Instantiated let l: L", "@Instantiated let wBuilder: Instantiator<W>"],
		wDeclares: [String] = ["@Instantiated let uBuilder: Instantiator<U>", "@Instantiated let vBuilder: Instantiator<V>"],
		uDeclares: [String] = ["@Instantiated let pBuilder: Instantiator<P>", "@Instantiated let wBuilder: Instantiator<W>"],
		pDeclares: [String] = ["@Instantiated let l: L", "@Instantiated let uBuilder: Instantiator<U>"],
		vDeclares: [String] = ["@Received let l: L"],
	) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclares),
			seamFixtureType(named: "W", isFinalClass: true, declarations: wDeclares),
			seamFixtureType(named: "U", isFinalClass: true, declarations: uDeclares),
			seamFixtureType(named: "P", isFinalClass: true, declarations: pDeclares),
			seamFixtureType(named: "V", isFinalClass: true, declarations: vDeclares),
			seamFixtureType(named: "L", isFinalClass: true, declarations: []),
		]
	}

	/// The tree of `fixture()` built by hand: each `V` is handed the `l` of the nearest `P` above it, or the root's.
	private static let handBuiltTree = """
	extension Root {
	    public convenience init() {
	        func w(l: L) -> W {
	            W(uBuilder: Instantiator<U> { u(l: l) }, vBuilder: Instantiator<V> { V(l: l) })
	        }
	        func u(l: L) -> U {
	            U(pBuilder: Instantiator<P> {
	                let stepL = L()
	                return P(l: stepL, uBuilder: Instantiator<U> { u(l: stepL) })
	            }, wBuilder: Instantiator<W> { w(l: l) })
	        }
	        let l = L()
	        self.init(l: l, wBuilder: Instantiator<W> { w(l: l) })
	    }
	}
	"""

	/// Generates `fixture`, expects `root`'s generated tree to be `expectedTree` and, when `expectedMock` is given, its mock
	/// to be `expectedMock`, and compares the values each builds with those `handBuiltTree` builds.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectGeneratedTree(
		of fixture: [String],
		root: String,
		equals expectedTree: String,
		mock expectedMock: String? = nil,
		buildsTheSameValuesAs handBuiltTree: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == ["\(root)+SafeDI.swift": generatedFileHeader + expectedTree], sourceLocation: sourceLocation)
		#expect(output.mockFiles == (expectedMock.map { ["\(root)+SafeDIMock.swift": generatedFileHeader + $0] } ?? [:]), sourceLocation: sourceLocation)
		let comparesMock = expectedMock != nil
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: output.generatedFiles ?? [:]),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: [
				"\(root)+SafeDI.swift": handBuiltTree + (comparesMock ? "\n\nextension \(root) {\n    static func mock() -> \(root) {\n        \(root)()\n    }\n}" : ""),
			]),
			probes: [DifferentialValueProbe("\(root)()")] + (comparesMock ? [DifferentialValueProbe("\(root).mock()")] : []),
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// `files` named as `executeSafeDIToolTest` names them, after the type each declares.
	private static func fixtureFiles(_ files: [String]) -> [String: String] {
		var fixtureFiles = [String: String]()
		for file in files {
			let name = file.split(separator: "\n").compactMap { line -> String? in
				guard let classRange = line.range(of: "final class ") else { return nil }
				return String(line[classRange.upperBound...].prefix { $0 != ":" })
			}.first ?? "File"
			fixtureFiles["\(name).swift"] = file
		}
		return fixtureFiles
	}
}
