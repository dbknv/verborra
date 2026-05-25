import Atomics
import Foundation

/// Lock-free кольцевой буфер для одного producer и одного consumer.
/// Producer (audio thread): write()
/// Consumer (main thread): read(), readAll(), reset()
final class SPSCRingBuffer<T>: @unchecked Sendable {
    private let buffer: UnsafeMutableBufferPointer<T?>
    private let capacity: Int
    private let writeIndex = ManagedAtomic<Int>(0)
    private let readIndex = ManagedAtomic<Int>(0)

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = .allocate(capacity: capacity)
        self.buffer.initialize(repeating: nil)
    }

    deinit {
        buffer.deinitialize()
        buffer.deallocate()
    }

    /// Записать элемент (вызывается только из producer thread).
    /// - Returns: true если записано, false если буфер полон
    func write(_ value: T) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        let next = (write + 1) % capacity
        guard next != read else { return false }
        buffer[write] = value
        writeIndex.store(next, ordering: .releasing)
        return true
    }

    /// Прочитать один элемент (вызывается только из consumer thread).
    func read() -> T? {
        let read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        guard read != write else { return nil }
        let value = buffer[read]
        buffer[read] = nil
        readIndex.store((read + 1) % capacity, ordering: .releasing)
        return value
    }

    /// Прочитать все доступные элементы.
    func readAll() -> [T] {
        var results: [T] = []
        while let value = read() {
            results.append(value)
        }
        return results
    }

    /// Сбросить индексы (вызывать только из consumer, когда producer неактивен).
    func reset() {
        // Drain remaining elements
        while read() != nil {}
        writeIndex.store(0, ordering: .relaxed)
        readIndex.store(0, ordering: .relaxed)
    }

    /// Приблизительное количество элементов.
    var count: Int {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .relaxed)
        return (write - read + capacity) % capacity
    }

    /// Буфер пуст.
    var isEmpty: Bool {
        writeIndex.load(ordering: .relaxed) == readIndex.load(ordering: .relaxed)
    }
}
