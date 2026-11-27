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

/// A type as one generator holds it, exactly: two spellings that differ in any byte, or in structure, have two IDs.
struct TypeID: Hashable, Sendable {
	fileprivate init(_ index: Int) {
		// An ID per distinct value the generator reads: no module holds 2^31 of them, so the index never wraps.
		raw = Int32(truncatingIfNeeded: index)
	}

	let raw: Int32
}

extension TypeID {
	/// An ID no value has: a lookup spells a child it finds no ID for with it, so that the key misses.
	fileprivate static let notInterned = TypeID(-1)
}

/// A type as `TypeDescription.==` and `hash` compare it: two types have one class ID exactly when `==` holds.
struct TypeClassID: Hashable, Sendable {
	fileprivate init(_ index: Int) {
		raw = Int32(truncatingIfNeeded: index)
	}

	let raw: Int32
}

/// A type as the construction memo compares it: its class, and its spelling's bytes (`isSpelledAlike`).
struct TypeAlikeID: Hashable, Sendable {
	fileprivate init(_ index: Int) {
		raw = Int32(truncatingIfNeeded: index)
	}

	let raw: Int32
}

/// A label by its UTF-8 bytes.
struct LabelID: Hashable, Sendable {
	fileprivate init(_ index: Int) {
		raw = Int32(truncatingIfNeeded: index)
	}

	let raw: Int32
}

extension LabelID {
	/// An ID no label has: a property's lookup spells a label it finds no ID for with it, so that the key misses.
	fileprivate static let notInterned = LabelID(-1)
}

/// A label as `String.==` compares it, which reads canonically equivalent spellings as one.
struct LabelClassID: Hashable, Sendable {
	fileprivate init(_ index: Int) {
		raw = Int32(truncatingIfNeeded: index)
	}

	let raw: Int32
}

/// A property as one generator holds it, exactly: its label's bytes and its type's exact ID.
struct PropertyID: Hashable, Sendable {
	fileprivate init(_ index: Int) {
		raw = Int32(truncatingIfNeeded: index)
	}

	let raw: Int32
}

/// A property as `Property.==` and `hash` compare it: its label's class and its type's class.
struct PropertyClassID: Hashable, Sendable {
	fileprivate init(_ index: Int) {
		raw = Int32(truncatingIfNeeded: index)
	}

	let raw: Int32
}

/// A property whose instance `Property.asLazilyInstantiatedInstanceProperty` returns, which only
/// `ConstructionInterner.lazilyInstantiated(_:)` makes, so that `instance(of:)` reads only a property in its table's domain.
struct LazilyInstantiatedPropertyID: Hashable, Sendable {
	fileprivate init(_ id: PropertyID) {
		self.id = id
	}

	let id: PropertyID
}

/// An append-only table read by position, held in chunks so that a published copy shares every full chunk and copies
/// at most the last, partial one when the table grows after it.
struct ChunkedTable<Element: Sendable>: Sendable {
	/// How many elements a full chunk holds.
	static var chunkSize: Int {
		4_096
	}

	/// A full chunk, never changed.
	final class Chunk: Sendable {
		init(_ elements: [Element]) {
			self.elements = elements
		}

		let elements: [Element]
	}

	/// How many elements the table holds.
	var count: Int {
		fullChunks.count * Self.chunkSize + tail.count
	}

	/// The element at `index`, which is less than `count`.
	subscript(index: Int) -> Element {
		let (chunk, offset) = index.quotientAndRemainder(dividingBy: Self.chunkSize)
		return if chunk < fullChunks.count {
			fullChunks[chunk].elements[offset]
		} else {
			tail[offset]
		}
	}

	/// Adds `element` at position `count`.
	mutating func append(_ element: Element) {
		tail.append(element)
		if tail.count == Self.chunkSize {
			fullChunks.append(Chunk(tail))
			tail = []
		}
	}

	private var fullChunks = [Chunk]()
	private var tail = [Element]()
}

/// Every type and label one generator's construction reads, by ID, with what each ID projects: immutable, published by
/// the serial `Builder` that owns the generator's ID space, and read by every task that builds a tree. A later snapshot
/// of the same builder answers every ID an earlier one gave as it did, since the builder never renumbers.
final class ConstructionInterner: Sendable {
	fileprivate init(
		index: ExactIndex,
		typeClass: ChunkedTable<TypeClassID>,
		typeAlike: ChunkedTable<TypeAlikeID>,
		labelClass: ChunkedTable<LabelClassID>,
		propertyClass: ChunkedTable<PropertyClassID>,
		propertyValidatedForDependencyCycles: ChunkedTable<PropertyID>,
		propertyLazilyInstantiatedInstance: ChunkedTable<PropertyID>,
		propertyIsLazilyInstantiated: ChunkedTable<Bool>,
		propertyLabel: ChunkedTable<LabelID>,
		propertyType: ChunkedTable<TypeID>,
	) {
		self.index = index
		self.typeClass = typeClass
		self.typeAlike = typeAlike
		self.labelClass = labelClass
		self.propertyClass = propertyClass
		self.propertyValidatedForDependencyCycles = propertyValidatedForDependencyCycles
		self.propertyLazilyInstantiatedInstance = propertyLazilyInstantiatedInstance
		self.propertyIsLazilyInstantiated = propertyIsLazilyInstantiated
		self.propertyLabel = propertyLabel
		self.propertyType = propertyType
	}

	/// The ID the builder gave `type`, spelled exactly so, before this snapshot was published, or `nil` when it gave none.
	func id(of type: TypeDescription) -> TypeID? {
		index.typeID(for: Self.exactKey(of: type) { id(of: $0) ?? .notInterned })
	}

	/// The ID the builder gave a label of exactly `label`’s bytes before this snapshot was published, or `nil`.
	func id(ofLabel label: String) -> LabelID? {
		index.labelID(for: Array(label.utf8))
	}

	/// The ID the builder gave `property`, its label’s bytes and its type’s spelling, before this snapshot was published,
	/// or `nil`.
	func id(of property: Property) -> PropertyID? {
		index.propertyID(for: PropertyExactKey(label: id(ofLabel: property.label) ?? .notInterned, type: id(of: property.typeDescription) ?? .notInterned))
	}

	/// The label of `property`.
	func label(of property: PropertyID) -> LabelID {
		propertyLabel[Int(property.raw)]
	}

	/// The type of `property`.
	func type(of property: PropertyID) -> TypeID {
		propertyType[Int(property.raw)]
	}

	/// How many frozen layers the snapshot’s lookups read.
	var layerCount: Int {
		index.layers.count
	}

	/// The class of `type`.
	func classID(of type: TypeID) -> TypeClassID {
		typeClass[Int(type.raw)]
	}

	/// The class of `type` with its spelling's bytes.
	func alikeID(of type: TypeID) -> TypeAlikeID {
		typeAlike[Int(type.raw)]
	}

	/// The class of `label`.
	func classID(of label: LabelID) -> LabelClassID {
		labelClass[Int(label.raw)]
	}

	/// The class of `property`.
	func classID(of property: PropertyID) -> PropertyClassID {
		propertyClass[Int(property.raw)]
	}

	/// `Property.asValidatedForDependencyCycles` of `property`.
	func asValidatedForDependencyCycles(_ property: PropertyID) -> PropertyID {
		propertyValidatedForDependencyCycles[Int(property.raw)]
	}

	/// `property` as a lazily instantiated property, where `Property.asLazilyInstantiatedInstanceProperty` returns its
	/// instance.
	func lazilyInstantiated(_ property: PropertyID) -> LazilyInstantiatedPropertyID? {
		propertyIsLazilyInstantiated[Int(property.raw)] ? LazilyInstantiatedPropertyID(property) : nil
	}

	/// `Property.asLazilyInstantiatedInstanceProperty` of `property`.
	func instance(of property: LazilyInstantiatedPropertyID) -> PropertyID {
		propertyLazilyInstantiatedInstance[Int(property.id.raw)]
	}

	private let typeClass: ChunkedTable<TypeClassID>
	private let typeAlike: ChunkedTable<TypeAlikeID>
	private let labelClass: ChunkedTable<LabelClassID>
	private let propertyClass: ChunkedTable<PropertyClassID>
	private let propertyValidatedForDependencyCycles: ChunkedTable<PropertyID>
	/// Outside `propertyIsLazilyInstantiated`'s domain, an entry holds the property itself, which nothing reads.
	private let propertyLazilyInstantiatedInstance: ChunkedTable<PropertyID>
	private let propertyIsLazilyInstantiated: ChunkedTable<Bool>
	private let propertyLabel: ChunkedTable<LabelID>
	private let propertyType: ChunkedTable<TypeID>
	private let index: ExactIndex

	fileprivate struct PropertyExactKey: Hashable, Sendable {
		let label: LabelID
		let type: TypeID
	}

	/// A type’s structure, its names by their bytes and its children by their exact IDs.
	fileprivate enum ExactKey: Hashable, Sendable {
		case void(spelling: String)
		case simple(name: [UInt8], generics: [TypeID])
		case nested(name: [UInt8], parent: TypeID, generics: [TypeID])
		case composition([TypeID])
		case optional(TypeID)
		case implicitlyUnwrappedOptional(TypeID)
		case some(TypeID)
		case any(TypeID)
		case metatype(TypeID, isType: Bool)
		case attributed(TypeID, specifiers: [[UInt8]], attributes: [[UInt8]])
		case array(TypeID)
		case dictionary(key: TypeID, value: TypeID)
		case tuple([ExactTupleElement])
		case closure(arguments: [TypeID], isAsync: Bool, doesThrow: Bool, thrownType: TypeID?, returnType: TypeID)
		case variadic(TypeID)
		case unknown([UInt8])
	}

	fileprivate struct ExactTupleElement: Hashable, Sendable {
		let label: [UInt8]?
		let type: TypeID
	}

	/// The exact key of `type`, its children’s IDs from `childID`: the builder interns them, and a snapshot looks them up.
	fileprivate static func exactKey(of type: TypeDescription, childID: (TypeDescription) -> TypeID) -> ExactKey {
		switch type {
		case let .void(spelling):
			.void(spelling: spelling.rawValue)
		case let .simple(name, generics):
			.simple(name: Array(name.utf8), generics: generics.map { childID($0) })
		case let .nested(name, parentType, generics):
			.nested(name: Array(name.utf8), parent: childID(parentType), generics: generics.map { childID($0) })
		case let .composition(types):
			.composition(types.map { childID($0) })
		case let .optional(wrapped):
			.optional(childID(wrapped))
		case let .implicitlyUnwrappedOptional(wrapped):
			.implicitlyUnwrappedOptional(childID(wrapped))
		case let .some(constraint):
			.some(childID(constraint))
		case let .any(constraint):
			.any(childID(constraint))
		case let .metatype(instanceType, isType):
			.metatype(childID(instanceType), isType: isType)
		case let .attributed(attributedType, specifiers, attributes):
			.attributed(childID(attributedType), specifiers: specifiers.map { Array($0.utf8) }, attributes: attributes.map { Array($0.utf8) })
		case let .array(element):
			.array(childID(element))
		case let .dictionary(key, value):
			.dictionary(key: childID(key), value: childID(value))
		case let .tuple(elements):
			.tuple(elements.map { ExactTupleElement(label: $0.label.map { Array($0.utf8) }, type: childID($0.typeDescription)) })
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			.closure(arguments: arguments.map { childID($0) }, isAsync: isAsync, doesThrow: doesThrow, thrownType: thrownType.map { childID($0) }, returnType: childID(returnType))
		case let .variadic(variadicType):
			.variadic(childID(variadicType))
		case let .unknown(text):
			.unknown(Array(text.utf8))
		}
	}

	/// Every value’s ID by its exact key, in frozen layers that every snapshot and every copy of the builder share, and
	/// what was interned since the last freeze. A freeze merges the newest layer into the one before it while that one is
	/// no larger, so the layers’ sizes at least double from the newest to the oldest: a run holds as many layers as the
	/// logarithm of its values, and copies each value as many times.
	fileprivate struct ExactIndex: Sendable {
		/// One frozen layer, never changed.
		final class Layer: Sendable {
			init(typeIDByExactKey: [ExactKey: TypeID], labelIDByBytes: [[UInt8]: LabelID], propertyIDByExactKey: [PropertyExactKey: PropertyID]) {
				self.typeIDByExactKey = typeIDByExactKey
				self.labelIDByBytes = labelIDByBytes
				self.propertyIDByExactKey = propertyIDByExactKey
			}

			/// A layer of `older`’s values and `newer`’s, which share none.
			convenience init(merging older: Layer, _ newer: Layer) {
				var typeIDByExactKey = older.typeIDByExactKey
				typeIDByExactKey.reserveCapacity(older.typeIDByExactKey.count + newer.typeIDByExactKey.count)
				for (key, id) in newer.typeIDByExactKey {
					typeIDByExactKey[key] = id
				}
				var labelIDByBytes = older.labelIDByBytes
				labelIDByBytes.reserveCapacity(older.labelIDByBytes.count + newer.labelIDByBytes.count)
				for (bytes, id) in newer.labelIDByBytes {
					labelIDByBytes[bytes] = id
				}
				var propertyIDByExactKey = older.propertyIDByExactKey
				propertyIDByExactKey.reserveCapacity(older.propertyIDByExactKey.count + newer.propertyIDByExactKey.count)
				for (key, id) in newer.propertyIDByExactKey {
					propertyIDByExactKey[key] = id
				}
				self.init(typeIDByExactKey: typeIDByExactKey, labelIDByBytes: labelIDByBytes, propertyIDByExactKey: propertyIDByExactKey)
			}

			let typeIDByExactKey: [ExactKey: TypeID]
			let labelIDByBytes: [[UInt8]: LabelID]
			let propertyIDByExactKey: [PropertyExactKey: PropertyID]

			var count: Int {
				typeIDByExactKey.count + labelIDByBytes.count + propertyIDByExactKey.count
			}
		}

		/// The frozen layers, oldest and largest first.
		private(set) var layers = [Layer]()

		func typeID(for key: ExactKey) -> TypeID? {
			layers.lazy.compactMap { $0.typeIDByExactKey[key] }.first ?? pendingTypeIDByExactKey[key]
		}

		func labelID(for bytes: [UInt8]) -> LabelID? {
			layers.lazy.compactMap { $0.labelIDByBytes[bytes] }.first ?? pendingLabelIDByBytes[bytes]
		}

		func propertyID(for key: PropertyExactKey) -> PropertyID? {
			layers.lazy.compactMap { $0.propertyIDByExactKey[key] }.first ?? pendingPropertyIDByExactKey[key]
		}

		mutating func insert(_ id: TypeID, for key: ExactKey) {
			pendingTypeIDByExactKey[key] = id
		}

		mutating func insert(_ id: LabelID, for bytes: [UInt8]) {
			pendingLabelIDByBytes[bytes] = id
		}

		mutating func insert(_ id: PropertyID, for key: PropertyExactKey) {
			pendingPropertyIDByExactKey[key] = id
		}

		/// Moves what was interned since the last freeze into a layer of its own, merging layers that are no larger.
		mutating func freeze() {
			guard !pendingTypeIDByExactKey.isEmpty || !pendingLabelIDByBytes.isEmpty || !pendingPropertyIDByExactKey.isEmpty else { return }
			var newest = Layer(typeIDByExactKey: pendingTypeIDByExactKey, labelIDByBytes: pendingLabelIDByBytes, propertyIDByExactKey: pendingPropertyIDByExactKey)
			pendingTypeIDByExactKey = [:]
			pendingLabelIDByBytes = [:]
			pendingPropertyIDByExactKey = [:]
			while let older = layers.last, older.count <= newest.count {
				layers.removeLast()
				newest = Layer(merging: older, newest)
			}
			layers.append(newest)
		}

		private var pendingTypeIDByExactKey = [ExactKey: TypeID]()
		private var pendingLabelIDByBytes = [[UInt8]: LabelID]()
		private var pendingPropertyIDByExactKey = [PropertyExactKey: PropertyID]()
	}

	/// The one writer of a generator's ID space. It gives IDs in the order it is asked for values, a type's children
	/// before the type, and publishes snapshots (`snapshot()`).
	struct Builder: Sendable {
		/// The ID of `type`, given now when the builder has none.
		mutating func intern(_ type: TypeDescription) -> TypeID {
			let exactKey = ConstructionInterner.exactKey(of: type) { intern($0) }
			if let id = index.typeID(for: exactKey) {
				return id
			} else {
				let classID = classID(of: type)
				let alikeKey = AlikeKey(classID: classID, spelling: Array(type.asSource.utf8))
				let alikeID = typeAlikeIDByKey[alikeKey] ?? TypeAlikeID(typeAlikeIDByKey.count)
				typeAlikeIDByKey[alikeKey] = alikeID
				let id = TypeID(typeClass.count)
				index.insert(id, for: exactKey)
				typeClass.append(classID)
				typeAlike.append(alikeID)
				return id
			}
		}

		/// The ID of `label`, given now when the builder has none.
		mutating func intern(label: String) -> LabelID {
			let bytes = Array(label.utf8)
			if let id = index.labelID(for: bytes) {
				return id
			} else {
				let classID = labelClassIDByLabel[label] ?? LabelClassID(labelClassIDByLabel.count)
				labelClassIDByLabel[label] = classID
				let id = LabelID(labelClass.count)
				index.insert(id, for: bytes)
				labelClass.append(classID)
				return id
			}
		}

		/// The ID of `property`, given now when the builder has none, after the IDs of the forms construction derives from
		/// it: `asValidatedForDependencyCycles` and `asLazilyInstantiatedInstanceProperty`. Each takes a generic argument of
		/// the type, so it is smaller, and interning them first ends.
		mutating func intern(_ property: Property) -> PropertyID {
			let label = intern(label: property.label)
			let type = intern(property.typeDescription)
			let exactKey = PropertyExactKey(label: label, type: type)
			if let id = index.propertyID(for: exactKey) {
				return id
			} else {
				let validatedForDependencyCycles = property.typeDescription.lazilyInstantiatedInstanceType.map { _ in intern(property.asValidatedForDependencyCycles) }
				let lazilyInstantiatedInstance = property.asLazilyInstantiatedInstanceProperty.map { intern($0) }
				let classKey = PropertyClassKey(label: labelClass[Int(label.raw)], type: typeClass[Int(type.raw)])
				let classID = propertyClassIDByKey[classKey] ?? PropertyClassID(propertyClassIDByKey.count)
				propertyClassIDByKey[classKey] = classID
				let id = PropertyID(propertyClass.count)
				index.insert(id, for: exactKey)
				propertyClass.append(classID)
				propertyLabel.append(label)
				propertyType.append(type)
				propertyValidatedForDependencyCycles.append(validatedForDependencyCycles ?? id)
				propertyLazilyInstantiatedInstance.append(lazilyInstantiatedInstance ?? id)
				propertyIsLazilyInstantiated.append(lazilyInstantiatedInstance != nil)
				return id
			}
		}

		/// Interns, before any map is frozen, what the generator's declarations spell, in the order `instantiables` holds
		/// them and each one's dependencies in declaration order: its concrete type, the types it fulfills, and each
		/// dependency's property, the type it instantiates, what fulfills it, and, for an alias, its fulfilling property
		/// spelled as the alias spells it (`ValueSpellings.fulfillingProperty(_:spelledAsAlias:)`).
		mutating func internDeclarations(of instantiables: some Sequence<Instantiable>) {
			for instantiable in instantiables {
				_ = intern(instantiable.concreteInstantiable)
				for instantiableType in instantiable.instantiableTypes {
					_ = intern(instantiableType)
				}
				for dependency in instantiable.dependencies {
					_ = intern(dependency.property)
					_ = intern(dependency.asInstantiatedType)
					switch dependency.source {
					case let .instantiated(fulfillingTypeDescription, _):
						if let fulfillingTypeDescription {
							_ = intern(fulfillingTypeDescription)
						}
					case let .aliased(fulfillingProperty, _, _):
						_ = intern(fulfillingProperty)
						_ = intern(ValueSpellings.fulfillingProperty(fulfillingProperty, spelledAsAlias: dependency.property))
					case .received, .forwarded:
						break
					}
				}
			}
		}

		/// The class of `type`, as a snapshot answers it.
		func classID(of type: TypeID) -> TypeClassID {
			typeClass[Int(type.raw)]
		}

		/// The class of `property`, as a snapshot answers it.
		func classID(of property: PropertyID) -> PropertyClassID {
			propertyClass[Int(property.raw)]
		}

		/// `Property.asValidatedForDependencyCycles` of `property`, as a snapshot answers it.
		func asValidatedForDependencyCycles(_ property: PropertyID) -> PropertyID {
			propertyValidatedForDependencyCycles[Int(property.raw)]
		}

		/// How many types, labels and properties the builder has interned: a snapshot's tables differ from the builder's
		/// exactly when this has grown since it was published, since every interned value appends to its domain's tables.
		var internedCount: Int {
			typeClass.count + labelClass.count + propertyClass.count
		}

		/// What the builder holds now, for every reader until the next snapshot, with what it has interned since the last
		/// one frozen into the layers they share.
		mutating func snapshot() -> ConstructionInterner {
			index.freeze()
			return ConstructionInterner(
				index: index,
				typeClass: typeClass,
				typeAlike: typeAlike,
				labelClass: labelClass,
				propertyClass: propertyClass,
				propertyValidatedForDependencyCycles: propertyValidatedForDependencyCycles,
				propertyLazilyInstantiatedInstance: propertyLazilyInstantiatedInstance,
				propertyIsLazilyInstantiated: propertyIsLazilyInstantiated,
				propertyLabel: propertyLabel,
				propertyType: propertyType,
			)
		}

		private struct PropertyClassKey: Hashable {
			let label: LabelClassID
			let type: TypeClassID
		}

		/// A type as `TypeDescription.==` and `hash` read it, case by case: names by `String ==`, which reads canonically
		/// equivalent spellings as one; children by their classes; `any P` as `P` at every depth; one `Void` however it
		/// is spelled; a composition's members as a set; a metatype by whether it is the existential metatype; a
		/// closure's thrown type beyond `any Error`.
		private enum ClassKey: Hashable {
			case void
			case simple(name: String, generics: [TypeClassID])
			case nested(name: String, parent: TypeClassID, generics: [TypeClassID])
			case composition([TypeClassID])
			case optional(TypeClassID)
			case implicitlyUnwrappedOptional(TypeClassID)
			case some(TypeClassID)
			case metatype(TypeClassID, isExistentialMetatype: Bool)
			case attributed(TypeClassID, specifiers: [String], attributes: [String])
			case array(TypeClassID)
			case dictionary(key: TypeClassID, value: TypeClassID)
			case tuple([ClassTupleElement])
			case closure(arguments: [TypeClassID], isAsync: Bool, doesThrow: Bool, thrownTypeBeyondAnyError: TypeClassID?, returnType: TypeClassID)
			case variadic(TypeClassID)
			case unknown(String)
		}

		private struct ClassTupleElement: Hashable {
			let label: String?
			let type: TypeClassID
		}

		private struct AlikeKey: Hashable {
			let classID: TypeClassID
			let spelling: [UInt8]
		}

		/// The class of `type`, interning the classes of its children first.
		private mutating func classID(of type: TypeDescription) -> TypeClassID {
			let key: ClassKey
			switch type {
			case let .any(constraint):
				return classID(of: constraint)
			case .void:
				key = .void
			case let .simple(name, generics):
				key = .simple(name: name, generics: generics.map { classID(of: $0) })
			case let .nested(name, parentType, generics):
				key = .nested(name: name, parent: classID(of: parentType), generics: generics.map { classID(of: $0) })
			case let .composition(types):
				key = .composition(Set(types.map { classID(of: $0) }).sorted { $0.raw < $1.raw })
			case let .optional(wrapped):
				key = .optional(classID(of: wrapped))
			case let .implicitlyUnwrappedOptional(wrapped):
				key = .implicitlyUnwrappedOptional(classID(of: wrapped))
			case let .some(constraint):
				key = .some(classID(of: constraint))
			case let .metatype(instanceType, isType):
				key = .metatype(classID(of: instanceType), isExistentialMetatype: TypeDescription.isExistentialMetatype(ofInstanceType: instanceType, isType: isType))
			case let .attributed(attributedType, specifiers, attributes):
				key = .attributed(classID(of: attributedType), specifiers: specifiers, attributes: attributes)
			case let .array(element):
				key = .array(classID(of: element))
			case let .dictionary(dictionaryKey, value):
				key = .dictionary(key: classID(of: dictionaryKey), value: classID(of: value))
			case let .tuple(elements):
				key = .tuple(elements.map { ClassTupleElement(label: $0.label, type: classID(of: $0.typeDescription)) })
			case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
				key = .closure(
					arguments: arguments.map { classID(of: $0) },
					isAsync: isAsync,
					doesThrow: doesThrow,
					thrownTypeBeyondAnyError: TypeDescription.thrownTypeBeyondAnyError(thrownType).map { classID(of: $0) },
					returnType: classID(of: returnType),
				)
			case let .variadic(variadicType):
				key = .variadic(classID(of: variadicType))
			case let .unknown(text):
				key = .unknown(text)
			}
			if let classID = typeClassIDByKey[key] {
				return classID
			} else {
				let classID = TypeClassID(typeClassIDByKey.count)
				typeClassIDByKey[key] = classID
				return classID
			}
		}

		private var index = ExactIndex()
		private var typeClassIDByKey = [ClassKey: TypeClassID]()
		private var typeAlikeIDByKey = [AlikeKey: TypeAlikeID]()
		private var labelClassIDByLabel = [String: LabelClassID]()
		private var typeClass = ChunkedTable<TypeClassID>()
		private var typeAlike = ChunkedTable<TypeAlikeID>()
		private var labelClass = ChunkedTable<LabelClassID>()
		private var propertyClassIDByKey = [PropertyClassKey: PropertyClassID]()
		private var propertyClass = ChunkedTable<PropertyClassID>()
		private var propertyValidatedForDependencyCycles = ChunkedTable<PropertyID>()
		private var propertyLazilyInstantiatedInstance = ChunkedTable<PropertyID>()
		private var propertyIsLazilyInstantiated = ChunkedTable<Bool>()
		private var propertyLabel = ChunkedTable<LabelID>()
		private var propertyType = ChunkedTable<TypeID>()
	}
}

/// The ID space of one generator: the one `ConstructionInterner.Builder` its serial code appends to, seeded with what its
/// declarations spell before any map is frozen, and the snapshot each freeze publishes for the trees built from its table.
/// Not `Sendable`: only the generator's serial code, which freezes its maps, holds it, and construction reads only the
/// snapshots, which are.
final class ConstructionInternerSpace {
	/// A space that has interned, first, what `instantiables` spell, in their order (`Builder.internDeclarations(of:)`).
	init(declarationsOf instantiables: some Sequence<Instantiable>) {
		builder.internDeclarations(of: instantiables)
	}

	/// A space whose IDs start as `builder`'s, for a task that freezes maps of its own.
	init(copying builder: ConstructionInterner.Builder) {
		self.builder = builder
	}

	/// A copy of the space's IDs as they are now, which `init(copying:)` starts a space from.
	func copyOfBuilder() -> ConstructionInterner.Builder {
		builder
	}

	/// Interns what `instantiables` spell, in their order, as the space's own declarations are interned: a computation over
	/// another declaration map – a seam module's view, or the callers' – freezes its scopes in this space.
	func internDeclarations(of instantiables: some Sequence<Instantiable>) {
		builder.internDeclarations(of: instantiables)
	}

	/// The ID of `type`, given now when the space has none.
	func intern(_ type: TypeDescription) -> TypeID {
		reportingMiss(of: type.asSource) { $0.intern(type) }
	}

	/// The ID of `property`, given now when the space has none.
	func intern(_ property: Property) -> PropertyID {
		reportingMiss(of: "\(property.label): \(property.typeDescription.asSource)") { $0.intern(property) }
	}

	/// What `intern` returns, reporting `value` to the miss observer, if any, when it interned what the space did not hold.
	private func reportingMiss<ID>(of value: @autoclosure () -> String, _ intern: (inout ConstructionInterner.Builder) -> ID) -> ID {
		let internedCount = builder.internedCount
		let id = intern(&builder)
		if builder.internedCount != internedCount, let missObserver = ConstructionInternerObservation.missObserver {
			missObserver(missBucket, value())
		}
		return id
	}

	/// What `body` returns, counting each value it interns that the space did not hold in `bucket`.
	func interning<Value>(countingMissesIn bucket: ConstructionInternerMiss, _ body: () -> Value) -> Value {
		let enclosingBucket = missBucket
		missBucket = bucket
		defer { missBucket = enclosingBucket }
		return body()
	}

	/// The class of `type`.
	func classID(of type: TypeID) -> TypeClassID {
		builder.classID(of: type)
	}

	/// The class of `property`.
	func classID(of property: PropertyID) -> PropertyClassID {
		builder.classID(of: property)
	}

	/// `Property.asValidatedForDependencyCycles` of `property`.
	func asValidatedForDependencyCycles(_ property: PropertyID) -> PropertyID {
		builder.asValidatedForDependencyCycles(property)
	}

	/// What the space holds now: the snapshot published last, while nothing has been interned since.
	func snapshot() -> ConstructionInterner {
		if let publishedSnapshot, publishedCount == builder.internedCount {
			return publishedSnapshot
		} else {
			let snapshot = builder.snapshot()
			publishedSnapshot = snapshot
			publishedCount = builder.internedCount
			return snapshot
		}
	}

	private var builder = ConstructionInterner.Builder()
	private var publishedSnapshot: ConstructionInterner?
	private var publishedCount = 0
	private var missBucket = ConstructionInternerMiss.notExcluded
}

/// Where a value the declarations did not give a generator's interner, and a freeze interns, is read (see
/// `ConstructionInternerObservation.missObserver`).
public enum ConstructionInternerMiss: Sendable {
	/// By construction, which reads only what the declarations give and what the freezes are designed to intern: a miss
	/// here is a construction site the interner does not cover.
	case notExcluded
	/// Only by places that hold a fill or are inside one, which no memo entry keys or stores: a fill's context stack.
	case excluded
	/// By a record the freezes are designed to intern: a root's, whose promotion respells what a mock root receives, and a
	/// leaf's that calls a seam or another module's public mock, whose instantiable is the call's signature.
	case internedAtFreeze
}

/// How the tests order what a generator interns: set by the tests, never by the tool.
public enum ConstructionInternerObservation {
	/// When set, a generator interns its declarations in the order this returns, a permutation of the positions of as many
	/// declarations as it is passed, so that a test can show that no ID's value, which the order assigns, reaches output.
	@TaskLocal public static var declarationOrder: (@Sendable (_ declarationCount: Int) -> [Int])?
	/// When set, called with each value a freeze interns that the generator's interner did not hold, and where it is read:
	/// the closure test, which requires no value of `ConstructionInternerMiss.notExcluded`.
	@TaskLocal public static var missObserver: (@Sendable (_ bucket: ConstructionInternerMiss, _ value: String) -> Void)?
}
