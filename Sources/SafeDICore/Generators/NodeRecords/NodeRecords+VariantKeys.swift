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

extension NodeRecords {
	/// The by-value properties `declaration`'s type receives, in `variant`, as the instance of a `LazilyInstantiated` or a
	/// `SendableLazilyInstantiated` declared above it: what the tree hands its place as `lazilyInstantiatedInstanceProperties`
	/// (`Scope.createScopeGenerator`), read from the variant's key alone, which every call of the variant shares.
	///
	/// A required receive's read (`value`) keys in full, so its key names the declaration that answers it, whose instance it
	/// reads where that declaration is a lazy wrapper. A receive only if available keys by rule 1, which names only the
	/// wrapper kind of a wrapper answering a read of its value (`TypeFactsGraph.optionalParameterKey(of:)`): the instance is
	/// then the receive's own unwrapped property, the value it reads.
	static func lazilyInstantiatedInstanceProperties(of declaration: DeclarationID, variant: VariantID, in world: some NodeRecordVariantFacts) -> Set<Property> {
		let reads = world.reads(of: declaration)
		let keys = world.keys(of: variant)
		var keyByChannelByLabel = [String: [ReadChannel: AnswerID]]()
		for (read, key) in zip(reads.map(world.read), keys) where read.channel.asksAboutLabel {
			keyByChannelByLabel[world.text(ofLabel: read.label), default: [:]][read.channel] = key
		}
		guard !keyByChannelByLabel.isEmpty else { return [] }
		var properties = Set<Property>()
		for dependency in world.scope(of: declaration).instantiable.dependencies {
			let keyByChannel = keyByChannelByLabel[dependency.property.label] ?? [:]
			switch dependency.source {
			case .received(onlyIfAvailable: true):
				// A receive of the wrapper itself is handed the wrapper, never its instance.
				if let key = keyByChannel[.optionalValue], isLazyWrapperOfAValueRead(key), dependency.property.asUnwrappedProperty.propertyType.isConstant {
					properties.insert(dependency.property.asUnwrappedProperty)
				}
			case .received(onlyIfAvailable: false):
				if let key = keyByChannel[.value], let declared = world.declaredProperty(ofKey: key), !declared.typeDescription.isOptional, let instance = declared.asLazilyInstantiatedInstanceProperty {
					properties.insert(instance)
				}
			case .instantiated, .forwarded, .aliased:
				// An alias is a leaf of its own, whose record reads its key (`renameRecord`).
				break
			}
		}
		return properties
	}

	/// Whether `key`, a read's key that rule 1 projected, is a lazy wrapper answering a read of its value.
	static func isLazyWrapperOfAValueRead(_ key: AnswerID) -> Bool {
		key == TypeFactsGraph.optionalLazilyInstantiatedParameterKey || key == TypeFactsGraph.optionalSendableLazilyInstantiatedParameterKey
	}
}
