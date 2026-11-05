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

import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

#if canImport(SafeDIMacros)
	@testable import SafeDIMacros

	/// Two spellings of `@Received(fulfilledByDependencyNamed:ofType:)` the macro rejects: a rename of another rename of
	/// the same declaration, and a rename of a dependency to itself.
	struct InstantiableMacroRenameTests {
		// MARK: A rename of another rename

		@Test
		func declaration_fixit_renamesTheFirstProperty_whenRenameRenamesAnotherRenameOfAnInheritedProperty() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        self.logger = logger
				        self.sink = sink
				    }

				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let logger: any Logger
				    @Received(fulfilledByDependencyNamed: "logger", ofType: (any Logger).self) let sink: any LogSink
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        self.logger = logger
				        self.sink = sink
				    }

				    let logger: any Logger
				    let sink: any LogSink
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`sink` is renamed from `logger`, which this declaration also renames. Rename `fileLogger`, the property the renames start from, instead.",
						line: 9,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `fileLogger` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `fileLogger` instead"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        self.logger = logger
				        self.sink = sink
				    }

				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let logger: any Logger
				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let sink: any LogSink
				}
				""",
			)
		}

		@Test
		func declaration_fixit_renamesTheFirstPropertyAtEachLaterLink_whenThreeRenamesFollowOneAnother() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(b: B, c: B, d: B) {
				        self.b = b
				        self.c = c
				        self.d = d
				    }

				    @Received(fulfilledByDependencyNamed: "a", ofType: B.self) let b: B
				    @Received(fulfilledByDependencyNamed: "b", ofType: B.self) let c: B
				    @Received(fulfilledByDependencyNamed: "c", ofType: B.self) let d: B
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(b: B, c: B, d: B) {
				        self.b = b
				        self.c = c
				        self.d = d
				    }

				    let b: B
				    let c: B
				    let d: B
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`c` is renamed from `b`, which this declaration also renames. Rename `a`, the property the renames start from, instead.",
						line: 10,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `a` instead")],
					),
					DiagnosticSpec(
						message: "`d` is renamed from `c`, which this declaration also renames. Rename `a`, the property the renames start from, instead.",
						line: 11,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `a` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `a` instead"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public init(b: B, c: B, d: B) {
				        self.b = b
				        self.c = c
				        self.d = d
				    }

				    @Received(fulfilledByDependencyNamed: "a", ofType: B.self) let b: B
				    @Received(fulfilledByDependencyNamed: "a", ofType: B.self) let c: B
				    @Received(fulfilledByDependencyNamed: "a", ofType: B.self) let d: B
				}
				""",
			)
		}

		@Test
		func declaration_fixit_renamesTheInstantiatedProperty_whenRenameRenamesARenameOfAnInstantiatedProperty() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(fileLogger: FileLogger, logger: any Logger, sink: any LogSink) {
				        self.fileLogger = fileLogger
				        self.logger = logger
				        self.sink = sink
				    }

				    @Instantiated let fileLogger: FileLogger
				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let logger: any Logger
				    @Received(fulfilledByDependencyNamed: "logger", ofType: (any Logger).self) let sink: any LogSink
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    public init(fileLogger: FileLogger, logger: any Logger, sink: any LogSink) {
				        self.fileLogger = fileLogger
				        self.logger = logger
				        self.sink = sink
				    }

				    let fileLogger: FileLogger
				    let logger: any Logger
				    let sink: any LogSink
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`sink` is renamed from `logger`, which this declaration also renames. Rename `fileLogger`, the property the renames start from, instead.",
						line: 11,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `fileLogger` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `fileLogger` instead"],
				fixedSource: """
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(fileLogger: FileLogger, logger: any Logger, sink: any LogSink) {
				        self.fileLogger = fileLogger
				        self.logger = logger
				        self.sink = sink
				    }

				    @Instantiated let fileLogger: FileLogger
				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let logger: any Logger
				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let sink: any LogSink
				}
				""",
			)
		}

		@Test
		func declaration_fixit_renamesTheInstanceOfTheLazilyInstantiatedProperty_whenRenameReadsTheInstanceOfARenamedWrapper() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, renamedService: LazilyInstantiated<Service>, other: Service) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let service: LazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "service", ofType: LazilyInstantiated<Service>.self) let renamedService: LazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "renamedService", ofType: Service.self) let other: Service
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, renamedService: LazilyInstantiated<Service>, other: Service) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    let service: LazilyInstantiated<Service>
				    let renamedService: LazilyInstantiated<Service>
				    let other: Service
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`other` is renamed from `renamedService`, which this declaration also renames. Rename `service`, the property the renames start from, instead.",
						line: 9,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `service` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `service` instead"],
				fixedSource: """
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, renamedService: LazilyInstantiated<Service>, other: Service) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let service: LazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "service", ofType: LazilyInstantiated<Service>.self) let renamedService: LazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let other: Service
				}
				""",
			)
		}

		@Test
		func declaration_throwsErrorWithoutFixit_whenALinkOfTheRenamesWrapsItsValue() {
			// Renaming `fileLogger` directly would skip the wrapper `logger` builds.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(logger: AnyLogger, sink: AnyLogger) {
				        self.logger = logger
				        self.sink = sink
				    }

				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self, erasedToConcreteExistential: true) let logger: AnyLogger
				    @Received(fulfilledByDependencyNamed: "logger", ofType: AnyLogger.self) let sink: AnyLogger
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(logger: AnyLogger, sink: AnyLogger) {
				        self.logger = logger
				        self.sink = sink
				    }

				    let logger: AnyLogger
				    let sink: AnyLogger
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`sink` is renamed from `logger`, which this declaration also renames. Rename `fileLogger`, the property the renames start from, instead, wrapping it as `logger` does with `erasedToConcreteExistential: true` if `sink` needs the wrapper.",
						line: 9,
						column: 5,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_acceptsRenames_whenTheyAreInExclusiveClausesOfOneIfBlock() {
			// No evaluation selects both clauses: under `#else`, `sink` renames the `logger` its type receives.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    #if FILE_LOGGING
				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let logger: any Logger
				    #else
				    @Received(fulfilledByDependencyNamed: "logger", ofType: (any Logger).self) let sink: any LogSink
				    #endif
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    #if FILE_LOGGING
				    let logger: any Logger
				    #else
				    let sink: any LogSink
				    #endif
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWithoutFixitAtEachRename_whenRenamesFulfillOneAnother() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Middle: Instantiable {
				    public init(y: X, x: X) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self) private let y: X
				    @Received(fulfilledByDependencyNamed: "y", ofType: X.self) private let x: X
				}
				""",
				expandedSource: """
				public struct Middle: Instantiable {
				    public init(y: X, x: X) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    private let y: X
				    private let x: X
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`y` is renamed from `x`, which this declaration also renames. These renames are fulfilled by one another, so none of them is ever created. Rename a property this declaration does not rename.",
						line: 7,
						column: 5,
						severity: .error,
					),
					DiagnosticSpec(
						message: "`x` is renamed from `y`, which this declaration also renames. These renames are fulfilled by one another, so none of them is ever created. Rename a property this declaration does not rename.",
						line: 8,
						column: 5,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_copiesTheFirstRenamesTypeAsSpelled_whenItsTypeIsExistentialNestedAliasedOrOptional() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(first1: any Logger, second1: any Logger, first2: Outer.Inner, second2: Outer.Inner, first3: LoggerAlias, second3: LoggerAlias, first4: (any Logger)?, second4: (any Logger)?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received(fulfilledByDependencyNamed: "source1", ofType: (any Logger).self) let first1: any Logger
				    @Received(fulfilledByDependencyNamed: "first1", ofType: (any Logger).self) let second1: any Logger
				    @Received(fulfilledByDependencyNamed: "source2", ofType: Outer.Inner.self) let first2: Outer.Inner
				    @Received(fulfilledByDependencyNamed: "first2", ofType: Outer.Inner.self) let second2: Outer.Inner
				    @Received(fulfilledByDependencyNamed: "source3", ofType: LoggerAlias.self) let first3: LoggerAlias
				    @Received(fulfilledByDependencyNamed: "first3", ofType: LoggerAlias.self) let second3: LoggerAlias
				    @Received(fulfilledByDependencyNamed: "source4", ofType: (any Logger)?.self) let first4: (any Logger)?
				    @Received(fulfilledByDependencyNamed: "first4", ofType: (any Logger)?.self) let second4: (any Logger)?
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(first1: any Logger, second1: any Logger, first2: Outer.Inner, second2: Outer.Inner, first3: LoggerAlias, second3: LoggerAlias, first4: (any Logger)?, second4: (any Logger)?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    let first1: any Logger
				    let second1: any Logger
				    let first2: Outer.Inner
				    let second2: Outer.Inner
				    let first3: LoggerAlias
				    let second3: LoggerAlias
				    let first4: (any Logger)?
				    let second4: (any Logger)?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`second1` is renamed from `first1`, which this declaration also renames. Rename `source1`, the property the renames start from, instead.",
						line: 8,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `source1` instead")],
					),
					DiagnosticSpec(
						message: "`second2` is renamed from `first2`, which this declaration also renames. Rename `source2`, the property the renames start from, instead.",
						line: 10,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `source2` instead")],
					),
					DiagnosticSpec(
						message: "`second3` is renamed from `first3`, which this declaration also renames. Rename `source3`, the property the renames start from, instead.",
						line: 12,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `source3` instead")],
					),
					DiagnosticSpec(
						message: "`second4` is renamed from `first4`, which this declaration also renames. Rename `source4`, the property the renames start from, instead.",
						line: 14,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `source4` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `source1` instead", "Rename `source2` instead", "Rename `source3` instead", "Rename `source4` instead"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public init(first1: any Logger, second1: any Logger, first2: Outer.Inner, second2: Outer.Inner, first3: LoggerAlias, second3: LoggerAlias, first4: (any Logger)?, second4: (any Logger)?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received(fulfilledByDependencyNamed: "source1", ofType: (any Logger).self) let first1: any Logger
				    @Received(fulfilledByDependencyNamed: "source1", ofType: (any Logger).self) let second1: any Logger
				    @Received(fulfilledByDependencyNamed: "source2", ofType: Outer.Inner.self) let first2: Outer.Inner
				    @Received(fulfilledByDependencyNamed: "source2", ofType: Outer.Inner.self) let second2: Outer.Inner
				    @Received(fulfilledByDependencyNamed: "source3", ofType: LoggerAlias.self) let first3: LoggerAlias
				    @Received(fulfilledByDependencyNamed: "source3", ofType: LoggerAlias.self) let second3: LoggerAlias
				    @Received(fulfilledByDependencyNamed: "source4", ofType: (any Logger)?.self) let first4: (any Logger)?
				    @Received(fulfilledByDependencyNamed: "source4", ofType: (any Logger)?.self) let second4: (any Logger)?
				}
				""",
			)
		}

		@Test
		func declaration_throwsError_whenOneRenameIsOutsideTheIfBlockAndTheOtherInAClause() {
			// An evaluation that selects the clause forms the chain.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let logger: any Logger
				    #if SINK
				    @Received(fulfilledByDependencyNamed: "logger", ofType: (any Logger).self) let sink: any LogSink
				    #endif
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    let logger: any Logger
				    #if SINK
				    let sink: any LogSink
				    #endif
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`sink` is renamed from `logger`, which this declaration also renames. Rename `fileLogger`, the property the renames start from, instead.",
						line: 9,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `fileLogger` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `fileLogger` instead"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let logger: any Logger
				    #if SINK
				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let sink: any LogSink
				    #endif
				}
				""",
			)
		}

		@Test
		func declaration_throwsError_whenRenamesAreInOneClauseOrOnOneNestedClausePath() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(b: B, c: B, e: E, f: E) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    #if FIRST
				    @Received(fulfilledByDependencyNamed: "a", ofType: B.self) let b: B
				    @Received(fulfilledByDependencyNamed: "b", ofType: B.self) let c: B
				    #elseif SECOND
				    @Received(fulfilledByDependencyNamed: "d", ofType: E.self) let e: E
				    #if THIRD
				    @Received(fulfilledByDependencyNamed: "e", ofType: E.self) let f: E
				    #endif
				    #endif
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(b: B, c: B, e: E, f: E) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    #if FIRST
				    let b: B
				    let c: B
				    #elseif SECOND
				    let e: E
				    #if THIRD
				    let f: E
				    #endif
				    #endif
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`c` is renamed from `b`, which this declaration also renames. Rename `a`, the property the renames start from, instead.",
						line: 9,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `a` instead")],
					),
					DiagnosticSpec(
						message: "`f` is renamed from `e`, which this declaration also renames. Rename `d`, the property the renames start from, instead.",
						line: 13,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `d` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `a` instead", "Rename `d` instead"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public init(b: B, c: B, e: E, f: E) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    #if FIRST
				    @Received(fulfilledByDependencyNamed: "a", ofType: B.self) let b: B
				    @Received(fulfilledByDependencyNamed: "a", ofType: B.self) let c: B
				    #elseif SECOND
				    @Received(fulfilledByDependencyNamed: "d", ofType: E.self) let e: E
				    #if THIRD
				    @Received(fulfilledByDependencyNamed: "d", ofType: E.self) let f: E
				    #endif
				    #endif
				}
				""",
			)
		}

		@Test
		func declaration_acceptsRenames_whenTheyAreInTwoIndependentIfBlocks() {
			// Whether both blocks are active is the compiler's to decide; SafeDITool reports the chain when it evaluates both.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    #if FILE_LOGGING
				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let logger: any Logger
				    #endif
				    #if SINK
				    @Received(fulfilledByDependencyNamed: "logger", ofType: (any Logger).self) let sink: any LogSink
				    #endif
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    #if FILE_LOGGING
				    let logger: any Logger
				    #endif
				    #if SINK
				    let sink: any LogSink
				    #endif
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_renamesTheFirstPropertyOnlyIfAvailable_whenRequiredRenameRenamesAnOnlyIfAvailableRename() {
			// `a` is `nil` where `x` is unavailable, and so is `b`: the fixed-up `b` receives `x` only if available too.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(a: X?, b: X?) {
				        self.a = a
				        self.b = b
				    }

				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let a: X?
				    @Received(fulfilledByDependencyNamed: "a", ofType: X?.self) let b: X?
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(a: X?, b: X?) {
				        self.a = a
				        self.b = b
				    }

				    let a: X?
				    let b: X?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`b` is renamed from `a`, which this declaration also renames. Rename `x`, the property the renames start from, instead.",
						line: 9,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `x` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `x` instead"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public init(a: X?, b: X?) {
				        self.a = a
				        self.b = b
				    }

				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let a: X?
				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let b: X?
				}
				""",
			)
		}

		@Test
		func declaration_fixit_keepsOnlyIfAvailable_whenOnlyIfAvailableRenameRenamesAnOnlyIfAvailableRename() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(a: X?, b: X?) {
				        self.a = a
				        self.b = b
				    }

				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let a: X?
				    @Received(fulfilledByDependencyNamed: "a", ofType: X?.self, onlyIfAvailable: true) let b: X?
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(a: X?, b: X?) {
				        self.a = a
				        self.b = b
				    }

				    let a: X?
				    let b: X?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`b` is renamed from `a`, which this declaration also renames. Rename `x`, the property the renames start from, instead.",
						line: 9,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `x` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `x` instead"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public init(a: X?, b: X?) {
				        self.a = a
				        self.b = b
				    }

				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let a: X?
				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let b: X?
				}
				""",
			)
		}

		@Test
		func declaration_throwsErrorWithoutFixit_whenTheRenamesHoldAnOnlyIfAvailableLinkAndAWrappingLink() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(a: AnyX?, b: AnyX?) {
				        self.a = a
				        self.b = b
				    }

				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let a: AnyX?
				    @Received(fulfilledByDependencyNamed: "a", ofType: AnyX?.self) let b: AnyX?
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(a: AnyX?, b: AnyX?) {
				        self.a = a
				        self.b = b
				    }

				    let a: AnyX?
				    let b: AnyX?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`b` is renamed from `a`, which this declaration also renames. Rename `x`, the property the renames start from, instead, wrapping it as `a` does with `erasedToConcreteExistential: true` if `b` needs the wrapper.",
						line: 9,
						column: 5,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWithoutFixit_whenARenameOfAnOnlyIfAvailableRenameIsNotOptional() {
			// Renaming `x` only if available makes `b` optional, which its declaration is not.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(a: X?, b: X) {
				        self.a = a
				        self.b = b
				    }

				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let a: X?
				    @Received(fulfilledByDependencyNamed: "a", ofType: X?.self) let b: X
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(a: X?, b: X) {
				        self.a = a
				        self.b = b
				    }

				    let a: X?
				    let b: X
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`b` is renamed from `a`, which this declaration also renames. Rename `x`, the property the renames start from, instead; since `a` receives it only if available, declare `b` optional and rename `x` with `onlyIfAvailable: true`.",
						line: 9,
						column: 5,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWithoutFixit_whenRenameRenamesARenameThatKeepsItsLabel() {
			// `token` is the closest declaration of its label, so `bearer` cannot name the `token` the type receives.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(token: (any Auth)?, bearer: (any Auth)?) {
				        self.token = token
				        self.bearer = bearer
				    }

				    @Received(fulfilledByDependencyNamed: "token", ofType: Secret.self, onlyIfAvailable: true) let token: (any Auth)?
				    @Received(fulfilledByDependencyNamed: "token", ofType: (any Auth)?.self) let bearer: (any Auth)?
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(token: (any Auth)?, bearer: (any Auth)?) {
				        self.token = token
				        self.bearer = bearer
				    }

				    let token: (any Auth)?
				    let bearer: (any Auth)?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`bearer` is renamed from `token`, which this declaration also renames. Rename the property the renames start from instead.",
						line: 9,
						column: 5,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_setsOnlyIfAvailableToTrue_whenRenameSpellsItFalseAndRenamesAnOnlyIfAvailableRename() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(a: X?, b: X?) {
				        self.a = a
				        self.b = b
				    }

				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let a: X?
				    @Received(fulfilledByDependencyNamed: "a", ofType: X?.self, onlyIfAvailable: false) let b: X?
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(a: X?, b: X?) {
				        self.a = a
				        self.b = b
				    }

				    let a: X?
				    let b: X?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`b` is renamed from `a`, which this declaration also renames. Rename `x`, the property the renames start from, instead.",
						line: 9,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `x` instead")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `x` instead"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public init(a: X?, b: X?) {
				        self.a = a
				        self.b = b
				    }

				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let a: X?
				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let b: X?
				}
				""",
			)
		}

		@Test
		func declaration_throwsErrorWithoutFixit_whenTheRenamedRenameIsDeclaredInEachClauseOfAnIfBlock() {
			// `b` renames whichever `a` the compiler selects, so no one property is where the renames start. The macro reads
			// both declarations of `a`, which no initializer can take, as it would for any label declared in two clauses.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(a: X, b: X) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    #if FIRST
				    @Received(fulfilledByDependencyNamed: "x", ofType: X.self) let a: X
				    #else
				    @Received(fulfilledByDependencyNamed: "y", ofType: X.self) let a: X
				    #endif
				    @Received(fulfilledByDependencyNamed: "a", ofType: X.self) let b: X
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(a: X, b: X) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    #if FIRST
				    let a: X
				    #else
				    let a: X
				    #endif
				    let b: X
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`b` is renamed from `a`, which this declaration also renames. Rename the property the renames start from instead.",
						line: 12,
						column: 5,
						severity: .error,
					),
					// Two declarations of `a` hold in no one evaluation, and the macro reads both.
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `a: X`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Add arguments for a: X")],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWithoutFixit_whenRenameReadsTheRenameItRenamesAsAnotherType() {
			// `sink` reads `logger` as `FileLogger`, which `logger` is not declared as, so no type to rename `fileLogger` as follows.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        self.logger = logger
				        self.sink = sink
				    }

				    @Received(fulfilledByDependencyNamed: "fileLogger", ofType: FileLogger.self) let logger: any Logger
				    @Received(fulfilledByDependencyNamed: "logger", ofType: FileLogger.self) let sink: any LogSink
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(logger: any Logger, sink: any LogSink) {
				        self.logger = logger
				        self.sink = sink
				    }

				    let logger: any Logger
				    let sink: any LogSink
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`sink` is renamed from `logger`, which this declaration also renames. Rename the property the renames start from instead.",
						line: 9,
						column: 5,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_acceptsRenameOfARenameOfItsParent() {
			// A rename of a property another type renames is a receive of that type's rename.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(sink: any LogSink) {
				        self.sink = sink
				    }

				    @Received(fulfilledByDependencyNamed: "logger", ofType: (any Logger).self) let sink: any LogSink
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public init(sink: any LogSink) {
				        self.sink = sink
				    }

				    let sink: any LogSink
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: A rename of a dependency to itself

		@Test
		func declaration_fixit_receivesOnlyIfAvailable_whenRenameKeepsItsLabelAndMakesItsTypeOptionalOnlyIfAvailable() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self, onlyIfAvailable: true) private let session: Session?
				}
				""",
				expandedSource: """
				public final class Profile: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    private let session: Session?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`session` is renamed from itself, made optional only if available, which is what `@Received(onlyIfAvailable: true)` does. Receive it with `@Received(onlyIfAvailable: true)`.",
						line: 7,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Replace with `@Received(onlyIfAvailable: true)`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace with `@Received(onlyIfAvailable: true)`"],
				fixedSource: """
				@Instantiable
				public final class Profile: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received(onlyIfAvailable: true) private let session: Session?
				}
				""",
			)
		}

		@Test
		func declaration_fixit_receivesOnlyIfAvailable_whenRenameKeepsItsLabelAndItsOptionalTypeOnlyIfAvailable() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received(fulfilledByDependencyNamed: "session", ofType: Session?.self, onlyIfAvailable: true) let session: Session?
				}
				""",
				expandedSource: """
				public final class Profile: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    let session: Session?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`session` is renamed from itself, made optional only if available, which is what `@Received(onlyIfAvailable: true)` does. Receive it with `@Received(onlyIfAvailable: true)`.",
						line: 7,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Replace with `@Received(onlyIfAvailable: true)`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace with `@Received(onlyIfAvailable: true)`"],
				fixedSource: """
				@Instantiable
				public final class Profile: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received(onlyIfAvailable: true) let session: Session?
				}
				""",
			)
		}

		@Test
		func declaration_fixit_receivesOnlyIfAvailable_whenRenameKeepsItsLabelAndMakesItsExistentialTypeOptionalOnlyIfAvailable() {
			// `any` is no part of what makes two types the same.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(auth: (any Auth)?) {
				        self.auth = auth
				    }

				    @Received(fulfilledByDependencyNamed: "auth", ofType: Auth.self, onlyIfAvailable: true) let auth: (any Auth)?
				}
				""",
				expandedSource: """
				public final class Profile: Instantiable {
				    public init(auth: (any Auth)?) {
				        self.auth = auth
				    }

				    let auth: (any Auth)?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`auth` is renamed from itself, made optional only if available, which is what `@Received(onlyIfAvailable: true)` does. Receive it with `@Received(onlyIfAvailable: true)`.",
						line: 7,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Replace with `@Received(onlyIfAvailable: true)`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace with `@Received(onlyIfAvailable: true)`"],
				fixedSource: """
				@Instantiable
				public final class Profile: Instantiable {
				    public init(auth: (any Auth)?) {
				        self.auth = auth
				    }

				    @Received(onlyIfAvailable: true) let auth: (any Auth)?
				}
				""",
			)
		}

		@Test
		func declaration_acceptsRename_whenItKeepsItsLabelAndChangesItsType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(token: (any Auth)?, session: Session?) {
				        self.token = token
				        self.session = session
				    }

				    @Received(fulfilledByDependencyNamed: "token", ofType: Secret.self, onlyIfAvailable: true) let token: (any Auth)?
				    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self) let session: Session?
				}
				""",
				expandedSource: """
				public final class Profile: Instantiable {
				    public init(token: (any Auth)?, session: Session?) {
				        self.token = token
				        self.session = session
				    }

				    let token: (any Auth)?
				    let session: Session?
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_acceptsRename_whenItChangesItsLabelAndKeepsItsType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(currentSession: Session?) {
				        self.currentSession = currentSession
				    }

				    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self, onlyIfAvailable: true) let currentSession: Session?
				}
				""",
				expandedSource: """
				public final class Profile: Instantiable {
				    public init(currentSession: Session?) {
				        self.currentSession = currentSession
				    }

				    let currentSession: Session?
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_acceptsRename_whenItKeepsItsLabelAndWrapsItsTypeOnlyIfAvailable() {
			// The wrapper is what the rename adds: `session` is `Session(session)` where the received `session` is available.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let session: Session?
				}
				""",
				expandedSource: """
				public final class Profile: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    let session: Session?
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_receivesTheDependency_whenRenameKeepsItsLabelAndItsType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(session: Session) { self.session = session }
				    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self) private let session: Session
				}
				""",
				expandedSource: """
				public struct Profile: Instantiable {
				    public init(session: Session) { self.session = session }
				    private let session: Session
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`session` is renamed from itself with the same type, which renames nothing. Receive it with `@Received`.",
						line: 4,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Replace with `@Received`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace with `@Received`"],
				fixedSource: """
				@Instantiable
				public struct Profile: Instantiable {
				    public init(session: Session) { self.session = session }
				    @Received private let session: Session
				}
				""",
			)
		}

		@Test
		func declaration_fixit_receivesTheDependency_whenRequiredRenameKeepsItsLabelAndItsOptionalType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(session: Session?) { self.session = session }
				    @Received(fulfilledByDependencyNamed: "session", ofType: Session?.self, onlyIfAvailable: false) let session: Session?
				}
				""",
				expandedSource: """
				public struct Profile: Instantiable {
				    public init(session: Session?) { self.session = session }
				    let session: Session?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`session` is renamed from itself with the same type, which renames nothing. Receive it with `@Received`.",
						line: 4,
						column: 5,
						severity: .error,
						fixIts: [FixItSpec(message: "Replace with `@Received`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace with `@Received`"],
				fixedSource: """
				@Instantiable
				public struct Profile: Instantiable {
				    public init(session: Session?) { self.session = session }
				    @Received let session: Session?
				}
				""",
			)
		}

		@Test
		func declaration_throwsErrorWithoutFixit_whenRenameKeepsItsLabelAndItsTypeAndWrapsItself() {
			// Dropping the arguments would drop the wrapper too, so the remedy is left to whoever wrote it.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(session: AnySession) { self.session = session }
				    @Received(fulfilledByDependencyNamed: "session", ofType: AnySession.self, erasedToConcreteExistential: true) let session: AnySession
				}
				""",
				expandedSource: """
				public struct Profile: Instantiable {
				    public init(session: AnySession) { self.session = session }
				    let session: AnySession
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`session` is renamed from itself with the same type, which renames nothing, and `erasedToConcreteExistential: true` would wrap it in itself. Receive it with `@Received`.",
						line: 4,
						column: 5,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}
	}
#endif
