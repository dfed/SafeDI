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
@testable import SafeDITool

/// A lazy cycle that re-enters a seam calls the seam's generated initializer again, passing the nearest declaration of
/// each label the seam receives, as the Manual's `@Received` rule says. Inline's cycle-closing scope reuses the enclosing
/// builder function, which captured the declarations above the cycle: a defect of main's that its own pull request on
/// main is to fix, so the seam corpus lists its seed as a known-issue shape until both builds agree.
struct SafeDIToolSeamLazyCycleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A lazy cycle that re-enters the seam

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclarationToSeamReenteredThroughLazyCycle_whenTypeInsideSeamDeclaresLabelSeamReceives() async throws {
		// `T3`, the seam, instantiates `T0` through an instantiator and receives `t1Builder`; `T0` declares its own `t1Builder` and
		// instantiates `T3` again. The nested call passes `T0`'s declaration, the nearest, as the `@Received` rule says. Inline,
		// the cycle-closing scope reuses `Root`'s builder function, which captured `Root`'s `t1Builder`: a defect of main's, so the
		// values are compared with a hand-built tree whose closer passes `T0`'s binding, not with the inline build.
		let fixture = Self.lazyCycleFixture
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t1Builder() -> T1 {
			            T1()
			        }
			        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			        func __safeDI_t3Builder() -> T3 {
			            _ = T3.__safeDI_T3_637A336A650792AD.self
			            return T3(t1Builder: t1Builder)
			        }
			        let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			        self.init(t1Builder: t1Builder, t3Builder: t3Builder)
			    }
			}
			""",
			"T3+SafeDI.swift": generatedFileHeader + """
			extension T3 {
			    public convenience init(t1Builder: Instantiator<T1>) {
			        func __safeDI_t0Builder() -> T0 {
			            func __safeDI_t1Builder() -> T1 {
			                T1()
			            }
			            let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			            func __safeDI_t3Builder() -> T3 {
			                _ = T3.__safeDI_T3_637A336A650792AD.self
			                return T3(t1Builder: t1Builder)
			            }
			            let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			            return T0(t1Builder: t1Builder, t3Builder: t3Builder)
			        }
			        let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			        self.init(t0Builder: t0Builder, t1Builder: t1Builder)
			    }
			}

			extension T3 {
			    public enum __safeDI_T3_637A336A650792AD {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t1Builder() -> T1 {
			            T1()
			        }
			        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			        func __safeDI_t3Builder() -> T3 {
			            func __safeDI_t0Builder() -> T0 {
			                func __safeDI_t1Builder() -> T1 {
			                    T1()
			                }
			                let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			                let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			                return T0(t1Builder: t1Builder, t3Builder: t3Builder)
			            }
			            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			            return T3(t0Builder: t0Builder, t1Builder: t1Builder)
			        }
			        let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			        self.init(t1Builder: t1Builder, t3Builder: t3Builder)
			    }
			}
			""",
		])
		try expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: output.dependencyTreeFiles),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(inlineFixture(fixture)), generatedFiles: ["Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t1Builder() -> T1 {
			            T1()
			        }
			        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			        func __safeDI_t3Builder(t1Builder: Instantiator<T1>) -> T3 {
			            func __safeDI_t0Builder() -> T0 {
			                func __safeDI_t1Builder() -> T1 {
			                    T1()
			                }
			                let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			                let t3Builder = Instantiator<T3> {
			                    __safeDI_t3Builder(t1Builder: t1Builder)
			                }
			                return T0(t1Builder: t1Builder, t3Builder: t3Builder)
			            }
			            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			            return T3(t0Builder: t0Builder, t1Builder: t1Builder)
			        }
			        let t3Builder = Instantiator<T3> {
			            __safeDI_t3Builder(t1Builder: t1Builder)
			        }
			        self.init(t1Builder: t1Builder, t3Builder: t3Builder)
			    }
			}
			"""]),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromSeamsChain_whenTypeInsideSeamDeclaresLabelSeamReceivesWithAnotherType() async throws {
		// `T0` declares `t1Builder` as `Instantiator<Other>`, so the nested call's receive of `t1Builder: Instantiator<T1>` is hidden
		// beneath it: the hidden-label error from the seam's chain.
		let fixture = Self.hiddenCycleFixture
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):9:5: error: @Received property `t1Builder: Instantiator<T1>` is hidden in chain: T3 -> Instantiator<T0> -> T3. `T0` declares `t1Builder: Instantiator<Other>` with the same label, so the types below `T0` receive `t1Builder: Instantiator<Other>` instead. Give `t1Builder: Instantiator<Other>` on `T0` a different label to fix.
			\(fixtures["T0.swift"]):8:5: note: `t1Builder: Instantiator<Other>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t1Builder() -> T1 {
			            T1()
			        }
			        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			        func __safeDI_t3Builder() -> T3 {
			            func __safeDI_t0Builder() -> T0 {
			                func __safeDI_t1Builder() -> Other {
			                    Other()
			                }
			                let t1Builder = Instantiator<Other>(__safeDI_t1Builder)
			                let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			                return T0(t1Builder: t1Builder, t3Builder: t3Builder)
			            }
			            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			            return T3(t0Builder: t0Builder, t1Builder: t1Builder)
			        }
			        let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			        self.init(t1Builder: t1Builder, t3Builder: t3Builder)
			    }
			}
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"])
	private static let t1 = seamFixtureType(named: "T1", isFinalClass: true, declarations: [])
	private static let t3 = seamFixtureType(named: "T3", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received let t1Builder: Instantiator<T1>"])
	private static let lazyCycleFixture = [
		root,
		seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"]),
		t1,
		t3,
	]
	private static let hiddenCycleFixture = [
		root,
		seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<Other>", "@Instantiated let t3Builder: Instantiator<T3>"]),
		t1,
		t3,
		seamFixtureType(named: "Other", isFinalClass: true, declarations: []),
	]

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
