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

// The judgements of fulfillment validation, each a function of a read and of what the place it is made at answers it
// with, by value. None reads the walk that reached the place, an index on its stacks, or which declaration gave an
// answer: those belong to a route, which only the text of an error reads. So every place that answers a read alike is
// judged alike, and what supplies the answers can change from the walk of every path to a fold over the facts of each
// type (`TypeFactsWorld`) without a judgement changing.

extension DependencyTreeGenerator {
	/// A read a judgement is about: one channel's read of a label (`Read`), with the forms that answer it. In `Property`
	/// values, as the walk that supplies the answers holds them; a fold holds the IDs of the same three.
	struct FulfillmentRead {
		let channel: ReadChannel
		let label: String
		/// The forms that answer the read. A receive of an optional property, required or only if available, resolves to its
		/// non-optional form too, and an `onlyIfAvailable` alias reads the optional form of its fulfilling property too, as
		/// `nil` where it is.
		let acceptedProperties: Set<Property>
	}

	/// What a declaration provides, by value: its property and, where it is lazily instantiated and offers one, the
	/// instance a by-value receive reads. Never the declaration, whose location and declaring type belong to a route.
	struct FulfillmentForms {
		let property: Property
		let lazilyInstantiatedInstanceProperty: Property?

		/// Whether a declaration of these forms answers `read`: one of the forms the read accepts is the declaration's, or
		/// its instance's.
		func answers(_ read: FulfillmentRead) -> Bool {
			read.acceptedProperties.contains(property) || lazilyInstantiatedInstanceProperty.map(read.acceptedProperties.contains) ?? false
		}
	}

	/// An answer to a read, by value, in the forms `TypeFactsAnswer.Form` has.
	enum FulfillmentAnswer {
		/// No declaration above answers the read.
		case none
		/// A declaration answers it with the forms it provides.
		case declared(FulfillmentForms)
		/// The declaration is still being built where it answers.
		case beingBuilt(FulfillmentForms)
	}

	/// What a place answers a receive whose label a scope above it declares.
	struct DeclaredLabelAnswer {
		/// The forms of the nearest declaration of the read's label above the reader, which generated code passes the
		/// receive: a received dependency is passed by its label.
		let nearest: FulfillmentForms
		/// Whether some scope above the reader provides a form the read accepts, whatever declaration is nearer.
		let isProvidedAbove: Bool
	}

	/// Whether the nearest declaration of a receive's label hides the receive: it provides no form the receive accepts,
	/// and is passed in its place. That is the hidden-label error where a scope above provides the receive, required or
	/// only if available. Where none does, production passes `nil` for a receive only if available and reports a required
	/// one as unfulfillable (`requiredReceiveIsUnfulfillable(nonOptionalForm:rootBindsEveryReceive:)`).
	/// - Parameter rootBindsEveryReceive: Whether the tree is a mock's, whose root declares every received dependency,
	///   above every hiding declaration, so the receive is provided whatever the scopes above provide.
	static func receiveIsHidden(_ read: FulfillmentRead, answeredWith answer: DeclaredLabelAnswer, rootBindsEveryReceive: Bool) -> Bool {
		!answer.nearest.answers(read) && (rootBindsEveryReceive || answer.isProvidedAbove)
	}

	/// Whether a receive in a tree a cycle builds again is newly hidden on that lap: it is hidden as the lap answers it,
	/// and the tree's first build, which judged every receive as `receiveIsHidden` does, did not report the same.
	/// - Parameters:
	///   - firstBuild: What the first build answered the read with, where the declaration that answers it on the lap
	///     answered it there too; `nil` where a declaration between the scope the cycle closes on and the cycle-closing
	///     scope answers it on the lap, whose judgement the first build cannot have made.
	///   - builtAgain: What the lap answers it with.
	static func receiveIsHiddenOnLapBuiltAgain(
		_ read: FulfillmentRead,
		firstBuild: DeclaredLabelAnswer?,
		builtAgain: DeclaredLabelAnswer,
		rootBindsEveryReceive: Bool,
	) -> Bool {
		receiveIsHidden(read, answeredWith: builtAgain, rootBindsEveryReceive: rootBindsEveryReceive)
			&& !(firstBuild.map { receiveIsHidden(read, answeredWith: $0, rootBindsEveryReceive: rootBindsEveryReceive) } ?? false)
	}

	/// Whether a required receive that no scope above provides as it asks, that its own scope does not create, and whose
	/// scope is no root, is unfulfillable.
	/// - Parameters:
	///   - answer: What the place answers a read of the receive's non-optional form.
	///   - rootBindsEveryReceive: Whether the tree is a mock's, which binds every property its tree receives from above
	///     it, so there only a property still being built is unfulfillable.
	static func requiredReceiveIsUnfulfillable(nonOptionalForm answer: FulfillmentAnswer, rootBindsEveryReceive: Bool) -> Bool {
		switch answer {
		case .none, .declared:
			!rootBindsEveryReceive
		case .beingBuilt:
			true
		}
	}

	/// Whether a required receive in a tree a cycle builds again closes a dependency cycle on that lap: the declaration
	/// that newly answers it there provides a form it accepts and is a value still being built around the cycle-closing
	/// scope. An instantiator still being built is wrapped again where the cycle-closing scope passes it (see
	/// `ScopeGenerator.ReceivedBuilderLoops`), and a declaration of another form is the hidden-label error.
	/// - Parameter answer: What the lap answers the read with, where a declaration between the scope the cycle closes on
	///   and the cycle-closing scope answers it.
	static func requiredReceiveClosesCycleOnLapBuiltAgain(_ read: FulfillmentRead, newlyAnsweredWith answer: FulfillmentAnswer) -> Bool {
		switch answer {
		case .none, .declared:
			false
		case let .beingBuilt(forms):
			forms.answers(read) && !ScopeGenerator.isBuilder(forms.property.asValidatedForDependencyCycles)
		}
	}
}

extension DependencyTreeGenerator.DependencyTreeGeneratorError.LabelDeclaration {
	/// What the declaration provides, by value.
	var forms: DependencyTreeGenerator.FulfillmentForms {
		DependencyTreeGenerator.FulfillmentForms(property: property, lazilyInstantiatedInstanceProperty: lazilyInstantiatedInstanceProperty)
	}
}
