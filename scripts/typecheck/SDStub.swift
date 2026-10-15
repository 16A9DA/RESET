import Foundation
import SwiftUI
import Observation

// Typecheck-only stand-in for SwiftData so the app target can be checked without Xcode's macro plugin.
public protocol PersistentModel: AnyObject, Observable {}
public struct SDPredicate<T> { public init() {} }
public func makePredicate<T>(_ f: (T) -> Bool) -> SDPredicate<T> { SDPredicate<T>() }

public struct FetchDescriptor<T: PersistentModel> {
    public var predicate: SDPredicate<T>?
    public var sortBy: [SortDescriptor<T>]
    public var fetchLimit: Int?
    public init(predicate: SDPredicate<T>? = nil, sortBy: [SortDescriptor<T>] = []) { self.predicate = predicate; self.sortBy = sortBy }
}

public final class ModelContext {
    public func fetch<T: PersistentModel>(_ d: FetchDescriptor<T>) throws -> [T] { [] }
    public func fetchCount<T: PersistentModel>(_ d: FetchDescriptor<T>) throws -> Int { 0 }
    public func insert<T: PersistentModel>(_ m: T) {}
    public func delete<T: PersistentModel>(_ m: T) {}
    public func delete<T: PersistentModel>(model: T.Type, where: SDPredicate<T>? = nil, includeSubclasses: Bool = true) throws {}
    public func save() throws {}
}

public struct Schema { public init(_ types: [any PersistentModel.Type]) {} }
public struct ModelConfiguration { public init(isStoredInMemoryOnly: Bool = false) {} }
public final class ModelContainer {
    public let mainContext = ModelContext()
    public init(for schema: Schema, configurations: ModelConfiguration...) throws {}
}

@propertyWrapper public struct Query<Element: PersistentModel>: DynamicProperty {
    public var wrappedValue: [Element] { [] }
    public init() {}
    public init(filter: SDPredicate<Element>? = nil, sort: [SortDescriptor<Element>] = []) {}
    public init<V: Comparable>(sort: KeyPath<Element, V>, order: SortOrder = .forward) {}
}

private struct ModelContextKey: EnvironmentKey { static let defaultValue = ModelContext() }
extension EnvironmentValues { public var modelContext: ModelContext { get { self[ModelContextKey.self] } set { self[ModelContextKey.self] = newValue } } }
extension View { public func modelContainer(_ c: ModelContainer) -> some View { self } }
extension Scene { public func modelContainer(_ c: ModelContainer) -> some Scene { self } }
