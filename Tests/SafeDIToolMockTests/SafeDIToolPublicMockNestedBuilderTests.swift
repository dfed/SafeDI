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

/// A public mock takes one builder per hole type and family over an enum of the places its tree builds, as a seam does, and
/// a module that calls it fills each place it can and passes the others up.
struct SafeDIToolPublicMockNestedBuilderTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the declaring module

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderOverAnEnumOfItsPlaces_whenPublicMockBuildsTwoPlacesUnderOneLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [Self.screen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    @frozen public enum SafeDIMockScope_Service {
		        case row_service(row_service_Values)
		        case service(service_Values)

		        public struct row_service_Values {
		            public let token: Token
		        }

		        public struct service_Values {
		            public let row: Row
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            row: __safeDI_Core_Row_MockConfiguration = .init()
		        ) {
		            self.row = row
		        }

		        public private(set) var row: __safeDI_Core_Row_MockConfiguration
		    }

		    public static func mock(
		        serviceBuilder: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        let __safeDI_serviceBuilder = serviceBuilder
		        func __safeDI_row() -> Row {
		            let token = if let safeDIBuilder = safeDIOverrides.row.token { safeDIBuilder() } else { Token() }
		            let service: any Service = __safeDI_serviceBuilder(.row_service(SafeDIMockScope_Service.row_service_Values(token: token)))
		            return Row.__safeDI_init(token: token, service: service, safeDIBuilder: safeDIOverrides.row.safeDIBuilder)
		        }
		        let row: Row = __safeDI_row()
		        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIMockScope_Service.service_Values(row: row)))
		        return Panel(row: row, service: service)
		    }
		}

		extension Panel {
		    public enum \(Self.panelGuard) {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Row` is constructed within the public mock trees of module `Core`.
		public struct __safeDI_Core_Row_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        _ safeDIBuilder: ((Token, any Service) -> Row)? = nil
		    ) {
		        self.token = token
		        self.safeDIBuilder = safeDIBuilder
		    }

		    public private(set) var token: (() -> Token)?
		    /// Overrides how `Row` is constructed. Parameters match the type’s initializer or custom mock method.
		    public private(set) var safeDIBuilder: ((Token, any Service) -> Row)?
		}

		extension Row {
		    static func __safeDI_init(token: Token, service: any Service, safeDIBuilder: ((Token, any Service) -> Row)?) -> Row {
		        if let safeDIBuilder { safeDIBuilder(token, service) } else { Row(token: token, service: service) }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesHandWrittenCallerThatSwitchesOverTheEnum_whenAModuleCallsAPublicMockByHand() async throws {
		_ = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			"""
			import Core

			struct StubService: Service {
			    let name: String
			}

			func panel() -> Panel {
			    Panel.mock(serviceBuilder: { scope in
			        switch scope {
			        case let .row_service(values): StubService(name: "row \\(ObjectIdentifier(values.token))")
			        case let .service(values): StubService(name: "panel beside \\(values.row)")
			        }
			    })
			}

			func ignoringTheScope() -> Panel {
			    Panel.mock(serviceBuilder: { _ in StubService(name: "any") })
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
	}

	// MARK: Tests – an internal caller

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEveryPlaceWithADispatcher_whenInternalCallerSeesATypeThatFulfillsTheHole() async throws {
		let modules = Self.modules(app: [Self.screen, Self.defaultService])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		\(Self.screenPrelude)
		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_panel() -> Panel {
		            func __safeDI_serviceBuilder_Panel(_ scope: Panel.SafeDIMockScope_Service) -> any Service {
		                switch scope {
		                case .row_service:
		                    let service: any Service = DefaultService()
		                    return service
		                case .service:
		                    let service: any Service = DefaultService()
		                    return service
		                }
		            }
		            _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		            return Panel.mock(serviceBuilder: __safeDI_serviceBuilder_Panel, safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(panel: panel)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTheCalledMocksBuilderAsAFlatParameter_whenInternalCallerSeesNoTypeThatFulfillsTheHole() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [Self.screen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.screenTakingTheBuilder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesUpThePlacesItCannotFill_whenInternalCallerFillsSomePlacesOfAnEnum() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [Self.screen, Self.defaultServiceReceivingToken]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		\(Self.screenPrelude)
		    static func mock(
		        serviceBuilder: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_panel() -> Panel {
		            func __safeDI_serviceBuilder_Panel_row_service(_ scope: Panel.SafeDIMockScope_Service.row_service_Values) -> any Service {
		                let token = scope.token
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Panel(_ scope: Panel.SafeDIMockScope_Service, passUp: () -> any Service) -> any Service {
		                switch scope {
		                case let .row_service(scope): return __safeDI_serviceBuilder_Panel_row_service(scope)
		                case .service: return passUp()
		                }
		            }
		            _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		            return Panel.mock(serviceBuilder: { scope in __safeDI_serviceBuilder_Panel(scope, passUp: { serviceBuilder(scope) }) }, safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(panel: panel)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesUpThePlaceAFillWouldCallAPartlyFilledMockFor_whenTheFulfillersTreeCallsAPublicMockWithAnUnfilledPlace() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(core: [Self.gadget], app: [
			Self.screen,
			"""
			import Core
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [Service.self])
			public struct DefaultService: Service, Instantiable {
			    public init(gadget: Gadget) {
			        self.gadget = gadget
			    }

			    @Instantiated let gadget: Gadget
			}

			@Instantiable(fulfillingAdditionalTypes: [Widget.self])
			public struct DefaultWidget: Widget, Instantiable {
			    public init() {}
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		// The fill of either place would call `Gadget`'s mock, whose `gizmo` `App` cannot fill, so both pass up.
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.screenTakingTheBuilder])
	}

	// MARK: Tests – a public caller

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsTheCalledMocksEnumInACaseOfEachFamily_whenPublicCallerCallsItInPlainCodeAndInASendableFunction() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [Self.board], app: [Self.boardScreen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		\(Self.boardPrelude)
		    public static func mock(
		        serviceBuilder: @escaping (Board.SafeDIMockScope_Service) -> any Service,
		        serviceSendableBuilder: @escaping @Sendable (Board.SafeDISendableMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let __safeDI_serviceBuilder = serviceBuilder
		        let __safeDI_serviceSendableBuilder = serviceSendableBuilder
		        _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		        let panel = Panel.mock(serviceBuilder: { __safeDI_serviceBuilder(.panel($0)) }, safeDIOverrides: safeDIOverrides.panel)
		        _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		        let __safeDI_held__safeDIBuilder = safeDIOverrides.held
		        @Sendable func __safeDI_held() -> Panel {
		            Panel.mock(serviceBuilder: { __safeDI_serviceSendableBuilder(.held($0)) }, safeDIOverrides: __safeDI_held__safeDIBuilder?() ?? .init())
		        }
		        let held = SendableInstantiator<Panel>(__safeDI_held)
		        return Board(panel: panel, held: held)
		    }
		}

		extension Board {
		    public enum \(Self.boardGuard) {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesEachPassedUpBuilderSendableOnce_whenInternalCallerBuildsAPublicCallerInASendableFunction() async throws {
		// `BoardScreen` builds `Board` in a `@Sendable` builder function, which captures both builders `Board`'s mock passes
		// up: the plain family's, which `BoardScreen`'s mock takes `@Sendable`, and the `@Sendable` family's, which is
		// `@Sendable` already.
		let heldBoardScreen = """
		import Core
		import Mid
		import SafeDI

		@Instantiable(generateMock: true)
		public struct BoardScreen: Instantiable {
		    public init(board: SendableInstantiator<Board>) {
		        self.board = board
		    }

		    @Instantiated let board: SendableInstantiator<Board>
		}
		"""
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [Self.board], app: [heldBoardScreen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension BoardScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            board: (@Sendable () -> Board.SafeDIOverrides)? = nil
		        ) {
		            self.board = board
		        }

		        private(set) var board: (@Sendable () -> Board.SafeDIOverrides)?
		    }

		    static func mock(
		        serviceBuilder: @escaping @Sendable (Board.SafeDIMockScope_Service) -> any Service,
		        serviceSendableBuilder: @escaping @Sendable (Board.SafeDISendableMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> BoardScreen {
		        _ = Board.\(Self.boardGuard).self\(Self.comment("Mid"))
		        let __safeDI_board__safeDIBuilder = safeDIOverrides.board
		        @Sendable func __safeDI_board() -> Board {
		            Board.mock(serviceBuilder: serviceBuilder, serviceSendableBuilder: serviceSendableBuilder, safeDIOverrides: __safeDI_board__safeDIBuilder?() ?? .init())
		        }
		        let board = SendableInstantiator<Board>(__safeDI_board)
		        return BoardScreen(board: board)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsThroughBothFamiliesDispatchers_whenCallerOfAPublicCallerSeesATypeThatFulfillsTheHole() async throws {
		let modules = Self.modules(mid: [Self.board], app: [Self.boardScreen, Self.defaultService])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension BoardScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            board: Board.SafeDIOverrides = .init()
		        ) {
		            self.board = board
		        }

		        private(set) var board: Board.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> BoardScreen {
		        func __safeDI_board() -> Board {
		            func __safeDI_serviceBuilder_Board(_ scope: Board.SafeDIMockScope_Service) -> any Service {
		                switch scope {
		                case let .panel(scope): return __safeDI_serviceBuilder_Panel(scope)
		                }
		            }
		            @Sendable func __safeDI_serviceBuilder_Panel(_ scope: Panel.SafeDIMockScope_Service) -> any Service {
		                switch scope {
		                case .row_service:
		                    let service: any Service = DefaultService()
		                    return service
		                case .service:
		                    let service: any Service = DefaultService()
		                    return service
		                }
		            }
		            @Sendable func __safeDI_serviceSendableBuilder_Board(_ scope: Board.SafeDISendableMockScope_Service) -> any Service {
		                switch scope {
		                case let .held(scope): return __safeDI_serviceBuilder_Panel(scope)
		                }
		            }
		            _ = Board.\(Self.boardGuard).self\(Self.comment("Mid"))
		            return Board.mock(serviceBuilder: __safeDI_serviceBuilder_Board, serviceSendableBuilder: __safeDI_serviceSendableBuilder_Board, safeDIOverrides: safeDIOverrides.board)
		        }
		        let board: Board = __safeDI_board()
		        return BoardScreen(board: board)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("BoardScreen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesTheWholeScopeUpUnderTheRoutesCase_whenPublicCallerFillsSomePlacesOfTheCalledMock() async throws {
		let modules = Self.modules(mid: [Self.board, Self.defaultServiceReceivingToken], app: [Self.boardScreen])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		\(Self.boardPrelude)
		    public static func mock(
		        serviceBuilder: @escaping (Board.SafeDIMockScope_Service) -> any Service,
		        serviceSendableBuilder: @escaping @Sendable (Board.SafeDISendableMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let __safeDI_serviceBuilder = serviceBuilder
		        let __safeDI_serviceSendableBuilder = serviceSendableBuilder
		        func __safeDI_panel() -> Panel {
		            func __safeDI_serviceBuilder_Panel_row_service(_ scope: Panel.SafeDIMockScope_Service.row_service_Values) -> any Service {
		                let token = scope.token
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Panel(_ scope: Panel.SafeDIMockScope_Service, passUp: () -> any Service) -> any Service {
		                switch scope {
		                case let .row_service(scope): return __safeDI_serviceBuilder_Panel_row_service(scope)
		                case .service: return passUp()
		                }
		            }
		            _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		            return Panel.mock(serviceBuilder: { scope in __safeDI_serviceBuilder_Panel(scope, passUp: { __safeDI_serviceBuilder(.panel(scope)) }) }, safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        let __safeDI_held__safeDIBuilder = safeDIOverrides.held
		        @Sendable func __safeDI_held() -> Panel {
		            func __safeDI_serviceBuilder_Panel_row_service(_ scope: Panel.SafeDIMockScope_Service.row_service_Values) -> any Service {
		                let token = scope.token
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Panel(_ scope: Panel.SafeDIMockScope_Service, passUp: () -> any Service) -> any Service {
		                switch scope {
		                case let .row_service(scope): return __safeDI_serviceBuilder_Panel_row_service(scope)
		                case .service: return passUp()
		                }
		            }
		            _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		            return Panel.mock(serviceBuilder: { scope in __safeDI_serviceBuilder_Panel(scope, passUp: { __safeDI_serviceSendableBuilder(.held(scope)) }) }, safeDIOverrides: __safeDI_held__safeDIBuilder?() ?? .init())
		        }
		        let held = SendableInstantiator<Panel>(__safeDI_held)
		        return Board(panel: panel, held: held)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_74FD5923C8626E63 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesAStagedPlaceUpUnderTheCalledMocksStem_whenNeitherCallerFillsIt() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(
			core: [
				"""
				import SafeDI

				@Instantiable
				public struct Job: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated let service: any Service
				}

				@Instantiable(generateMock: .public)
				public struct Crate: Instantiable, Sendable {
				    package init(job: SendableInstantiator<Job>) {
				        self.job = job
				    }

				    @Instantiated let job: SendableInstantiator<Job>
				}
				""",
			],
			mid: [
				"""
				import Core
				import SafeDI

				@Instantiable(generateMock: .public)
				public struct Shelf: Instantiable {
				    package init(crate: Crate) {
				        self.crate = crate
				    }

				    @Instantiated let crate: Crate
				}
				""",
			],
			app: [
				"""
				import Mid
				import SafeDI

				@Instantiable(generateMock: true)
				public struct ShelfScreen: Instantiable {
				    public init(shelf: Shelf) {
				        self.shelf = shelf
				    }

				    @Instantiated let shelf: Shelf
				}
				""",
			],
		), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Shelf {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            crate: Crate.SafeDIOverrides = .init()
		        ) {
		            self.crate = crate
		        }

		        public private(set) var crate: Crate.SafeDIOverrides
		    }

		    public static func mock(
		        serviceBuilder_Crate_job_service: @escaping (Crate.SafeDIStagedMockScope_Service_job_service.Stage1) -> @Sendable (Crate.SafeDIStagedMockScope_Service_job_service.Stage2) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shelf {
		        let __safeDI_serviceBuilder_Crate_job_service = serviceBuilder_Crate_job_service
		        _ = Crate.__safeDI_Crate_mock_4E6FF0184436B101.self\(Self.comment("Core"))
		        let crate = Crate.mock(serviceBuilder_job_service: __safeDI_serviceBuilder_Crate_job_service, safeDIOverrides: safeDIOverrides.crate)
		        return Shelf(crate: crate)
		    }
		}

		extension Shelf {
		    public enum __safeDI_Shelf_mock_BF4FCC7689F901A5 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension ShelfScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            shelf: Shelf.SafeDIOverrides = .init()
		        ) {
		            self.shelf = shelf
		        }

		        private(set) var shelf: Shelf.SafeDIOverrides
		    }

		    static func mock(
		        serviceBuilder_Crate_job_service: @escaping (Crate.SafeDIStagedMockScope_Service_job_service.Stage1) -> @Sendable (Crate.SafeDIStagedMockScope_Service_job_service.Stage2) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> ShelfScreen {
		        _ = Shelf.__safeDI_Shelf_mock_BF4FCC7689F901A5.self\(Self.comment("Mid"))
		        let shelf = Shelf.mock(serviceBuilder_Crate_job_service: serviceBuilder_Crate_job_service, safeDIOverrides: safeDIOverrides.shelf)
		        return ShelfScreen(shelf: shelf)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsThePlaceThePublicCallerFillsItself_whenItsCallerFillsTheCalledMocksOtherPlace() async throws {
		// `Mid` fills `Panel`'s `row_service` with `TokenService` and passes `service` up; `Board`'s enum holds `Panel`'s whole
		// enum, so `App`'s dispatcher switches over `row_service` too, which `Board` never hands it.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [Self.plainBoard, Self.tokenService], app: [Self.boardScreen, Self.fakeService]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		\(Self.boardScreenPrelude)
		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> BoardScreen {
		        func __safeDI_board() -> Board {
		            func __safeDI_serviceBuilder_Board(_ scope: Board.SafeDIMockScope_Service) -> any Service {
		                switch scope {
		                case let .panel(scope): return __safeDI_serviceBuilder_Panel(scope)
		                }
		            }
		            func __safeDI_serviceBuilder_Panel(_ scope: Panel.SafeDIMockScope_Service) -> any Service {
		                switch scope {
		                case .row_service:
		                    let service: any Service = FakeService.mock()
		                    return service
		                case .service:
		                    let service: any Service = FakeService.mock()
		                    return service
		                }
		            }
		            _ = Board.__safeDI_Board_mock_57604ACF5DD3A914.self\(Self.comment("Mid"))
		            return Board.mock(serviceBuilder: __safeDI_serviceBuilder_Board, safeDIOverrides: safeDIOverrides.board)
		        }
		        let board: Board = __safeDI_board()
		        return BoardScreen(board: board)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsThePlacesThePublicCallerFillsItselfInEachFamily_whenItsCallerFillsTheCalledMocksOtherPlaces() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [Self.board, Self.tokenService], app: [Self.boardScreen, Self.fakeService]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		\(Self.boardScreenPrelude)
		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> BoardScreen {
		        func __safeDI_board() -> Board {
		            func __safeDI_serviceBuilder_Board(_ scope: Board.SafeDIMockScope_Service) -> any Service {
		                switch scope {
		                case let .panel(scope): return __safeDI_serviceBuilder_Panel(scope)
		                }
		            }
		            @Sendable func __safeDI_serviceBuilder_Panel(_ scope: Panel.SafeDIMockScope_Service) -> any Service {
		                switch scope {
		                case .row_service:
		                    let service: any Service = FakeService.mock()
		                    return service
		                case .service:
		                    let service: any Service = FakeService.mock()
		                    return service
		                }
		            }
		            @Sendable func __safeDI_serviceSendableBuilder_Board(_ scope: Board.SafeDISendableMockScope_Service) -> any Service {
		                switch scope {
		                case let .held(scope): return __safeDI_serviceBuilder_Panel(scope)
		                }
		            }
		            _ = Board.__safeDI_Board_mock_74FD5923C8626E63.self\(Self.comment("Mid"))
		            return Board.mock(serviceBuilder: __safeDI_serviceBuilder_Board, serviceSendableBuilder: __safeDI_serviceSendableBuilder_Board, safeDIOverrides: safeDIOverrides.board)
		        }
		        let board: Board = __safeDI_board()
		        return BoardScreen(board: board)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesThePlaceUp_whenInternalCallersFulfillerInstantiatesATypeNothingFulfills() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [Self.screen, Self.defaultServiceInstantiatingGizmo]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.screenTakingTheBuilder])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesABuilderForWhatTheFillInstantiates_whenPublicCallersFulfillerInstantiatesATypeNothingFulfills() async throws {
		let modules = Self.modules(mid: [Self.plainBoard, Self.defaultServiceInstantiatingGizmo], app: [Self.boardScreen])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Board {
		    @frozen public enum SafeDIMockScope_Gizmo {
		        case panel_row_service_gizmo(panel_row_service_gizmo_Values)
		        case panel_service_gizmo(panel_service_gizmo_Values)

		        public struct panel_row_service_gizmo_Values {
		            public let token: Token
		        }

		        public struct panel_service_gizmo_Values {
		            public let row: Row
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            self.panel = panel
		        }

		        public private(set) var panel: Panel.SafeDIOverrides
		    }

		    public static func mock(
		        gizmoBuilder: @escaping (Board.SafeDIMockScope_Gizmo) -> any Gizmo,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let __safeDI_gizmoBuilder = gizmoBuilder
		        func __safeDI_panel() -> Panel {
		            func __safeDI_serviceBuilder_Panel(_ scope: Panel.SafeDIMockScope_Service) -> any Service {
		                switch scope {
		                case let .row_service(scope):
		                    let token = scope.token
		                    func __safeDI_service() -> DefaultService {
		                        let gizmo: any Gizmo = __safeDI_gizmoBuilder(.panel_row_service_gizmo(SafeDIMockScope_Gizmo.panel_row_service_gizmo_Values(token: token)))
		                        return DefaultService(gizmo: gizmo)
		                    }
		                    let service: any Service = __safeDI_service()
		                    return service
		                case let .service(scope):
		                    let row = scope.row
		                    func __safeDI_service() -> DefaultService {
		                        let gizmo: any Gizmo = __safeDI_gizmoBuilder(.panel_service_gizmo(SafeDIMockScope_Gizmo.panel_service_gizmo_Values(row: row)))
		                        return DefaultService(gizmo: gizmo)
		                    }
		                    let service: any Service = __safeDI_service()
		                    return service
		                }
		            }
		            _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		            return Panel.mock(serviceBuilder: __safeDI_serviceBuilder_Panel, safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Board(panel: panel)
		    }
		}

		extension Board {
		    public enum __safeDI_Board_mock_C4C39BF9827F25CF {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_renamesTheBuildersStem_whenPublicMockTakesAParameterUnderTheBuildersLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				import SafeDI

				public protocol Service: Sendable {}

				public final class ServiceBuilder: Sendable {
				    public init() {}
				}

				@Instantiable
				public struct Row: Instantiable, Sendable {
				    public init(serviceBuilder: ServiceBuilder, service: any Service) {
				        self.serviceBuilder = serviceBuilder
				        self.service = service
				    }

				    @Received let serviceBuilder: ServiceBuilder
				    @Instantiated let service: any Service
				}

				@Instantiable(generateMock: .public)
				public struct Panel: Instantiable, Sendable {
				    package init(row: Row) {
				        self.row = row
				    }

				    @Instantiated let row: Row
				}
				""",
			]),
		], integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    @frozen public enum SafeDIMockScope_Service_Service {
		        case row_service(row_service_Values)

		        public struct row_service_Values {}
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            row: ((ServiceBuilder, any Service) -> Row)? = nil
		        ) {
		            self.row = row
		        }

		        public private(set) var row: ((ServiceBuilder, any Service) -> Row)?
		    }

		    public static func mock(
		        serviceBuilder: ServiceBuilder,
		        service_ServiceBuilder: @escaping (Panel.SafeDIMockScope_Service_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        let __safeDI_service_ServiceBuilder = service_ServiceBuilder
		        func __safeDI_row() -> Row {
		            let service: any Service = __safeDI_service_ServiceBuilder(.row_service(SafeDIMockScope_Service_Service.row_service_Values()))
		            return if let safeDIBuilder = safeDIOverrides.row { safeDIBuilder(serviceBuilder, service) } else { Row(serviceBuilder: serviceBuilder, service: service) }
		        }
		        let row: Row = __safeDI_row()
		        return Panel(row: row)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_042D6F61A871FD03 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenFillCallsPublicMockGeneratedUnderAnotherMockCondition() async {
		// `App` fills `Panel`'s places with `DefaultService`, whose public mock `Impl` generates under `TESTING`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):10:5: error: `DefaultService.mock()` is generated under `#if TESTING` in `Impl`, but this module's mocks compile under `#if DEBUG`. Give both modules one `mockConditionalCompilation`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panel]),
					ModuleFixture(
						name: "Impl",
						packageName: "impl",
						swiftFileContentByFilePath: [
							"DefaultService.swift": """
							import Core
							import SafeDI

							@Instantiable(fulfillingAdditionalTypes: [Service.self], generateMock: .public)
							public struct DefaultService: Service, Instantiable {
							    package init(token: Token) {
							        self.token = token
							    }

							    @Instantiated let token: Token
							}
							""",
							"SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"TESTING\")",
						],
						dependencies: ["Core"],
						mockConditionalCompilation: "TESTING",
					),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [Self.screen], dependencies: ["Core", "Impl"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicCallerFillsTheCalledMocksPlacesWithAFulfillerItsCallersCannotSee() async {
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(NormalizedFilePath(fixtures["Mid"]!.compilerPath(of: "Board.swift")).path):5:29: error: SafeDI cannot generate the public mock of `Board`: its signature depends on `DefaultService`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call the mock cannot see that declaration, so their calls would not match the mock. Declare `DefaultService` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panel]),
					ModuleFixture(name: "Vendor", packageName: "vendor", swiftFileContent: [Self.defaultService], dependencies: ["Core"], isCheckoutPackage: true),
					ModuleFixture(
						name: "Mid",
						packageName: "mid",
						swiftFileContentByFilePath: [
							"Board.swift": "import Vendor\n" + Self.plainBoard,
							"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/checkouts/vendor/Sources/Vendor\"])",
						],
						dependencies: ["Core", "Vendor"],
					),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [Self.boardScreen], dependencies: ["Core", "Mid"]),
				],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – what a fill's calls pass

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenFillCallsAPublicMockWhoseTierOmitsAValueTheCallerProvides() async {
		// `App` fills `Panel`'s place with `DefaultService`, whose `public` mock passes `nil` to `TokenCache`'s `filter`,
		// which the inline mock would hand the `filter` `Screen` forwards.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):11:5: error: `Screen` provides `filter: [3 of Int]`, but the `public` mock SafeDI generated for `DefaultService` in module `Impl`, the narrowest one module `App` can call, does not take it: `DefaultService.mock` takes `filter` only on its `package` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Impl` or on a type that receives it is `package` (`TokenCache.init(filter:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `TokenCache.init(filter:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `filter` on this path.
			\(fixtures["Impl"]!["TokenCache.swift"]):10:5: note: `TokenCache` receives `filter: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panelReceivingFilter]),
					ModuleFixture(name: "Impl", packageName: "impl", swiftFileContent: [Self.defaultServiceWithTokenCache], dependencies: ["Core"]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
						"""
						import Core
						import SafeDI

						@Instantiable(generateMock: true)
						public struct Screen: Instantiable {
						    public init(filter: [3 of Int], panel: Panel) {
						        self.filter = filter
						        self.panel = panel
						    }

						    @Forwarded let filter: [3 of Int]
						    @Instantiated let panel: Panel
						}
						""",
					], dependencies: ["Core", "Impl"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicCallersFillCallsAPublicMockWhoseTierOmitsAValueItsCallerProvides() async {
		// `Mid` fills `Panel`'s places in `Board`'s public mock with `DefaultService`, whose `public` mock passes `nil` to
		// `TokenCache`'s `filter`, so no tier of `Board`'s mock takes the `filter` `Screen` forwards.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):12:5: error: `Screen` provides `filter: [3 of Int]`, but no mock SafeDI generated for `Board` takes it: `Board`'s mock tree calls the `public` mock SafeDI generated for `DefaultService` in module `Impl`, the narrowest one module `Mid` can call, which takes `filter` only on its `package` tier, so calling it would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Impl` or on a type that receives it is `package` (`TokenCache.init(filter:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `TokenCache.init(filter:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `filter` on this path.
			\(fixtures["Impl"]!["TokenCache.swift"]):10:5: note: `TokenCache` receives `filter: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panel]),
					ModuleFixture(name: "Impl", packageName: "impl", swiftFileContent: [Self.defaultServiceWithTokenCache], dependencies: ["Core"]),
					ModuleFixture(name: "Mid", packageName: "mid", swiftFileContent: [Self.plainBoard], dependencies: ["Core", "Impl"]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
						"""
						import Core
						import Mid
						import SafeDI

						@Instantiable(generateMock: true)
						public struct Screen: Instantiable {
						    public init(filter: [3 of Int], board: Board) {
						        self.filter = filter
						        self.board = board
						    }

						    @Forwarded let filter: [3 of Int]
						    @Instantiated let board: Board
						}
						""",
					], dependencies: ["Core", "Impl", "Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – an internal caller's passed-up builders

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesThePassedUpBuilderAfterTheCalledMock_whenInternalCallerInstantiatesAPropertyUnderTheBuildersLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			Self.thing,
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(serviceBuilder: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.panel = panel
			    }

			    @Instantiated let serviceBuilder: Thing
			    @Instantiated let panel: Panel
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            serviceBuilder: (() -> Thing)? = nil,
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            self.serviceBuilder = serviceBuilder
		            self.panel = panel
		        }

		        private(set) var serviceBuilder: (() -> Thing)?
		        private(set) var panel: Panel.SafeDIOverrides
		    }

		    static func mock(
		        serviceBuilder_Panel: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let serviceBuilder = if let safeDIBuilder = safeDIOverrides.serviceBuilder { safeDIBuilder() } else { Thing() }
		        _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		        func __safeDI_panel() -> Panel {
		            let serviceBuilder: (Panel.SafeDIMockScope_Service) -> any Service = serviceBuilder_Panel
		            return Panel.mock(serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(serviceBuilder: serviceBuilder, panel: panel)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesThePassedUpBuilderAfterTheCalledMock_whenInternalCallerReceivesAPropertyUnderTheBuildersLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			"""
			import SafeDI

			public struct Thing: Sendable {
			    public init() {}
			}
			""",
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(serviceBuilder: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.panel = panel
			    }

			    @Received let serviceBuilder: Thing
			    @Instantiated let panel: Panel
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		\(Self.screenPrelude)
		    static func mock(
		        serviceBuilder_Panel: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        serviceBuilder_Thing: Thing,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let serviceBuilder: Thing = serviceBuilder_Thing
		        _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		        func __safeDI_panel() -> Panel {
		            let serviceBuilder: (Panel.SafeDIMockScope_Service) -> any Service = serviceBuilder_Panel
		            return Panel.mock(serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(serviceBuilder: serviceBuilder, panel: panel)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesThePassedUpBuilderAfterTheCalledMock_whenATypeBetweenTheCallerAndTheCallInstantiatesAPropertyUnderTheBuildersLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			Self.thing,
			"""
			import Core
			import SafeDI

			@Instantiable
			public struct Middle: Instantiable {
			    public init(serviceBuilder: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.panel = panel
			    }

			    @Instantiated let serviceBuilder: Thing
			    @Instantiated let panel: Panel
			}
			""",
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(middle: Middle) {
			        self.middle = middle
			    }

			    @Instantiated let middle: Middle
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            middle: Middle.SafeDIMockConfiguration = .init()
		        ) {
		            self.middle = middle
		        }

		        private(set) var middle: Middle.SafeDIMockConfiguration
		    }

		    static func mock(
		        serviceBuilder_Panel: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_middle() -> Middle {
		            let serviceBuilder = if let safeDIBuilder = safeDIOverrides.middle.serviceBuilder { safeDIBuilder() } else { Thing() }
		            _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		            func __safeDI_panel() -> Panel {
		                let serviceBuilder: (Panel.SafeDIMockScope_Service) -> any Service = serviceBuilder_Panel
		                return Panel.mock(serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides.middle.panel)
		            }
		            let panel: Panel = __safeDI_panel()
		            return if let safeDIBuilder = safeDIOverrides.middle.safeDIBuilder { safeDIBuilder(serviceBuilder, panel) } else { Middle(serviceBuilder: serviceBuilder, panel: panel) }
		        }
		        let middle: Middle = __safeDI_middle()
		        return Screen(middle: middle)
		    }
		}
		#endif

		#if DEBUG
		extension Middle {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            serviceBuilder: (() -> Thing)? = nil,
		            panel: Panel.SafeDIOverrides = .init(),
		            _ safeDIBuilder: ((Thing, Panel) -> Middle)? = nil
		        ) {
		            self.serviceBuilder = serviceBuilder
		            self.panel = panel
		            self.safeDIBuilder = safeDIBuilder
		        }

		        private(set) var serviceBuilder: (() -> Thing)?
		        private(set) var panel: Panel.SafeDIOverrides
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        private(set) var safeDIBuilder: ((Thing, Panel) -> Middle)?
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesEachPassedUpBuilderAfterItsCalledMock_whenInternalCallerCallsTwoPublicMocksWithOneHoleType() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(core: [
			"""
			import SafeDI

			@Instantiable(generateMock: .public)
			public struct Deck: Instantiable, Sendable {
			    package init(service: any Service) {
			        self.service = service
			    }

			    @Instantiated let service: any Service
			}
			""",
		], app: [
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(panel: Panel, deck: Deck) {
			        self.panel = panel
			        self.deck = deck
			    }

			    @Instantiated let panel: Panel
			    @Instantiated let deck: Deck
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: Panel.SafeDIOverrides = .init(),
		            deck: ((@escaping (Deck.SafeDIMockScope_Service) -> any Service) -> Deck)? = nil
		        ) {
		            self.panel = panel
		            self.deck = deck
		        }

		        private(set) var panel: Panel.SafeDIOverrides
		        private(set) var deck: ((@escaping (Deck.SafeDIMockScope_Service) -> any Service) -> Deck)?
		    }

		    static func mock(
		        serviceBuilder_Deck: @escaping (Deck.SafeDIMockScope_Service) -> any Service,
		        serviceBuilder_Panel: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		        func __safeDI_panel() -> Panel {
		            let serviceBuilder: (Panel.SafeDIMockScope_Service) -> any Service = serviceBuilder_Panel
		            return Panel.mock(serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        _ = Deck.\(Self.deckGuard).self\(Self.comment("Core"))
		        func __safeDI_deck() -> Deck {
		            let serviceBuilder: (Deck.SafeDIMockScope_Service) -> any Service = serviceBuilder_Deck
		            return if let safeDIBuilder = safeDIOverrides.deck { safeDIBuilder(serviceBuilder) } else { Deck.mock(serviceBuilder: serviceBuilder) }
		        }
		        let deck: Deck = __safeDI_deck()
		        return Screen(panel: panel, deck: deck)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesThePassedUpBuilderAfterItsType_whenTheNameAfterTheCalledMockIsTaken() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(app: [
			Self.thing,
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(serviceBuilder: Thing, serviceBuilder_Panel: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.serviceBuilder_Panel = serviceBuilder_Panel
			        self.panel = panel
			    }

			    @Instantiated let serviceBuilder: Thing
			    @Instantiated let serviceBuilder_Panel: Thing
			    @Instantiated let panel: Panel
			}
			""",
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            serviceBuilder: (() -> Thing)? = nil,
		            serviceBuilder_Panel: (() -> Thing)? = nil,
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            self.serviceBuilder = serviceBuilder
		            self.serviceBuilder_Panel = serviceBuilder_Panel
		            self.panel = panel
		        }

		        private(set) var serviceBuilder: (() -> Thing)?
		        private(set) var serviceBuilder_Panel: (() -> Thing)?
		        private(set) var panel: Panel.SafeDIOverrides
		    }

		    static func mock(
		        serviceBuilder_Panel_SafeDIMockScope_Service_to_any_Service: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let serviceBuilder = if let safeDIBuilder = safeDIOverrides.serviceBuilder { safeDIBuilder() } else { Thing() }
		        let serviceBuilder_Panel = if let safeDIBuilder = safeDIOverrides.serviceBuilder_Panel { safeDIBuilder() } else { Thing() }
		        _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		        func __safeDI_panel() -> Panel {
		            let serviceBuilder: (Panel.SafeDIMockScope_Service) -> any Service = serviceBuilder_Panel_SafeDIMockScope_Service_to_any_Service
		            return Panel.mock(serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(serviceBuilder: serviceBuilder, serviceBuilder_Panel: serviceBuilder_Panel, panel: panel)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsTheCalledMockACaseOfItsOwnEnum_whenPublicCallerInstantiatesAPropertyUnderTheCalledMocksBuilderLabel() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(mid: [
			Self.thing,
			"""
			import Core
			import SafeDI

			@Instantiable(generateMock: .public)
			public struct Board: Instantiable, Sendable {
			    package init(serviceBuilder: Thing, panel: Panel) {
			        self.serviceBuilder = serviceBuilder
			        self.panel = panel
			    }

			    @Instantiated let serviceBuilder: Thing
			    @Instantiated let panel: Panel
			}
			""",
		], app: [Self.boardScreen]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Board {
		    @frozen public enum SafeDIMockScope_Service {
		        case panel(Panel.SafeDIMockScope_Service)
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            serviceBuilder: (() -> Thing)? = nil,
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            self.serviceBuilder = serviceBuilder
		            self.panel = panel
		        }

		        public private(set) var serviceBuilder: (() -> Thing)?
		        public private(set) var panel: Panel.SafeDIOverrides
		    }

		    public static func mock(
		        serviceBuilder: @escaping (Board.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let __safeDI_serviceBuilder_ = serviceBuilder
		        let serviceBuilder = if let safeDIBuilder = safeDIOverrides.serviceBuilder { safeDIBuilder() } else { Thing() }
		        _ = Panel.\(Self.panelGuard).self\(Self.comment("Core"))
		        let panel = Panel.mock(serviceBuilder: { __safeDI_serviceBuilder_(.panel($0)) }, safeDIOverrides: safeDIOverrides.panel)
		        return Board(serviceBuilder: serviceBuilder, panel: panel)
		    }
		}

		extension Board {
		    public enum \(Self.boardBesideThingGuard) {}
		}
		#endif
		"""])
	}

	// MARK: Tests – forwarded values

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesAForwardedTypealiasOfAFunctionInTheCaseAndTheStagedBuilder_whenPublicMocksPlaceIsAnErasedInstantiator() async throws {
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				import SafeDI

				public typealias OnTap = @Sendable () -> Void

				public protocol Service: Sendable {}

				public struct AnyService: Service {
				    public init(_ service: any Service) {
				        self.service = service
				    }

				    public let service: any Service
				}

				@Instantiable(generateMock: .public)
				public struct Host: Instantiable {
				    package init(maker: ErasedInstantiator<OnTap, AnyService>, sendableMaker: SendableErasedInstantiator<OnTap, AnyService>) {
				        self.maker = maker
				        self.sendableMaker = sendableMaker
				    }

				    @Instantiated(fulfilledByType: "TapService", erasedToConcreteExistential: true) let maker: ErasedInstantiator<OnTap, AnyService>
				    @Instantiated(fulfilledByType: "TapService", erasedToConcreteExistential: true) let sendableMaker: SendableErasedInstantiator<OnTap, AnyService>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable
				public struct TapService: Service, Instantiable {
				    public init(onTap: @escaping OnTap) {
				        self.onTap = onTap
				    }

				    @Forwarded let onTap: OnTap
				}

				@Instantiable(generateMock: true)
				public struct HostScreen: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Host {
		    @frozen public enum SafeDIMockScope_TapService {
		        case maker(maker_Values, OnTap)

		        public struct maker_Values {}
		    }

		    public enum SafeDIStagedMockScope_TapService_sendableMaker {
		        public struct Stage1 {
		            public let maker: ErasedInstantiator<OnTap, AnyService>
		        }

		        public struct Stage2 {}

		        public typealias SendableLastStage<__safeDI_Forwarded> = @Sendable (Stage2, __safeDI_Forwarded) -> AnyService
		    }

		    public static func mock(
		        tapServiceBuilder: @escaping (Host.SafeDIMockScope_TapService) -> AnyService,
		        tapServiceBuilder_sendableMaker: @escaping (Host.SafeDIStagedMockScope_TapService_sendableMaker.Stage1) -> Host.SafeDIStagedMockScope_TapService_sendableMaker.SendableLastStage<OnTap>
		    ) -> Host {
		        let __safeDI_tapServiceBuilder = tapServiceBuilder
		        let __safeDI_tapServiceBuilder_sendableMaker = tapServiceBuilder_sendableMaker
		        let maker = ErasedInstantiator<OnTap, AnyService> {
		            __safeDI_tapServiceBuilder(.maker(SafeDIMockScope_TapService.maker_Values(), $0))
		        }
		        let __safeDI_tapServiceBuilder_sendableMaker_Stage2 = __safeDI_tapServiceBuilder_sendableMaker(SafeDIStagedMockScope_TapService_sendableMaker.Stage1(maker: maker))
		        let sendableMaker = SendableErasedInstantiator<OnTap, AnyService> {
		            __safeDI_tapServiceBuilder_sendableMaker_Stage2(SafeDIStagedMockScope_TapService_sendableMaker.Stage2(), $0)
		        }
		        return Host(maker: maker, sendableMaker: sendableMaker)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_mock_DB42C7557BAACB34 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension HostScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            host: ((@escaping (Host.SafeDIMockScope_TapService) -> AnyService, @escaping (Host.SafeDIStagedMockScope_TapService_sendableMaker.Stage1) -> Host.SafeDIStagedMockScope_TapService_sendableMaker.SendableLastStage<OnTap>) -> Host)? = nil
		        ) {
		            self.host = host
		        }

		        private(set) var host: ((@escaping (Host.SafeDIMockScope_TapService) -> AnyService, @escaping (Host.SafeDIStagedMockScope_TapService_sendableMaker.Stage1) -> Host.SafeDIStagedMockScope_TapService_sendableMaker.SendableLastStage<OnTap>) -> Host)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> HostScreen {
		        func __safeDI_host() -> Host {
		            func __safeDI_tapServiceBuilder_sendableMaker(_ scope: Host.SafeDIStagedMockScope_TapService_sendableMaker.Stage1) -> Host.SafeDIStagedMockScope_TapService_sendableMaker.SendableLastStage<OnTap> {
		                @Sendable func __safeDI_tapServiceBuilder_sendableMaker_Stage2(_ scope: Host.SafeDIStagedMockScope_TapService_sendableMaker.Stage2, _ __safeDI_forwarded: @escaping OnTap) -> AnyService {
		                    @Sendable func __safeDI_sendableMaker(onTap: @escaping OnTap) -> TapService {
		                        TapService(onTap: onTap)
		                    }
		                    return AnyService(__safeDI_sendableMaker(onTap: __safeDI_forwarded))
		                }
		                return __safeDI_tapServiceBuilder_sendableMaker_Stage2
		            }
		            func __safeDI_tapServiceBuilder_Host(_ scope: Host.SafeDIMockScope_TapService) -> AnyService {
		                switch scope {
		                case let .maker(_, __safeDI_forwarded):
		                    func __safeDI_maker(onTap: @escaping OnTap) -> TapService {
		                        TapService(onTap: onTap)
		                    }
		                    return AnyService(__safeDI_maker(onTap: __safeDI_forwarded))
		                }
		            }
		            _ = Host.__safeDI_Host_mock_DB42C7557BAACB34.self\(Self.comment("Core"))
		            return if let safeDIBuilder = safeDIOverrides.host { safeDIBuilder(__safeDI_tapServiceBuilder_Host, __safeDI_tapServiceBuilder_sendableMaker) } else { Host.mock(tapServiceBuilder: __safeDI_tapServiceBuilder_Host, tapServiceBuilder_sendableMaker: __safeDI_tapServiceBuilder_sendableMaker) }
		        }
		        let host: Host = __safeDI_host()
		        return HostScreen(host: host)
		    }
		}
		#endif
		"""])
	}

	// MARK: Tests – each tier names its builders apart from its own parameters and wider ones only

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPublicTiersBuilderLabelAndEnum_whenPackageParameterTakesBuildersLabel() async throws {
		// `Badge`, a `package` type in `Panel`'s mock tree, receives `serviceBuilder` only if available, so only the mock's
		// `package` tier takes it. The `public` tier names its builder `serviceBuilder` over `SafeDIMockScope_Service`, as it
		// would without `Badge`; the `package` tier names the same builder apart from its parameter. Neither caller can
		// construct `Panel`, whose initializer is `internal`: `Mid`, in `Panel`'s package, calls the `package` tier, and
		// `App`, in another package, the `public` one.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panelBesideBadgeReceivingServiceBuilder]),
				ModuleFixture(name: "Mid", packageName: "pkg", swiftFileContent: [Self.screen], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [Self.screen], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    @frozen public enum SafeDIMockScope_Service {
		        case service(service_Values)

		        public struct service_Values {
		            package let badge: Badge
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init() {
		            self.badge = nil
		        }

		        package init(
		            badge: ((Thing?) -> Badge)? = nil
		        ) {
		            self.badge = badge
		        }

		        package private(set) var badge: ((Thing?) -> Badge)?
		    }

		    public static func mock(
		        serviceBuilder: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        Panel.mock(service_ServiceBuilder: serviceBuilder, serviceBuilder: nil, safeDIOverrides: safeDIOverrides)
		    }

		    package static func mock(
		        service_ServiceBuilder: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        serviceBuilder: Thing? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        let __safeDI_serviceBuilder = service_ServiceBuilder
		        let badge = if let safeDIBuilder = safeDIOverrides.badge { safeDIBuilder(serviceBuilder) } else { Badge(serviceBuilder: serviceBuilder) }
		        let service: any Service = __safeDI_serviceBuilder(.service(SafeDIMockScope_Service.service_Values(badge: badge)))
		        return Panel(service: service, badge: badge)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_61A401DADCD3362C {}
		}
		#endif
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            self.panel = panel
		        }

		        private(set) var panel: Panel.SafeDIOverrides
		    }

		    static func mock(
		        service_ServiceBuilder: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Panel.__safeDI_Panel_mock_61A401DADCD3362C.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let panel = Panel.mock(service_ServiceBuilder: service_ServiceBuilder, serviceBuilder: nil, safeDIOverrides: safeDIOverrides.panel)
		        return Screen(panel: panel)
		    }
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: Panel.SafeDIOverrides = .init()
		        ) {
		            self.panel = panel
		        }

		        private(set) var panel: Panel.SafeDIOverrides
		    }

		    static func mock(
		        serviceBuilder: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Panel.__safeDI_Panel_mock_61A401DADCD3362C.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let panel = Panel.mock(serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides.panel)
		        return Screen(panel: panel)
		    }
		}
		#endif
		"""])
	}

	// MARK: Private

	/// `Panel`, whose public mock's tree builds `service`, a hole, and `badge`, whose `package` type receives
	/// `serviceBuilder: Thing?` only if available.
	private static let panelBesideBadgeReceivingServiceBuilder = """
	import SafeDI

	public protocol Service: Sendable {}

	package struct Thing {}

	@Instantiable
	package struct Badge: Instantiable {
	    package init(serviceBuilder: Thing?) {
	        self.serviceBuilder = serviceBuilder
	    }

	    @Received(onlyIfAvailable: true) let serviceBuilder: Thing?
	}

	@Instantiable(generateMock: .public)
	public struct Panel: Instantiable {
	    init(service: any Service, badge: Badge) {
	        self.service = service
	        self.badge = badge
	    }

	    @Instantiated let service: any Service
	    @Instantiated let badge: Badge
	}
	"""

	private var filesToDelete: [URL]

	/// The guard enum of `Panel`'s public mock.
	private static let panelGuard = "__safeDI_Panel_mock_DA3C8BD7DA14623B"

	/// The guard enum of `Board`'s public mock.
	private static let boardGuard = "__safeDI_Board_mock_E46D6B3F6612366C"

	/// The guard enum of `Deck`'s public mock, whose tree builds one place of `Service`.
	private static let deckGuard = "__safeDI_Deck_mock_FDD4CAA715265C6A"

	/// The guard enum of the public mock of a `Board` that instantiates `serviceBuilder: Thing` beside `panel: Panel`.
	private static let boardBesideThingGuard = "__safeDI_Board_mock_F3287210C4D40341"

	/// The comment that ends the line that names the guard of a public mock `module` declares.
	private static func comment(_ module: String) -> String {
		MultiModuleIntegration.moduleInfo.seamCallComment(type: "", declaringModule: module)
	}

	/// `App`'s file up to `Screen`'s `mock()`.
	private static let screenPrelude = """
	#if canImport(Core)
	import Core
	#endif
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Screen {
	    /// Overrides for the mock dependency tree.
	    struct SafeDIOverrides {
	        init(
	            panel: Panel.SafeDIOverrides = .init()
	        ) {
	            self.panel = panel
	        }

	        private(set) var panel: Panel.SafeDIOverrides
	    }

	"""

	/// `App`'s file when `Screen`'s mock fills no place of `Panel`'s.
	private static let screenTakingTheBuilder = """
	\(screenPrelude)
	    static func mock(
	        serviceBuilder: @escaping (Panel.SafeDIMockScope_Service) -> any Service,
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Screen {
	        _ = Panel.\(panelGuard).self\(comment("Core"))
	        let panel = Panel.mock(serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides.panel)
	        return Screen(panel: panel)
	    }
	}
	#endif
	"""

	/// `Mid`'s file up to `Board`'s `mock()`.
	private static let boardPrelude = """
	#if canImport(Core)
	import Core
	#endif
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension Board {
	    @frozen public enum SafeDIMockScope_Service {
	        case panel(Panel.SafeDIMockScope_Service)
	    }

	    @frozen public enum SafeDISendableMockScope_Service {
	        case held(Panel.SafeDIMockScope_Service)
	    }

	    /// Overrides for the mock dependency tree.
	    public struct SafeDIOverrides {
	        public init(
	            panel: Panel.SafeDIOverrides = .init(),
	            held: (@Sendable () -> Panel.SafeDIOverrides)? = nil
	        ) {
	            self.panel = panel
	            self.held = held
	        }

	        public private(set) var panel: Panel.SafeDIOverrides
	        public private(set) var held: (@Sendable () -> Panel.SafeDIOverrides)?
	    }

	"""

	/// `Core`'s `Panel`, whose public mock's tree builds a `Service` at two places, one inside `Row`, which carries `token`, and
	/// one beside it, which carries `row`; `Mid`, another package, holding `mid`, when given; and `App`, a third package.
	private static func modules(core: [String] = [], mid: [String]? = nil, app: [String]) -> [ModuleFixture] {
		var modules = [ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [Self.panel] + core)]
		if let mid {
			modules.append(ModuleFixture(name: "Mid", packageName: "mid", swiftFileContent: mid, dependencies: ["Core"]))
		}
		modules.append(ModuleFixture(name: "App", packageName: "app", swiftFileContent: app, dependencies: mid == nil ? ["Core"] : ["Core", "Mid"]))
		return modules
	}

	private static let panel = """
	import SafeDI

	public protocol Service: Sendable {}

	@Instantiable
	public final class Token: Instantiable, Sendable {
	    public init() {}
	}

	@Instantiable
	public struct Row: Instantiable, Sendable {
	    public init(token: Token, service: any Service) {
	        self.token = token
	        self.service = service
	    }

	    @Instantiated public let token: Token
	    @Instantiated let service: any Service
	}

	@Instantiable(generateMock: .public)
	public struct Panel: Instantiable, Sendable {
	    package init(row: Row, service: any Service) {
	        self.row = row
	        self.service = service
	    }

	    @Instantiated let row: Row
	    @Instantiated let service: any Service
	}
	"""

	/// `Panel`, receiving a `filter` its callers provide.
	private static let panelReceivingFilter = """
	import SafeDI

	public protocol Service: Sendable {}

	@Instantiable
	public struct Row: Instantiable, Sendable {
	    package init() {}
	}

	@Instantiable(generateMock: .public)
	public struct Panel: Instantiable {
	    public init(filter: [3 of Int], row: Row, service: any Service) {
	        self.filter = filter
	        self.row = row
	        self.service = service
	    }

	    @Received let filter: [3 of Int]
	    @Instantiated let row: Row
	    @Instantiated let service: any Service
	}
	"""

	/// A fulfiller in another package whose public mock's `public` tier passes `nil` to the `filter` its tree receives.
	private static let defaultServiceWithTokenCache = """
	import Core
	import SafeDI

	@Instantiable
	package struct TokenCache: Instantiable {
	    package init(filter: [3 of Int]?) {
	        self.filter = filter
	    }

	    @Received(onlyIfAvailable: true) let filter: [3 of Int]?
	}

	@Instantiable(fulfillingAdditionalTypes: [Service.self], generateMock: .public)
	public struct DefaultService: Service, Instantiable {
	    package init(tokenCache: TokenCache) {
	        self.tokenCache = tokenCache
	    }

	    @Instantiated let tokenCache: TokenCache
	}
	"""

	/// A type whose name no hole has, for a property under a builder's label.
	private static let thing = """
	import SafeDI

	@Instantiable
	public struct Thing: Instantiable, Sendable {
	    public init() {}
	}
	"""

	/// A public mock with two holes, one `App` fills.
	private static let gadget = """
	import SafeDI

	public protocol Widget: Sendable {}

	public protocol Gizmo: Sendable {}

	@Instantiable(generateMock: .public)
	public struct Gadget: Instantiable, Sendable {
	    package init(widget: any Widget, gizmo: any Gizmo) {
	        self.widget = widget
	        self.gizmo = gizmo
	    }

	    @Instantiated let widget: any Widget
	    @Instantiated let gizmo: any Gizmo
	}
	"""

	private static let screen = """
	import Core
	import SafeDI

	@Instantiable(generateMock: true)
	public struct Screen: Instantiable {
	    public init(panel: Panel) {
	        self.panel = panel
	    }

	    @Instantiated let panel: Panel
	}
	"""

	private static let defaultService = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct DefaultService: Service, Instantiable {
	    public init() {}
	}
	"""

	/// A fulfiller only the place inside `Row` carries what it reads for.
	private static let defaultServiceReceivingToken = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct DefaultService: Service, Instantiable {
	    public init(token: Token) {
	        self.token = token
	    }

	    @Received let token: Token
	}
	"""

	/// A public mock in `Mid` that calls `Panel`'s in plain code and inside a `@Sendable` function.
	private static let board = """
	import Core
	import SafeDI

	@Instantiable(generateMock: .public)
	public struct Board: Instantiable, Sendable {
	    package init(panel: Panel, held: SendableInstantiator<Panel>) {
	        self.panel = panel
	        self.held = held
	    }

	    @Instantiated let panel: Panel
	    @Instantiated let held: SendableInstantiator<Panel>
	}
	"""

	/// A public mock in `Mid` that calls `Panel`'s in plain code only.
	private static let plainBoard = """
	import Core
	import SafeDI

	@Instantiable(generateMock: .public)
	public struct Board: Instantiable, Sendable {
	    package init(panel: Panel) {
	        self.panel = panel
	    }

	    @Instantiated let panel: Panel
	}
	"""

	/// A fulfiller that fills only the place inside `Row`, which carries `token`.
	private static let tokenService = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct TokenService: Service, Instantiable {
	    public init(token: Token) {
	        self.token = token
	    }

	    @Received let token: Token
	}
	"""

	/// A fake that fills every place of `Service`, in mocks only.
	private static let fakeService = """
	import Core
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [Service.self], mockOnly: true)
	public struct FakeService: Service {
	    public static func mock() -> FakeService {
	        FakeService()
	    }
	}
	"""

	/// A fulfiller whose tree instantiates a type nothing fulfills.
	private static let defaultServiceInstantiatingGizmo = """
	import Core
	import SafeDI

	public protocol Gizmo: Sendable {}

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct DefaultService: Service, Instantiable {
	    public init(gizmo: any Gizmo) {
	        self.gizmo = gizmo
	    }

	    @Instantiated let gizmo: any Gizmo
	}
	"""

	/// `App`'s file up to `BoardScreen`'s `mock()`.
	private static let boardScreenPrelude = """
	#if canImport(Core)
	import Core
	#endif
	#if canImport(Mid)
	import Mid
	#endif
	#if canImport(SafeDI)
	import SafeDI
	#endif

	#if DEBUG
	extension BoardScreen {
	    /// Overrides for the mock dependency tree.
	    struct SafeDIOverrides {
	        init(
	            board: Board.SafeDIOverrides = .init()
	        ) {
	            self.board = board
	        }

	        private(set) var board: Board.SafeDIOverrides
	    }

	"""

	private static let boardScreen = """
	import Core
	import Mid
	import SafeDI

	@Instantiable(generateMock: true)
	public struct BoardScreen: Instantiable {
	    public init(board: Board) {
	        self.board = board
	    }

	    @Instantiated let board: Board
	}
	"""

	/// Compares the values the mocks of `modules`, as `output` generated them, build for `probes` with what internal
	/// mocks build inline when every declaration of `modules` is in one module and every public mock is internal.
	private mutating func expectValuesAgreeWithInlineMocks(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let moduleNames = Set(modules.map(\.name))
		func inline(_ source: String) -> String {
			source
				.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { line in !moduleNames.contains { line == "import \($0)" } }
				.joined(separator: "\n")
				.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
		}
		var inlineFiles = [String: String]()
		for module in modules {
			for (index, content) in module.swiftFileContent.enumerated() {
				inlineFiles["\(module.name)_File\(index).swift"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		func path(of modules: [ModuleFixture], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
			try DifferentialValuePath(modules: modules.map { module in
				var fixtureFiles = module.swiftFileContentByFilePath
				for (index, content) in module.swiftFileContent.enumerated() {
					fixtureFiles["File\(index).swift"] = content
				}
				return try DifferentialValueModule(
					name: module.name,
					packageName: module.packageName,
					dependencyModuleNames: module.dependencies,
					fixtureFiles: fixtureFiles,
					generatedFiles: #require(output.modules[module.name], sourceLocation: sourceLocation).generatedFiles,
				)
			})
		}
		try expectDifferentialValuesAgree(
			feature: path(of: modules, output: output),
			knownRight: path(of: inlineModules, output: inlineOutput),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
