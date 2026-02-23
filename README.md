# AppleFoundationMCPTool

A Swift package that bridges [Model Context Protocol (MCP)](https://modelcontextprotocol.io) servers to [AnyLanguageModel](https://github.com/mattt/AnyLanguageModel)'s `Tool` protocol. Connect any MCP server and its tools become available to any language model — OpenAI, MLX, Ollama, Apple's on-device models, and more.

## How It Works

```
┌─────────────────┐      ┌──────────────────────┐      ┌────────────────┐
│  MCP Server      │◄────►│  AppleFoundationMCP   │◄────►│  AnyLanguage   │
│  (any server)    │      │  ToolBridge           │      │  ModelSession  │
│                  │      │                       │      │                │
│  Tools:          │      │  Discovers tools,     │      │  Model calls   │
│  - get_weather   │      │  converts schemas,    │      │  tools auto-   │
│  - search_web    │      │  bridges calls        │      │  matically     │
│  - run_query     │      │                       │      │                │
└─────────────────┘      └──────────────────────┘      └────────────────┘
```

1. `MCPToolBridge` connects to an MCP server (HTTP or stdio)
2. It discovers available tools and converts their JSON schemas to `GenerationSchema`
3. Each tool is wrapped as a `DynamicMCPTool` conforming to AnyLanguageModel's `Tool` protocol
4. Pass these tools to a `LanguageModelSession` — the model can now call them automatically

## Requirements

- macOS 26.0+ / iOS 26.0+
- Swift 6.2+
- An MCP-compliant server

## Installation

Add AppleFoundationMCPTool to your `Package.swift`. Since this library depends on AnyLanguageModel, you must also declare AnyLanguageModel as a direct dependency **with the traits you need** (e.g. MLX, CoreML).

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v26), .iOS(.v26)],
    dependencies: [
        // 1. AnyLanguageModel — declare with YOUR traits
        .package(
            url: "https://github.com/mattt/AnyLanguageModel.git",
            from: "0.7.1",
            traits: ["MLX"]  // Add traits you need: "MLX", "CoreML", "Llama"
        ),
        // 2. The MCP bridge
        .package(
            url: "https://github.com/Adi2K/AppleFoundationMCPTool.git",
            from: "0.7.1"
        ),
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
                "AppleFoundationMCPTool",
            ]
        ),
    ]
)
```

### Why declare AnyLanguageModel separately?

AppleFoundationMCPTool depends on AnyLanguageModel but intentionally does **not** specify any traits. Swift Package Manager traits are controlled by the **consuming application**, not intermediate libraries. This means:

- AppleFoundationMCPTool works with all model backends — it only uses the base `Tool` and `GeneratedContent` APIs
- **You** choose which backends to enable by specifying traits on your own AnyLanguageModel dependency
- Both packages resolve to the same version of AnyLanguageModel — no duplication

If you forget to declare AnyLanguageModel with traits, everything compiles, but only `SystemLanguageModel` and API-based models (OpenAI, Anthropic, Gemini, Ollama) are available. MLX/CoreML/Llama models require their respective traits.

## Quick Start

### Connect to an HTTP MCP server

```swift
import AppleFoundationMCPTool

let bridge = MCPToolBridge(serverURL: URL(string: "http://127.0.0.1:8080/mcp")!)
let tools = try await bridge.connectAndDiscoverTools()

// Use with any AnyLanguageModel backend
let model = OpenAILanguageModel(
    baseURL: URL(string: "https://api.openai.com/v1")!,
    apiKey: "sk-...",
    model: "gpt-4o"
)
let session = LanguageModelSession(model: model, tools: tools)
let response = try await session.respond(to: "What's the weather in Tokyo?")
print(response.content)

await bridge.disconnect()
```

### Launch a local MCP server via stdio

```swift
let bridge = MCPToolBridge(
    executablePath: "/usr/local/bin/my-mcp-server",
    arguments: ["--port", "disabled"]
)
let tools = try await bridge.connectAndDiscoverTools()

// Use with MLX (requires "MLX" trait in Package.swift)
let model = MLXLanguageModel(modelId: "mlx-community/Qwen3-8B-4bit")
let session = LanguageModelSession(model: model, tools: tools)
let response = try await session.respond(to: "Search for recent news about Swift")
print(response.content)

await bridge.disconnect()
```

### Filter tools

Some models have limited context windows. You can filter which tools are exposed:

```swift
let tools = try await bridge.connectAndDiscoverTools { mcpTool in
    // Only include specific tools
    ["get_weather", "search"].contains(mcpTool.name)
}
```

### Use a pre-configured MCP client

For advanced scenarios (custom auth, logging, proxies), create your own `MCP.Client` and pass it in:

```swift
import MCP

let transport = HTTPClientTransport(endpoint: myURL)
let client = Client(name: "MyApp", version: "1.0.0")
try await client.connect(transport: transport)

let bridge = MCPToolBridge(client: client)
let tools = try await bridge.connectAndDiscoverTools()
```

### Track which tools came from which server

When connecting multiple MCP servers, use the `tools` property to track provenance:

```swift
let weatherBridge = MCPToolBridge(serverURL: weatherServerURL)
let dbBridge = MCPToolBridge(serverURL: databaseServerURL)

try await weatherBridge.connectAndDiscoverTools()
try await dbBridge.connectAndDiscoverTools()

// Each bridge knows its own tools
let weatherTools = await weatherBridge.tools   // [DynamicMCPTool]
let dbTools = await dbBridge.tools             // [DynamicMCPTool]

// Combine for the session
let allTools: [any Tool] = weatherTools + dbTools
let session = LanguageModelSession(model: model, tools: allTools)
```

## Usage in an iOS App (SwiftUI)

Here's a complete example for an iOS app using OpenAI with MCP tools:

```swift
import SwiftUI
import AppleFoundationMCPTool

@Observable
@MainActor
class ChatViewModel {
    var messages: [(role: String, content: String)] = []
    var isLoading = false

    private var bridge: MCPToolBridge?
    private var session: LanguageModelSession?

    func connect() async {
        do {
            // Connect to your MCP server
            let bridge = MCPToolBridge(serverURL: URL(string: "http://your-server:8080/mcp")!)
            let tools = try await bridge.connectAndDiscoverTools()
            self.bridge = bridge

            // Create a session with tools
            let model = OpenAILanguageModel(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
                model: "gpt-4o"
            )
            self.session = LanguageModelSession(model: model, tools: tools)
        } catch {
            messages.append(("system", "Failed to connect: \(error.localizedDescription)"))
        }
    }

    func send(_ text: String) async {
        guard let session else { return }
        messages.append(("user", text))
        isLoading = true

        do {
            let response = try await session.respond(to: text)
            messages.append(("assistant", response.content))
        } catch {
            messages.append(("system", "Error: \(error.localizedDescription)"))
        }

        isLoading = false
    }

    func disconnect() async {
        await bridge?.disconnect()
        bridge = nil
        session = nil
    }
}

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var input = ""

    var body: some View {
        VStack {
            ScrollView {
                ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { _, message in
                    HStack {
                        if message.role == "user" { Spacer() }
                        Text(message.content)
                            .padding(8)
                            .background(message.role == "user" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(8)
                        if message.role != "user" { Spacer() }
                    }
                }
            }

            HStack {
                TextField("Message", text: $input)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    let text = input
                    input = ""
                    Task { await viewModel.send(text) }
                }
                .disabled(input.isEmpty || viewModel.isLoading)
            }
            .padding()
        }
        .task { await viewModel.connect() }
    }
}
```

## API Reference

### `MCPToolBridge` (actor)

The main entry point. Connects to an MCP server and produces `DynamicMCPTool` instances.

| Initializer | Description |
|---|---|
| `init(connection: MCPConnection)` | Connect via `.http(serverURL:)` or `.stdio(executablePath:arguments:)` |
| `init(serverURL: URL)` | Shorthand for HTTP connection |
| `init(executablePath:arguments:)` | Shorthand for stdio connection |
| `init(client: Client)` | Use a pre-configured MCP client |

| Method / Property | Description |
|---|---|
| `connectAndDiscoverTools(_:)` | Connects and returns discovered tools. Optional filter closure. |
| `disconnect()` | Disconnects client and terminates server process if applicable. |
| `tools: [DynamicMCPTool]` | The tools from the most recent `connectAndDiscoverTools()` call. |

### `DynamicMCPTool` (struct, conforms to `Tool`)

A single MCP tool wrapped for use with AnyLanguageModel. You don't create these directly — `MCPToolBridge` creates them.

| Property | Type | Description |
|---|---|---|
| `name` | `String` | The MCP tool name |
| `description` | `String` | Natural language description |
| `parameters` | `GenerationSchema` | Converted from the MCP tool's JSON Schema |

`Arguments` is `GeneratedContent` — the model produces structured content that gets serialized to JSON and sent to the MCP server.

## Known Limitations

The `ValueSchemaConverter` that translates MCP JSON Schema to AnyLanguageModel's `DynamicGenerationSchema` handles common cases but has known gaps:

- No `allOf`/`oneOf`/`not` composition operators
- No `pattern` (regex), `minLength`/`maxLength` on strings
- No `minimum`/`maximum` on numbers
- No `additionalProperties` support
- No `format` validation (email, uri, date-time)
- Circular `$ref` references are silently unresolved

These cover the vast majority of real-world MCP tool schemas. Complex schemas may fall back to a generic string parameter.

## License

MIT
