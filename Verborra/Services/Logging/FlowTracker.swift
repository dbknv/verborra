import Foundation

// MARK: - RingBuffer (T009)

/// Generic ring buffer с фиксированной ёмкостью. O(1) append, O(n) drain.
struct RingBuffer<T> {
    private var storage: [T] = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    mutating func append(_ element: T) {
        if storage.count >= capacity {
            storage.removeFirst()
        }
        storage.append(element)
    }

    /// Возвращает все элементы в порядке вставки и очищает буфер.
    mutating func drain() -> [T] {
        let result = storage
        storage.removeAll(keepingCapacity: true)
        return result
    }

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }
}

// MARK: - FlowTracker (T010)

/// Per-flow breadcrumb trail. Thread-safe (NSLock).
/// Flow начинается при инициирующем действии (хоткей) и заканчивается при завершении или ошибке.
final class FlowTracker: @unchecked Sendable {
    static let shared = FlowTracker()

    private var flows: [UUID: RingBuffer<Breadcrumb>] = [:]
    private let lock = NSLock()

    private init() {}

    /// Создаёт новый flow и возвращает его UUID.
    func beginFlow() -> UUID {
        let id = UUID()
        lock.lock()
        flows[id] = RingBuffer<Breadcrumb>(capacity: 20)
        lock.unlock()
        return id
    }

    /// Добавляет breadcrumb в указанный flow.
    func addBreadcrumb(_ breadcrumb: Breadcrumb, to flowId: UUID) {
        lock.lock()
        flows[flowId]?.append(breadcrumb)
        lock.unlock()
    }

    /// Дренирует breadcrumbs из flow и удаляет его. Возвращает пустой массив если flow не найден.
    func endFlow(_ flowId: UUID) -> [Breadcrumb] {
        lock.lock()
        let breadcrumbs = flows[flowId]?.drain() ?? []
        flows.removeValue(forKey: flowId)
        lock.unlock()
        return breadcrumbs
    }
}
