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

// A module info file carries, beside its module's own declarations, the declarations of other modules that a seam or
// public mock of a module it depends on is computed from. Those carry no line or column: a position is what an edit
// elsewhere in a file changes, and nothing a signature reads, so a module whose `.safedi` holds them is rebuilt only
// when a declaration a signature can depend on changes. Every fact stays: which file holds a declaration
// (`sourceFilePath`), and whether a declaration spells an access modifier (`AccessDeclaration.spellsAccessModifier`).

extension Instantiable {
	/// This declaration without a line or column anywhere in it: every `Dependency.DeclarationLocation` and
	/// `Dependency.SourceRange` it holds is `nil`.
	public func withoutPositions() -> Instantiable {
		var instantiable = Instantiable(
			instantiableType: concreteInstantiable,
			isRoot: isRoot,
			generatesDependencyTree: generatesDependencyTree,
			initializer: initializer?.withoutPositions(),
			otherInitializers: otherInitializers.map { $0.withoutPositions() },
			additionalInstantiables: Array(instantiableTypes.dropFirst()),
			dependencies: dependencies.map { $0.withoutPositions() },
			declarationType: declarationType,
			access: access.withoutPositions(),
			enclosingTypeAccess: enclosingTypeAccess.map { $0.withoutPositions() },
			enclosingExtensionAccess: enclosingExtensionAccess?.withoutPositions(),
			generatedInitializerAttributes: generatedInitializerAttributes,
			mockAttributes: mockAttributes,
			declarationIsolation: declarationIsolation,
			generateMock: generateMock,
			mockGenerationArgumentRange: nil,
			mockOnly: mockOnly,
			mockInitializer: mockInitializer?.withoutPositions(),
			mockReturnType: mockReturnType,
			customMockName: customMockName,
			mockDeclarationLocation: nil,
			mockDeclarationAccess: mockDeclarationAccess?.withoutPositions(),
			mockDeclarationModuleName: mockDeclarationModuleName,
			mockDeclarationPackageName: mockDeclarationPackageName,
			declarationLocation: nil,
			moduleName: moduleName,
			packageName: packageName,
		)
		instantiable.sourceFilePath = sourceFilePath
		return instantiable
	}
}

extension Dependency {
	/// This dependency without where it is declared.
	public func withoutPositions() -> Dependency {
		Dependency(property: property, source: source)
	}
}

extension Initializer {
	/// This initializer without where its access modifier is.
	public func withoutPositions() -> Initializer {
		Initializer(
			access: access.withoutPositions(),
			isOptional: isOptional,
			isAsync: isAsync,
			doesThrow: doesThrow,
			hasGenericParameter: hasGenericParameter,
			hasGenericWhereClause: hasGenericWhereClause,
			arguments: arguments,
			spelledIsolation: spelledIsolation,
		)
	}
}

extension AccessDeclaration {
	/// This access without where its modifier and its declaration are, keeping whether a modifier is spelled.
	public func withoutPositions() -> AccessDeclaration {
		AccessDeclaration(level: level, spellsAccessModifier: spellsAccessModifier, isExtension: isExtension)
	}
}

extension PlainTypeDeclaration {
	/// This declaration without where its access modifiers and its declaration are.
	public func withoutPositions() -> PlainTypeDeclaration {
		PlainTypeDeclaration(
			typeDescription: typeDescription,
			access: access.withoutPositions(),
			enclosingTypeAccess: enclosingTypeAccess.map { $0.withoutPositions() },
			enclosingExtensionAccess: enclosingExtensionAccess?.withoutPositions(),
			moduleName: moduleName,
			packageName: packageName,
			sourceFilePath: sourceFilePath,
		)
	}
}
