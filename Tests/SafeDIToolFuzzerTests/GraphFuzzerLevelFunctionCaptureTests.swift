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
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The check that no closure a caller's level function returns keeps a level's values alive
/// (`GraphFuzzerLevelFunctionCaptures`): hand-written generated code, each shape the generator writes and each wrong form
/// the check must fail, and the tool's own output for three seams, whose exact counts fail when the check reads nothing
/// of real output.
struct GraphFuzzerLevelFunctionCaptureTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests of hand-written generated code

	@Test
	func captures_findNothing_whenEachLevelFunctionHandsOnTheValuesItsFillReads() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		    .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(logger: values.logger) })
		}
		func __safeDI_apiBuilder_Home_Detail_Scope(logger: Logger) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		    .init(leafBuilder: { _ in __safeDI_apiBuilder_Home_Leaf_Scope(logger: logger) })
		}
		func __safeDI_apiBuilder_Home_Leaf_Scope(logger: Logger) -> Home.SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		    .init(api: { _ in LiveApi(logger: logger) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 3, namedMemberClosureCount: 1, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	@Test
	func captures_findNothing_whenCarrierMemberHandsPositionalValuesOn() {
		// Each positional parameter holds one value, which the member hands on whole, as inline hands the value.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_mixHoleService_MixMid(up: Mix.__safeDI_MixHoleServiceCarrier<any MixWorker>) -> Mix.__safeDI_MixHoleServiceCarrier<any MixHoleService> {
		    .init(mixHoleService: { scope_mixToken, scope_mixLeafBuilder in __safeDI_fill(scope_mixToken, scope_mixLeafBuilder, inner: up.mixHoleService(scope_mixToken, scope_mixLeafBuilder)) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 1, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	@Test
	func captures_reportWholeUse_whenCarrierMemberHandsRunStructToNextLevelFunction() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		    .init(detailBuilder: { scope, scope_token in __safeDI_apiBuilder_Home_Detail_Scope(scope, token: scope_token) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .wholeUse, fileName: "App.swift", line: 2, function: "__safeDI_apiBuilder_Home", member: "detailBuilder", parameter: "scope")],
			levelFunctionCount: 1,
			namedMemberClosureCount: 1,
			conversionFunctionCount: 0,
			fillFunctionCount: 0,
		))
	}

	@Test
	func captures_reportNestedReferenceOnce_whenKeptClosureReadsMemberClosuresValues() {
		// The next levels are built inline, so the closure `api` returns keeps `values` alive.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		    .init(detailBuilder: { values in .init(leafBuilder: { _ in .init(api: { _ in LiveApi(logger: values.logger, navigator: values.navigator) }) }) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .nestedReference, fileName: "App.swift", line: 2, function: "__safeDI_apiBuilder_Home", member: "detailBuilder", parameter: "values")],
			levelFunctionCount: 1,
			namedMemberClosureCount: 1,
			conversionFunctionCount: 0,
			fillFunctionCount: 0,
		))
	}

	@Test
	func captures_reportNestedReference_whenKeptClosureCapturesValuesWhole() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		    .init(detailBuilder: { values in .init(leafBuilder: { _ in __safeDI_leaf(values) }) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .nestedReference, fileName: "App.swift", line: 2, function: "__safeDI_apiBuilder_Home", member: "detailBuilder", parameter: "values")],
			levelFunctionCount: 1,
			namedMemberClosureCount: 1,
			conversionFunctionCount: 0,
			fillFunctionCount: 0,
		))
	}

	@Test
	func captures_findNothing_whenNestedClosureReadsValuesInItsCaptureList() {
		// A capture list is evaluated where its closure is made, so the memo the member makes keeps the field, not `values`.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		    .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Leaf_Scope(logger: LazilyInstantiated<Logger>({ [handed = values.logger] in handed })) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [],
			levelFunctionCount: 1,
			namedMemberClosureCount: 1,
			conversionFunctionCount: 0,
			fillFunctionCount: 0,
		))
	}

	@Test
	func captures_reportNestedReference_whenNestedClosureWithCaptureListReadsValuesInItsBody() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		    .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Leaf_Scope(logger: LazilyInstantiated<Logger>({ [handed = values.logger] in values.logger })) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .nestedReference, fileName: "App.swift", line: 2, function: "__safeDI_apiBuilder_Home", member: "detailBuilder", parameter: "values")],
			levelFunctionCount: 1,
			namedMemberClosureCount: 1,
			conversionFunctionCount: 0,
			fillFunctionCount: 0,
		))
	}

	@Test
	func captures_reportWholeUse_whenMemberClosureHandsValuesToNextLevelFunction() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		    .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(values) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .wholeUse, fileName: "App.swift", line: 2, function: "__safeDI_apiBuilder_Home", member: "detailBuilder", parameter: "values")],
			levelFunctionCount: 1,
			namedMemberClosureCount: 1,
			conversionFunctionCount: 0,
			fillFunctionCount: 0,
		))
	}

	@Test
	func captures_reportValuesParameter_whenLevelFunctionTakesValuesStruct() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home_Detail_Scope(_ values: Home.SafeDIScope_Api.detailBuilder_Values) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		    .init(leafBuilder: { _ in __safeDI_apiBuilder_Home_Leaf_Scope(logger: values.logger) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .valuesParameter, fileName: "App.swift", line: 1, function: "__safeDI_apiBuilder_Home_Detail_Scope", member: nil, parameter: "values")],
			levelFunctionCount: 1,
			namedMemberClosureCount: 0,
			conversionFunctionCount: 0,
			fillFunctionCount: 0,
		))
	}

	@Test
	func captures_findNothing_whenMemberClosuresHandValuesWholeToCallersMemberForTheLevel() {
		// Each function takes the caller's struct for its level, `up`, and calls the caller's member with the level's
		// values where the seam binds the level; a fill's local function is hoisted out of the struct's closure.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["Inner.swift": """
		func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		    .init(innermost: { values in __safeDI_serviceBuilder_Innermost(up: up.innermost(values)) })
		}
		func __safeDI_serviceBuilder_Innermost(up: Innermost.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Innermost.SafeDIScope_Service.__safeDI_Builder<any Service> {
		    .init(detailBuilder: { values in __safeDI_serviceBuilder_Innermost_Detail_Scope(up: up.detailBuilder(values), logger: values.logger) })
		}
		func __safeDI_serviceBuilder_Innermost_Detail_Scope(up: Innermost.SafeDIScope_Service.Detail_Scope.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, logger: Logger) -> Innermost.SafeDIScope_Service.Detail_Scope.__safeDI_Builder<any Service> {
		    func __safeDI_service(__safeDI_gadgetBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> DefaultService {
		        let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(.init())
		        return DefaultService(logger: logger, gadget: gadget)
		    }
		    return .init(service: { values in __safeDI_service(__safeDI_gadgetBuilder: up.service(values)) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 3, namedMemberClosureCount: 3, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	@Test
	func captures_reportNestedReference_whenCallersMemberIsCalledInsideNestedClosure() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["Inner.swift": """
		func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		    .init(innermost: { values in __safeDI_serviceBuilder_Innermost(up: up.innermost(values)) })
		}
		func __safeDI_serviceBuilder_Innermost(up: Innermost.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Innermost.SafeDIScope_Service.__safeDI_Builder<any Service> {
		    .init(detailBuilder: { values in __safeDI_serviceBuilder_Innermost_Detail_Scope(up: up.detailBuilder(values), logger: values.logger) })
		}
		func __safeDI_serviceBuilder_Innermost_Detail_Scope(up: Innermost.SafeDIScope_Service.Detail_Scope.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, logger: Logger) -> Innermost.SafeDIScope_Service.Detail_Scope.__safeDI_Builder<any Service> {
		    func __safeDI_service(__safeDI_gadgetBuilder: @escaping () -> SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> DefaultService {
		        let gadget: any Gadget = __safeDI_gadgetBuilder().gadget(.init())
		        return DefaultService(logger: logger, gadget: gadget)
		    }
		    return .init(service: { values in __safeDI_service(__safeDI_gadgetBuilder: { up.service(values) }) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .nestedReference, fileName: "Inner.swift", line: 12, function: "__safeDI_serviceBuilder_Innermost_Detail_Scope", member: "service", parameter: "values")],
			levelFunctionCount: 3,
			namedMemberClosureCount: 3,
			conversionFunctionCount: 0,
			fillFunctionCount: 0,
		))
	}

	@Test
	func captures_reportWholeUseOnFillFunction_whenHoistedFillHandsValuesToCallersMember() {
		// The member closure's whole pass to the fill function is allowed; the fill function may only read from its values.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["Inner.swift": """
		func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIScope_Service.__safeDI_Builder<any Service> {
		    .init(innermost: { values in __safeDI_serviceBuilder_Innermost(up: up.innermost(values)) })
		}
		func __safeDI_serviceBuilder_Innermost(up: Innermost.SafeDIScope_Service.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Innermost.SafeDIScope_Service.__safeDI_Builder<any Service> {
		    .init(detailBuilder: { values in __safeDI_serviceBuilder_Innermost_Detail_Scope(up: up.detailBuilder(values), logger: values.logger) })
		}
		func __safeDI_serviceBuilder_Innermost_Detail_Scope(up: Innermost.SafeDIScope_Service.Detail_Scope.__safeDI_Builder<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>, logger: Logger) -> Innermost.SafeDIScope_Service.Detail_Scope.__safeDI_Builder<any Service> {
		    func __safeDI_service(_ values: Innermost.SafeDIScope_Service.Detail_Scope.service_Values) -> DefaultService {
		        let gadget: any Gadget = up.service(values).gadget(.init())
		        return DefaultService(logger: logger, gadget: gadget)
		    }
		    return .init(service: { values in __safeDI_service(values) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .wholeUse, fileName: "Inner.swift", line: 9, function: "__safeDI_service", member: nil, parameter: "values")],
			levelFunctionCount: 3,
			namedMemberClosureCount: 3,
			conversionFunctionCount: 0,
			fillFunctionCount: 1,
		))
	}

	@Test
	func captures_countFillFunction_whenMemberClosureHandsValuesToFillThatBindsThemAtItsTop() {
		// A fill that declares a function: the member closure hands its values whole to the fill function, which binds what
		// it reads at its top, so the kept `__safeDI_jobBuilder` reads `reportBuilder`, never the struct.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope: ExportFeature.SafeDIScope_Uploader.uploader_Values) -> any Uploader {
		    let reportBuilder = scope.reportBuilder
		    func __safeDI_uploader() -> DefaultUploader {
		        func __safeDI_jobBuilder() -> UploadJob {
		            UploadJob(exportService: exportService.instance, reportBuilder: reportBuilder)
		        }
		        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
		        return DefaultUploader(jobBuilder: jobBuilder)
		    }
		    let uploader: any Uploader = __safeDI_uploader()
		    return uploader
		}
		func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.SafeDIScope_Uploader.__safeDI_Builder<any Uploader> {
		    .init(uploader: { scope in __safeDI_uploaderBuilder_ExportFeature_uploader(scope) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 1, namedMemberClosureCount: 1, conversionFunctionCount: 0, fillFunctionCount: 1))
	}

	@Test
	func captures_reportNestedReferenceOnFillFunction_whenFillsLocalFunctionReadsValuesStruct() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_uploaderBuilder_ExportFeature_uploader(_ scope: ExportFeature.SafeDIScope_Uploader.uploader_Values) -> any Uploader {
		    func __safeDI_uploader() -> DefaultUploader {
		        func __safeDI_jobBuilder() -> UploadJob {
		            UploadJob(exportService: exportService.instance, reportBuilder: scope.reportBuilder)
		        }
		        let jobBuilder = Instantiator<UploadJob>(__safeDI_jobBuilder)
		        return DefaultUploader(jobBuilder: jobBuilder)
		    }
		    let uploader: any Uploader = __safeDI_uploader()
		    return uploader
		}
		func __safeDI_uploaderBuilder_ExportFeature() -> ExportFeature.SafeDIScope_Uploader.__safeDI_Builder<any Uploader> {
		    .init(uploader: { scope in __safeDI_uploaderBuilder_ExportFeature_uploader(scope) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .nestedReference, fileName: "App.swift", line: 4, function: "__safeDI_uploaderBuilder_ExportFeature_uploader", member: nil, parameter: "scope")],
			levelFunctionCount: 1,
			namedMemberClosureCount: 1,
			conversionFunctionCount: 0,
			fillFunctionCount: 1,
		))
	}

	@Test
	func captures_reportWholeUse_whenMemberClosureHandsValuesToFunctionThatTakesNoValuesStruct() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_keep(_ values: Any) -> any Api {
		    LiveApi()
		}
		func __safeDI_apiBuilder_Home_Leaf_Scope() -> Home.SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		    .init(api: { values in __safeDI_keep(values) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .wholeUse, fileName: "App.swift", line: 5, function: "__safeDI_apiBuilder_Home_Leaf_Scope", member: "api", parameter: "values")],
			levelFunctionCount: 1,
			namedMemberClosureCount: 1,
			conversionFunctionCount: 0,
			fillFunctionCount: 0,
		))
	}

	@Test
	func captures_resolveEachReferenceToItsNearestDeclaration_whenNestedFillsShareParameterName() {
		// The `App` output of `generate_namesNestedFillApart_whenCallInsideItPassesEnclosingFillOfSameName`: an outer fill
		// `(_ scope:)` nests an inner fill `(_ scope:)`, another seam's level functions and `{ scope in …(scope) }`. Each
		// `scope` the outer fill nests is a nearer declaration than its own parameter, and each member closure is counted
		// once, under its nearest function.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["Root+SafeDI.swift": """
		func __safeDI_service() -> Service {
		    _ = Service.__safeDI_Service_DAEE219B0D380A33.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		    func __safeDI_userServiceBuilder_Service_Profile_Scope_userService(_ scope: Service.SafeDIScope_UserService.Profile_Scope.userService_Values) -> any UserService {
		        func __safeDI_userService() -> DefaultUserService {
		            func __safeDI_inner2() -> Inner2 {
		                _ = Inner2.__safeDI_Inner2_04A50D6F8B93E72E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_trackerBuilder_Inner2_Badge_Scope_userService(_ scope: Inner2.SafeDIScope_Tracker.Badge_Scope.userService_Values) -> any Tracker {
		                    func __safeDI_userService() -> DefaultTracker {
		                        func __safeDI_serviceBuilder() -> Service {
		                            _ = Service.__safeDI_Service_DAEE219B0D380A33.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service())
		                        }
		                        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		                        return DefaultTracker(serviceBuilder: serviceBuilder)
		                    }
		                    let userService: any Tracker = __safeDI_userService()
		                    return userService
		                }
		                func __safeDI_trackerBuilder_Inner2() -> Inner2.SafeDIScope_Tracker.__safeDI_Builder<any Tracker> {
		                    .init(badgeBuilder: { _ in __safeDI_trackerBuilder_Inner2_Badge_Scope() })
		                }
		                func __safeDI_trackerBuilder_Inner2_Badge_Scope() -> Inner2.SafeDIScope_Tracker.Badge_Scope.__safeDI_Builder<any Tracker> {
		                    .init(userService: { scope in __safeDI_trackerBuilder_Inner2_Badge_Scope_userService(scope) })
		                }
		                return Inner2(__safeDI_trackerBuilder: __safeDI_trackerBuilder_Inner2())
		            }
		            let inner2: Inner2 = __safeDI_inner2()
		            return DefaultUserService(inner2: inner2)
		        }
		        let userService: any UserService = __safeDI_userService()
		        return userService
		    }
		    func __safeDI_userServiceBuilder_Service() -> Service.SafeDIScope_UserService.__safeDI_Builder<any UserService> {
		        .init(profileBuilder: { _ in __safeDI_userServiceBuilder_Service_Profile_Scope() })
		    }
		    func __safeDI_userServiceBuilder_Service_Profile_Scope() -> Service.SafeDIScope_UserService.Profile_Scope.__safeDI_Builder<any UserService> {
		        .init(userService: { scope in __safeDI_userServiceBuilder_Service_Profile_Scope_userService(scope) })
		    }
		    return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service())
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 4, namedMemberClosureCount: 2, conversionFunctionCount: 0, fillFunctionCount: 2))
	}

	@Test
	func captures_reportNestedReferenceOnFillFunction_whenOuterFillsLocalFunctionReadsItsValuesBesideAnInnerFillOfTheSameName() {
		// As the nested fills above, where the outer fill's own local function reads the outer `scope`: only that reference
		// resolves to the outer fill's parameter.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["Root+SafeDI.swift": """
		func __safeDI_userServiceBuilder_Service_Profile_Scope_userService(_ scope: Service.SafeDIScope_UserService.Profile_Scope.userService_Values) -> any UserService {
		    func __safeDI_trackerBuilder_Inner2_Badge_Scope_userService(_ scope: Inner2.SafeDIScope_Tracker.Badge_Scope.userService_Values) -> any Tracker {
		        DefaultTracker(mark: scope.mark)
		    }
		    func __safeDI_trackerBuilder_Inner2_Badge_Scope() -> Inner2.SafeDIScope_Tracker.Badge_Scope.__safeDI_Builder<any Tracker> {
		        .init(userService: { scope in __safeDI_trackerBuilder_Inner2_Badge_Scope_userService(scope) })
		    }
		    func __safeDI_userService() -> DefaultUserService {
		        DefaultUserService(inner2: Inner2(__safeDI_trackerBuilder: __safeDI_trackerBuilder_Inner2_Badge_Scope()), id: scope.id)
		    }
		    return __safeDI_userService()
		}
		func __safeDI_userServiceBuilder_Service_Profile_Scope() -> Service.SafeDIScope_UserService.Profile_Scope.__safeDI_Builder<any UserService> {
		    .init(userService: { scope in __safeDI_userServiceBuilder_Service_Profile_Scope_userService(scope) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .nestedReference, fileName: "Root+SafeDI.swift", line: 9, function: "__safeDI_userServiceBuilder_Service_Profile_Scope_userService", member: nil, parameter: "scope")],
			levelFunctionCount: 2,
			namedMemberClosureCount: 2,
			conversionFunctionCount: 0,
			fillFunctionCount: 2,
		))
	}

	@Test
	func captures_countPlaceFunctionNowhere_whenMemberClosureHandsItOneField() {
		// A forwarding place's function returns the closure its wrapper keeps, which holds `id`, an `Int`.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_livePanel_PanelBuilder_Home_Screen_Scope() -> Home.SafeDIScope_LivePanel_Panel.Screen_Scope.__safeDI_Builder<any Panel> {
		    .init(panel: { values in __safeDI_livePanel_PanelBuilder_Home_Screen_Scope_panel(id: values.id) }, next: { _ in __safeDI_livePanel_PanelBuilder_Home_Screen_Scope() })
		}
		func __safeDI_livePanel_PanelBuilder_Home_Screen_Scope_panel(id: Int) -> ErasedInstantiator<String, any Panel>.Builder {
		    func __safeDI_panel(title: String) -> LivePanel { LivePanel(title: title, id: id) }
		    return { forwarded in __safeDI_panel(title: forwarded) }
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 1, namedMemberClosureCount: 1, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	@Test
	func captures_reportNestedReferenceOnPlaceFunction_whenItsReturnedClosureReadsValuesStruct() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_livePanel_PanelBuilder_Home_Screen_Scope() -> Home.SafeDIScope_LivePanel_Panel.Screen_Scope.__safeDI_Builder<any Panel> {
		    .init(panel: { values in __safeDI_livePanel_PanelBuilder_Home_Screen_Scope_panel(values) }, next: { _ in __safeDI_livePanel_PanelBuilder_Home_Screen_Scope() })
		}
		func __safeDI_livePanel_PanelBuilder_Home_Screen_Scope_panel(_ values: Home.SafeDIScope_LivePanel_Panel.Screen_Scope.panel_Values) -> ErasedInstantiator<String, any Panel>.Builder {
		    func __safeDI_panel(title: String, id: Int) -> LivePanel { LivePanel(title: title, id: id) }
		    return { forwarded in __safeDI_panel(title: forwarded, id: values.id) }
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(
			findings: [.init(kind: .nestedReference, fileName: "App.swift", line: 6, function: "__safeDI_livePanel_PanelBuilder_Home_Screen_Scope_panel", member: nil, parameter: "values")],
			levelFunctionCount: 1,
			namedMemberClosureCount: 1,
			conversionFunctionCount: 0,
			fillFunctionCount: 1,
		))
	}

	@Test
	func captures_countConversionWithoutJudgingIt_whenKeptSeamConvertsStructToItsEnum() {
		// A kept seam's body converts inline, in no function that returns a builder struct, and a conversion function takes
		// a function that returns a scope enum: its closures capture the member closure's values on purpose.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["Feature.swift": """
		func __safeDI_innermost() -> Innermost {
		    return Innermost(__safeDI_serviceBuilder: .init(
		        detailBuilder: { __safeDI_detailBuilderValues in
		            .init(service: { __safeDI_serviceValues in __safeDI_serviceBuilder(.innermost(.detailBuilder(__safeDI_detailBuilderValues, .service(__safeDI_serviceValues)))) })
		        }))
		}
		func __safeDI_apiBuilder_Hub_T_Scope(_ __safeDI_apiBuilder_Hub_T_Scope_wrap: @escaping (Hub.SafeDIScope_Api.T_Scope) -> Hub.SafeDIScope_Api) -> Hub.SafeDIScope_Api.T_Scope.__safeDI_Builder<any Api> {
		    .init(cBuilder: { __safeDI_cBuilderValues in __safeDI_apiBuilder_Hub_C_Scope({ __safeDI_apiBuilder_Hub_T_Scope_wrap(.cBuilder(__safeDI_cBuilderValues, $0)) }, __safeDI_apiBuilder_Hub_T_Scope_wrap: __safeDI_apiBuilder_Hub_T_Scope_wrap) }, api: { __safeDI_apiValues in __safeDI_apiBuilder(.hub(__safeDI_apiBuilder_Hub_T_Scope_wrap(.api(__safeDI_apiValues)))) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 0, namedMemberClosureCount: 0, conversionFunctionCount: 1, fillFunctionCount: 0))
	}

	@Test
	func captures_judgeNothing_whenDispatcherSwitchesOverEnumToFillThatTakesValuesStruct() {
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_trackerBuilder_Inner(_ scope: Inner.SafeDIScope_Tracker) -> any Tracker {
		    switch scope {
		    case let .innerJob(scope): return __safeDI_trackerBuilder_Inner_innerJob(scope)
		    }
		}
		func __safeDI_trackerBuilder_Inner_innerJob(_ scope: Inner.SafeDIScope_Tracker.innerJob_Values) -> any Tracker {
		    DefaultTracker(job: { scope })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 0, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	@Test
	func captures_findNothing_whenKeptClosureReadsLevelFunctionsParameterNamedValues() {
		// The member closure's parameter is named apart from the level function's parameter `values`, which the kept
		// closure reads: a value the fill reads, not a level's values struct.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		    .init(leafBuilder: { values_ in __safeDI_apiBuilder_Home_Leaf_Scope(values: values_.values) })
		}
		func __safeDI_apiBuilder_Home_Leaf_Scope(values: Values) -> Home.SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		    .init(api: { _ in Live(values: values) })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 2, namedMemberClosureCount: 1, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	@Test
	func captures_reportNothing_whenNestedClosureDeclaresItsOwnBindingOfTheName() {
		// A kept closure that binds its own `values` before reading it reads no level's values.
		let captures = GraphFuzzerLevelFunctionCaptures(generatedFiles: ["App.swift": """
		func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		    .init(detailBuilder: { values in
		        let logger = values.logger
		        return .init(leafBuilder: { _ in
		            let values = Values(logger: logger)
		            return .init(api: { _ in LiveApi(logger: values.logger) })
		        })
		    })
		}
		"""])

		#expect(captures == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 1, namedMemberClosureCount: 1, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	// MARK: Tests of the tool's output

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func captures_findNothing_inToolsOutputForSeamWhosePlaceIsTwoLevelsBeneathItsValues() async throws {
		// `Home` binds `navigator` and `logger`, then `detailBuilder`, whose `Detail` builds `Leaf`, whose `api` only `App`
		// builds, reading `logger`. Each level holds at most eight values, so its carrier's members take them positionally
		// and no member closure names a run struct.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(
			feature: [
				"public protocol Api: AnyObject {}",
				seamFixtureType(named: "Navigator", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let leafBuilder: Instantiator<Leaf>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let navigator: Navigator", "@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			],
		), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		// `App`'s three level functions, and the three `Home`'s plain initializer declares, one per level it builds from the
		// builder it is handed.
		#expect(Self.captures(of: output) == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 6, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func captures_findNothing_inToolsOutputWhenRouteBindsPropertiesLabeledValuesAndScope() async throws {
		// `Home` binds `values` before `detailBuilder`, and `Detail` binds `scope` before `leafBuilder`; `LiveApi` reads both,
		// so the level functions take parameters of those labels, and the carriers' members take them positionally, under
		// names joined with their labels, which no run struct's name equals.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(
			feature: [
				"public protocol Api: AnyObject {}",
				seamFixtureType(named: "Values", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Scope", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let scope: Scope", "@Instantiated public let leafBuilder: Instantiator<Leaf>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let values: Values", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let values: Values", "@Received public let scope: Scope"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			],
		), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		// `App`'s three level functions, and the three `Home`'s plain initializer declares, one per level it builds from the
		// builder it is handed.
		#expect(Self.captures(of: output) == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 6, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func captures_findNothing_inToolsOutputForSendableLevelFunctions() async throws {
		// The graph of `generate_callsSendableMemberAtTopOfSendableFunction_whenPlaceIsBuiltInsideSendableInstantiator`:
		// `Home`'s place is built inside a `SendableInstantiator`, so `App`'s level functions are
		// `@Sendable nonisolated func`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Worker", isFinalClass: true, declarations: ["@Instantiated public let logger: Logger", "@Instantiated public let detail: Detail"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let workerBuilder: SendableInstantiator<Worker>"]),
			],
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			],
		), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		// Six level functions, whose carriers' members take each level's values positionally, so none names a run struct:
		// `App`'s three level functions, and the three `Home`'s plain initializer declares, one per level it builds from the
		// builder it is handed.
		#expect(Self.captures(of: output) == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 6, namedMemberClosureCount: 0, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func captures_findNothing_inToolsOutputWhenCarrierLevelTakesRunStruct() async throws {
		// `Home` binds nine values before `detailBuilder`, more than a carrier's member takes positionally, so the member
		// closure of `Home`'s level takes them in a run struct, which it reads `logger` of and hands on no further.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.featureAndApp(
			feature: [
				"public protocol Api: AnyObject {}",
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let leafBuilder: Instantiator<Leaf>"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: (1...8).map { "@Instantiated public let wide\($0): Logger" } + ["@Instantiated public let logger: Logger", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			],
			app: [
				Self.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received public let logger: Logger"]),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
			],
		), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		// `App`'s three level functions, and the three `Home`'s plain initializer declares, one per level it builds from the
		// builder it is handed.
		#expect(Self.captures(of: output) == GraphFuzzerLevelFunctionCaptures(levelFunctionCount: 6, namedMemberClosureCount: 1, conversionFunctionCount: 0, fillFunctionCount: 0))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What the check finds in every module's generated files, each file named by its module.
	private static func captures(of output: MultiModuleTestOutput) -> GraphFuzzerLevelFunctionCaptures {
		var generatedFiles = [String: String]()
		for (moduleName, module) in output.modules {
			for (fileName, contents) in module.generatedFiles {
				generatedFiles["\(moduleName)/\(fileName)"] = contents
			}
		}
		return GraphFuzzerLevelFunctionCaptures(generatedFiles: generatedFiles)
	}

	/// `Feature`, which declares `feature`'s types and generates readable initializers, and `App`, which declares `app`'s.
	private static func featureAndApp(feature: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// A final class `name` that fulfills `fulfilledType` and declares `declarations`.
	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}
}
