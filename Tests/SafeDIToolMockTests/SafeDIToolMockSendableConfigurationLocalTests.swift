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

/// A `@Sendable` builder function that builds a node with a configuration reads that whole configuration into one local
/// before it, since the configuration is `Sendable`, rather than one local per override and default it reads.
struct SafeDIToolMockSendableConfigurationLocalTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsWholeConfigurationIntoOneLocal_whenSendableBuilderBuildsConfiguredNode() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Header: Instantiable, Sendable {
				    public init(title: String = "title") {}
				}
				""",
				"""
				@Instantiable
				public final class Footer: Instantiable, Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Screen: Instantiable, Sendable {
				    public init(header: Header, footer: Footer, retries: Int = 3) {
				        self.header = header
				        self.footer = footer
				    }

				    @Instantiated let header: Header
				    @Instantiated let footer: Footer
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(screenBuilder: SendableInstantiator<Screen>) {
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let screenBuilder: SendableInstantiator<Screen>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            screenBuilder: Screen.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                screenBuilder: screenBuilder
			            )
			        }

			        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                screenBuilder: Screen.SafeDIMockConfiguration
			            ) {
			                self.screenBuilder = screenBuilder
			            }

			            let screenBuilder: Screen.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_screenBuilder__overrides = safeDIOverrides.screenBuilder
			        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
			            func __safeDI_header() -> Header {
			                return if let safeDIBuilder = __safeDI_screenBuilder__overrides.header.safeDIBuilder { safeDIBuilder(__safeDI_screenBuilder__overrides.header.title()) } else { Header(title: __safeDI_screenBuilder__overrides.header.title()) }
			            }
			            let header: Header = __safeDI_header()
			            let footer = if let safeDIBuilder = __safeDI_screenBuilder__overrides.footer { safeDIBuilder() } else { Footer() }
			            return if let safeDIBuilder = __safeDI_screenBuilder__overrides.safeDIBuilder { safeDIBuilder(header, footer, __safeDI_screenBuilder__overrides.retries()) } else { Screen(header: header, footer: footer, retries: __safeDI_screenBuilder__overrides.retries()) }
			        }
			        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
			        return Root(screenBuilder: screenBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Header {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            title: @autoclosure @escaping @Sendable () -> String = "title",
			            _ safeDIBuilder: (@Sendable (String) -> Header)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                title: title,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var title: @Sendable () -> String { __safeDI_storage.title }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (String) -> Header)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                title: @escaping @Sendable () -> String,
			                safeDIBuilder: (@Sendable (String) -> Header)?
			            ) {
			                self.title = title
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let title: @Sendable () -> String
			            let safeDIBuilder: (@Sendable (String) -> Header)?
			        }
			    }
			}

			extension Screen {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            header: Header.SafeDIMockConfiguration = .init(),
			            footer: (@Sendable () -> Footer)? = nil,
			            retries: @autoclosure @escaping @Sendable () -> Int = 3,
			            _ safeDIBuilder: (@Sendable (Header, Footer, Int) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                header: header,
			                footer: footer,
			                retries: retries,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var header: Header.SafeDIMockConfiguration { __safeDI_storage.header }
			        var footer: (@Sendable () -> Footer)? { __safeDI_storage.footer }
			        var retries: @Sendable () -> Int { __safeDI_storage.retries }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Header, Footer, Int) -> Screen)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                header: Header.SafeDIMockConfiguration,
			                footer: (@Sendable () -> Footer)?,
			                retries: @escaping @Sendable () -> Int,
			                safeDIBuilder: (@Sendable (Header, Footer, Int) -> Screen)?
			            ) {
			                self.header = header
			                self.footer = footer
			                self.retries = retries
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let header: Header.SafeDIMockConfiguration
			            let footer: (@Sendable () -> Footer)?
			            let retries: @Sendable () -> Int
			            let safeDIBuilder: (@Sendable (Header, Footer, Int) -> Screen)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
