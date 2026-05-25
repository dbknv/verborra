import XCTest
@testable import Verborra

final class SPSCRingBufferTests: XCTestCase {

    func testWriteAndReadSingle() {
        let buffer = SPSCRingBuffer<Int>(capacity: 4)
        XCTAssertTrue(buffer.write(42))
        XCTAssertEqual(buffer.read(), 42)
        XCTAssertNil(buffer.read())
    }

    func testWriteAndReadAll() {
        let buffer = SPSCRingBuffer<Int>(capacity: 8)
        for i in 0..<5 {
            XCTAssertTrue(buffer.write(i))
        }
        let all = buffer.readAll()
        XCTAssertEqual(all, [0, 1, 2, 3, 4])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testBufferFull() {
        let buffer = SPSCRingBuffer<Int>(capacity: 4)
        XCTAssertTrue(buffer.write(1))
        XCTAssertTrue(buffer.write(2))
        XCTAssertTrue(buffer.write(3))
        // capacity=4 means 3 usable slots (one slot reserved)
        XCTAssertFalse(buffer.write(4))
    }

    func testBufferEmpty() {
        let buffer = SPSCRingBuffer<Int>(capacity: 4)
        XCTAssertNil(buffer.read())
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
    }

    func testReset() {
        let buffer = SPSCRingBuffer<Int>(capacity: 8)
        for i in 0..<5 {
            XCTAssertTrue(buffer.write(i))
        }
        buffer.reset()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.read())
        // Should be usable after reset
        XCTAssertTrue(buffer.write(99))
        XCTAssertEqual(buffer.read(), 99)
    }

    func testSequentialCycle() {
        let buffer = SPSCRingBuffer<Int>(capacity: 256)
        for i in 0..<256 {
            if buffer.write(i) {
                // drain periodically to avoid full
                if i % 64 == 63 {
                    _ = buffer.readAll()
                }
            }
        }
        _ = buffer.readAll()
        XCTAssertTrue(buffer.isEmpty)
    }

    func testCount() {
        let buffer = SPSCRingBuffer<Int>(capacity: 8)
        XCTAssertEqual(buffer.count, 0)
        buffer.write(1)
        buffer.write(2)
        XCTAssertEqual(buffer.count, 2)
        _ = buffer.read()
        XCTAssertEqual(buffer.count, 1)
    }

    func testConcurrentProducerConsumer() {
        let buffer = SPSCRingBuffer<Int>(capacity: 256)
        let writeCount = 10_000
        let expectation = XCTestExpectation(description: "Concurrent read/write")
        var readValues: [Int] = []
        let readQueue = DispatchQueue(label: "reader")

        // Producer
        DispatchQueue.global(qos: .userInitiated).async {
            var written = 0
            while written < writeCount {
                if buffer.write(written) {
                    written += 1
                }
                // Yield to let consumer catch up
                if written % 100 == 0 {
                    Thread.sleep(forTimeInterval: 0.0001)
                }
            }
        }

        // Consumer
        readQueue.async {
            var totalRead = 0
            while totalRead < writeCount {
                let batch = buffer.readAll()
                if !batch.isEmpty {
                    readValues.append(contentsOf: batch)
                    totalRead += batch.count
                } else {
                    Thread.sleep(forTimeInterval: 0.0001)
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
        XCTAssertEqual(readValues.count, writeCount)
        // Values should be in order (SPSC guarantee)
        XCTAssertEqual(readValues, Array(0..<writeCount))
    }
}
