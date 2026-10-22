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

import SwiftParser
import SwiftSyntax
import Testing
@testable import SafeDICore

struct FileVisitorConditionalCompilationTests {
	// MARK: Known conditions

	@Test
	func walk_scansElseClause_whenConditionIsFalse() {
		let fileVisitor = walk("""
		#if false
		@Instantiable
		public struct InactiveService {
		    public init() {}
		}
		#else
		@Instantiable
		public struct ActiveService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "ActiveService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_scansIfClause_whenActiveConditionIsTrue() {
		let fileVisitor = walk("""
		#if DEBUG
		@Instantiable
		public struct DebugService {
		    public init() {}
		}
		#else
		@Instantiable
		public struct ReleaseService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["DEBUG"])
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "DebugService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "DEBUG", isActive: true),
		])
	}

	@Test
	func walk_scansElseClause_whenNegatedActiveConditionIsFalse() {
		let fileVisitor = walk("""
		#if !DEBUG
		@Instantiable
		public struct ReleaseService {
		    public init() {}
		}
		#else
		@Instantiable
		public struct DebugService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["DEBUG"])
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "DebugService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "!DEBUG", isActive: false),
		])
	}

	@Test
	func walk_scansElseifClause_whenEarlierConditionIsFalse() {
		let fileVisitor = walk("""
		#if false
		@Instantiable
		public struct InactiveService {
		    public init() {}
		}
		#elseif STAGING && !false
		@Instantiable
		public struct StagingService {
		    public init() {}
		}
		#else
		@Instantiable
		public struct FallbackService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["STAGING"])
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "StagingService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "STAGING && !false", isActive: true),
		])
	}

	@Test
	func walk_scansNoClause_whenEveryConditionIsFalse() {
		let fileVisitor = walk("""
		#if false
		@Instantiable
		public struct InactiveService {
		    public init() {}
		}
		#elseif !DEBUG
		@Instantiable
		public struct ReleaseService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["DEBUG"])
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "!DEBUG", isActive: false),
		])
	}

	@Test
	func walk_evaluatesConjunctionAsFalse_whenOneOperandIsFalse() {
		let fileVisitor = walk("""
		#if DEBUG && false
		@Instantiable
		public struct InactiveService {
		    public init() {}
		}
		#else
		@Instantiable
		public struct ActiveService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["DEBUG"])
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "ActiveService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "DEBUG && false", isActive: false),
		])
	}

	@Test
	func walk_evaluatesDisjunctionAsTrue_whenOneOperandIsTrue() {
		let fileVisitor = walk("""
		#if DEBUG || true
		@Instantiable
		public struct ActiveService {
		    public init() {}
		}
		#else
		@Instantiable
		public struct InactiveService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "ActiveService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "DEBUG || true", isActive: true),
		])
	}

	@Test
	func walk_bindsConjunctionTighterThanDisjunction() {
		// `false && DEBUG || STAGING` is `(false && DEBUG) || STAGING`, which `STAGING` settles.
		let fileVisitor = walk("""
		#if false && DEBUG || STAGING
		@Instantiable
		public struct StagingService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["STAGING"])
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "StagingService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "false && DEBUG || STAGING", isActive: true),
		])
	}

	@Test
	func walk_evaluatesParenthesizedCondition() {
		let fileVisitor = walk("""
		#if (DEBUG || STAGING) && !false
		@Instantiable
		public struct DebugService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["DEBUG"])
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "DebugService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "(DEBUG || STAGING) && !false", isActive: true),
		])
	}

	@Test
	func walk_ignoresInactiveMember_whenConditionIsFalse() {
		let fileVisitor = walk("""
		@Instantiable
		public struct SomeService {
		    public init() {}

		    #if false
		    @Received let inactiveDependency: InactiveDependency
		    #endif
		}
		""")
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "SomeService"),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
			),
		])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	// MARK: Compiler-determined conditions

	@Test
	func walk_scansEveryClause_whenConditionDependsOnPlatform() {
		let fileVisitor = walk("""
		#if os(iOS)
		@Instantiable
		public struct TouchService {
		    public init() {}
		}
		#elseif os(macOS)
		@Instantiable
		public struct PointerService {
		    public init() {}
		}
		#else
		@Instantiable
		public struct FallbackService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [
			.simple(name: "TouchService"),
			.simple(name: "PointerService"),
			.simple(name: "FallbackService"),
		])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_scansNegatedPlatformClause() {
		let fileVisitor = walk("""
		#if !canImport(UIKit)
		@Instantiable
		public struct PointerService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "PointerService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_scansPlatformClause_whenCombinedPlatformConditionsAreUndecidable() {
		let fileVisitor = walk("""
		#if os(iOS) && targetEnvironment(simulator) || os(macOS) || os(tvOS)
		@Instantiable
		public struct SimulatorService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "SimulatorService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_scansPlatformClause_whenCompilationConditionLeavesItUndecided() {
		let fileVisitor = walk("""
		#if DEBUG && os(iOS)
		@Instantiable
		public struct DebugTouchService {
		    public init() {}
		}
		#endif
		#if os(iOS) && DEBUG
		@Instantiable
		public struct TouchDebugService {
		    public init() {}
		}
		#endif
		#if !DEBUG || os(iOS)
		@Instantiable
		public struct ReleaseOrTouchService {
		    public init() {}
		}
		#endif
		#if os(iOS) || !DEBUG
		@Instantiable
		public struct TouchOrReleaseService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["DEBUG"])
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [
			.simple(name: "DebugTouchService"),
			.simple(name: "TouchDebugService"),
			.simple(name: "ReleaseOrTouchService"),
			.simple(name: "TouchOrReleaseService"),
		])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_decidesPlatformClause_whenCompilationConditionSettlesIt() {
		let fileVisitor = walk("""
		#if DEBUG && os(iOS)
		@Instantiable
		public struct DebugTouchService {
		    public init() {}
		}
		#endif
		#if os(iOS) && DEBUG
		@Instantiable
		public struct TouchDebugService {
		    public init() {}
		}
		#endif
		#if !DEBUG || os(iOS)
		@Instantiable
		public struct ReleaseOrTouchService {
		    public init() {}
		}
		#endif
		#if os(iOS) || !DEBUG
		@Instantiable
		public struct TouchOrReleaseService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [
			.simple(name: "ReleaseOrTouchService"),
			.simple(name: "TouchOrReleaseService"),
		])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "DEBUG && os(iOS)", isActive: false),
			ConditionalCompilationDecision(condition: "os(iOS) && DEBUG", isActive: false),
			ConditionalCompilationDecision(condition: "!DEBUG || os(iOS)", isActive: true),
			ConditionalCompilationDecision(condition: "os(iOS) || !DEBUG", isActive: true),
		])
	}

	@Test
	func walk_scansFeatureFlagClause_andRecordsNoDecision() {
		let fileVisitor = walk("""
		#if $Macros
		@Instantiable
		public struct MacroService {
		    public init() {}
		}
		#endif
		#if !$Macros
		@Instantiable
		public struct LegacyService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [
			.simple(name: "MacroService"),
			.simple(name: "LegacyService"),
		])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_decidesFeatureFlagClause_whenCompilationConditionSettlesIt() {
		let fileVisitor = walk("""
		#if $Macros && DEBUG
		@Instantiable
		public struct DebugMacroService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "$Macros && DEBUG", isActive: false),
		])
	}

	// MARK: Inactive conditions guarding production declarations

	@Test
	func walk_skipsInstantiable_whenGuardingConditionIsInactive() {
		let fileVisitor = walk("""
		#if DEBUG
		@Instantiable
		public struct DebugService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "DEBUG", isActive: false),
		])
	}

	@Test
	func walk_recordsEveryMentionedCondition_whenConjunctionIsInactive() {
		let fileVisitor = walk("""
		#if STAGING && DEBUG
		@Instantiable
		public struct DebugService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["DEBUG"])
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "STAGING && DEBUG", isActive: false),
		])
	}

	@Test
	func walk_recordsEveryMentionedCondition_whenDisjunctionIsActive() {
		let fileVisitor = walk("""
		#if STAGING || DEBUG
		@Instantiable
		public struct DebugService {
		    public init() {}
		}
		#endif
		""", activeCompilationConditions: ["DEBUG"])
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "DebugService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "STAGING || DEBUG", isActive: true),
		])
	}

	@Test
	func walk_scansInstantiable_whenNegatedInactiveConditionIsTrue() {
		let fileVisitor = walk("""
		#if !DEBUG
		@Instantiable
		public struct ReleaseService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "ReleaseService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "!DEBUG", isActive: true),
		])
	}

	@Test
	func walk_recordsElseifDecision_whenEarlierClauseIsConstantFalse() {
		let fileVisitor = walk("""
		#if false
		@Instantiable
		public struct InactiveService {
		    public init() {}
		}
		#elseif STAGING
		@Instantiable
		public struct StagingService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "STAGING", isActive: false),
		])
	}

	@Test
	func walk_scansElseClause_whenInactiveConditionGuardsNoSafeDIDeclaration() {
		let fileVisitor = walk("""
		#if STAGING
		public struct PlainService {}
		#else
		@Instantiable
		public struct ProductionService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "ProductionService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "STAGING", isActive: false),
		])
	}

	@Test
	func walk_recordsDecision_whenNestedInstantiableIsGuarded() {
		let fileVisitor = walk("""
		#if STAGING
		public enum Namespace {
		    @Instantiable
		    public struct NestedService {
		        public init() {}
		    }
		}
		#endif
		""")
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "STAGING", isActive: false),
		])
	}

	@Test
	func walk_recordsDecision_whenConfigurationIsGuarded() {
		let fileVisitor = walk("""
		#if STAGING
		#SafeDIConfiguration(additionalImportedModules: ["StagingModule"])
		#endif
		""")
		#expect(fileVisitor.configurations == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "STAGING", isActive: false),
		])
	}

	@Test
	func walk_recordsDecisionOnce_whenDependencyIsGuarded() {
		let fileVisitor = walk("""
		@Instantiable
		public struct SomeService {
		    public init(debugDependency: DebugDependency) {
		        self.debugDependency = debugDependency
		    }

		    #if DEBUG
		    @Received let debugDependency: DebugDependency
		    #endif
		}
		""")
		#expect(fileVisitor.instantiables.map(\.dependencies) == [[]])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "DEBUG", isActive: false),
		])
	}

	@Test
	func walk_recordsDecisionOnce_whenBlockGuardsDependencyAndNestedInstantiable() {
		let fileVisitor = walk("""
		@Instantiable
		public struct SomeService {
		    public init(debugDependency: DebugDependency) {
		        self.debugDependency = debugDependency
		    }

		    #if DEBUG
		    @Received let debugDependency: DebugDependency

		    @Instantiable
		    public struct DebugDependency {
		        public init() {}
		    }
		    #endif
		}
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "SomeService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "DEBUG", isActive: false),
		])
	}

	@Test
	func walk_recordsDecision_whenInitializerIsGuarded() {
		let fileVisitor = walk("""
		@Instantiable
		public struct SomeService {
		    #if STAGING
		    public init() {}
		    #endif
		}
		""")
		#expect(fileVisitor.instantiables.map(\.initializer) == [nil])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "STAGING", isActive: false),
		])
	}

	@Test
	func walk_recordsDecision_whenInstantiateMethodIsGuarded() {
		let fileVisitor = walk("""
		@Instantiable
		extension SomeService {
		    #if STAGING
		    public static func instantiate() -> SomeService {
		        SomeService()
		    }
		    #endif
		}
		""")
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "STAGING", isActive: false),
		])
	}

	// MARK: Mock-only declarations

	@Test
	func walk_scansMockOnlyExtension_whenGuardedByMockConditionalCompilation() {
		let fileVisitor = walk("""
		#if DEBUG
		@Instantiable(mockOnly: true)
		extension SomeService {
		    public static func mock() -> SomeService {
		        SomeService()
		    }
		}
		#endif
		""")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "SomeService")])
		#expect(fileVisitor.instantiables.map(\.mockOnly) == [true])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_scansMockOnlyType_whenGuardedByCustomMockConditionalCompilation() {
		let fileVisitor = walk("""
		#if TESTING
		@Instantiable(mockOnly: true)
		public final class MockService {
		    public static func mock() -> MockService {
		        MockService()
		    }
		}
		#endif
		""", mockConditionalCompilation: "TESTING")
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "MockService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_scansMockOnlyMembers_whenGuardedByMockConditionalCompilation() {
		let fileVisitor = walk("""
		@Instantiable(mockOnly: true)
		public final class MockService {
		    #if DEBUG
		    public static func mock() -> MockService {
		        MockService()
		    }

		    init() {}
		    #endif
		}
		""")
		#expect(fileVisitor.instantiables.map(\.mockInitializer) == [Initializer(arguments: [])])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_scansHandWrittenMock_whenGuardedByMockConditionalCompilation() {
		let fileVisitor = walk("""
		@Instantiable(generateMock: true, customMockName: "customMock")
		public struct SomeService {
		    public init() {}

		    #if DEBUG
		    public static func customMock() -> SomeService {
		        SomeService()
		    }
		    #endif
		}
		""")
		#expect(fileVisitor.instantiables.map(\.mockInitializer) == [Initializer(arguments: [])])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_skipsHandWrittenMock_whenConditionIsFalseUnderMockConditionalCompilation() {
		let fileVisitor = walk("""
		@Instantiable(generateMock: true)
		public struct SomeService {
		    public init() {}

		    #if !DEBUG
		    public static func mock() -> SomeService {
		        SomeService()
		    }
		    #endif
		}
		""")
		#expect(fileVisitor.instantiables.map(\.mockInitializer) == [nil])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	@Test
	func walk_recordsDecision_whenMockOnlyTypeIsGuardedByOtherCondition() {
		let fileVisitor = walk("""
		#if TESTING
		@Instantiable(mockOnly: true)
		public final class MockService {
		    public static func mock() -> MockService {
		        MockService()
		    }
		}
		#endif
		""")
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "TESTING", isActive: false),
		])
	}

	@Test
	func walk_skipsMockOnlyType_whenGuardedByMockConditionalCompilationAndMocksAreUnconditional() {
		let fileVisitor = walk("""
		#if DEBUG
		@Instantiable(mockOnly: true)
		public final class MockService {
		    public static func mock() -> MockService {
		        MockService()
		    }
		}
		#endif
		""", mockConditionalCompilation: nil)
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "DEBUG", isActive: false),
		])
	}

	@Test
	func walk_skipsBlock_whenInactiveConditionGuardsBothMockOnlyAndProductionDeclarations() {
		let fileVisitor = walk("""
		#if DEBUG
		@Instantiable(mockOnly: true)
		extension SomeService {
		    public static func mock() -> SomeService {
		        SomeService()
		    }
		}

		@Instantiable
		public struct DebugService {
		    public init() {}
		}
		#endif
		""")
		#expect(fileVisitor.instantiables == [])
		#expect(fileVisitor.conditionalCompilationDecisions == [
			ConditionalCompilationDecision(condition: "DEBUG", isActive: false),
		])
	}

	// MARK: Blocks guarding nothing SafeDI scans

	@Test
	func walk_recordsNoDecision_whenInactiveConditionGuardsNoSafeDIDeclaration() {
		let fileVisitor = walk("""
		#if STAGING
		import StagingKit

		public actor PlainActor {}
		#endif

		public struct PlainService {
		    #if STAGING
		    let value = 1
		    #endif
		}

		extension PlainService {
		    #if STAGING
		    public static func instantiate() -> PlainService {
		        PlainService()
		    }
		    #endif
		}

		@Instantiable
		public struct SomeService {
		    public init() {}

		    #if STAGING
		    public func log() {}
		    let value = 1

		    enum Namespace {}
		    #endif
		}
		""")
		#expect(fileVisitor.imports == [])
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "SomeService")])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	// MARK: Scanning every clause

	@Test
	func walk_scansEveryClause_whenHandlingIsScanAllClauses() {
		let fileVisitor = walk("""
		#if DEBUG
		@Instantiable
		public struct DebugService {
		    public init(debugDependency: DebugDependency) {
		        self.debugDependency = debugDependency
		    }

		    #if DEBUG
		    @Received let debugDependency: DebugDependency
		    #endif
		}
		#elseif false
		@Instantiable
		public struct InactiveService {
		    public init() {}
		}
		#else
		@Instantiable
		public struct ReleaseService {
		    public init() {}
		}
		#endif
		""", conditionalCompilation: .scanAllClauses)
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [
			.simple(name: "DebugService"),
			.simple(name: "InactiveService"),
			.simple(name: "ReleaseService"),
		])
		#expect(fileVisitor.instantiables.map(\.dependencies.count) == [1, 0, 0])
		#expect(fileVisitor.conditionalCompilationDecisions == [])
	}

	// MARK: Private

	private func walk(
		_ source: String,
		activeCompilationConditions: Set<String> = [],
		mockConditionalCompilation: String? = "DEBUG",
	) -> FileVisitor {
		walk(source, conditionalCompilation: .evaluate(ConditionalCompilationEvaluator(
			activeCompilationConditions: activeCompilationConditions,
			mockConditionalCompilation: mockConditionalCompilation,
		)))
	}

	private func walk(_ source: String, conditionalCompilation: ConditionalCompilationHandling) -> FileVisitor {
		let fileVisitor = FileVisitor(conditionalCompilation: conditionalCompilation)
		fileVisitor.walk(Parser.parse(source: source))
		return fileVisitor
	}
}
