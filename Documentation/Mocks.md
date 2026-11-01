# Generated mocks in detail

The Manual’s [Mock generation](Manual.md#mock-generation) section shows how to enable a generated `mock()`, call it, override what it builds, and provide a hand-written mock, with the rule behind each. This page holds the detail behind those rules. Its sections continue the Manual’s sections of the same names, in the same order, so a reader can go back and forth between them; a Manual section with no detail beyond its rule has no section here.

## Overriding dependencies

[Overriding dependencies](Manual.md#overriding-dependencies) introduces the three buckets of a generated `mock()` and the `SafeDIMockConfiguration` of a type with its own subtree or default-valued construction inputs.

A `SafeDIMockConfiguration` field for a default-valued parameter takes its default from the type’s hand-written `mock` method when it has one, and from its `init` (or `instantiate(…)`) otherwise. The builder’s parameters match the type’s hand-written `mock` method signature if one is defined, or its `init` parameters otherwise.

A type reached through a [`Sendable` wrapper](Manual.md#sendable-wrappers) is built in a `@Sendable` function. Two values that production creates inside the function, a labeled default-valued initializer parameter of a type in the subtree and a dependency the mock cannot build that a type in the subtree instantiates, the mock takes as `@Sendable` autoclosures – the `SafeDIMockConfiguration` field is declared `formatter: @autoclosure @escaping @Sendable () -> Formatter = Formatter()` and stored as `@Sendable () -> Formatter` (a field whose type is itself a closure is stored as a `@Sendable` closure, without an autoclosure), and the `mock()` parameter is declared `service: @autoclosure @escaping @Sendable () -> Service` – and calls them where it builds the type, so each value is created there, once per construction, as in production. A caller still passes a value, as in `Root.mock(service: MockService())`; an argument that captures a non-`Sendable` value, such as a `MockService` held in a `let` outside the call, does not compile.

### Dependency kinds in the generated mock

[Dependency kinds in the generated mock](Manual.md#dependency-kinds-in-the-generated-mock) tabulates where each kind of dependency lands in a generated `mock()`. This section explains the rows the table leaves terse.

A type with `@Forwarded` properties can only be built by an `Instantiator` handed the forwarded values, so when the mocked type’s tree receives such a type as a constant, `mock()` takes the instance as a parameter, even when the type has a hand-written mock. A received `Instantiator` of the type is built as usual.

A type in a mock’s tree can declare an `@Instantiated(fulfilledByType:)` dependency whose `@Instantiable` declaration the mock’s module cannot see, such as a `DefaultUserService` declared in a module only the app imports. Production code is generated where every module is visible; the mock cannot build the dependency, so `mock()` takes it as a parameter, such as `mock(userService:)`, a `@Sendable` autoclosure when the type that instantiates it is built through a `Sendable` wrapper, as [above](#overriding-dependencies). The parameter does not excuse a missing fulfiller: a root in the mock’s module that reaches the type still fails to generate.

A `@Received(onlyIfAvailable: true)` dependency gets no `SafeDIOverrides` entry of its own when the mock already builds that dependency — because the mocked type instantiates it, or because another type in the tree requires it — or when nothing fulfills it and another type in the tree requires it, which makes it a required flat `mock()` parameter. It is an optional entry only when every receiver in the tree, renames included, receives it `onlyIfAvailable`; a receiver built inside the instance is passed `nil`, as in production.

In the Manual’s `ProfileView` example, an entry for a composition such as `(EventTracker & CrashReporter).self` does not cover its members: list each member a mock receives.

The mock builds the dependencies its tree receives after the mocked type’s own `@Instantiated` dependencies, each after the ones it is built from, in an order set by where you declare properties, never by labels or type names; the `SafeDIOverrides` entries follow that order. Of two that receive each other only if available, the one received later is passed `nil`, as [under a root](Manual.md#conditionally-receiving-dependencies).

When two flat `mock()` parameters or two entries in the same `SafeDIOverrides` or `SafeDIMockConfiguration` share a label, each is named by its label followed by its type as an identifier: received dependencies named `items` of types `[String]` and `Set<String>` become `items_Array_String` and `items_Set__String`. A mock builds every form in which its tree receives a dependency under one label, a label the mocked type forwards included: when one type requires `x: X` and another requires `x: Instantiator<X>`, the mock builds both, with the entries `x_X` and `x_Instantiator__X`. An optional form beside its non-optional form, and the instance of a `LazilyInstantiated`, are not forms of their own.

### Receiving a type-erased dependency

[Receiving a type-erased dependency](Manual.md#receiving-a-type-erased-dependency) describes how a mock builds a received type that a parent erases a concrete type to.

SafeDI looks at every `@Instantiated` property with `erasedToConcreteExistential: true` in the current module and the modules it depends on, and matches the received dependency by its type: a received `AnyUserService` matches properties of type `AnyUserService`, not an `ErasedInstantiator<…, AnyUserService>`.

Say `NotesApp` erases `DefaultUserService` and another parent erases `OfflineUserService` to `AnyUserService`:

```swift
@Instantiable(generateMock: true)
public struct SettingsView: View, Instantiable {
    // …
    @ObservedObject @Received private var userService: AnyUserService
}

SettingsView.mock(userService: AnyUserService(StubUserService()))
```

The same matching applies to a received erased instantiator: a mock builds a received `childViewBuilder: ErasedInstantiator<(), AnyView>` from a property of that type, such as `ParentView`’s in [ErasedInstantiator](Manual.md#erasedinstantiator).

## Hand-written mocks

[Hand-written mocks](Manual.md#hand-written-mocks) states where a hand-written mock method may be declared, what it must accept and return, and how `customMockName` names it.

When the hand-written method returns an additional type the `@Instantiable` declaration fulfills (for example, a protocol declared in `fulfillingAdditionalTypes`), the generated `mock()` method also returns that type. This keeps the signatures type-compatible on extension-based declarations where a concrete `Self` return wouldn’t line up with a protocol-returning `customMock`.

## Cross-module mock generation

[Cross-module mock generation](Manual.md#cross-module-mock-generation) describes the two ways a module gets the mock of a type: generating the mocks of the types it declares, or listing a dependency module’s types in `additionalMocksToGenerate`.

Each `SafeDIMockConfiguration` a module’s mocks use is, like its `mock()`, an `internal` member of an extension of the configured type in that module.
