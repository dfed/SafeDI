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

/// The effective access SafeDITool computes for the declarations it parses. Each rule was checked with the compiler:
/// a member of a type defaults to `internal` whatever the type's level, a member of a `private` extension to
/// `fileprivate`, a type directly inside an extension to the extension's level, and an extension caps nothing.
struct AccessReachabilityTests {
	@Test
	func effective_isTheSpelledLevel_whenTypeAndInitializerSpellModifiers() throws {
		let instantiable = try instantiable(in: """
		@Instantiable
		package final class Service: Instantiable {
		    package init() {}
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .package)
		#expect(effectiveConstructionAccess(of: instantiable) == .package)
	}

	@Test
	func effective_isInternalForInitializer_whenInitializerOfPublicTypeSpellsNoModifier() throws {
		let instantiable = try instantiable(in: """
		@Instantiable
		public final class Service: Instantiable {
		    init() {}
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .public)
		#expect(effectiveConstructionAccess(of: instantiable) == .internal)
	}

	@Test
	func effective_isCappedByEachEnclosingType() throws {
		let instantiable = try instantiable(in: """
		public enum Outer {
		    internal enum Middle {
		        @Instantiable
		        public final class Service: Instantiable {
		            public init() {}
		        }
		    }
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .internal)
		#expect(effectiveConstructionAccess(of: instantiable) == .internal)
	}

	@Test
	func effective_isTheExtensionsLevel_whenTypeDirectlyInsideExtensionSpellsNoModifier() throws {
		let instantiable = try instantiable(in: """
		public extension Outer {
		    @Instantiable
		    final class Service: Instantiable {
		        public init() {}
		    }
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .public)
		#expect(effectiveConstructionAccess(of: instantiable) == .public)
	}

	@Test
	func effective_isFileprivate_whenTypeDirectlyInsidePrivateExtensionSpellsNoModifier() throws {
		let instantiable = try instantiable(in: """
		private extension Outer {
		    @Instantiable
		    final class Service: Instantiable {
		        public init() {}
		    }
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .fileprivate)
	}

	@Test
	func effective_ignoresTheExtension_whenTypeDirectlyInsideExtensionSpellsModifier() throws {
		let instantiable = try instantiable(in: """
		internal extension Outer {
		    @Instantiable
		    public final class Service: Instantiable {
		        public init() {}
		    }
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .public)
	}

	@Test
	func effective_givesOutermostEnclosingTypeTheExtensionsLevel_whenItSpellsNoModifier() throws {
		let instantiable = try instantiable(in: """
		package extension Outer {
		    struct Middle {
		        @Instantiable
		        public final class Service: Instantiable {
		            public init() {}
		        }
		    }
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .package)
	}

	@Test
	func effective_isOpen_whenExtensionBasedInstantiableExtensionSpellsNoModifier() throws {
		let instantiable = try instantiable(in: """
		@Instantiable
		extension Service: Instantiable {
		    public static func instantiate() -> Service { Service() }
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .open)
		#expect(effectiveConstructionAccess(of: instantiable) == .public)
	}

	@Test
	func effective_isInternalForInstantiateMethod_whenNeitherMethodNorExtensionSpellsModifier() throws {
		let instantiable = try instantiable(in: """
		@Instantiable
		extension Service: Instantiable {
		    static func instantiate() -> Service { Service() }
		}
		""")

		#expect(effectiveConstructionAccess(of: instantiable) == .internal)
	}

	@Test
	func effective_isTheExtensionsLevelForInstantiateMethod_whenOnlyTheExtensionSpellsModifier() throws {
		let instantiable = try instantiable(in: """
		@Instantiable
		package extension Service: Instantiable {
		    static func instantiate() -> Service { Service() }
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .package)
		#expect(effectiveConstructionAccess(of: instantiable) == .package)
	}

	@Test
	func effective_capsInstantiateMethodByTheExtensionsSpelledLevel() throws {
		let instantiable = try instantiable(in: """
		@Instantiable
		internal extension Service: Instantiable {
		    public static func instantiate() -> Service { Service() }
		}
		""")

		#expect(AccessLevel.effective(ofTypeDeclaredBy: instantiable) == .internal)
		#expect(effectiveConstructionAccess(of: instantiable) == .internal)
	}

	@Test
	func effective_isInternalForMockMethod_whenMockOfTypeDeclarationSpellsNoModifier() throws {
		let instantiable = try instantiable(in: """
		@Instantiable
		public final class Service: Instantiable {
		    public init() {}
		    static func mock() -> Service { Service() }
		}
		""")

		#expect(try effectiveMockAccess(of: instantiable) == .internal)
	}

	@Test
	func effective_isTheExtensionsLevelForMockMethod_whenMockOfExtensionSpellsNoModifier() throws {
		let instantiable = try instantiable(in: """
		@Instantiable(mockOnly: true)
		public extension Service {
		    static func mock() -> Service { Service() }
		}
		""")

		#expect(try effectiveMockAccess(of: instantiable) == .public)
	}

	@Test
	func effective_isFileprivateForMockMethod_whenMockOfPrivateExtensionSpellsNoModifier() throws {
		let instantiable = try instantiable(in: """
		@Instantiable(mockOnly: true)
		private extension Service {
		    static func mock() -> Service { Service() }
		}
		""")

		#expect(try effectiveMockAccess(of: instantiable) == .fileprivate)
	}

	@Test(arguments: [
		// An own file is in the emitting module, whatever names are recorded.
		(ModuleIdentity(moduleName: "App", packageName: "P"), ModuleIdentity(moduleName: "Feature", packageName: "Q"), true, AccessRequirement.internal),
		(ModuleIdentity(moduleName: nil, packageName: nil), ModuleIdentity(moduleName: nil, packageName: nil), true, AccessRequirement.internal),
		(ModuleIdentity(moduleName: "App", packageName: nil), ModuleIdentity(moduleName: "App", packageName: nil), false, AccessRequirement.internal),
		(ModuleIdentity(moduleName: "App", packageName: "P"), ModuleIdentity(moduleName: "Feature", packageName: "P"), false, AccessRequirement.package),
		(ModuleIdentity(moduleName: nil, packageName: "P"), ModuleIdentity(moduleName: nil, packageName: "P"), false, AccessRequirement.package),
		(ModuleIdentity(moduleName: "App", packageName: "P"), ModuleIdentity(moduleName: "Feature", packageName: "Q"), false, AccessRequirement.public),
		(ModuleIdentity(moduleName: "App", packageName: "P"), ModuleIdentity(moduleName: "Feature", packageName: nil), false, AccessRequirement.packageUnverified),
		(ModuleIdentity(moduleName: "App", packageName: nil), ModuleIdentity(moduleName: "Feature", packageName: "P"), false, AccessRequirement.packageUnverified),
		(ModuleIdentity(moduleName: nil, packageName: nil), ModuleIdentity(moduleName: nil, packageName: nil), false, AccessRequirement.packageUnverified),
	])
	func required_followsOwnFileThenModuleThenPackage(emitter: ModuleIdentity, declarer: ModuleIdentity, isOwnFile: Bool, requirement: AccessRequirement) {
		#expect(AccessLevel.required(toConstructFrom: emitter, declaredIn: declarer, isOwnFile: isOwnFile) == requirement)
	}

	@Test
	func satisfies_acceptsEachLevelOnlyWhereSwiftDoes() {
		let requirements = [AccessRequirement.internal, .package, .packageUnverified, .public]
		func satisfiedRequirements(of level: AccessLevel) -> [AccessRequirement] {
			requirements.filter(level.satisfies)
		}
		#expect(satisfiedRequirements(of: .open) == requirements)
		#expect(satisfiedRequirements(of: .public) == requirements)
		#expect(satisfiedRequirements(of: .package) == [.internal, .package, .packageUnverified])
		#expect(satisfiedRequirements(of: .internal) == [.internal])
		#expect(satisfiedRequirements(of: .fileprivate) == [])
		#expect(satisfiedRequirements(of: .private) == [])
	}

	// MARK: Private

	private func instantiable(in source: String) throws -> Instantiable {
		let syntaxTree = Parser.parse(source: source)
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		return try #require(fileVisitor.instantiables.first)
	}

	private func effectiveConstructionAccess(of instantiable: Instantiable) -> AccessLevel? {
		instantiable.initializer.map { initializer in
			AccessLevel.effective(
				ofMember: initializer,
				declaredIn: instantiable.access,
				ofTypeWithEffectiveAccess: AccessLevel.effective(ofTypeDeclaredBy: instantiable),
			)
		}
	}

	private func effectiveMockAccess(of instantiable: Instantiable) throws -> AccessLevel {
		try AccessLevel.effective(
			ofMember: #require(instantiable.mockInitializer),
			declaredIn: #require(instantiable.mockDeclarationAccess),
			ofTypeWithEffectiveAccess: AccessLevel.effective(ofTypeDeclaredBy: instantiable),
		)
	}
}
