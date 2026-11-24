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

/// A module’s own dependency tree that builds one type at several places, which a builder function shared between the
/// places must hand the value each place is handed today. The test compiles the fixture with the code generated from
/// it and runs it, so a seam that shares one builder function per type changes only the expected text here.
struct SafeDIToolSeamSharedBuilderTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	/// A type whose module generates its own dependency tree, which receives a session from its caller. The session is
	/// created when the tree first reads it. One reader of it is built in three places: by a builder at the top, by a
	/// builder beneath a type that instantiates a session of its own, and by value inside a type a builder builds.
	///
	/// From the review that tried to break shared builder functions: the probe reports which token, identifier, clock,
	/// session or override each place was handed, and the expected lines are what each place is handed today.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsCallersSessionAtFirstRead_whenSeamTreeReadsDeferredSessionAtThreePlaces() async throws {
		let fixtureFiles = [
			"Feature.swift": """
			@Instantiable(generateDependencyTree: true)
			public final class Feature: Instantiable {
				public init(screenBuilder: Instantiator<Screen>, panel: Panel, subBuilder: Instantiator<Sub>) {
					self.screenBuilder = screenBuilder
					self.panel = panel
					self.subBuilder = subBuilder
				}

				@Instantiated let screenBuilder: Instantiator<Screen>
				@Instantiated let panel: Panel
				@Instantiated let subBuilder: Instantiator<Sub>
			}

			@Instantiable
			public final class Panel: Instantiable {
				public init(session: Session, screenBuilder: Instantiator<Screen>) {
					self.session = session
					self.screenBuilder = screenBuilder
				}

				@Instantiated let session: Session
				@Instantiated let screenBuilder: Instantiator<Screen>
			}

			@Instantiable
			public final class Sub: Instantiable {
				public init(screen: Screen) {
					self.screen = screen
				}

				@Instantiated let screen: Screen
			}

			@Instantiable
			public final class Screen: Instantiable {
				public init(session: Session) {
					self.session = session
				}

				@Received let session: Session
			}

			@Instantiable
			public final class Session: Instantiable {
				public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Feature+SafeDI.swift": generatedFileHeader + """
			extension Feature {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_session __safeDI_session_: @autoclosure @escaping () -> Session) {
			        let session = LazilyInstantiated<Session>(__safeDI_session_)
			        func __safeDI_screenBuilder() -> Screen {
			            Screen(session: session.instance)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        func __safeDI_panel() -> Panel {
			            let session = Session()
			            func __safeDI_screenBuilder() -> Screen {
			                Screen(session: session)
			            }
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			            return Panel(session: session, screenBuilder: screenBuilder)
			        }
			        let panel: Panel = __safeDI_panel()
			        func __safeDI_subBuilder() -> Sub {
			            let screen = Screen(session: session.instance)
			            return Sub(screen: screen)
			        }
			        let subBuilder = Instantiator<Sub>(__safeDI_subBuilder)
			        self.init(screenBuilder: screenBuilder, panel: panel, subBuilder: subBuilder)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_1E2B55CC1D77755A {}
			}
			""",
		])
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "what each place was handed",
					expression: #"""
					{ () -> [String] in
						var lines = [String]()
						func report(_ name: String, _ value: some Any) { lines.append("\(name): \(value)") }

						var created = 0
						func makeSession() -> Session {
							created += 1
							return Session()
						}

						let feature = Feature(__safeDI_session: makeSession())
						report("sessions created once the tree is built", created)
						let panelScreen = feature.panel.screenBuilder.instantiate()
						report("the panel's screen reads the panel's session", panelScreen.session === feature.panel.session)
						report("sessions created after the panel's screen", created)
						let screen = feature.screenBuilder.instantiate()
						report("sessions created after the top screen", created)
						let sub = feature.subBuilder.instantiate()
						report("sessions created after the sub", created)
						report("the top screen and the sub's screen share the caller's session", screen.session === sub.screen.session)
						report("the caller's session is not the panel's", screen.session !== feature.panel.session)
						report("a second top screen shares it too", feature.screenBuilder.instantiate().session === screen.session)
						report("sessions created at the end", created)
						return lines
					}()
					"""#,
					knownRightExpression: #"""
					[
						"sessions created once the tree is built: 0",
						"the panel's screen reads the panel's session: true",
						"sessions created after the panel's screen: 0",
						"sessions created after the top screen: 1",
						"sessions created after the sub: 1",
						"the top screen and the sub's screen share the caller's session: true",
						"the caller's session is not the panel's: true",
						"a second top screen shares it too: true",
						"sessions created at the end: 1",
					]
					"""#,
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
