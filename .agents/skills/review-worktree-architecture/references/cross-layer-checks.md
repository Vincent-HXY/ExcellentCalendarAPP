# Cross-layer and cross-language checks

Read this file only when the uncommitted delta spans multiple architectural layers, modules, processes, languages, schemas, or runtime boundaries. Apply only sections relevant to the repository.

## 1. General dependency-boundary review

Establish the documented dependency direction before judging the change. For every new dependency edge, record:

```text
source layer/module -> target layer/module | public or private surface | allowed by rule | reason needed
```

Check for:

- lower-level or stable modules importing higher-level policy, UI, orchestration, or platform code;
- domain/data abstractions depending on concrete storage, transport, framework, or presentation classes;
- access to another module's internal/private namespace, source directory, package, or non-exported header;
- dependency cycles introduced through adapters, callbacks, service locators, global registries, or build dependencies;
- a boundary bypassed for convenience even though an interface/port/adapter exists;
- duplicated policy on both sides of a boundary instead of one authoritative owner;
- a new public surface created only to expose an implementation detail;
- a broad dependency or build-file change used to solve a narrow local need.

Do not flag a dependency edge solely because it is new. A valid finding needs a governing direction/ownership rule or a concrete coupling consequence.

## 2. Task scope across modules or languages

A cross-module or cross-language edit is normally one of these:

- **Necessary ripple:** the public contract changed and all affected adapters/consumers must follow.
- **Compatibility work:** old and new representations must coexist or migrate.
- **Boundary repair:** the previous implementation violated the intended ownership and this change restores it.
- **Scope leakage:** implementation details spread into a layer that does not own them.
- **Unrelated work:** cleanup/refactoring is mixed into the development increment without necessity.

Evidence of a necessary ripple includes an explicit requirement, a changed public contract, matching changes on both sides, compatibility handling, and boundary tests. Without that evidence, classify the edit as suspicious rather than automatically violating.

## 3. Kotlin/JVM to C++/JNI/NDK boundary

When Kotlin/Java and C/C++ change together, verify the complete bridge contract.

### Registration and symbol agreement

- Native method names, signatures, descriptors, namespaces/packages, and registration tables agree.
- Static versus instance receiver semantics agree.
- `extern "C"`, symbol visibility, name mangling, and exported-library configuration are correct where required.
- CMake/Gradle/NDK source lists, ABI filters, packaging, and library load names include the change.
- R8/ProGuard keep rules preserve reflected or dynamically registered entry points where applicable.

### Type and value agreement

- Integer width, signedness, floating-point semantics, enum values, string encoding, array/buffer length, and boolean representation agree.
- Nullability and optional/absent values have one documented mapping.
- Unknown enum or version values degrade safely.
- Object handles, pointers, IDs, and ownership tokens cannot be confused across lifetimes or instances.

### Ownership and lifecycle

- Local/global/weak JNI references have correct lifetime and release behavior.
- Native memory ownership is explicit; allocations and handles have a matching release path.
- Kotlin/Java object lifecycle cannot call a destroyed native object.
- Native callbacks cannot target collected, stopped, or detached JVM objects.
- Reinitialization, repeated start/stop, shutdown, and process recreation are handled.

### Threading and errors

- JNI calls occur on an attached thread and detach behavior is correct for native-created threads.
- Thread affinity for UI, engine, rendering, or callback work is respected.
- Native exceptions do not cross a C ABI; C++ failures map consistently to JVM exceptions/results.
- Pending JNI exceptions are checked before additional JNI operations.
- Cancellation, timeout, and callback races have a defined result.

### Independent tests

Prefer tests that:

- compile or load the real bridge and call it through the public Kotlin/Java surface;
- test null, empty, maximum-size, Unicode, invalid enum/version, repeated lifecycle, and concurrent calls;
- confirm native failure mapping without reading private native state;
- statically compare declared/registered signatures when runtime execution is unavailable.

## 4. Data/schema layer to concrete implementation

When a data model, schema, DTO, entity, protocol, or repository abstraction changes, verify that the data layer remains about representation and invariant ownership rather than concrete execution.

Check for:

- network clients, database drivers, UI types, platform services, filesystem APIs, or framework lifecycle objects entering the data/domain layer;
- persistence annotations or transport-specific fields becoming the only domain representation without an explicit architecture decision;
- business policy hidden inside serializers, mappers, database entities, or generated models;
- concrete service construction inside models instead of injection through an owned boundary;
- schema/default/migration logic split across several layers with no authoritative owner;
- data validation duplicated with inconsistent rules across DTO, domain, storage, and UI layers;
- implementation-specific error types leaking through a stable domain/public contract.

A data-model change is complete only when applicable read/write paths, defaults, validation, migrations, unknown values, backward compatibility, and downstream consumers agree.

Independent tests should favor schema fixtures, round trips, old-version fixtures, unknown fields/values, missing fields, invalid values, and public repository/service contracts. Do not mirror a mapper's internal branch structure.

## 5. IPC, RPC, plugins, and process boundaries

Verify:

- protocol/schema versioning and backward/forward compatibility;
- request and response correlation, retries, idempotency, timeout, cancellation, and partial failure;
- authentication/authorization and trust-boundary validation;
- ownership and cleanup for connections, subscriptions, listeners, and shared memory;
- unknown message types and malformed payload handling;
- both producer and consumer registration/build/package changes;
- observability sufficient to diagnose boundary failures without leaking secrets.

Independent tests should exercise the public protocol with valid, boundary, malformed, old-version, unknown-version, timeout, retry, and duplicate cases.

## 6. Static architecture-test patterns

Generate these from written rules, not from the current implementation layout:

- forbid imports/includes from disallowed module roots;
- assert the build graph contains no prohibited dependency edge or cycle;
- assert public modules do not include private/internal headers or packages;
- assert data/domain packages do not reference framework/platform/concrete implementation namespaces;
- assert bridge declarations and registration descriptors match;
- assert each public schema/enum version has explicit compatibility handling;
- compile consumers against only exported/public interfaces.

A static architecture test is valuable when it encodes a stable documented rule. Do not freeze an accidental directory layout unless the documentation declares that layout as the boundary.
