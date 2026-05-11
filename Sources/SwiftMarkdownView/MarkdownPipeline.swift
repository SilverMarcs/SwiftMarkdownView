import SwiftUI

struct MarkdownRenderRequest: Hashable, Sendable {
    let text: String
    let fontSize: CGFloat
    let themeName: String
    let codeBlockBackground: Color
}

@MainActor
final class MarkdownRenderCacheStore {
    private final class Node {
        let key: MarkdownRenderRequest
        var value: MarkdownRenderedDocument
        var prev: Node?
        var next: Node?

        init(key: MarkdownRenderRequest, value: MarkdownRenderedDocument) {
            self.key = key
            self.value = value
        }
    }

    static let shared = MarkdownRenderCacheStore()

    private let cacheLimit = 120
    private var map: [MarkdownRenderRequest: Node] = [:]
    private var head: Node?
    private var tail: Node?

    func document(for request: MarkdownRenderRequest) -> MarkdownRenderedDocument? {
        guard let node = map[request] else { return nil }
        moveToHead(node)
        return node.value
    }

    func store(_ document: MarkdownRenderedDocument, for request: MarkdownRenderRequest) {
        if let node = map[request] {
            node.value = document
            moveToHead(node)
        } else {
            let node = Node(key: request, value: document)
            map[request] = node
            insertAtHead(node)

            if map.count > cacheLimit {
                if let evicted = tail {
                    removeNode(evicted)
                    map.removeValue(forKey: evicted.key)
                }
            }
        }
    }

    private func moveToHead(_ node: Node) {
        guard node !== head else { return }
        removeNode(node)
        insertAtHead(node)
    }

    private func insertAtHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func removeNode(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if node === head { head = node.next }
        if node === tail { tail = node.prev }
        node.prev = nil
        node.next = nil
    }
}

actor MarkdownRenderScheduler {
    static let shared = MarkdownRenderScheduler()

    private var inFlightTasks: [MarkdownRenderRequest: Task<MarkdownRenderedDocument, Never>] = [:]

    func document(for request: MarkdownRenderRequest) async -> MarkdownRenderedDocument {
        if let existingTask = inFlightTasks[request] {
            return await existingTask.value
        }

        let renderTask = Task.detached(priority: .utility) {
            await MarkdownRenderer(
                fontSize: request.fontSize,
                themeName: request.themeName,
                codeBlockBackground: request.codeBlockBackground
            ).render(request.text)
        }

        inFlightTasks[request] = renderTask
        let document = await renderTask.value
        inFlightTasks[request] = nil
        return document
    }
}
