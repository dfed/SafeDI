# SafeDIParameters Reference Spec

This document defines the target generated output for the SafeDIParameters mock API redesign.
Each example shows input Swift source and the expected generated mock code.
All expected output has been verified to compile as valid Swift.

---

## Example 1: Full tree with custom mocks and defaults

### Input

```swift
public enum Theme { case light, dark }
public enum Style { case compact, expanded }

@Instantiable(isRoot: true, generateMock: true)
public struct Root: Instantiable {
    public init(service: Service, childA: ChildA, childB: ChildB, name: String) {
        self.service = service
        self.childA = childA
        self.childB = childB
        self.name = name
    }
    @Instantiated let service: Service
    @Instantiated let childA: ChildA
    @Instantiated let childB: ChildB
    @Forwarded let name: String
}

@Instantiable(generateMock: true)
public struct Service: Instantiable {
    public init() {}
}

@Instantiable(generateMock: true, customMockName: "customMock")
public struct ChildA: Instantiable {
    public init(grandchild: Grandchild, service: Service, name: String) {
        self.grandchild = grandchild
        self.service = service
        self.name = name
    }
    @Instantiated let grandchild: Grandchild
    @Received let service: Service
    @Received let name: String

    public static func customMock(
        grandchild: Grandchild,
        service: Service,
        name: String,
        theme: Theme = .light
    ) -> ChildA {
        ChildA(grandchild: grandchild, service: service, name: name)
    }
}

@Instantiable(generateMock: true, customMockName: "customMock")
public struct Grandchild: Instantiable {
    public init(service: Service, name: String) {
        self.service = service
        self.name = name
    }
    @Received let service: Service
    @Received let name: String

    public static func customMock(
        service: Service,
        name: String,
        style: Style = .compact
    ) -> Grandchild {
        Grandchild(service: service, name: name)
    }
}

@Instantiable(generateMock: true)
public struct ChildB: Instantiable {
    public init(service: Service, name: String, isPro: Bool = false) {
        self.service = service
        self.name = name
    }
    @Received let service: Service
    @Received let name: String
}
```

### Expected Output: Root+SafeDIMock.swift

```swift
#if DEBUG
extension Root {
    public struct SafeDIParameters {
        public struct Service_Configuration {
            public init(
                _ safeDIBuilder: @escaping () -> Service = Service.init
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: () -> Service
        }

        public struct Grandchild_Configuration {
            public init(
                style: Style = .compact,
                _ safeDIBuilder: @escaping (Service, String, Style) -> Grandchild = Grandchild.customMock(service:name:style:)
            ) {
                self.style = style
                self.safeDIBuilder = safeDIBuilder
            }

            public let style: Style
            public let safeDIBuilder: (Service, String, Style) -> Grandchild
        }

        public struct ChildA_Configuration {
            public init(
                grandchild: Grandchild_Configuration = .init(),
                theme: Theme = .light,
                _ safeDIBuilder: @escaping (Grandchild, Service, String, Theme) -> ChildA = ChildA.customMock(grandchild:service:name:theme:)
            ) {
                self.grandchild = grandchild
                self.theme = theme
                self.safeDIBuilder = safeDIBuilder
            }

            public let grandchild: Grandchild_Configuration
            public let theme: Theme
            public let safeDIBuilder: (Grandchild, Service, String, Theme) -> ChildA
        }

        public struct ChildB_Configuration {
            public init(
                isPro: Bool = false,
                _ safeDIBuilder: @escaping (Service, String, Bool) -> ChildB = ChildB.init(service:name:isPro:)
            ) {
                self.isPro = isPro
                self.safeDIBuilder = safeDIBuilder
            }

            public let isPro: Bool
            public let safeDIBuilder: (Service, String, Bool) -> ChildB
        }

        public init(
            service: Service_Configuration = .init(),
            childA: ChildA_Configuration = .init(),
            childB: ChildB_Configuration = .init()
        ) {
            self.service = service
            self.childA = childA
            self.childB = childB
        }

        public let service: Service_Configuration
        public let childA: ChildA_Configuration
        public let childB: ChildB_Configuration
    }

    public static func mock(
        name: String,
        safeDIParameters: SafeDIParameters = .init()
    ) -> Root {
        let service = safeDIParameters.service.safeDIBuilder()
        let grandchild = safeDIParameters.childA.grandchild.safeDIBuilder(
            service,
            name,
            safeDIParameters.childA.grandchild.style
        )
        let childA = safeDIParameters.childA.safeDIBuilder(
            grandchild,
            service,
            name,
            safeDIParameters.childA.theme
        )
        let childB = safeDIParameters.childB.safeDIBuilder(
            service,
            name,
            safeDIParameters.childB.isPro
        )
        return Root(
            service: service,
            childA: childA,
            childB: childB,
            name: name
        )
    }
}
#endif
```

### Expected Output: Service+SafeDIMock.swift

```swift
#if DEBUG
extension Service {
    public static func mock() -> Service {
        Service()
    }
}
#endif
```

### Expected Output: ChildA+SafeDIMock.swift

ChildA is a non-root type with `generateMock: true`. Its own mock promotes received deps (Service) into SafeDIParameters. Its own non-dependency default (theme from customMock) stays flat on `mock()`.

```swift
#if DEBUG
extension ChildA {
    public struct SafeDIParameters {
        public struct Service_Configuration {
            public init(
                _ safeDIBuilder: @escaping () -> Service = Service.init
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: () -> Service
        }

        public struct Grandchild_Configuration {
            public init(
                style: Style = .compact,
                _ safeDIBuilder: @escaping (Service, String, Style) -> Grandchild = Grandchild.customMock(service:name:style:)
            ) {
                self.style = style
                self.safeDIBuilder = safeDIBuilder
            }

            public let style: Style
            public let safeDIBuilder: (Service, String, Style) -> Grandchild
        }

        public init(
            grandchild: Grandchild_Configuration = .init(),
            service: Service_Configuration = .init()
        ) {
            self.grandchild = grandchild
            self.service = service
        }

        public let grandchild: Grandchild_Configuration
        public let service: Service_Configuration
    }

    public static func mock(
        name: String,
        theme: Theme = .light,
        safeDIParameters: SafeDIParameters = .init()
    ) -> ChildA {
        let service = safeDIParameters.service.safeDIBuilder()
        let grandchild = safeDIParameters.grandchild.safeDIBuilder(
            service,
            name,
            safeDIParameters.grandchild.style
        )
        return ChildA.customMock(
            grandchild: grandchild,
            service: service,
            name: name,
            theme: theme
        )
    }
}
#endif
```

### Expected Output: Grandchild+SafeDIMock.swift

Grandchild has only received deps. Service is instantiable (promoted). String (name) is not instantiable (flat).

```swift
#if DEBUG
extension Grandchild {
    public struct SafeDIParameters {
        public struct Service_Configuration {
            public init(
                _ safeDIBuilder: @escaping () -> Service = Service.init
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: () -> Service
        }

        public init(
            service: Service_Configuration = .init()
        ) {
            self.service = service
        }

        public let service: Service_Configuration
    }

    public static func mock(
        name: String,
        style: Style = .compact,
        safeDIParameters: SafeDIParameters = .init()
    ) -> Grandchild {
        let service = safeDIParameters.service.safeDIBuilder()
        return Grandchild.customMock(
            service: service,
            name: name,
            style: style
        )
    }
}
#endif
```

### Expected Output: ChildB+SafeDIMock.swift

ChildB has no custom mock. Uses init. `isPro` is a non-dependency default — flat on `mock()` since ChildB is the mock root.

```swift
#if DEBUG
extension ChildB {
    public struct SafeDIParameters {
        public struct Service_Configuration {
            public init(
                _ safeDIBuilder: @escaping () -> Service = Service.init
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: () -> Service
        }

        public init(
            service: Service_Configuration = .init()
        ) {
            self.service = service
        }

        public let service: Service_Configuration
    }

    public static func mock(
        name: String,
        isPro: Bool = false,
        safeDIParameters: SafeDIParameters = .init()
    ) -> ChildB {
        let service = safeDIParameters.service.safeDIBuilder()
        return ChildB(
            service: service,
            name: name,
            isPro: isPro
        )
    }
}
#endif
```

---

## Example 2: Instantiator edge

### Input

```swift
@Instantiable(isRoot: true, generateMock: true)
public struct Root: Instantiable {
    public init(shared: Shared, childBuilder: Instantiator<Child>) {
        self.shared = shared
        self.childBuilder = childBuilder
    }
    @Instantiated let shared: Shared
    @Instantiated let childBuilder: Instantiator<Child>
}

@Instantiable(generateMock: true)
public struct Child: Instantiable {
    public init(name: String, shared: Shared) {
        self.name = name
        self.shared = shared
    }
    @Forwarded let name: String
    @Received let shared: Shared
}

@Instantiable(generateMock: true)
public struct Shared: Instantiable {
    public init() {}
}
```

### Expected Output: Root+SafeDIMock.swift

The Instantiator edge uses `Child_Configuration` (named by `asInstantiatedType`, not by property label `childBuilder`). The `safeDIBuilder` builds Child (not Instantiator). The mock body wraps the builder call in `Instantiator<Child> { ... }`.

```swift
#if DEBUG
extension Root {
    public struct SafeDIParameters {
        public struct Shared_Configuration {
            public init(
                _ safeDIBuilder: @escaping () -> Shared = Shared.init
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: () -> Shared
        }

        public struct Child_Configuration {
            public init(
                _ safeDIBuilder: @escaping (String, Shared) -> Child = Child.init(name:shared:)
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: (String, Shared) -> Child
        }

        public init(
            shared: Shared_Configuration = .init(),
            childBuilder: Child_Configuration = .init()
        ) {
            self.shared = shared
            self.childBuilder = childBuilder
        }

        public let shared: Shared_Configuration
        public let childBuilder: Child_Configuration
    }

    public static func mock(
        safeDIParameters: SafeDIParameters = .init()
    ) -> Root {
        let shared = safeDIParameters.shared.safeDIBuilder()
        func __safeDI_childBuilder(name: String) -> Child {
            safeDIParameters.childBuilder.safeDIBuilder(name, shared)
        }
        let childBuilder = Instantiator<Child> {
            __safeDI_childBuilder(name: $0)
        }
        return Root(shared: shared, childBuilder: childBuilder)
    }
}
#endif
```

### Expected Output: Child+SafeDIMock.swift

Child's own mock: `name` is @Forwarded → flat. `shared` is @Received with scope → promoted to SafeDIParameters.

```swift
#if DEBUG
extension Child {
    public struct SafeDIParameters {
        public struct Shared_Configuration {
            public init(
                _ safeDIBuilder: @escaping () -> Shared = Shared.init
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: () -> Shared
        }

        public init(
            shared: Shared_Configuration = .init()
        ) {
            self.shared = shared
        }

        public let shared: Shared_Configuration
    }

    public static func mock(
        name: String,
        safeDIParameters: SafeDIParameters = .init()
    ) -> Child {
        let shared = safeDIParameters.shared.safeDIBuilder()
        return Child(name: name, shared: shared)
    }
}
#endif
```

### Expected Output: Shared+SafeDIMock.swift

```swift
#if DEBUG
extension Shared {
    public static func mock() -> Shared {
        Shared()
    }
}
#endif
```

---

## Example 3: Simple types (no SafeDIParameters)

### Input A: Leaf type with no dependencies

```swift
@Instantiable(generateMock: true)
public struct SimpleType: Instantiable {
    public init() {}
}
```

### Expected Output A: SimpleType+SafeDIMock.swift

No SafeDIParameters — nothing to customize.

```swift
#if DEBUG
extension SimpleType {
    public static func mock() -> SimpleType {
        SimpleType()
    }
}
#endif
```

### Input B: Type with only non-instantiable received dep

```swift
@Instantiable(generateMock: true)
public struct Greeter: Instantiable {
    public init(name: String) {
        self.name = name
    }
    @Received let name: String
}
```

### Expected Output B: Greeter+SafeDIMock.swift

No SafeDIParameters — `String` has no scope. Flat required param.

```swift
#if DEBUG
extension Greeter {
    public static func mock(
        name: String
    ) -> Greeter {
        Greeter(name: name)
    }
}
#endif
```

### Input C: Extension-based type with no dependencies

```swift
public class SomeThirdPartyType {}

@Instantiable(generateMock: true)
extension SomeThirdPartyType: Instantiable {
    public static func instantiate() -> SomeThirdPartyType {
        SomeThirdPartyType()
    }
}
```

### Expected Output C: SomeThirdPartyType+SafeDIMock.swift

```swift
#if DEBUG
extension SomeThirdPartyType {
    public static func mock() -> SomeThirdPartyType {
        SomeThirdPartyType.instantiate()
    }
}
#endif
```

---

## Example 4: Non-root type with custom mock and promoted received dep

This example shows a non-root type's own standalone mock where:
- A received dep (Service) is instantiable → promoted to SafeDIParameters
- The type has a custom mock with non-dependency defaults (theme) → flat on `mock()`
- An @Instantiated child (Grandchild) → SafeDIParameters child struct

### Input

```swift
@Instantiable(generateMock: true)
public struct Service: Instantiable {
    public init() {}
}

@Instantiable(generateMock: true)
public struct Grandchild: Instantiable {
    public init(service: Service) {
        self.service = service
    }
    @Received let service: Service
}

@Instantiable(generateMock: true, customMockName: "customMock")
public struct ChildA: Instantiable {
    public init(grandchild: Grandchild, service: Service) {
        self.grandchild = grandchild
        self.service = service
    }
    @Instantiated let grandchild: Grandchild
    @Received let service: Service

    public static func customMock(
        grandchild: Grandchild,
        service: Service,
        theme: Theme = .light
    ) -> ChildA {
        ChildA(grandchild: grandchild, service: service)
    }
}
```

### Expected Output: ChildA+SafeDIMock.swift

- `service: Service` is @Received with scope → promoted to SafeDIParameters (`Service_Configuration`)
- `grandchild: Grandchild` is @Instantiated with scope → SafeDIParameters (`Grandchild_Configuration`)
- `theme: Theme = .light` is non-dep default on customMock → flat on `mock()` (ChildA is the mock root)
- Return calls `ChildA.customMock(...)` with labeled args

```swift
#if DEBUG
extension ChildA {
    public struct SafeDIParameters {
        public struct Service_Configuration {
            public init(
                _ safeDIBuilder: @escaping () -> Service = Service.init
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: () -> Service
        }

        public struct Grandchild_Configuration {
            public init(
                _ safeDIBuilder: @escaping (Service) -> Grandchild = Grandchild.init(service:)
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: (Service) -> Grandchild
        }

        public init(
            grandchild: Grandchild_Configuration = .init(),
            service: Service_Configuration = .init()
        ) {
            self.grandchild = grandchild
            self.service = service
        }

        public let grandchild: Grandchild_Configuration
        public let service: Service_Configuration
    }

    public static func mock(
        theme: Theme = .light,
        safeDIParameters: SafeDIParameters = .init()
    ) -> ChildA {
        let service = safeDIParameters.service.safeDIBuilder()
        let grandchild = safeDIParameters.grandchild.safeDIBuilder(service)
        return ChildA.customMock(
            grandchild: grandchild,
            service: service,
            theme: theme
        )
    }
}
#endif
```

### Expected Output: Grandchild+SafeDIMock.swift

```swift
#if DEBUG
extension Grandchild {
    public struct SafeDIParameters {
        public struct Service_Configuration {
            public init(
                _ safeDIBuilder: @escaping () -> Service = Service.init
            ) {
                self.safeDIBuilder = safeDIBuilder
            }

            public let safeDIBuilder: () -> Service
        }

        public init(
            service: Service_Configuration = .init()
        ) {
            self.service = service
        }

        public let service: Service_Configuration
    }

    public static func mock(
        safeDIParameters: SafeDIParameters = .init()
    ) -> Grandchild {
        let service = safeDIParameters.service.safeDIBuilder()
        return Grandchild(service: service)
    }
}
#endif
```

### Expected Output: Service+SafeDIMock.swift

```swift
#if DEBUG
extension Service {
    public static func mock() -> Service {
        Service()
    }
}
#endif
```
