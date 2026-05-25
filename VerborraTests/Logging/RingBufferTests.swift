import Testing
@testable import Verborra

// MARK: - RingBufferTests (T019)

struct RingBufferTests {

    @Test func append_fillsBuffer() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        #expect(buffer.count == 3)
    }

    @Test func drain_returnsInInsertionOrder() {
        var buffer = RingBuffer<Int>(capacity: 5)
        buffer.append(10)
        buffer.append(20)
        buffer.append(30)
        let result = buffer.drain()
        #expect(result == [10, 20, 30])
        #expect(buffer.isEmpty)
    }

    @Test func overflow_evictsOldElements() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        buffer.append(4) // evicts 1
        buffer.append(5) // evicts 2
        let result = buffer.drain()
        #expect(result == [3, 4, 5])
    }

    @Test func drain_emptiesBuffer() {
        var buffer = RingBuffer<String>(capacity: 2)
        buffer.append("a")
        buffer.append("b")
        _ = buffer.drain()
        #expect(buffer.count == 0)
        #expect(buffer.drain().isEmpty)
    }

    @Test func capacityOne_keepsOnlyLastElement() {
        var buffer = RingBuffer<Int>(capacity: 1)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        let result = buffer.drain()
        #expect(result == [3])
    }

    @Test func emptyBuffer_drainReturnsEmpty() {
        var buffer = RingBuffer<Int>(capacity: 10)
        #expect(buffer.drain().isEmpty)
        #expect(buffer.isEmpty)
    }
}
