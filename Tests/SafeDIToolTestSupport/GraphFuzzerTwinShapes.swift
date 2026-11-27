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

/// A shape of the twins draw, read from a graph's source.
enum TwinShape: String, CaseIterable, Comparable {
	/// Every graph that draws the tree.
	case drawn
	/// `TwinFirst` declares the model by value, so the value is first on the path to the cycle.
	case valueFirst
	/// `TwinFirst` declares the model lazily, so the wrapper is first on the path to the cycle.
	case wrapperFirst
	/// The lazy twin is a `SendableLazilyInstantiated`, and the cycle closes through a `SendableInstantiator`.
	case sendableWrapper
	/// `TwinScreen` receives the model only if available.
	case screenReceivesOnlyIfAvailable
	/// `TwinScreen` builds `TwinPanel`, which receives the model too.
	case screenBuildsPanel
	/// The tree's top builds `TwinFirst` through an instantiator.
	case firstThroughInstantiator
	/// The tree's top opens `TwinSecond` too.
	case topOpensSecond
	/// `TwinSeam`, a seam, holds the tree.
	case inSeam
	/// `TwinFirst` and `TwinSecond` each declare `twinTheme` by value, which `TwinModel`, the twins' type, receives.
	case themeInSameForm
	/// `TwinFirst` declares `twinTheme` by value and `TwinSecond` as the lazy wrapper, which `TwinModel` receives.
	case themeInMixedForms
	/// `themeInMixedForms` where a parent holds the model in a `SendableLazilyInstantiated`, so the body of `TwinModel`
	/// that reads the theme in its two forms is inside that wrapper's `@Sendable` builder.
	case themeInMixedFormsInsideSendableBuilder

	static func < (lhs: TwinShape, rhs: TwinShape) -> Bool {
		lhs.rawValue < rhs.rawValue
	}

	static func shapes(of fixture: GraphFuzzerFixture) -> Set<TwinShape> {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: fixture.seed)
		var shapes = Set<TwinShape>()
		var currentTypeName = ""
		var firstDeclaresTheme = false
		var secondThemeType: String?
		for line in fixture.swiftFileContent.flatMap(GraphFuzzerSourceLine.lines(of:)) {
			switch line {
			case let .typeDeclaration(name):
				currentTypeName = name
				if name == "\(prefix)TwinRoot" || name == "\(prefix)TwinHome" {
					shapes.insert(.drawn)
				} else if name == "\(prefix)TwinSeam" {
					shapes.insert(.inSeam)
				}
			case let .property(attribute, label, type):
				switch currentTypeName {
				case "\(prefix)TwinFirst" where label == "twinModel":
					shapes.insert(type.contains("LazilyInstantiated<") ? .wrapperFirst : .valueFirst)
					if type.hasPrefix("SendableLazilyInstantiated<") {
						shapes.insert(.sendableWrapper)
					}
				case "\(prefix)TwinSecond" where label == "twinModel":
					if type.hasPrefix("SendableLazilyInstantiated<") {
						shapes.insert(.sendableWrapper)
					}
				case "\(prefix)TwinFirst" where label == "twinTheme":
					firstDeclaresTheme = true
				case "\(prefix)TwinSecond" where label == "twinTheme":
					secondThemeType = type
				case "\(prefix)TwinScreen":
					if attribute.contains("onlyIfAvailable") {
						shapes.insert(.screenReceivesOnlyIfAvailable)
					} else if label == "twinPanel" {
						shapes.insert(.screenBuildsPanel)
					}
				case "\(prefix)TwinRoot", "\(prefix)TwinSeam", "\(prefix)TwinHome":
					if label == "twinFirstBuilder" {
						shapes.insert(.firstThroughInstantiator)
					} else if label == "twinSecondBuilder" {
						shapes.insert(.topOpensSecond)
					}
				default:
					break
				}
			case .instantiableAttribute, .instantiateMethod, .other:
				break
			}
		}
		if firstDeclaresTheme, let secondThemeType {
			if secondThemeType.contains("LazilyInstantiated<") {
				shapes.insert(.themeInMixedForms)
				if shapes.contains(.sendableWrapper) {
					shapes.insert(.themeInMixedFormsInsideSendableBuilder)
				}
			} else {
				shapes.insert(.themeInSameForm)
			}
		}
		return shapes
	}
}
