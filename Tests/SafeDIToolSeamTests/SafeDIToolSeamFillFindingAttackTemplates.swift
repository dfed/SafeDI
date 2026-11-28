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

@testable import SafeDIToolTestSupport

/// The graphs the fill-finding attack (`SafeDIToolSeamFillFindingAttackTests`) varies: for each kind of
/// `FillFinding`, graphs of the suite's own tests whose run reports only that kind, as those tests write them.
extension SafeDIToolSeamFillFindingAttackTests {
	struct Template {
		/// The `FillFinding` kind the graph's run reports (`FillFinding.kindName`).
		let kind: String
		let modules: [ModuleFixture]
	}

	static let templates: [Template] = [
		// From `generate_throwsFillClosesCycleInSeamTreeSuggestingLabelFromSeamsOwnName_whenSeamIsNestedType`.
		Template(kind: "closesCycleInSeamTree", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				public enum Outer {
				    @Instantiable(generateDependencyTree: true)
				    public struct Service: Instantiable {
				        public init(aBuilder: Instantiator<A>) {
				            self.aBuilder = aBuilder
				        }

				        @Instantiated let aBuilder: Instantiator<A>
				    }
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct LoopingUserService: Instantiable, UserService {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Outer.Service) {
				        self.service = service
				    }

				    @Instantiated let service: Outer.Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillClosesCycleInSeamTree_whenFillOfPassedUpBuilderRepeatsPropertyOfInnerSeamsPath`.
		Template(kind: "closesCycleInSeamTree", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(profileBuilder: Instantiator<Profile>) {
				        self.profileBuilder = profileBuilder
				    }

				    @Instantiated let profileBuilder: Instantiator<Profile>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Shell: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Mid

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct LoopingUserService: Instantiable, UserService {
				    public init(profileBuilder: Instantiator<Profile>) {
				        self.profileBuilder = profileBuilder
				    }

				    @Instantiated let profileBuilder: Instantiator<Profile>
				}
				"""#,
				#"""
				import Feature
				import Mid

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(shell: Shell) {
				        self.shell = shell
				    }

				    @Instantiated let shell: Shell
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Mid"]),
		]),
		// From `generate_buildsFillOfItsOwnForPlace_whenOnlyItsPathHoldsDeclarationItsFillClosesCycleOn`.
		Template(kind: "closesCycleInSeamTree", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable {
				    public init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated let api: any Api
				}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(aPanel: Panel) {
				        self.aPanel = aPanel
				    }

				    @Instantiated let aPanel: Panel
				}
				"""#,
				#"""
				@Instantiable
				public struct B: Instantiable {
				    public init(bPanel: Panel) {
				        self.bPanel = bPanel
				    }

				    @Instantiated let bPanel: Panel
				}
				"""#,
				#"""
				@Instantiable
				public struct Shell: Instantiable {
				    public init(panel: Panel) {
				        self.panel = panel
				    }

				    @Instantiated let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Home: Instantiable {
				    public init(a: A, b: B, shellBuilder: Instantiator<Shell>) {
				        self.a = a
				        self.b = b
				        self.shellBuilder = shellBuilder
				    }

				    @Instantiated let a: A
				    @Instantiated let b: B
				    @Instantiated let shellBuilder: Instantiator<Shell>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(shellBuilder: Instantiator<Shell>) {
				        self.shellBuilder = shellBuilder
				    }

				    @Instantiated let shellBuilder: Instantiator<Shell>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(home: Home) {
				        self.home = home
				    }

				    @Instantiated let home: Home
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillClosesCycleInSeamTreeNamingEachType_whenTypeBeneathFulfillerInstantiatesPropertyOfSeamsPath`.
		Template(kind: "closesCycleInSeamTree", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				public struct Analytics: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(userService: any UserService, analytics: Analytics) {
				        self.userService = userService
				        self.analytics = analytics
				    }

				    @Instantiated let userService: any UserService
				    @Received let analytics: Analytics
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(analytics: Analytics, aBuilder: Instantiator<A>) {
				        self.analytics = analytics
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let analytics: Analytics
				    @Instantiated let aBuilder: Instantiator<A>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct LoopingUserService: Instantiable, UserService {
				    public init(middle: Middle) {
				        self.middle = middle
				    }

				    @Instantiated let middle: Middle
				}
				"""#,
				#"""
				import Feature

				@Instantiable
				public struct Middle: Instantiable {
				    public init(aBuilder: Instantiator<A>, analytics: Analytics) {
				        self.aBuilder = aBuilder
				        self.analytics = analytics
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				    @Received let analytics: Analytics
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillClosesCycleInSeamTree_whenFulfillerInstantiatesPropertyOfSeamsPath`.
		Template(kind: "closesCycleInSeamTree", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}

				public struct AnyUserService: UserService {
				    public init(_ base: any UserService) {
				        self.base = base
				    }

				    let base: any UserService
				}
				"""#,
				#"""
				@Instantiable
				public struct Analytics: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(userService: AnyUserService, analytics: Analytics) {
				        self.userService = userService
				        self.analytics = analytics
				    }

				    @Instantiated(fulfilledByType: "LoopingUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				    @Received let analytics: Analytics
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(analytics: Analytics, aBuilder: Instantiator<A>) {
				        self.analytics = analytics
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let analytics: Analytics
				    @Instantiated let aBuilder: Instantiator<A>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable
				public struct LoopingUserService: Instantiable, UserService {
				    public init(aBuilder: Instantiator<A>, analytics: Analytics) {
				        self.aBuilder = aBuilder
				        self.analytics = analytics
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				    @Received let analytics: Analytics
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillClosesCycleInSeamTreeNotingHolesDeclaration_whenClosingPropertyIsHoleWhoseFillHoldsSite`.
		Template(kind: "closesCycleInSeamTree", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Widget {}
				"""#,
				#"""
				public protocol Gadget {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable {
				    public init(widgetMaker: Instantiator<Widget>) {
				        self.widgetMaker = widgetMaker
				    }

				    @Instantiated let widgetMaker: Instantiator<Widget>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable {
				    public init(panelMaker: Instantiator<Panel>) {
				        self.panelMaker = panelMaker
				    }

				    @Instantiated let panelMaker: Instantiator<Panel>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Shell: Instantiable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Upper", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Widget.self])
				public struct DefaultWidget: Instantiable, Widget {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Host: Instantiable {
				    public init(shell: Shell) {
				        self.shell = shell
				    }

				    @Instantiated let shell: Shell
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Upper

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct DefaultGadget: Instantiable, Gadget {
				    public init(widgetMaker: Instantiator<Widget>) {
				        self.widgetMaker = widgetMaker
				    }

				    @Instantiated let widgetMaker: Instantiator<Widget>
				}
				"""#,
				#"""
				import Feature
				import Upper

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Upper"]),
		]),
		// From `generate_throwsFillClosesCycleInSeamTreeNamingDeclaredProperties_whenSiteIsInsideFillOfPassedUpHole`.
		Template(kind: "closesCycleInSeamTree", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Widget {}
				"""#,
				#"""
				public protocol Gadget {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable {
				    public init(widget: any Widget) {
				        self.widget = widget
				    }

				    @Instantiated let widget: any Widget
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable {
				    public init(panelMaker: Instantiator<Panel>) {
				        self.panelMaker = panelMaker
				    }

				    @Instantiated let panelMaker: Instantiator<Panel>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Shell: Instantiable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "Upper", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(fulfillingAdditionalTypes: [Widget.self])
				public struct DefaultWidget: Instantiable, Widget {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(generateDependencyTree: true)
				public struct Host: Instantiable {
				    public init(shell: Shell) {
				        self.shell = shell
				    }

				    @Instantiated let shell: Shell
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle
				import Upper

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct DefaultGadget: Instantiable, Gadget {
				    public init(panelMaker: Instantiator<Panel>) {
				        self.panelMaker = panelMaker
				    }

				    @Instantiated let panelMaker: Instantiator<Panel>
				}
				"""#,
				#"""
				import Feature
				import Middle
				import Upper

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle", "Upper"]),
		]),
		// From `generate_throwsFillClosesCycleInSeamTree_whenClosingPropertyIsAnySpellingOfPathsProperty`.
		Template(kind: "closesCycleInSeamTree", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Widget {}
				"""#,
				#"""
				public protocol Gadget {}
				"""#,
				#"""
				@Instantiable
				public struct Row: Instantiable {
				    public init(widget: any Widget) {
				        self.widget = widget
				    }

				    @Instantiated let widget: any Widget
				}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable, Sendable {
				    public init(rowMaker: Instantiator<Row>) {
				        self.rowMaker = rowMaker
				    }

				    @Instantiated let rowMaker: Instantiator<Row>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable {
				    public init(panel: Panel) {
				        self.panel = panel
				    }

				    @Instantiated let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Shell: Instantiable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Upper", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Widget.self])
				public struct DefaultWidget: Instantiable, Widget {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Host: Instantiable {
				    public init(shell: Shell) {
				        self.shell = shell
				    }

				    @Instantiated let shell: Shell
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Upper

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct DefaultGadget: Instantiable, Gadget {
				    public init(panel: Panel) {
				        self.panel = panel
				    }

				    @Instantiated let panel: Panel
				}
				"""#,
				#"""
				import Feature
				import Upper

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Upper"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillReadsSiblingThatRequiresHolesCarrier`.
		Template(kind: "declarationBoundAfterSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				@Instantiable
				public struct Badge: Instantiable {
				    public init(profile: Profile) {
				        self.profile = profile
				    }

				    @Received let profile: Profile
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(profile: Profile, badge: Badge) {
				        self.profile = profile
				        self.badge = badge
				    }

				    @Instantiated let profile: Profile
				    @Instantiated let badge: Badge
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct DefaultUserService: Instantiable, UserService {
				    public init(badge: Badge?) {
				        self.badge = badge
				    }

				    @Received(onlyIfAvailable: true) let badge: Badge?
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsErrorOfferingToInstantiateAboveTheSeam_whenFillReceivesHoleBuiltAfterItWhoseImplementationReceivesNothing`.
		Template(kind: "declarationBoundAfterSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Detail {}
				public protocol Settings {}
				public protocol Pair {}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(detailBuilder: ErasedInstantiator<(), any Detail>, settingsBuilder: ErasedInstantiator<(), any Settings>) {
				        self.detailBuilder = detailBuilder
				        self.settingsBuilder = settingsBuilder
				    }

				    @Instantiated(fulfilledByType: "DefaultDetail") public let detailBuilder: ErasedInstantiator<(), any Detail>
				    @Instantiated(fulfilledByType: "DefaultSettings") public let settingsBuilder: ErasedInstantiator<(), any Settings>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable
				public struct DefaultDetail: Instantiable, Detail {
				    public init(settingsBuilder: ErasedInstantiator<(), any Settings>) {
				        self.settingsBuilder = settingsBuilder
				    }

				    @Received public let settingsBuilder: ErasedInstantiator<(), any Settings>
				}
				"""#,
				#"""
				import Feature

				@Instantiable
				public struct DefaultSettings: Instantiable, Settings {
				    public init() {}
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated public let screen: Screen
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarryNamingDeclaringType_whenTypeInSeamsTreeDeclaresSiblingThatRequiresHolesCarrier`.
		Template(kind: "declarationBoundAfterSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				@Instantiable
				public struct Badge: Instantiable {
				    public init(profile: Profile) {
				        self.profile = profile
				    }

				    @Received let profile: Profile
				}
				"""#,
				#"""
				@Instantiable
				public struct Mid: Instantiable {
				    public init(profile: Profile, badge: Badge) {
				        self.profile = profile
				        self.badge = badge
				    }

				    @Instantiated let profile: Profile
				    @Instantiated let badge: Badge
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(mid: Mid) {
				        self.mid = mid
				    }

				    @Instantiated let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct DefaultUserService: Instantiable, UserService {
				    public init(badge: Badge?) {
				        self.badge = badge
				    }

				    @Received(onlyIfAvailable: true) let badge: Badge?
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarry_whenImplementationsOfTwoHolesReceiveEachOthersInstantiators`.
		Template(kind: "declarationBoundAfterSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Detail {}
				public protocol Settings {}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(detailBuilder: ErasedInstantiator<(), any Detail>, settingsBuilder: ErasedInstantiator<(), any Settings>) {
				        self.detailBuilder = detailBuilder
				        self.settingsBuilder = settingsBuilder
				    }

				    @Instantiated(fulfilledByType: "DefaultDetail") let detailBuilder: ErasedInstantiator<(), any Detail>
				    @Instantiated(fulfilledByType: "DefaultSettings") let settingsBuilder: ErasedInstantiator<(), any Settings>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable
				public struct DefaultDetail: Instantiable, Detail {
				    public init(settingsBuilder: ErasedInstantiator<(), any Settings>) {
				        self.settingsBuilder = settingsBuilder
				    }

				    @Received let settingsBuilder: ErasedInstantiator<(), any Settings>
				}
				"""#,
				#"""
				import Feature

				@Instantiable
				public struct DefaultSettings: Instantiable, Settings {
				    public init(detailBuilder: ErasedInstantiator<(), any Detail>) {
				        self.detailBuilder = detailBuilder
				    }

				    @Received let detailBuilder: ErasedInstantiator<(), any Detail>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsErrorOfferingOneHoleInPlaceOfBoth_whenFillReceivesInstantiatorWhoseTreeReceivesValuesTheSeamBinds`.
		Template(kind: "declarationBoundAfterSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol AScreen {}
				public protocol BScreen {}
				public protocol Pair {}
				"""#,
				#"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable(fulfillingAdditionalTypes: [AScreen.self])
				public struct A: Instantiable, AScreen {
				    public init(user: User, bBuilder: ErasedInstantiator<(), any BScreen>) {
				        self.user = user
				        self.bBuilder = bBuilder
				    }

				    @Received public let user: User
				    @Received public let bBuilder: ErasedInstantiator<(), any BScreen>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SignedIn: Instantiable {
				    public init(user: User, aBuilder: ErasedInstantiator<(), any AScreen>, bBuilder: ErasedInstantiator<(), any BScreen>) {
				        self.user = user
				        self.aBuilder = aBuilder
				        self.bBuilder = bBuilder
				    }

				    @Forwarded public let user: User
				    @Instantiated(fulfilledByType: "A") public let aBuilder: ErasedInstantiator<(), any AScreen>
				    @Instantiated(fulfilledByType: "B") public let bBuilder: ErasedInstantiator<(), any BScreen>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [BScreen.self])
				public struct B: Instantiable, BScreen {
				    public init(aBuilder: ErasedInstantiator<(), any AScreen>) {
				        self.aBuilder = aBuilder
				    }

				    @Received public let aBuilder: ErasedInstantiator<(), any AScreen>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(signedInBuilder: Instantiator<SignedIn>) {
				        self.signedInBuilder = signedInBuilder
				    }

				    @Instantiated public let signedInBuilder: Instantiator<SignedIn>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsErrorOfferingOnlyToFulfillTheHole_whenFillReceivesHoleBuiltAfterItThatAnotherModuleFills`.
		Template(kind: "declarationBoundAfterSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Detail {}
				public protocol Settings {}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(detailBuilder: ErasedInstantiator<(), any Detail>, settingsBuilder: ErasedInstantiator<(), any Settings>) {
				        self.detailBuilder = detailBuilder
				        self.settingsBuilder = settingsBuilder
				    }

				    @Instantiated(fulfilledByType: "DefaultDetail") public let detailBuilder: ErasedInstantiator<(), any Detail>
				    @Instantiated(fulfilledByType: "DefaultSettings") public let settingsBuilder: ErasedInstantiator<(), any Settings>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
				#"""
				import Feature

				@Instantiable
				public final class Token: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				import Feature

				@Instantiable
				public struct DefaultSettings: Instantiable, Settings {
				    public init(token: Token) {
				        self.token = token
				    }

				    @Received public let token: Token
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Outer: Instantiable {
				    public init(token: Token, screen: Screen) {
				        self.token = token
				        self.screen = screen
				    }

				    @Instantiated public let token: Token
				    @Instantiated public let screen: Screen
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable
				public struct DefaultDetail: Instantiable, Detail {
				    public init(settingsBuilder: ErasedInstantiator<(), any Settings>) {
				        self.settingsBuilder = settingsBuilder
				    }

				    @Received public let settingsBuilder: ErasedInstantiator<(), any Settings>
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(outer: Outer) {
				        self.outer = outer
				    }

				    @Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsFindingOfOnePlace_whenAnotherPlacesFillStandsForPlaceThatBindsValueAfterIt`.
		Template(kind: "declarationBoundAfterSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				"""#,
				#"""
				public protocol Gadget {}
				"""#,
				#"""
				@Instantiable
				public struct Token: Instantiable {
				    public init(panel: Panel) {
				        self.panel = panel
				    }

				    @Received let panel: Panel
				}
				"""#,
				#"""
				@Instantiable
				public struct Row: Instantiable {
				    public init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated let api: any Api
				}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable {
				    public init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated let api: any Api
				}
				"""#,
				#"""
				@Instantiable
				public struct First: Instantiable {
				    public init(panel: Panel) {
				        self.panel = panel
				    }

				    @Instantiated let panel: Panel
				}
				"""#,
				#"""
				@Instantiable
				public struct Second: Instantiable {
				    public init(panel: Panel) {
				        self.panel = panel
				    }

				    @Instantiated let panel: Panel
				}
				"""#,
				#"""
				@Instantiable
				public struct Third: Instantiable {
				    public init(panel: Panel, token: Token) {
				        self.panel = panel
				        self.token = token
				    }

				    @Instantiated let panel: Panel
				    @Instantiated let token: Token
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Home: Instantiable {
				    public init(first: First, second: Second, third: Third) {
				        self.first = first
				        self.second = second
				        self.third = third
				    }

				    @Instantiated let first: First
				    @Instantiated let second: Second
				    @Instantiated let third: Third
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(home: Home) {
				        self.home = home
				    }

				    @Instantiated let home: Home
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueBuiltAfterPlacesNamingEveryBuilder_whenOneReaderFillsPlacesOfTwoBuildersDeclaredInTwoFiles`.
		Template(kind: "declarationBoundAfterSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService: Sendable {}

				public struct AnyUserService: UserService {
				    public init(_ base: any UserService) {
				        self.base = base
				    }

				    let base: any UserService
				}
				"""#,
				#"""
				@Instantiable
				public struct Holder: Instantiable {
				    public init(profile: Profile, account: Account) {
				        self.profile = profile
				        self.account = account
				    }

				    @Instantiated let profile: Profile
				    @Instantiated let account: Account
				}
				"""#,
				#"""
				@Instantiable
				public struct Badge: Instantiable {
				    public init(holder: Holder) {
				        self.holder = holder
				    }

				    @Received let holder: Holder
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(holder: Holder, badge: Badge) {
				        self.holder = holder
				        self.badge = badge
				    }

				    @Instantiated let holder: Holder
				    @Instantiated let badge: Badge
				}
				"""#,
			], swiftFileContentByFilePath: [
				"PlaceA.swift": #"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: AnyUserService) {
				        self.userService = userService
				    }

				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				"""#,
				"PlaceB.swift": #"""
				@Instantiable
				public struct Account: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated(fulfilledByType: "DefaultUserService") let userService: any UserService
				}
				"""#,
			], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable
				public struct DefaultUserService: Instantiable, UserService {
				    public init(badge: Badge?) {
				        self.badge = badge
				    }

				    @Received(onlyIfAvailable: true) let badge: Badge?
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueACycleDeclaresAgain_whenHoleSitsOnLazyCycle`.
		Template(kind: "declarationBoundOnCycleReentry", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(api: any Api, bBuilder: Instantiator<B>) {
				        self.api = api
				        self.bBuilder = bBuilder
				    }

				    @Instantiated public let api: any Api
				    @Instantiated public let bBuilder: Instantiator<B>
				}
				"""#,
				#"""
				@Instantiable
				public struct B: Instantiable {
				    public init(count: Int, a: LazilyInstantiated<A>) {
				        self.count = count
				        self.a = a
				    }

				    @Forwarded public let count: Int
				    @Instantiated public let a: LazilyInstantiated<A>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Hub: Instantiable {
				    public init(a: LazilyInstantiated<A>) {
				        self.a = a
				    }

				    @Instantiated public let a: LazilyInstantiated<A>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(count: Int?) {
				        self.count = count
				    }

				    @Received(onlyIfAvailable: true) public let count: Int?
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(hub: Hub) {
				        self.hub = hub
				    }

				    @Instantiated public let hub: Hub
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsErrorOfferingReceiveOnlyIfAvailableOnTheTypeBuiltAgain_whenFillReceivesValueTheCycleDeclaresOnlyIfAvailable`.
		Template(kind: "declarationBoundOnCycleReentry", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(name: String, api: any Api, bBuilder: Instantiator<B>) {
				        self.name = name
				        self.api = api
				        self.bBuilder = bBuilder
				    }

				    @Forwarded public let name: String
				    @Instantiated public let api: any Api
				    @Instantiated public let bBuilder: Instantiator<B>
				}
				"""#,
				#"""
				@Instantiable
				public struct B: Instantiable {
				    public init(count: Int, aBuilder: Instantiator<A>) {
				        self.count = count
				        self.aBuilder = aBuilder
				    }

				    @Forwarded public let count: Int
				    @Instantiated public let aBuilder: Instantiator<A>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Hub: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated public let aBuilder: Instantiator<A>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(name: String?, count: Int?) {
				        self.name = name
				        self.count = count
				    }

				    @Received(onlyIfAvailable: true) public let name: String?
				    @Received(onlyIfAvailable: true) public let count: Int?
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(hub: Hub) {
				        self.hub = hub
				    }

				    @Instantiated public let hub: Hub
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueACycleDeclaresAgain_whenHoleSitsOnInstantiatorCycleAndFillReceivesLabelOnlyIfAvailable`.
		Template(kind: "declarationBoundOnCycleReentry", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(name: String, api: any Api, bBuilder: Instantiator<B>) {
				        self.name = name
				        self.api = api
				        self.bBuilder = bBuilder
				    }

				    @Forwarded public let name: String
				    @Instantiated public let api: any Api
				    @Instantiated public let bBuilder: Instantiator<B>
				}
				"""#,
				#"""
				@Instantiable
				public struct B: Instantiable {
				    public init(count: Int, aBuilder: Instantiator<A>) {
				        self.count = count
				        self.aBuilder = aBuilder
				    }

				    @Forwarded public let count: Int
				    @Instantiated public let aBuilder: Instantiator<A>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Hub: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated public let aBuilder: Instantiator<A>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(name: String?, count: Int?) {
				        self.name = name
				        self.count = count
				    }

				    @Received(onlyIfAvailable: true) public let name: String?
				    @Received(onlyIfAvailable: true) public let count: Int?
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(hub: Hub) {
				        self.hub = hub
				    }

				    @Instantiated public let hub: Hub
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueACycleDeclaresAgain_whenTangleOfCyclesBuildsTypeAgainThroughFunctionThatTakesNoParameter`.
		Template(kind: "declarationBoundOnCycleReentry", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				"""#,
				#"""
				@Instantiable
				public struct Mark: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct T: Instantiable {
				    public init(cBuilder: Instantiator<C>, api: any Api) {
				        self.cBuilder = cBuilder
				        self.api = api
				    }

				    @Instantiated public let cBuilder: Instantiator<C>
				    @Instantiated public let api: any Api
				}
				"""#,
				#"""
				@Instantiable
				public struct C: Instantiable {
				    public init(mark: Mark, tBuilder: Instantiator<T>) {
				        self.mark = mark
				        self.tBuilder = tBuilder
				    }

				    @Instantiated public let mark: Mark
				    @Instantiated public let tBuilder: Instantiator<T>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Hub: Instantiable {
				    public init(tBuilder: Instantiator<T>, cBuilder: Instantiator<C>) {
				        self.tBuilder = tBuilder
				        self.cBuilder = cBuilder
				    }

				    @Instantiated public let tBuilder: Instantiator<T>
				    @Instantiated public let cBuilder: Instantiator<C>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(mark: Mark?) {
				        self.mark = mark
				    }

				    @Received(onlyIfAvailable: true) public let mark: Mark?
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(hub: Hub) {
				        self.hub = hub
				    }

				    @Instantiated public let hub: Hub
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueACycleDeclaresAgain_whenSeamPassesUpPlaceOfCallInsideCycleOfItsOwnTree`.
		Template(kind: "declarationBoundOnCycleReentry", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				"""#,
				#"""
				@Instantiable
				public final class L: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Hub: Instantiable {
				    public init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Shell: Instantiable {
				    public init(wBuilder: Instantiator<W>) {
				        self.wBuilder = wBuilder
				    }

				    @Instantiated public let wBuilder: Instantiator<W>
				}
				"""#,
				#"""
				@Instantiable
				public struct W: Instantiable {
				    public init(hub: Hub, pBuilder: Instantiator<P>) {
				        self.hub = hub
				        self.pBuilder = pBuilder
				    }

				    @Instantiated public let hub: Hub
				    @Instantiated public let pBuilder: Instantiator<P>
				}
				"""#,
				#"""
				@Instantiable
				public struct P: Instantiable {
				    public init(l: L, wBuilder: Instantiator<W>) {
				        self.l = l
				        self.wBuilder = wBuilder
				    }

				    @Instantiated public let l: L
				    @Instantiated public let wBuilder: Instantiator<W>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(l: L) {
				        self.l = l
				    }

				    @Received public let l: L
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(l: L, shell: Shell) {
				        self.l = l
				        self.shell = shell
				    }

				    @Instantiated public let l: L
				    @Instantiated public let shell: Shell
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueACycleDeclaresAgain_whenSeamThatCallsHubPassesBuilderUp`.
		Template(kind: "declarationBoundOnCycleReentry", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(name: String, api: any Api, bBuilder: Instantiator<B>) {
				        self.name = name
				        self.api = api
				        self.bBuilder = bBuilder
				    }

				    @Forwarded public let name: String
				    @Instantiated public let api: any Api
				    @Instantiated public let bBuilder: Instantiator<B>
				}
				"""#,
				#"""
				@Instantiable
				public struct B: Instantiable {
				    public init(count: Int, aBuilder: Instantiator<A>) {
				        self.count = count
				        self.aBuilder = aBuilder
				    }

				    @Forwarded public let count: Int
				    @Instantiated public let aBuilder: Instantiator<A>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Hub: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated public let aBuilder: Instantiator<A>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Shell: Instantiable {
				    public init(hub: Hub) {
				        self.hub = hub
				    }

				    @Instantiated public let hub: Hub
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(count: Int?) {
				        self.count = count
				    }

				    @Received(onlyIfAvailable: true) public let count: Int?
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(shell: Shell) {
				        self.shell = shell
				    }

				    @Instantiated public let shell: Shell
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsErrorOfferingReceiveOnTheTypeBuiltAgain_whenFillReadsValueTheCycleDeclaresAgain`.
		Template(kind: "declarationBoundOnCycleReentry", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				public protocol StepScreen {}
				"""#,
				#"""
				@Instantiable
				public final class Cache: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Home: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated public let screen: Screen
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(cache: Cache, stepBuilder: Instantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }

				    @Instantiated public let cache: Cache
				    @Instantiated public let stepBuilder: Instantiator<Step>
				}
				"""#,
				#"""
				@Instantiable
				public struct Step: Instantiable, StepScreen {
				    public init(api: any Api, screenBuilder: Instantiator<Screen>) {
				        self.api = api
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let api: any Api
				    @Instantiated public let screenBuilder: Instantiator<Screen>
				}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable {
				    public init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct Live: Instantiable, Api {
				    public init(cache: Cache) {
				        self.cache = cache
				    }

				    @Received public let cache: Cache
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(home: Home) {
				        self.home = home
				    }

				    @Instantiated public let home: Home
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsErrorOfferingReceiveOnTheTypeBuiltAgain_whenPlaceIsBeneathTheTypeBuiltAgain`.
		Template(kind: "declarationBoundOnCycleReentry", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				public protocol StepScreen {}
				"""#,
				#"""
				@Instantiable
				public final class Cache: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Home: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated public let screen: Screen
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(cache: Cache, stepBuilder: Instantiator<Step>) {
				        self.cache = cache
				        self.stepBuilder = stepBuilder
				    }

				    @Instantiated public let cache: Cache
				    @Instantiated public let stepBuilder: Instantiator<Step>
				}
				"""#,
				#"""
				@Instantiable
				public struct Step: Instantiable, StepScreen {
				    public init(panel: Panel, screenBuilder: Instantiator<Screen>) {
				        self.panel = panel
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let panel: Panel
				    @Instantiated public let screenBuilder: Instantiator<Screen>
				}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable {
				    public init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct Live: Instantiable, Api {
				    public init(cache: Cache) {
				        self.cache = cache
				    }

				    @Received public let cache: Cache
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(home: Home) {
				        self.home = home
				    }

				    @Instantiated public let home: Home
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarry_whenScopeInsideFillDeclaresLabelFillReadsFromCallerAboveCallThatReentersSeam`.
		Template(kind: "declarationBoundOnPathToReenteringCall", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				#if canImport(Foundation)
				public protocol Router {}
				#endif
				"""#,
				#"""
				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(router: any Router) {
				        self.router = router
				    }

				    @Instantiated let router: any Router
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public final class Flow: Instantiable {
				    public init(profileBuilder: Instantiator<Profile>) {
				        self.profileBuilder = profileBuilder
				    }

				    @Instantiated let profileBuilder: Instantiator<Profile>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Router.self])
				public struct DefaultRouter: Instantiable, Router {
				    public init(logger: Logger, middle: Middle) {
				        self.logger = logger
				        self.middle = middle
				    }

				    @Received let logger: Logger
				    @Instantiated let middle: Middle
				}
				"""#,
				#"""
				import Feature

				@Instantiable
				public final class Middle: Instantiable {
				    public init(logger: Logger, flowBuilder: Instantiator<Flow>) {
				        self.logger = logger
				        self.flowBuilder = flowBuilder
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let flowBuilder: Instantiator<Flow>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(logger: Logger, flow: Flow) {
				        self.logger = logger
				        self.flow = flow
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let flow: Flow
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarryNamingEveryPathAndRemedyOfEveryPlace_whenTwoBuildersOfOneFillReachCallThatReentersSeam`.
		Template(kind: "declarationBoundOnPathToReenteringCall", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				#if canImport(Foundation)
				public protocol Router {}
				#endif
				"""#,
				#"""
				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(routerLater: ErasedInstantiator<(), any Router>, router: any Router) {
				        self.routerLater = routerLater
				        self.router = router
				    }

				    @Instantiated(fulfilledByType: "DefaultRouter") let routerLater: ErasedInstantiator<(), any Router>
				    @Instantiated let router: any Router
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public final class Flow: Instantiable {
				    public init(profileBuilder: Instantiator<Profile>) {
				        self.profileBuilder = profileBuilder
				    }

				    @Instantiated let profileBuilder: Instantiator<Profile>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Router.self])
				public struct DefaultRouter: Instantiable, Router {
				    public init(logger: Logger, middle: Middle) {
				        self.logger = logger
				        self.middle = middle
				    }

				    @Received let logger: Logger
				    @Instantiated let middle: Middle
				}
				"""#,
				#"""
				import Feature

				@Instantiable
				public final class Middle: Instantiable {
				    public init(logger: Logger, flowBuilder: Instantiator<Flow>) {
				        self.logger = logger
				        self.flowBuilder = flowBuilder
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let flowBuilder: Instantiator<Flow>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(logger: Logger, flow: Flow) {
				        self.logger = logger
				        self.flow = flow
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let flow: Flow
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarryNamingEveryPath_whenFillsOfPlacesDeclaredInTwoFilesReachCallThatReentersSeam`.
		Template(kind: "declarationBoundOnPathToReenteringCall", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [], swiftFileContentByFilePath: [
				"File1.swift": #"""
				#if canImport(Foundation)
				public protocol Router {}
				#endif
				"""#,
				"File2.swift": #"""
				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				}
				"""#,
				"File3.swift": #"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(router: any Router) {
				        self.router = router
				    }

				    @Instantiated let router: any Router
				}
				"""#,
				"File4.swift": #"""
				@Instantiable
				public final class Screen: Instantiable {
				    public init(screenRouter: any Router) {
				        self.screenRouter = screenRouter
				    }

				    @Instantiated let screenRouter: any Router
				}
				"""#,
				"File5.swift": #"""
				@Instantiable(generateDependencyTree: true)
				public final class Flow: Instantiable {
				    public init(profileBuilder: Instantiator<Profile>, screenBuilder: Instantiator<Screen>) {
				        self.profileBuilder = profileBuilder
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let profileBuilder: Instantiator<Profile>
				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				"""#,
			], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Router.self])
				public struct DefaultRouter: Instantiable, Router {
				    public init(logger: Logger, middle: Middle) {
				        self.logger = logger
				        self.middle = middle
				    }

				    @Received let logger: Logger
				    @Instantiated let middle: Middle
				}
				"""#,
				#"""
				import Feature

				@Instantiable
				public final class Middle: Instantiable {
				    public init(logger: Logger, flowBuilder: Instantiator<Flow>) {
				        self.logger = logger
				        self.flowBuilder = flowBuilder
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let flowBuilder: Instantiator<Flow>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(logger: Logger, flow: Flow) {
				        self.logger = logger
				        self.flow = flow
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let flow: Flow
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarryNamingEveryPathAndRemedyOfEveryPlace_whenTwoPlacesPassedUpThroughOnePropertyReachCallThatReentersSeam`.
		Template(kind: "declarationBoundOnPathToReenteringCall", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				#if canImport(Foundation)
				public protocol Router {}
				#endif
				"""#,
				#"""
				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(routerLater: ErasedInstantiator<(), any Router>, router: any Router) {
				        self.routerLater = routerLater
				        self.router = router
				    }

				    @Instantiated(fulfilledByType: "DefaultRouter") let routerLater: ErasedInstantiator<(), any Router>
				    @Instantiated let router: any Router
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public final class Flow: Instantiable {
				    public init(profileBuilder: Instantiator<Profile>) {
				        self.profileBuilder = profileBuilder
				    }

				    @Instantiated let profileBuilder: Instantiator<Profile>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public final class Shell: Instantiable {
				    public init(flow: Flow) {
				        self.flow = flow
				    }

				    @Instantiated let flow: Flow
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Router.self])
				public struct DefaultRouter: Instantiable, Router {
				    public init(logger: Logger, middle: Middle) {
				        self.logger = logger
				        self.middle = middle
				    }

				    @Received let logger: Logger
				    @Instantiated let middle: Middle
				}
				"""#,
				#"""
				import Feature

				@Instantiable
				public final class Middle: Instantiable {
				    public init(logger: Logger, shellBuilder: Instantiator<Shell>) {
				        self.logger = logger
				        self.shellBuilder = shellBuilder
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let shellBuilder: Instantiator<Shell>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(logger: Logger, shell: Shell) {
				        self.logger = logger
				        self.shell = shell
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let shell: Shell
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsDeclarationBoundOnPathToReenteringCall_whenCallInsideOneFillPassesSiblingFillBeneathRedeclaredLabel`.
		Template(kind: "declarationBoundOnPathToReenteringCall", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Router {}
				public protocol Tracker {}
				"""#,
				#"""
				@Instantiable
				public final class Logger: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(router: any Router) {
				        self.router = router
				    }

				    @Instantiated let router: any Router
				}
				"""#,
				#"""
				@Instantiable
				public struct Settings: Instantiable {
				    public init(tracker: any Tracker) {
				        self.tracker = tracker
				    }

				    @Instantiated let tracker: any Tracker
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Flow: Instantiable {
				    public init(profileBuilder: Instantiator<Profile>, settings: Settings) {
				        self.profileBuilder = profileBuilder
				        self.settings = settings
				    }

				    @Instantiated let profileBuilder: Instantiator<Profile>
				    @Instantiated let settings: Settings
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Router.self])
				public struct DefaultRouter: Instantiable, Router {
				    public init(middle: Middle) {
				        self.middle = middle
				    }

				    @Instantiated let middle: Middle
				}
				"""#,
				#"""
				import Feature

				@Instantiable
				public struct Middle: Instantiable {
				    public init(logger: Logger, flowBuilder: Instantiator<Flow>) {
				        self.logger = logger
				        self.flowBuilder = flowBuilder
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let flowBuilder: Instantiator<Flow>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Tracker.self])
				public struct DefaultTracker: Instantiable, Tracker {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received let logger: Logger
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(logger: Logger, flow: Flow) {
				        self.logger = logger
				        self.flow = flow
				    }

				    @Instantiated let logger: Logger
				    @Instantiated let flow: Flow
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueOfOneRoute_whenCallerFillsPlaceInsideFillBuiltAgain`.
		Template(kind: "declarationBoundOnPathToReenteringCall", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol First {}
				"""#,
				#"""
				public protocol Second {}
				"""#,
				#"""
				@Instantiable
				public struct X: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Label: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubA: Instantiable {
				    public init(first: any First) {
				        self.first = first
				    }

				    @Instantiated let first: any First
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubB: Instantiable {
				    public init(second: any Second) {
				        self.second = second
				    }

				    @Instantiated let second: any Second
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Top: Instantiable {
				    public init(subA: SubA, subB: SubB) {
				        self.subA = subA
				        self.subB = subB
				    }

				    @Instantiated let subA: SubA
				    @Instantiated let subB: SubB
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
				#"""
				import Feature

				public protocol Gadget {}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [First.self])
				public struct DefaultFirst: Instantiable, First {
				    public init(x: X, subB: SubB) {
				        self.x = x
				        self.subB = subB
				    }

				    @Instantiated let x: X
				    @Instantiated let subB: SubB
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Second.self])
				public struct DefaultSecond: Instantiable, Second {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Host: Instantiable {
				    public init(top: Top) {
				        self.top = top
				    }

				    @Instantiated let top: Top
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct DefaultGadget: Instantiable, Gadget {
				    public init(x: X?) {
				        self.x = x
				    }

				    @Received(onlyIfAvailable: true) let x: X?
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsFillReadsValueOfOneRoute_whenTypeAboveSeamCallDeclaresLabelTooAndReaderRequiresIt`.
		Template(kind: "declarationBoundOnPathToReenteringCall", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol First {}
				"""#,
				#"""
				public protocol Second {}
				"""#,
				#"""
				@Instantiable
				public struct X: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Label: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubA: Instantiable {
				    public init(first: any First) {
				        self.first = first
				    }

				    @Instantiated let first: any First
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubB: Instantiable {
				    public init(second: any Second) {
				        self.second = second
				    }

				    @Instantiated let second: any Second
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Top: Instantiable {
				    public init(subA: SubA, subB: SubB) {
				        self.subA = subA
				        self.subB = subB
				    }

				    @Instantiated let subA: SubA
				    @Instantiated let subB: SubB
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
				#"""
				import Feature

				public protocol Gadget {}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [First.self])
				public struct DefaultFirst: Instantiable, First {
				    public init(x: X, subB: SubB) {
				        self.x = x
				        self.subB = subB
				    }

				    @Instantiated let x: X
				    @Instantiated let subB: SubB
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Second.self])
				public struct DefaultSecond: Instantiable, Second {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Host: Instantiable {
				    public init(x: X, top: Top) {
				        self.x = x
				        self.top = top
				    }

				    @Instantiated let x: X
				    @Instantiated let top: Top
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct DefaultGadget: Instantiable, Gadget {
				    public init(x: X) {
				        self.x = x
				    }

				    @Received let x: X
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsFillReadsValueOfOneRoute_whenPlaceWhoseFillBuildsSeamAgainCarriesLabelToo`.
		Template(kind: "declarationBoundOnPathToReenteringCall", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol First {}
				"""#,
				#"""
				public protocol Second {}
				"""#,
				#"""
				@Instantiable
				public struct X: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Label: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubA: Instantiable {
				    public init(x: X, first: any First) {
				        self.x = x
				        self.first = first
				    }

				    @Instantiated let x: X
				    @Instantiated let first: any First
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubB: Instantiable {
				    public init(second: any Second) {
				        self.second = second
				    }

				    @Instantiated let second: any Second
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Top: Instantiable {
				    public init(subA: SubA, subB: SubB) {
				        self.subA = subA
				        self.subB = subB
				    }

				    @Instantiated let subA: SubA
				    @Instantiated let subB: SubB
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
				#"""
				import Feature

				public protocol Gadget {}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [First.self])
				public struct DefaultFirst: Instantiable, First {
				    public init(x: X, subB: SubB) {
				        self.x = x
				        self.subB = subB
				    }

				    @Instantiated let x: X
				    @Instantiated let subB: SubB
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Second.self])
				public struct DefaultSecond: Instantiable, Second {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Host: Instantiable {
				    public init(top: Top) {
				        self.top = top
				    }

				    @Instantiated let top: Top
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct DefaultGadget: Instantiable, Gadget {
				    public init(x: X?) {
				        self.x = x
				    }

				    @Received(onlyIfAvailable: true) let x: X?
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsDeclarationHiddenByField_whenFillingSeamsFillReadsWrapperAlone`.
		Template(kind: "declarationHiddenByField", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public protocol Service: Sendable {}

				@Instantiable
				public final class Token: Instantiable, Sendable {
					public init() {}
				}

				@Instantiable
				public final class Leaf: Instantiable, Sendable {
					public init(token: Token) { self.token = token }
					@Received public let token: Token
				}

				@Instantiable(generateDependencyTree: true)
				public final class Inner: Instantiable, Sendable {
					public init(leafBuilder: SendableInstantiator<Leaf>, service: any Service) {
						self.leafBuilder = leafBuilder
						self.service = service
					}
					@Instantiated public let leafBuilder: SendableInstantiator<Leaf>
					@Instantiated public let service: any Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Session", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, Sendable {
					public init(token: SendableLazilyInstantiated<Token>, inner: Inner) {
						self.token = token
						self.inner = inner
					}
					@Instantiated public let token: SendableLazilyInstantiated<Token>
					@Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Session
				import SafeDI

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(token: SendableLazilyInstantiated<Token>) { self.token = token }
					@Received public let token: SendableLazilyInstantiated<Token>
				}

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public final class ServiceImpl: Instantiable, Service, Sendable {
					public init(wrapperReader: WrapperReader) {
						self.wrapperReader = wrapperReader
					}
					@Instantiated public let wrapperReader: WrapperReader
				}

				@Instantiable(generateDependencyTree: true)
				public final class Top: Instantiable, Sendable {
					public init(outer: Outer) { self.outer = outer }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Session"]),
			ModuleFixture(name: "App", packageName: "Min", swiftFileContent: [
				#"""
				import Feature
				import SafeDI

				@Instantiable(isRoot: true)
				public final class Root: Instantiable, Sendable {
					public init(top: Top) { self.top = top }
					@Instantiated public let top: Top
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Session", "Feature"]),
		]),
		// From `generate_throwsDeclarationHiddenByField_whenFillingSeamsFillReadsPlainWrapperBesideValueInsideSendableInstantiator`.
		Template(kind: "declarationHiddenByField", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public protocol Service: Sendable {}

				@Instantiable
				public final class Token: Instantiable, @unchecked Sendable {
					public init() {}
				}

				@Instantiable
				public final class Leaf: Instantiable, @unchecked Sendable {
					public init(token: Token) { self.token = token }
					@Received public let token: Token
				}

				@Instantiable(generateDependencyTree: true)
				public final class Inner: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<Leaf>, service: any Service) {
						self.leafBuilder = leafBuilder
						self.service = service
					}
					@Instantiated public let leafBuilder: Instantiator<Leaf>
					@Instantiated public let service: any Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Session", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(token: LazilyInstantiated<Token>, inner: Inner) {
						self.token = token
						self.inner = inner
					}
					@Instantiated public let token: LazilyInstantiated<Token>
					@Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Session
				import SafeDI

				@Instantiable
				public final class WrapperReader: Instantiable, @unchecked Sendable {
					public init(token: LazilyInstantiated<Token>) { self.token = token }
					@Received public let token: LazilyInstantiated<Token>
				}

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public final class ServiceImpl: Instantiable, Service, @unchecked Sendable {
					public init(leafBuilder: SendableInstantiator<Leaf>, wrapperReader: WrapperReader) {
						self.leafBuilder = leafBuilder
						self.wrapperReader = wrapperReader
					}
					@Instantiated public let leafBuilder: SendableInstantiator<Leaf>
					@Instantiated public let wrapperReader: WrapperReader
				}

				@Instantiable(generateDependencyTree: true)
				public final class Top: Instantiable, @unchecked Sendable {
					public init(outer: Outer) { self.outer = outer }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Session"]),
			ModuleFixture(name: "App", packageName: "Min", swiftFileContent: [
				#"""
				import Feature
				import SafeDI

				@Instantiable(isRoot: true)
				public final class Root: Instantiable, @unchecked Sendable {
					public init(top: Top) { self.top = top }
					@Instantiated public let top: Top
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Session", "Feature"]),
		]),
		// From `generate_throwsDeclarationHiddenByField_whenModuleFillsPlaceOfSeamThatFillsItsOwnPlaceAndPassingUpSeamDeclaresSendableWrapper`.
		Template(kind: "declarationHiddenByField", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, seam: Seam) { self.chainToken = chainToken; self.seam = seam; log.append("Outer") }
					@Instantiated public let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let seam: Seam
				}

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(reader: WrapperReader) { self.reader = reader; log.append("ThingImpl") }
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(mid: Mid) { self.mid = mid; log.append("TopRoot") }
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsDeclarationHiddenByField_whenOnlyCallingSeamDeclaresSendableWrapperTreeReadsAlone`.
		Template(kind: "declarationHiddenByField", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(seam: Seam) { self.seam = seam; log.append("Outer") }
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, outer: Outer) { self.chainToken = chainToken; self.outer = outer; log.append("Mid") }
					@Instantiated public let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(reader: WrapperReader) { self.reader = reader; log.append("ThingImpl") }
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(mid: Mid) { self.mid = mid; log.append("TopRoot") }
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsDeclarationHiddenByField_whenOnlyPassingUpSeamDeclaresSendableWrapperTreeReadsAlone`.
		Template(kind: "declarationHiddenByField", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, seam: Seam) { self.chainToken = chainToken; self.seam = seam; log.append("Outer") }
					@Instantiated public let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(reader: WrapperReader) { self.reader = reader; log.append("ThingImpl") }
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(mid: Mid) { self.mid = mid; log.append("TopRoot") }
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsDeclarationHiddenByField_whenOnlyPassingUpSeamDeclaresSendableWrapperTreeReadsOnlyIfAvailable`.
		Template(kind: "declarationHiddenByField", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, seam: Seam) { self.chainToken = chainToken; self.seam = seam; log.append("Outer") }
					@Instantiated public let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(reader: WrapperReader) { self.reader = reader; log.append("ThingImpl") }
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>?) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received(onlyIfAvailable: true) let chainToken: SendableLazilyInstantiated<ChainToken>?
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(mid: Mid) { self.mid = mid; log.append("TopRoot") }
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsDeclarationHiddenByField_whenPassingUpSeamAndRootDeclareLazyWrapperTreeReadsAlone`.
		Template(kind: "declarationHiddenByField", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(chainToken: LazilyInstantiated<ChainToken>, seam: Seam) { self.chainToken = chainToken; self.seam = seam; log.append("Outer") }
					@Instantiated public let chainToken: LazilyInstantiated<ChainToken>
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService, @unchecked Sendable {
					public init(reader: WrapperReader) { self.reader = reader; log.append("ThingImpl") }
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable {
					public init(chainToken: LazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: LazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(chainToken: LazilyInstantiated<ChainToken>, mid: Mid) { self.chainToken = chainToken; self.mid = mid; log.append("TopRoot") }
					@Instantiated let chainToken: LazilyInstantiated<ChainToken>
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsDeclarationHiddenByField_whenPassingUpSeamDeclaresSendableWrapperTreeReadsBesideValue`.
		Template(kind: "declarationHiddenByField", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, seam: Seam) { self.chainToken = chainToken; self.seam = seam; log.append("Outer") }
					@Instantiated public let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(chainToken: ChainToken, reader: WrapperReader) {
						self.chainToken = chainToken
						self.reader = reader
						log.append(reader.chainToken.instance === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
					}
					@Received let chainToken: ChainToken
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(mid: Mid) { self.mid = mid; log.append("TopRoot") }
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsFieldFormsDiffer_whenRoutesToOneCaseHoldReadValueLazilyAndByValue`.
		Template(kind: "fieldFormsDifferBetweenPlaces", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				public final class Session: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Avatar: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				@Instantiable
				public struct Home: Instantiable {
				    public init(session: LazilyInstantiated<Session>, avatar: Avatar) {
				        self.session = session
				        self.avatar = avatar
				    }

				    @Instantiated let session: LazilyInstantiated<Session>
				    @Instantiated let avatar: Avatar
				}
				"""#,
				#"""
				@Instantiable
				public struct Settings: Instantiable {
				    public init(session: Session, avatar: Avatar) {
				        self.session = session
				        self.avatar = avatar
				    }

				    @Instantiated let session: Session
				    @Instantiated let avatar: Avatar
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(home: Home, settings: Settings) {
				        self.home = home
				        self.settings = settings
				    }

				    @Instantiated let home: Home
				    @Instantiated let settings: Settings
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct DefaultUserService: Instantiable, UserService {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillRequiresValueSeamsTreeReceivesOnlyIfAvailable`.
		Template(kind: "fieldHeldOnlyOptionally", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				public struct Theme: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Badge: Instantiable {
				    public init(theme: Theme?) {
				        self.theme = theme
				    }

				    @Received(onlyIfAvailable: true) let theme: Theme?
				}
				"""#,
				#"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(badge: Badge, userService: any UserService) {
				        self.badge = badge
				        self.userService = userService
				    }

				    @Instantiated let badge: Badge
				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(profile: Profile) {
				        self.profile = profile
				    }

				    @Instantiated let profile: Profile
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct ThemedUserService: Instantiable, UserService {
				    public init(theme: Theme) {
				        self.theme = theme
				    }

				    @Received let theme: Theme
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(theme: Theme, service: Service) {
				        self.theme = theme
				        self.service = service
				    }

				    @Instantiated let theme: Theme
				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillRequiresCycleParameterFunctionTakesOptionally`.
		Template(kind: "fieldHeldOnlyOptionally", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public enum Counter {
					nonisolated(unsafe) private static var lastStamp = 0

					public static func next() -> Int {
						lastStamp += 1
						return lastStamp
					}
				}
				"""#,
				#"""
				public protocol Api {}
				"""#,
				#"""
				@Instantiable
				public final class Tag: Instantiable {
				    public init() {}

				    let differentialValueCreationStamp = Counter.next()
				}
				"""#,
				#"""
				@Instantiable
				public struct TagReader: Instantiable {
				    public init(tag: Tag?) {
				        self.tag = tag
				    }

				    @Received(onlyIfAvailable: true) let tag: Tag?
				}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(reader: TagReader, api: any Api, bBuilder: Instantiator<B>) {
				        self.reader = reader
				        self.api = api
				        self.bBuilder = bBuilder
				    }

				    @Instantiated let reader: TagReader
				    @Instantiated let api: any Api
				    @Instantiated let bBuilder: Instantiator<B>
				}
				"""#,
				#"""
				@Instantiable
				public struct B: Instantiable {
				    public init(tag: Tag, aBuilder: Instantiator<A>) {
				        self.tag = tag
				        self.aBuilder = aBuilder
				    }

				    @Forwarded let tag: Tag
				    @Instantiated let aBuilder: Instantiator<A>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Hub: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(tag: Tag) {
				        self.tag = tag
				    }

				    @Received let tag: Tag
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    let differentialValueCreationStamp = Counter.next()

				    public init(tag: Tag, hub: Hub) {
				        self.tag = tag
				        self.hub = hub
				    }

				    @Instantiated let tag: Tag
				    @Instantiated let hub: Hub
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillInOtherPackageReadsPackageField`.
		Template(kind: "fieldNotReadable", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    package init(session: Session, profile: Profile) {
				        self.session = session
				        self.profile = profile
				    }

				    @Instantiated let session: Session
				    @Instantiated let profile: Profile
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct SessionUserService: Instantiable, UserService {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillInOtherModuleReadsFieldOnlyInternalInitializerMentions`.
		Template(kind: "fieldNotReadable", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable {
				    init(token: [3 of Int], profile: Profile) {
				        self.token = token
				        self.profile = profile
				    }

				    @Forwarded let token: [3 of Int]
				    @Instantiated let profile: Profile
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(screenBuilder: Instantiator<Screen>) {
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct TokenUserService: Instantiable, UserService {
				    public init(token: [3 of Int]) {
				        self.token = token
				    }

				    @Received let token: [3 of Int]
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarryNamingPlaceOnce_whenSeamBuildsOwnerOfPlaceUnderTwoParentsDeclaredInTwoFiles`.
		Template(kind: "fieldNotReadable", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    package init(session: Session, a: A, b: B) {
				        self.session = session
				        self.a = a
				        self.b = b
				    }

				    @Instantiated let session: Session
				    @Instantiated let a: A
				    @Instantiated let b: B
				}
				"""#,
			], swiftFileContentByFilePath: [
				"ParentA.swift": #"""
				@Instantiable
				public struct A: Instantiable {
				    public init(profile: Profile) {
				        self.profile = profile
				    }

				    @Instantiated let profile: Profile
				}
				"""#,
				"ParentB.swift": #"""
				@Instantiable
				public struct B: Instantiable {
				    public init(profile: Profile) {
				        self.profile = profile
				    }

				    @Instantiated let profile: Profile
				}
				"""#,
			], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct SessionUserService: Instantiable, UserService {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarryNamingEveryBuilder_whenOneReaderOfPackageFieldFillsPlacesOfTwoBuildersDeclaredInTwoFiles`.
		Template(kind: "fieldNotReadable", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService: Sendable {}

				public struct AnyUserService: UserService {
				    public init(_ base: any UserService) {
				        self.base = base
				    }

				    let base: any UserService
				}
				"""#,
				#"""
				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    package init(session: Session, profile: Profile, account: Account) {
				        self.session = session
				        self.profile = profile
				        self.account = account
				    }

				    @Instantiated let session: Session
				    @Instantiated let profile: Profile
				    @Instantiated let account: Account
				}
				"""#,
			], swiftFileContentByFilePath: [
				"PlaceA.swift": #"""
				@Instantiable
				public struct Account: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated(fulfilledByType: "DefaultUserService") let userService: any UserService
				}
				"""#,
				"PlaceB.swift": #"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: AnyUserService) {
				        self.userService = userService
				    }

				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				"""#,
			], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable
				public struct DefaultUserService: Instantiable, UserService {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarryNamingEveryPlace_whenOneReaderOfPackageFieldFillsThreePlacesDeclaredInThreeFiles`.
		Template(kind: "fieldNotReadable", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    package init(session: Session, profile: Profile, settings: Settings, account: Account) {
				        self.session = session
				        self.profile = profile
				        self.settings = settings
				        self.account = account
				    }

				    @Instantiated let session: Session
				    @Instantiated let profile: Profile
				    @Instantiated let settings: Settings
				    @Instantiated let account: Account
				}
				"""#,
			], swiftFileContentByFilePath: [
				"PlaceA.swift": #"""
				@Instantiable
				public struct Account: Instantiable {
				    public init(userService: any UserService, backupUserService: any UserService) {
				        self.userService = userService
				        self.backupUserService = backupUserService
				    }

				    @Instantiated let userService: any UserService
				    @Instantiated let backupUserService: any UserService
				}
				"""#,
				"PlaceB.swift": #"""
				@Instantiable
				public struct Settings: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				"PlaceC.swift": #"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
			], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct SessionUserService: Instantiable, UserService {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReadsValueTheScopeDoesNotCarry_whenSeamHoldingHoleIsKnownOnlyThroughViewAndFieldIsInternal`.
		Template(kind: "fieldNotReadable", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol UserService {}
				"""#,
				#"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable {
				    init(token: [3 of Int], profile: Profile) {
				        self.token = token
				        self.profile = profile
				    }

				    @Forwarded let token: [3 of Int]
				    @Instantiated let profile: Profile
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    public init(screenBuilder: Instantiator<Screen>) {
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Shell: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Mid

				@Instantiable(fulfillingAdditionalTypes: [UserService.self])
				public struct TokenUserService: Instantiable, UserService {
				    public init(token: [3 of Int]) {
				        self.token = token
				    }

				    @Received let token: [3 of Int]
				}
				"""#,
				#"""
				import Feature
				import Mid

				@Instantiable
				public struct Carrier: Instantiable {
				    public init(token: [3 of Int], userService: any UserService) {
				        self.token = token
				        self.userService = userService
				    }

				    @Forwarded let token: [3 of Int]
				    @Instantiated let userService: any UserService
				}
				"""#,
				#"""
				import Feature
				import Mid

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(shell: Shell, carrierBuilder: Instantiator<Carrier>) {
				        self.shell = shell
				        self.carrierBuilder = carrierBuilder
				    }

				    @Instantiated let shell: Shell
				    @Instantiated let carrierBuilder: Instantiator<Carrier>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Mid"]),
		]),
		// From `generate_throwsFieldOfReenteringPlace_whenFillOpeningItsSeamAgainReadsOnlyIfAvailableValueTheSeamsScreenForwards`.
		Template(kind: "fieldOfReenteringPlace", modules: [
			ModuleFixture(name: "Shared", packageName: "Shop", swiftFileContent: [
				#"""
				import SafeDI

				public final class Cart {
				    public init() {}
				}

				public protocol Payments: AnyObject {}

				@Instantiable(generateDependencyTree: true)
				public struct Checkout: Instantiable {
				    public init(payments: any Payments, cartScreenBuilder: Instantiator<CartScreen>) {
				        self.payments = payments
				        self.cartScreenBuilder = cartScreenBuilder
				    }

				    @Instantiated public let payments: any Payments                    // the app supplies this; no cart here
				    @Instantiated public let cartScreenBuilder: Instantiator<CartScreen>
				}

				@Instantiable
				public struct CartScreen: Instantiable {
				    public init(cart: Cart, payments: any Payments) {
				        self.cart = cart
				        self.payments = payments
				    }

				    @Forwarded public let cart: Cart
				    @Instantiated public let payments: any Payments
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import SafeDI
				import Shared

				@Instantiable(fulfillingAdditionalTypes: [(any Payments).self])
				public final class LivePayments: Payments, Instantiable {
				    public init(cart: Cart?, retryBuilder: Instantiator<Checkout>) {
				        self.cart = cart
				        self.retryBuilder = retryBuilder
				    }

				    @Received(onlyIfAvailable: true) public let cart: Cart?
				    @Instantiated public let retryBuilder: Instantiator<Checkout>
				}
				"""#,
				#"""
				import SafeDI
				import Shared

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(checkout: Checkout) {
				        self.checkout = checkout
				    }

				    @Instantiated public let checkout: Checkout
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Shared"]),
		]),
		// From `generate_throwsFieldOfReenteringPlace_whenFillOpeningItsSeamAgainRequiresValueTheSeamsScreenForwards`.
		Template(kind: "fieldOfReenteringPlace", modules: [
			ModuleFixture(name: "Shared", packageName: "Shop", swiftFileContent: [
				#"""
				import SafeDI

				@Instantiable
				public final class Cart: Instantiable {
				    public init() {}
				}

				public protocol Payments: AnyObject {}

				@Instantiable(generateDependencyTree: true)
				public struct Checkout: Instantiable {
				    public init(payments: any Payments, cartScreenBuilder: Instantiator<CartScreen>) {
				        self.payments = payments
				        self.cartScreenBuilder = cartScreenBuilder
				    }

				    @Instantiated public let payments: any Payments                    // the app supplies this; no cart here
				    @Instantiated public let cartScreenBuilder: Instantiator<CartScreen>
				}

				@Instantiable
				public struct CartScreen: Instantiable {
				    public init(cart: Cart, payments: any Payments) {
				        self.cart = cart
				        self.payments = payments
				    }

				    @Forwarded public let cart: Cart
				    @Instantiated public let payments: any Payments
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import SafeDI
				import Shared

				@Instantiable(fulfillingAdditionalTypes: [(any Payments).self])
				public final class LivePayments: Payments, Instantiable {
				    public init(cart: Cart, retryBuilder: Instantiator<Checkout>) {
				        self.cart = cart
				        self.retryBuilder = retryBuilder
				    }

				    @Received public let cart: Cart
				    @Instantiated public let retryBuilder: Instantiator<Checkout>
				}
				"""#,
				#"""
				import SafeDI
				import Shared

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(cart: Cart, checkout: Checkout) {
				        self.cart = cart
				        self.checkout = checkout
				    }

				    @Instantiated public let cart: Cart
				    @Instantiated public let checkout: Checkout
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Shared"]),
		]),
		// From `generate_throwsOneFieldOfReenteringPlaceErrorNamingEveryFulfilledType_whenOneFillReadsTheValueForPlacesOfTwoTypes`.
		Template(kind: "fieldOfReenteringPlace", modules: [
			ModuleFixture(name: "Shared", packageName: "Shop", swiftFileContent: [
				#"""
				import SafeDI

				public final class Cart {
				    public init() {}
				}

				public protocol Payments: AnyObject {}

				public protocol Ledger: AnyObject {}

				@Instantiable(generateDependencyTree: true)
				public struct Checkout: Instantiable {
				    public init(payments: any Payments, ledger: any Ledger, cartScreenBuilder: Instantiator<CartScreen>) {
				        self.payments = payments
				        self.ledger = ledger
				        self.cartScreenBuilder = cartScreenBuilder
				    }

				    @Instantiated public let payments: any Payments
				    @Instantiated public let ledger: any Ledger
				    @Instantiated public let cartScreenBuilder: Instantiator<CartScreen>
				}

				@Instantiable
				public struct CartScreen: Instantiable {
				    public init(cart: Cart, payments: any Payments) {
				        self.cart = cart
				        self.payments = payments
				    }

				    @Forwarded public let cart: Cart
				    @Instantiated public let payments: any Payments
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import SafeDI
				import Shared

				@Instantiable(fulfillingAdditionalTypes: [(any Payments).self, (any Ledger).self])
				public final class LivePayments: Payments, Ledger, Instantiable {
				    public init(cart: Cart?, retryBuilder: Instantiator<Checkout>) {
				        self.cart = cart
				        self.retryBuilder = retryBuilder
				    }

				    @Received(onlyIfAvailable: true) public let cart: Cart?
				    @Instantiated public let retryBuilder: Instantiator<Checkout>
				}
				"""#,
				#"""
				import SafeDI
				import Shared

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(checkout: Checkout) {
				        self.checkout = checkout
				    }

				    @Instantiated public let checkout: Checkout
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Shared"]),
		]),
		// From `generate_throwsFieldOfReenteringPlace_whenCallOpeningSeamAgainPassesOnValueATypeOfTheSeamsTreeReceives`.
		Template(kind: "fieldOfReenteringPlace", modules: [
			ModuleFixture(name: "Shared", packageName: "Shop", swiftFileContent: [
				#"""
				import SafeDI

				public final class Cart {
				    public init() {}
				}

				public protocol Payments: AnyObject {}

				@Instantiable(generateDependencyTree: true)
				public struct Checkout: Instantiable {
				    public init(payments: any Payments, tracker: Tracker, cartScreenBuilder: Instantiator<CartScreen>) {
				        self.tracker = tracker
				        self.payments = payments
				        self.cartScreenBuilder = cartScreenBuilder
				    }

				    @Instantiated public let payments: any Payments                    // the app supplies this; no cart here
				    @Instantiated public let cartScreenBuilder: Instantiator<CartScreen>
				    @Instantiated public let tracker: Tracker
				}

				@Instantiable
				public struct CartScreen: Instantiable {
				    public init(cart: Cart, payments: any Payments) {
				        self.cart = cart
				        self.payments = payments
				    }

				    @Forwarded public let cart: Cart
				    @Instantiated public let payments: any Payments
				}
				@Instantiable
				public final class Tracker: Instantiable {
				    public init(cart: Cart?) {
				        self.cart = cart
				    }

				    @Received(onlyIfAvailable: true) public let cart: Cart?
				}

				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import SafeDI
				import Shared

				@Instantiable(fulfillingAdditionalTypes: [(any Payments).self])
				public final class LivePayments: Payments, Instantiable {
				    public init(retryBuilder: Instantiator<Checkout>) {
				        self.retryBuilder = retryBuilder
				    }

				    @Instantiated public let retryBuilder: Instantiator<Checkout>
				}
				"""#,
				#"""
				import SafeDI
				import Shared

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(checkout: Checkout) {
				        self.checkout = checkout
				    }

				    @Instantiated public let checkout: Checkout
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Shared"]),
		]),
		// From `generate_throwsFieldOfReenteringPlaceNamingOnlyAFulfillingType_whenPlaceIsBuiltInsideSendableFunction`.
		Template(kind: "fieldOfReenteringPlace", modules: [
			ModuleFixture(name: "Shared", packageName: "Shop", swiftFileContent: [
				#"""
				import SafeDI

				public final class Cart: Sendable {
				    public init() {}
				}

				public protocol Payments: AnyObject, Sendable {}

				@Instantiable(generateDependencyTree: true)
				public struct Checkout: Instantiable {
				    public init(cart: Cart?, ownerBuilder: SendableInstantiator<Owner>, cartScreenBuilder: Instantiator<CartScreen>) {
				        self.cart = cart
				        self.ownerBuilder = ownerBuilder
				        self.cartScreenBuilder = cartScreenBuilder
				    }

				    @Received(onlyIfAvailable: true) public let cart: Cart?
				    @Instantiated public let ownerBuilder: SendableInstantiator<Owner>
				    @Instantiated public let cartScreenBuilder: Instantiator<CartScreen>
				}

				@Instantiable
				public struct Owner: Instantiable, Sendable {
				    public init(payments: any Payments) {
				        self.payments = payments
				    }

				    @Instantiated public let payments: any Payments
				}

				@Instantiable
				public struct CartScreen: Instantiable {
				    public init(cart: Cart, payments: any Payments) {
				        self.cart = cart
				        self.payments = payments
				    }

				    @Forwarded public let cart: Cart
				    @Instantiated public let payments: any Payments
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import SafeDI
				import Shared

				@Instantiable(fulfillingAdditionalTypes: [(any Payments).self])
				public final class LivePayments: Payments, Instantiable, @unchecked Sendable {
				    public init(cart: Cart?, retryBuilder: Instantiator<Checkout>) {
				        self.cart = cart
				        self.retryBuilder = retryBuilder
				    }

				    @Received(onlyIfAvailable: true) public let cart: Cart?
				    @Instantiated public let retryBuilder: Instantiator<Checkout>
				}
				"""#,
				#"""
				import SafeDI
				import Shared

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(checkout: Checkout) {
				        self.checkout = checkout
				    }

				    @Instantiated public let checkout: Checkout
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Shared"]),
		]),
		// From `generate_throwsFieldOfReenteringPlaceNamingEveryPlace_whenTwoScreensInFilesOfEitherOrderCarryTheValue`.
		Template(kind: "fieldOfReenteringPlace", modules: [
			ModuleFixture(name: "Shared", packageName: "Shop", swiftFileContent: [], swiftFileContentByFilePath: [
				"A.swift": #"""
				import SafeDI

				@Instantiable
				public struct CartScreen: Instantiable {
				    public init(cart: Cart, payments: any Payments) {
				        self.cart = cart
				        self.payments = payments
				    }

				    @Forwarded public let cart: Cart
				    @Instantiated public let payments: any Payments
				}
				"""#,
				"B.swift": #"""
				import SafeDI

				@Instantiable
				public struct WishlistScreen: Instantiable {
				    public init(cart: Cart, payments: any Payments) {
				        self.cart = cart
				        self.payments = payments
				    }

				    @Forwarded public let cart: Cart
				    @Instantiated public let payments: any Payments
				}
				"""#,
				"Checkout.swift": #"""
				import SafeDI

				public final class Cart {
				    public init() {}
				}

				public protocol Payments: AnyObject {}

				@Instantiable(generateDependencyTree: true)
				public struct Checkout: Instantiable {
				    public init(payments: any Payments, cartScreenBuilder: Instantiator<CartScreen>, wishlistScreenBuilder: Instantiator<WishlistScreen>) {
				        self.payments = payments
				        self.cartScreenBuilder = cartScreenBuilder
				        self.wishlistScreenBuilder = wishlistScreenBuilder
				    }

				    @Instantiated public let payments: any Payments
				    @Instantiated public let cartScreenBuilder: Instantiator<CartScreen>
				    @Instantiated public let wishlistScreenBuilder: Instantiator<WishlistScreen>
				}
				"""#,
			], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import SafeDI
				import Shared

				@Instantiable(fulfillingAdditionalTypes: [(any Payments).self])
				public final class LivePayments: Payments, Instantiable {
				    public init(cart: Cart?, retryBuilder: Instantiator<Checkout>) {
				        self.cart = cart
				        self.retryBuilder = retryBuilder
				    }

				    @Received(onlyIfAvailable: true) public let cart: Cart?
				    @Instantiated public let retryBuilder: Instantiator<Checkout>
				}
				"""#,
				#"""
				import SafeDI
				import Shared

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(checkout: Checkout) {
				        self.checkout = checkout
				    }

				    @Instantiated public let checkout: Checkout
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Shared"]),
		]),
		// From `generate_throwsFieldOfReenteringPlace_whenCallerFillsPlaceInsideFillBuiltAgainAndOnlyThePlaceCarriesLabel`.
		Template(kind: "fieldOfReenteringPlace", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol First {}
				"""#,
				#"""
				public protocol Second {}
				"""#,
				#"""
				@Instantiable
				public struct X: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Label: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubA: Instantiable {
				    public init(x: X, first: any First) {
				        self.x = x
				        self.first = first
				    }

				    @Instantiated let x: X
				    @Instantiated let first: any First
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubB: Instantiable {
				    public init(second: any Second) {
				        self.second = second
				    }

				    @Instantiated let second: any Second
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Top: Instantiable {
				    public init(subA: SubA, subB: SubB) {
				        self.subA = subA
				        self.subB = subB
				    }

				    @Instantiated let subA: SubA
				    @Instantiated let subB: SubB
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
				#"""
				import Feature

				public protocol Gadget {}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [First.self])
				public struct DefaultFirst: Instantiable, First {
				    public init(subB: SubB) {
				        self.subB = subB
				    }

				    @Instantiated let subB: SubB
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Second.self])
				public struct DefaultSecond: Instantiable, Second {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Host: Instantiable {
				    public init(top: Top) {
				        self.top = top
				    }

				    @Instantiated let top: Top
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct DefaultGadget: Instantiable, Gadget {
				    public init(x: X?) {
				        self.x = x
				    }

				    @Received(onlyIfAvailable: true) let x: X?
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsFieldOfReenteringPlace_whenTypeAboveSeamCallDeclaresLabelTooAndReaderRequiresIt`.
		Template(kind: "fieldOfReenteringPlace", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol First {}
				"""#,
				#"""
				public protocol Second {}
				"""#,
				#"""
				@Instantiable
				public struct X: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Label: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubA: Instantiable {
				    public init(x: X, first: any First) {
				        self.x = x
				        self.first = first
				    }

				    @Instantiated let x: X
				    @Instantiated let first: any First
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct SubB: Instantiable {
				    public init(second: any Second) {
				        self.second = second
				    }

				    @Instantiated let second: any Second
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Top: Instantiable {
				    public init(subA: SubA, subB: SubB) {
				        self.subA = subA
				        self.subB = subB
				    }

				    @Instantiated let subA: SubA
				    @Instantiated let subB: SubB
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
				#"""
				import Feature

				public protocol Gadget {}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [First.self])
				public struct DefaultFirst: Instantiable, First {
				    public init(subB: SubB) {
				        self.subB = subB
				    }

				    @Instantiated let subB: SubB
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Second.self])
				public struct DefaultSecond: Instantiable, Second {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Host: Instantiable {
				    public init(x: X, top: Top) {
				        self.x = x
				        self.top = top
				    }

				    @Instantiated let x: X
				    @Instantiated let top: Top
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct DefaultGadget: Instantiable, Gadget {
				    public init(x: X) {
				        self.x = x
				    }

				    @Received let x: X
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(host: Host) {
				        self.host = host
				    }

				    @Instantiated let host: Host
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingPlacePassedUpByFillRoot_whenFillRootIsSeamWithPlace`.
		Template(kind: "placeInsideFillOfCaseOfBothRootEnums", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Service: Sendable {}
				public protocol Gadget: Sendable {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated public let service: any Service
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(id: Int, panel: Panel) {
				        self.id = id
				        self.panel = panel
				    }

				    @Forwarded public let id: Int
				    @Instantiated public let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable, Sendable {
				    public init(panel: Panel, screenBuilder: SendableInstantiator<Screen>) {
				        self.panel = panel
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let panel: Panel
				    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Service.self])
				public struct SeamService: Instantiable, Service, Sendable {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated public let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Outer: Instantiable, Sendable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct LiveGadget: Instantiable, Gadget, Sendable {
				    public init() {}
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable, Sendable {
				    public init(outer: Outer) {
				        self.outer = outer
				    }

				    @Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingPassedUpPlace_whenFillCallsSeamWhosePlaceItPassesUp`.
		Template(kind: "placeInsideFillOfCaseOfBothRootEnums", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Service: Sendable {}
				public protocol Gadget: Sendable {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated public let service: any Service
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(id: Int, panel: Panel) {
				        self.id = id
				        self.panel = panel
				    }

				    @Forwarded public let id: Int
				    @Instantiated public let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable, Sendable {
				    public init(panel: Panel, screenBuilder: SendableInstantiator<Screen>) {
				        self.panel = panel
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let panel: Panel
				    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Deep: Instantiable, Sendable {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated public let gadget: any Gadget
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public struct DefaultService: Instantiable, Service, Sendable {
				    public init(deep: Deep) {
				        self.deep = deep
				    }

				    @Instantiated public let deep: Deep
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Outer: Instantiable, Sendable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct LiveGadget: Instantiable, Gadget, Sendable {
				    public init() {}
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable, Sendable {
				    public init(outer: Outer) {
				        self.outer = outer
				    }

				    @Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingPlaceBeneathFillRoot_whenFillBuildsPlaceInTypeItInstantiates`.
		Template(kind: "placeInsideFillOfCaseOfBothRootEnums", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Service: Sendable {}
				public protocol Gadget: Sendable {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated public let service: any Service
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(id: Int, panel: Panel) {
				        self.id = id
				        self.panel = panel
				    }

				    @Forwarded public let id: Int
				    @Instantiated public let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable, Sendable {
				    public init(panel: Panel, screenBuilder: SendableInstantiator<Screen>) {
				        self.panel = panel
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let panel: Panel
				    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable
				public struct Helper: Instantiable, Sendable {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated public let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public struct DefaultService: Instantiable, Service, Sendable {
				    public init(helper: Helper) {
				        self.helper = helper
				    }

				    @Instantiated public let helper: Helper
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Outer: Instantiable, Sendable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct LiveGadget: Instantiable, Gadget, Sendable {
				    public init() {}
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable, Sendable {
				    public init(outer: Outer) {
				        self.outer = outer
				    }

				    @Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsPlaceInsideFillOfCaseOfBothRootEnums_whenInnerBuildsTypeHoldingPlaceInsideAndOutsideSendableFunction`.
		Template(kind: "placeInsideFillOfCaseOfBothRootEnums", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Service: Sendable {}
				public protocol Gadget: Sendable {}
				"""#,
				#"""
				@Instantiable
				public final class Mark: Instantiable, Sendable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated public let service: any Service
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(id: Int, panel: Panel) {
				        self.id = id
				        self.panel = panel
				    }

				    @Forwarded public let id: Int
				    @Instantiated public let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable, Sendable {
				    public init(panel: Panel, screenBuilder: SendableInstantiator<Screen>) {
				        self.panel = panel
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let panel: Panel
				    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public struct DefaultService: Instantiable, Service, Sendable {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated public let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Outer: Instantiable, Sendable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct LiveGadget: Instantiable, Gadget, Sendable {
				    public init(id: Int?, mark: Mark?) {
				        self.id = id
				        self.mark = mark
				    }

				    @Received(onlyIfAvailable: true) public let id: Int?
				    @Received(onlyIfAvailable: true) public let mark: Mark?
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable, Sendable {
				    public init(outer: Outer) {
				        self.outer = outer
				    }

				    @Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingPlaceInsideNestedFill_whenFillCallsSeamWhoseFillBuildsPlace`.
		Template(kind: "placeInsideFillOfCaseOfBothRootEnums", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Service: Sendable {}
				public protocol Gadget: Sendable {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated public let service: any Service
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(id: Int, panel: Panel) {
				        self.id = id
				        self.panel = panel
				    }

				    @Forwarded public let id: Int
				    @Instantiated public let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable, Sendable {
				    public init(panel: Panel, screenBuilder: SendableInstantiator<Screen>) {
				        self.panel = panel
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let panel: Panel
				    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
				}
				"""#,
				#"""
				public protocol Widget: Sendable {}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Deep: Instantiable, Sendable {
				    public init(widget: any Widget) {
				        self.widget = widget
				    }

				    @Instantiated public let widget: any Widget
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Widget.self])
				public struct DefaultWidget: Instantiable, Widget, Sendable {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated public let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public struct DefaultService: Instantiable, Service, Sendable {
				    public init(deep: Deep) {
				        self.deep = deep
				    }

				    @Instantiated public let deep: Deep
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Outer: Instantiable, Sendable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct LiveGadget: Instantiable, Gadget, Sendable {
				    public init() {}
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable, Sendable {
				    public init(outer: Outer) {
				        self.outer = outer
				    }

				    @Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingPlacePassedUpTwoSeamsDeep_whenCalledSeamFillsBuilderWithSeamWithPlace`.
		Template(kind: "placeInsideFillOfCaseOfBothRootEnums", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Service: Sendable {}
				public protocol Gadget: Sendable {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated public let service: any Service
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(id: Int, panel: Panel) {
				        self.id = id
				        self.panel = panel
				    }

				    @Forwarded public let id: Int
				    @Instantiated public let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable, Sendable {
				    public init(panel: Panel, screenBuilder: SendableInstantiator<Screen>) {
				        self.panel = panel
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let panel: Panel
				    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
				}
				"""#,
				#"""
				public protocol Widget: Sendable {}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Deep: Instantiable, Sendable {
				    public init(widget: any Widget) {
				        self.widget = widget
				    }

				    @Instantiated public let widget: any Widget
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Widget.self])
				public struct SeamWidget: Instantiable, Widget, Sendable {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated public let gadget: any Gadget
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public struct DefaultService: Instantiable, Service, Sendable {
				    public init(deep: Deep) {
				        self.deep = deep
				    }

				    @Instantiated public let deep: Deep
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Outer: Instantiable, Sendable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct LiveGadget: Instantiable, Gadget, Sendable {
				    public init() {}
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable, Sendable {
				    public init(outer: Outer) {
				        self.outer = outer
				    }

				    @Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingPlacePassedUpByNestedFillRoot_whenNestedFillRootIsSeamWithPlace`.
		Template(kind: "placeInsideFillOfCaseOfBothRootEnums", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Service: Sendable {}
				public protocol Gadget: Sendable {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated public let service: any Service
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(id: Int, panel: Panel) {
				        self.id = id
				        self.panel = panel
				    }

				    @Forwarded public let id: Int
				    @Instantiated public let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable, Sendable {
				    public init(panel: Panel, screenBuilder: SendableInstantiator<Screen>) {
				        self.panel = panel
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let panel: Panel
				    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
				}
				"""#,
				#"""
				public protocol Widget: Sendable {}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Deep: Instantiable, Sendable {
				    public init(widget: any Widget) {
				        self.widget = widget
				    }

				    @Instantiated public let widget: any Widget
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Widget.self])
				public struct SeamWidget: Instantiable, Widget, Sendable {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated public let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public struct DefaultService: Instantiable, Service, Sendable {
				    public init(deep: Deep) {
				        self.deep = deep
				    }

				    @Instantiated public let deep: Deep
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Outer: Instantiable, Sendable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct LiveGadget: Instantiable, Gadget, Sendable {
				    public init() {}
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable, Sendable {
				    public init(outer: Outer) {
				        self.outer = outer
				    }

				    @Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsPlaceInsideFillOfCaseOfBothRootEnumsNamingFillRootsOwnPlace_whenFillRootAlsoCallsSeamWhoseFillBuildsPlace`.
		Template(kind: "placeInsideFillOfCaseOfBothRootEnums", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Service: Sendable {}
				public protocol Gadget: Sendable {}
				"""#,
				#"""
				@Instantiable
				public struct Panel: Instantiable, Sendable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated public let service: any Service
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable, Sendable {
				    public init(id: Int, panel: Panel) {
				        self.id = id
				        self.panel = panel
				    }

				    @Forwarded public let id: Int
				    @Instantiated public let panel: Panel
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Inner: Instantiable, Sendable {
				    public init(panel: Panel, screenBuilder: SendableInstantiator<Screen>) {
				        self.panel = panel
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated public let panel: Panel
				    @Instantiated public let screenBuilder: SendableInstantiator<Screen>
				}
				"""#,
				#"""
				public protocol Widget: Sendable {}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Deep: Instantiable, Sendable {
				    public init(widget: any Widget) {
				        self.widget = widget
				    }

				    @Instantiated public let widget: any Widget
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Widget.self])
				public struct DefaultWidget: Instantiable, Widget, Sendable {
				    public init(gadget: any Gadget) {
				        self.gadget = gadget
				    }

				    @Instantiated public let gadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public struct DefaultService: Instantiable, Service, Sendable {
				    public init(deep: Deep, ownGadget: any Gadget) {
				        self.deep = deep
				        self.ownGadget = ownGadget
				    }

				    @Instantiated public let deep: Deep
				    @Instantiated public let ownGadget: any Gadget
				}
				"""#,
				#"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public struct Outer: Instantiable, Sendable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated public let inner: Inner
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature
				import Middle

				@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
				public struct LiveGadget: Instantiable, Gadget, Sendable {
				    public init() {}
				}
				"""#,
				#"""
				import Feature
				import Middle

				@Instantiable(isRoot: true)
				public struct Root: Instantiable, Sendable {
				    public init(outer: Outer) {
				        self.outer = outer
				    }

				    @Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature", "Middle"]),
		]),
		// From `generate_throwsFillReceivesInstantiatorBeingBuilt_whenFillReceivesHolesOwnInstantiator`.
		Template(kind: "receivesInstantiatorBuildingSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Detail {}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(detailBuilder: ErasedInstantiator<(), any Detail>) {
				        self.detailBuilder = detailBuilder
				    }

				    @Instantiated(fulfilledByType: "DefaultDetail") let detailBuilder: ErasedInstantiator<(), any Detail>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable
				public struct DefaultDetail: Instantiable, Detail {
				    public init(detailBuilder: ErasedInstantiator<(), any Detail>) {
				        self.detailBuilder = detailBuilder
				    }

				    @Received let detailBuilder: ErasedInstantiator<(), any Detail>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsFillReceivesInstantiatorBeingBuilt_whenFillReceivesInstantiatorOfScopeOnHolesPath`.
		Template(kind: "receivesInstantiatorBuildingSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Widget {}
				"""#,
				#"""
				@Instantiable
				public struct A: Instantiable {
				    public init(widget: any Widget) {
				        self.widget = widget
				    }

				    @Instantiated let widget: any Widget
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Flow: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Widget.self])
				public struct DefaultWidget: Instantiable, Widget {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Received let aBuilder: Instantiator<A>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(flow: Flow) {
				        self.flow = flow
				    }

				    @Instantiated let flow: Flow
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsErrorOfferingOnlyToFulfillTheHole_whenFillReceivesInstantiatorOnThePathWhoseTreeReceivesValueTheSeamForwards`.
		Template(kind: "receivesInstantiatorBuildingSite", modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				#"""
				public protocol Api {}
				"""#,
				#"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}
				"""#,
				#"""
				@Instantiable
				public struct Screen: Instantiable {
				    public init(user: User, api: any Api) {
				        self.user = user
				        self.api = api
				    }

				    @Received public let user: User
				    @Instantiated public let api: any Api
				}
				"""#,
				#"""
				@Instantiable(generateDependencyTree: true)
				public struct Home: Instantiable {
				    public init(user: User, screenBuilder: Instantiator<Screen>) {
				        self.user = user
				        self.screenBuilder = screenBuilder
				    }

				    @Forwarded public let user: User
				    @Instantiated public let screenBuilder: Instantiator<Screen>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				#"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct LiveApi: Instantiable, Api {
				    public init(screenBuilder: Instantiator<Screen>) {
				        self.screenBuilder = screenBuilder
				    }

				    @Received public let screenBuilder: Instantiator<Screen>
				}
				"""#,
				#"""
				import Feature

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(homeBuilder: Instantiator<Home>) {
				        self.homeBuilder = homeBuilder
				    }

				    @Instantiated public let homeBuilder: Instantiator<Home>
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Feature"]),
		]),
		// From `generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsValueThroughAlias`.
		Template(kind: "sendableWrapperReadBesidePlainMemo", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(seam: Seam) { self.seam = seam; log.append("Outer") }
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(token: ChainToken, reader: WrapperReader) { self.token = token; self.reader = reader; log.append("ThingImpl") }
					@Received(fulfilledByDependencyNamed: "chainToken", ofType: ChainToken.self) let token: ChainToken
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, mid: Mid) { self.chainToken = chainToken; self.mid = mid; log.append("TopRoot") }
					@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsValueInsideSendableInstantiator`.
		Template(kind: "sendableWrapperReadBesidePlainMemo", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(seam: Seam) { self.seam = seam; log.append("Outer") }
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(leafBuilder: SendableInstantiator<ChainLeaf>, reader: WrapperReader) {
						self.leafBuilder = leafBuilder
						self.reader = reader
						_ = leafBuilder.instantiate()
						log.append("ThingImpl")
					}
					@Instantiated let leafBuilder: SendableInstantiator<ChainLeaf>
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, mid: Mid) { self.chainToken = chainToken; self.mid = mid; log.append("TopRoot") }
					@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsValueAndSendableWrapperThroughSeamDeferringValueInLazilyInstantiated`.
		Template(kind: "sendableWrapperReadBesidePlainMemo", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(seam: Seam) { self.seam = seam; log.append("Outer") }
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(chainToken: ChainToken, reader: WrapperReader) {
						self.chainToken = chainToken
						self.reader = reader
						log.append(reader.chainToken.instance === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
					}
					@Received let chainToken: ChainToken
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, mid: Mid) { self.chainToken = chainToken; self.mid = mid; log.append("TopRoot") }
					@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsSendableWrapperInsideSendableInstantiator`.
		Template(kind: "sendableWrapperReadBesidePlainMemo", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(seam: Seam) { self.seam = seam; log.append("Outer") }
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(chainToken: ChainToken, readerHolder: SendableInstantiator<WrapperReader>) {
						self.chainToken = chainToken
						self.readerHolder = readerHolder
						log.append(readerHolder.instantiate().chainToken.instance === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
					}
					@Received let chainToken: ChainToken
					@Instantiated let readerHolder: SendableInstantiator<WrapperReader>
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, mid: Mid) { self.chainToken = chainToken; self.mid = mid; log.append("TopRoot") }
					@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsSendableWrapperReadBesidePlainMemo_whenTreeReadsSendableWrapperInsideSendableLazilyInstantiated`.
		Template(kind: "sendableWrapperReadBesidePlainMemo", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(seam: Seam) { self.seam = seam; log.append("Outer") }
					@Instantiated public let seam: Seam
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(chainToken: ChainToken, readerHolder: SendableLazilyInstantiated<WrapperReader>) {
						self.chainToken = chainToken
						self.readerHolder = readerHolder
						log.append(readerHolder.instance.chainToken.instance === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
					}
					@Received let chainToken: ChainToken
					@Instantiated let readerHolder: SendableLazilyInstantiated<WrapperReader>
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, mid: Mid) { self.chainToken = chainToken; self.mid = mid; log.append("TopRoot") }
					@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsSendableWrapperReadBesidePlainMemo_whenTwoPassingUpSeamsDeferValueInLazilyInstantiated`.
		Template(kind: "sendableWrapperReadBesidePlainMemo", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(seam: Seam, seamB: SeamB) { self.seam = seam; self.seamB = seamB; log.append("Outer") }
					@Instantiated public let seamB: SeamB
					@Instantiated public let seam: Seam
				}

				@Instantiable(generateDependencyTree: true)
				public final class SeamB: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("SeamB")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(chainToken: ChainToken, reader: WrapperReader) {
						self.chainToken = chainToken
						self.reader = reader
						log.append(reader.chainToken.instance === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
					}
					@Received let chainToken: ChainToken
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, mid: Mid) { self.chainToken = chainToken; self.mid = mid; log.append("TopRoot") }
					@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
		// From `generate_throwsSendableWrapperReadBesidePlainMemo_whenOneOfTwoPassingUpSeamsDefersValueInLazilyInstantiated`.
		Template(kind: "sendableWrapperReadBesidePlainMemo", modules: [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: [
				#"""
				import SafeDI

				public nonisolated(unsafe) var log = [String]()

				@Instantiable
				public final class ChainToken: Instantiable, Sendable {
					public init() { log.append("ChainToken") }
				}

				@Instantiable
				public final class ChainLeaf: Instantiable, Sendable {
					public init(chainToken: ChainToken) { self.chainToken = chainToken; log.append("ChainLeaf") }
					@Received let chainToken: ChainToken
				}

				public protocol HoleService: Sendable {}
				public protocol ThingService: Sendable {}
				public protocol GadgetService: Sendable {}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: []),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true)
				public final class Seam: Instantiable, @unchecked Sendable {
					public init(leafBuilder: Instantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("Seam")
					}
					@Instantiated public let leafBuilder: Instantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable, @unchecked Sendable {
					public init(seam: Seam, seamB: SeamB) { self.seam = seam; self.seamB = seamB; log.append("Outer") }
					@Instantiated public let seamB: SeamB
					@Instantiated public let seam: Seam
				}

				@Instantiable(generateDependencyTree: true)
				public final class SeamB: Instantiable, @unchecked Sendable {
					public init(leafBuilder: SendableInstantiator<ChainLeaf>, holeService: any HoleService) {
						self.leafBuilder = leafBuilder
						self.holeService = holeService
						log.append("SeamB")
					}
					@Instantiated public let leafBuilder: SendableInstantiator<ChainLeaf>
					@Instantiated public let holeService: any HoleService
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core"]),
			ModuleFixture(name: "Other", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import SafeDI

				@Instantiable
				public final class Worker: Instantiable, Sendable {
					public init(thing: any ThingService) { self.thing = thing; log.append("Worker") }
					@Instantiated let thing: any ThingService
				}

				@Instantiable(fulfillingAdditionalTypes: [HoleService.self])
				public final class HoleImpl: Instantiable, HoleService, @unchecked Sendable {
					public init(workerBuilder: Instantiator<Worker>) { self.workerBuilder = workerBuilder; log.append("HoleImpl") }
					@Instantiated public let workerBuilder: Instantiator<Worker>
				}

				@Instantiable(generateDependencyTree: true)
				public final class Mid: Instantiable {
					public init(outer: Outer) { self.outer = outer; log.append("Mid") }
					@Instantiated public let outer: Outer
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature"]),
			ModuleFixture(name: "Top", packageName: "Min", swiftFileContent: [
				#"""
				import Core
				import Feature
				import Other
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [ThingService.self])
				public final class ThingImpl: Instantiable, ThingService {
					public init(chainToken: ChainToken, reader: WrapperReader) {
						self.chainToken = chainToken
						self.reader = reader
						log.append(reader.chainToken.instance === chainToken ? "ThingImpl shares ChainToken" : "ThingImpl holds another ChainToken")
					}
					@Received let chainToken: ChainToken
					@Instantiated let reader: WrapperReader
				}

				@Instantiable
				public final class WrapperReader: Instantiable, Sendable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>) { self.chainToken = chainToken; log.append("WrapperReader") }
					@Received let chainToken: SendableLazilyInstantiated<ChainToken>
				}

				@Instantiable(isRoot: true)
				public final class TopRoot: Instantiable {
					public init(chainToken: SendableLazilyInstantiated<ChainToken>, mid: Mid) { self.chainToken = chainToken; self.mid = mid; log.append("TopRoot") }
					@Instantiated let chainToken: SendableLazilyInstantiated<ChainToken>
					@Instantiated public let mid: Mid
				}
				"""#,
			], swiftFileContentByFilePath: [:], dependencies: ["Core", "Feature", "Other"]),
		]),
	]
}
