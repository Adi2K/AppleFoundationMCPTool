import XCTest
import MCP
@testable import AppleFoundationMCPTool

@available(macOS 26.0, *)
final class ValueSchemaConverterTests: XCTestCase {

    // MARK: - Basic Types

    func testObjectWithStringIntBoolProperties() throws {
        let schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string"), "description": .string("The user's name")]),
                "age": .object(["type": .string("integer"), "description": .string("The user's age")]),
                "active": .object(["type": .string("boolean")]),
            ]),
            "required": .array([.string("name"), .string("age")]),
        ]

        let converter = ValueSchemaConverter(root: schema)
        let result = converter.schema()
        XCTAssertNotNil(result, "Should produce a valid DynamicGenerationSchema for object with mixed types")

        // Verify it can be converted to GenerationSchema
        let generationSchema = try GenerationSchema(root: result!, dependencies: [])
        XCTAssertNotNil(generationSchema)
    }

    func testNestedObjects() throws {
        let schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object([
                "address": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "street": .object(["type": .string("string")]),
                        "city": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("street"), .string("city")]),
                ]),
            ]),
            "required": .array([.string("address")]),
        ]

        let converter = ValueSchemaConverter(root: schema)
        let result = converter.schema()
        XCTAssertNotNil(result, "Should produce a valid schema for nested objects")

        let generationSchema = try GenerationSchema(root: result!, dependencies: [])
        XCTAssertNotNil(generationSchema)
    }

    // MARK: - Arrays

    func testArrayWithItemsAndConstraints() throws {
        let schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object([
                "tags": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "minItems": .int(1),
                    "maxItems": .int(10),
                ]),
            ]),
            "required": .array([.string("tags")]),
        ]

        let converter = ValueSchemaConverter(root: schema)
        let result = converter.schema()
        XCTAssertNotNil(result, "Should produce a valid schema for arrays with constraints")

        let generationSchema = try GenerationSchema(root: result!, dependencies: [])
        XCTAssertNotNil(generationSchema)
    }

    // MARK: - Enums

    func testStringEnum() throws {
        let schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object([
                "color": .object([
                    "type": .string("string"),
                    "enum": .array([.string("red"), .string("green"), .string("blue")]),
                ]),
            ]),
            "required": .array([.string("color")]),
        ]

        let converter = ValueSchemaConverter(root: schema)
        let result = converter.schema()
        XCTAssertNotNil(result, "Should produce a valid schema for string enums")

        let generationSchema = try GenerationSchema(root: result!, dependencies: [])
        XCTAssertNotNil(generationSchema)
    }

    func testMixedTypeEnum() throws {
        let schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object([
                "value": .object([
                    "enum": .array([.string("auto"), .int(42), .null]),
                ]),
            ]),
        ]

        let converter = ValueSchemaConverter(root: schema)
        let result = converter.schema()
        XCTAssertNotNil(result, "Should produce a valid schema for mixed-type enums")
    }

    // MARK: - Nullable / anyOf

    func testNullableFieldViaAnyOf() throws {
        let schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object([
                "nickname": .object([
                    "anyOf": .array([
                        .object(["type": .string("string")]),
                        .object(["type": .string("null")]),
                    ]),
                ]),
            ]),
            "required": .array([.string("nickname")]),
        ]

        let converter = ValueSchemaConverter(root: schema)
        let result = converter.schema()
        XCTAssertNotNil(result, "Should produce a valid schema for nullable fields via anyOf")
    }

    // MARK: - Const

    func testConstValue() throws {
        let schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object([
                "country": .object([
                    "type": .string("string"),
                    "const": .string("United States of America"),
                ]),
            ]),
            "required": .array([.string("country")]),
        ]

        let converter = ValueSchemaConverter(root: schema)
        let result = converter.schema()
        XCTAssertNotNil(result, "Should produce a valid schema for const values")

        let generationSchema = try GenerationSchema(root: result!, dependencies: [])
        XCTAssertNotNil(generationSchema)
    }

    // MARK: - Edge Cases

    func testEmptyObject() throws {
        let schema: [String: Value] = [
            "type": .string("object"),
        ]

        let converter = ValueSchemaConverter(root: schema)
        let result = converter.schema()
        XCTAssertNotNil(result, "Should produce a valid schema for empty objects")
    }

    func testNumberProperty() throws {
        let schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object([
                "temperature": .object([
                    "type": .string("number"),
                    "description": .string("Temperature in Celsius"),
                ]),
            ]),
        ]

        let converter = ValueSchemaConverter(root: schema)
        let result = converter.schema()
        XCTAssertNotNil(result, "Should produce a valid schema for number properties")
    }
}

// MARK: - Bridge Integration Tests

@available(macOS 26.0, *)
final class MCPToolBridgeTests: XCTestCase {

    func testConnectAndDiscoverToolsViaInMemory() async throws {
        // Set up an in-memory MCP server with known test tools
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(
            name: "TestServer",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            return ListTools.Result(tools: [
                MCP.Tool(
                    name: "get_weather",
                    description: "Get weather for a city",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "city": .object([
                                "type": .string("string"),
                                "description": .string("City name"),
                            ]),
                        ]),
                        "required": .array([.string("city")]),
                    ])
                ),
                MCP.Tool(
                    name: "search",
                    description: "Search the web",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object([
                                "type": .string("string"),
                            ]),
                        ]),
                        "required": .array([.string("query")]),
                    ])
                ),
            ])
        }
        await server.withMethodHandler(CallTool.self) { request in
            if request.name == "get_weather" {
                let city = request.arguments?["city"]?.stringValue ?? "unknown"
                return CallTool.Result(content: [.text("Sunny, 72°F in \(city)")])
            }
            return CallTool.Result(content: [.text("Unknown tool")], isError: true)
        }

        try await server.start(transport: serverTransport)

        let client = Client(name: "TestClient", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        // Use the init(client:) initializer
        let bridge = MCPToolBridge(client: client)
        let tools = try await bridge.connectAndDiscoverTools()

        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0].name, "get_weather")
        XCTAssertEqual(tools[1].name, "search")

        // Verify tools property is populated
        let storedTools = await bridge.tools
        XCTAssertEqual(storedTools.count, 2)

        await bridge.disconnect()
    }

    func testToolFilteringWorks() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(
            name: "TestServer",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            return ListTools.Result(tools: [
                MCP.Tool(name: "allowed_tool", description: "Allowed", inputSchema: [:]),
                MCP.Tool(name: "blocked_tool", description: "Blocked", inputSchema: [:]),
                MCP.Tool(name: "another_allowed", description: "Also allowed", inputSchema: [:]),
            ])
        }
        await server.withMethodHandler(CallTool.self) { _ in
            return CallTool.Result(content: [.text("ok")])
        }

        try await server.start(transport: serverTransport)

        let client = Client(name: "TestClient", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        let bridge = MCPToolBridge(client: client)
        let tools = try await bridge.connectAndDiscoverTools { tool in
            tool.name.hasPrefix("allowed") || tool.name.hasPrefix("another")
        }

        XCTAssertEqual(tools.count, 2)
        XCTAssertTrue(tools.allSatisfy { $0.name != "blocked_tool" })

        await bridge.disconnect()
    }

    func testDisconnectCleansUp() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(
            name: "TestServer",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            return ListTools.Result(tools: [
                MCP.Tool(name: "test_tool", description: "A test", inputSchema: [:]),
            ])
        }
        await server.withMethodHandler(CallTool.self) { _ in
            return CallTool.Result(content: [.text("ok")])
        }

        try await server.start(transport: serverTransport)

        let client = Client(name: "TestClient", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        let bridge = MCPToolBridge(client: client)
        let tools = try await bridge.connectAndDiscoverTools()
        XCTAssertEqual(tools.count, 1)

        await bridge.disconnect()

        let toolsAfterDisconnect = await bridge.tools
        XCTAssertEqual(toolsAfterDisconnect.count, 0)
    }
}

// MARK: - Tool Call Round-Trip Tests

@available(macOS 26.0, *)
final class DynamicMCPToolCallTests: XCTestCase {

    func testToolCallReturnsText() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(
            name: "TestServer",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            return ListTools.Result(tools: [
                MCP.Tool(
                    name: "echo",
                    description: "Echoes input",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "message": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("message")]),
                    ])
                ),
            ])
        }
        await server.withMethodHandler(CallTool.self) { request in
            let message = request.arguments?["message"]?.stringValue ?? ""
            return CallTool.Result(content: [.text("Echo: \(message)")])
        }

        try await server.start(transport: serverTransport)

        let client = Client(name: "TestClient", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        let bridge = MCPToolBridge(client: client)
        let tools = try await bridge.connectAndDiscoverTools()
        XCTAssertEqual(tools.count, 1)

        let echoTool = tools[0]
        XCTAssertEqual(echoTool.name, "echo")

        // Create GeneratedContent arguments
        let arguments = GeneratedContent(properties: ["message": "hello world"])
        let result = try await echoTool.call(arguments: arguments)
        XCTAssertEqual(result, "Echo: hello world")

        await bridge.disconnect()
    }

    func testToolCallReturnsErrorString() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(
            name: "TestServer",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            return ListTools.Result(tools: [
                MCP.Tool(
                    name: "failing_tool",
                    description: "Always fails",
                    inputSchema: .object(["type": .string("object")])
                ),
            ])
        }
        await server.withMethodHandler(CallTool.self) { request in
            return CallTool.Result(
                content: [.text("Something went wrong")],
                isError: true
            )
        }

        try await server.start(transport: serverTransport)

        let client = Client(name: "TestClient", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        let bridge = MCPToolBridge(client: client)
        let tools = try await bridge.connectAndDiscoverTools()
        let failTool = tools[0]

        let arguments = GeneratedContent(properties: [:])
        let result = try await failTool.call(arguments: arguments)
        XCTAssertTrue(result.hasPrefix("Error:"), "Error responses should be prefixed with 'Error:'")
        XCTAssertTrue(result.contains("Something went wrong"))

        await bridge.disconnect()
    }

    func testToolCallWithMultipleContentTypes() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(
            name: "TestServer",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            return ListTools.Result(tools: [
                MCP.Tool(
                    name: "multi_content",
                    description: "Returns mixed content",
                    inputSchema: .object(["type": .string("object")])
                ),
            ])
        }
        await server.withMethodHandler(CallTool.self) { request in
            return CallTool.Result(content: [
                .text("Here is the result: "),
                .image(data: "base64encodeddata", mimeType: "image/png", metadata: nil),
            ])
        }

        try await server.start(transport: serverTransport)

        let client = Client(name: "TestClient", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        let bridge = MCPToolBridge(client: client)
        let tools = try await bridge.connectAndDiscoverTools()
        let tool = tools[0]

        let arguments = GeneratedContent(properties: [:])
        let result = try await tool.call(arguments: arguments)
        XCTAssertTrue(result.contains("Here is the result: "))
        XCTAssertTrue(result.contains("[Image: image/png]"))
        // Verify no truncation of data in the display
        XCTAssertFalse(result.contains("..."), "Image data should not be truncated in display")

        await bridge.disconnect()
    }
}
