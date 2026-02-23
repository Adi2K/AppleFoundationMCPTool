#if os(macOS)
import System
#endif
import Foundation
@_exported import AnyLanguageModel
import MCP
import os

private let logger = Logger(subsystem: "com.airy.applefoundationmcptool", category: "main")

/// Defines the connection method for the MCP server.
public enum MCPConnection: Sendable {
  /// Connect to an MCP server via HTTP at the specified URL.
  case http(serverURL: URL)
#if os(macOS)
  /// Launch and connect to an MCP server via standard input/output.
  case stdio(executablePath: String, arguments: [String] = [])
#endif
}

/// A dynamic bridge that connects to an MCP server and registers its tools with Apple's Foundation Models
@available(macOS 26.0, iOS 26.0, *)
public actor MCPToolBridge {
  private let connection: MCPConnection?
  private var client: Client?
#if os(macOS)
  private var serverProcess: Process?
#endif

  /// The tools discovered from the MCP server.
  public private(set) var tools: [DynamicMCPTool] = []

  /// Initializes a new MCPToolBridge instance using a specific connection type.
  /// - Parameter connection: The connection type, either `.http` with a server URL or `.stdio` with a server executable
  /// path.
  public init(connection: MCPConnection) {
    self.connection = connection
  }

  /// Initializes a new MCPToolBridge with an already-connected MCP client.
  /// Use this when you need custom transport configuration (e.g. auth headers, custom logging).
  /// - Parameter client: An already-connected `MCP.Client`.
  public init(client: Client) {
    self.connection = nil
    self.client = client
  }

  /// Convenience initializer for creating a bridge with an HTTP connection.
  /// - Parameter serverURL: The URL of the MCP server.
  public init(serverURL: URL) {
    self.connection = .http(serverURL: serverURL)
  }

#if os(macOS)
  /// Convenience initializer for creating a bridge that launches and connects to a server via stdin/stdout.
  /// - Parameters:
  ///   - executablePath: The path to the MCP server executable.
  ///   - arguments: The command-line arguments to pass to the executable.
  public init(executablePath: String, arguments: [String] = []) {
    self.connection = .stdio(executablePath: executablePath, arguments: arguments)
  }
#endif

  /// Connects to the MCP server and discovers available tools. For stdio connections, it also launches the server
  /// process.
  @discardableResult
  public func connectAndDiscoverTools(_ filter: @Sendable (MCP.Tool) -> Bool = { _ in
    true
  }) async throws -> [DynamicMCPTool] {
    // If we don't already have a client, establish a connection
    if self.client == nil {
      guard let connection = connection else {
        throw MCPToolBridgeError.noConnectionConfigured
      }

      let transport: any Transport
      switch connection {
      case let .http(serverURL):
        transport = HTTPClientTransport(endpoint: serverURL)
#if os(macOS)
      case let .stdio(executablePath, arguments):
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let toServerPipe = Pipe()
        let fromServerPipe = Pipe()

        process.standardInput = toServerPipe
        process.standardOutput = fromServerPipe

        try process.run()
        serverProcess = process

        transport = StdioTransport(
          input: FileDescriptor(rawValue: fromServerPipe.fileHandleForReading.fileDescriptor),
          output: FileDescriptor(rawValue: toServerPipe.fileHandleForWriting.fileDescriptor)
        )
#endif
      }

      let client = Client(name: "AppleFoundationMCPTool", version: "1.0.0")
      try await client.connect(transport: transport)
      self.client = client
    }

    guard let client = client else {
      throw MCPToolBridgeError.clientNotConnected
    }

    let listToolsResponse = try await client.listTools()

    var discoveredTools: [DynamicMCPTool] = []
    for tool in listToolsResponse.tools.filter({ filter($0) }) {
      let mcpTool = DynamicMCPTool(
        mcpClient: client,
        toolName: tool.name,
        toolDescription: tool.description ?? "",
        inputSchema: tool.inputSchema
      )
      discoveredTools.append(mcpTool)
    }

    tools = discoveredTools
    return discoveredTools
  }

  /// Disconnects from the MCP server and terminates the server process if it was launched by the bridge.
  public func disconnect() async {
    if let client = client {
      await client.disconnect()
    }
    client = nil

#if os(macOS)
    if let serverProcess = serverProcess {
      if serverProcess.isRunning {
        serverProcess.terminate()
      }
      self.serverProcess = nil
    }
#endif

    tools = []
  }
}

/// Errors thrown by MCPToolBridge.
public enum MCPToolBridgeError: Error, CustomStringConvertible {
  case noConnectionConfigured
  case clientNotConnected

  public var description: String {
    switch self {
    case .noConnectionConfigured:
      return "No connection configured. Use init(connection:) or init(client:)."
    case .clientNotConnected:
      return "MCP client is not connected."
    }
  }
}

/// A dynamic tool that bridges between Apple's Foundation Models and MCP tools
@available(macOS 26.0, iOS 26.0, *)
public struct DynamicMCPTool: AnyLanguageModel.Tool {
  public typealias Arguments = GeneratedContent

  /// The MCP client
  private let mcpClient: Client

  /// The name of the MCP tool
  private let toolName: String

  /// The name of the tool
  public let name: String

  /// The description of the tool
  public let description: String

  /// The parameters schema for the tool
  public let parameters: GenerationSchema

  /// Whether to include the schema in instructions
  public let includesSchemaInInstructions = true

  /// Initializes a new DynamicMCPTool instance
  /// - Parameters:
  ///   - mcpClient: The MCP client
  ///   - toolName: The name of the MCP tool
  ///   - toolDescription: The description of the MCP tool
  ///   - inputSchema: The input schema for the MCP tool
  init(mcpClient: Client, toolName: String, toolDescription: String, inputSchema: Value) {
    self.mcpClient = mcpClient
    self.toolName = toolName
    self.name = toolName
    self.description = toolDescription
    self.parameters = Self.convertMCPSchemaToGenerationSchema(toolName: toolName, inputSchema: inputSchema)
  }

  /// Converts the MCP schema to Apple's GenerationSchema
  /// - Returns: The converted Apple GenerationSchema
  private static func convertMCPSchemaToGenerationSchema(toolName: String, inputSchema: Value) -> GenerationSchema {
    let converter = ValueSchemaConverter(root: inputSchema.objectValue ?? [:])
    if let dynamicSchema = converter.schema(), let schema = try? GenerationSchema(
      root: dynamicSchema,
      dependencies: []
    ) {
      return schema
    } else {
      return GenerationSchema(
        type: String.self,
        description: "tool parameters",
        properties: []
      )
    }
  }

  /// Calls the MCP tool with the provided arguments
  /// - Parameter arguments: The generated content arguments for the MCP tool
  /// - Returns: The response from the MCP tool
  public func call(arguments: GeneratedContent) async throws -> String {
    let jsonString = arguments.jsonString
    guard let jsonData = jsonString.data(using: .utf8) else {
      let errorMessage = "Error: Could not convert JSON string to Data."
      logger.error("\(errorMessage)")
      return errorMessage
    }

    do {
      guard let mcpArguments = try? JSONDecoder().decode([String: Value].self, from: jsonData) else {
        let errorMessage = "Error: can't convert arguments to MCP JSON."
        logger.error("\(errorMessage): \(jsonString)")
        return errorMessage
      }

      logger.debug("Calling MCP tool '\(toolName)' with arguments: \(mcpArguments)")

      // Call the MCP tool
      let response = try await mcpClient.callTool(name: toolName, arguments: mcpArguments)

      // Convert the result to a string
      var resultString = ""
      for content in response.content {
        switch content {
        case let .text(text):
          resultString += text
        case let .image(_, mimeType, _):
          resultString += "[Image: \(mimeType)]"
        case let .audio(_, mimeType):
          resultString += "[Audio: \(mimeType)]"
        case let .resource(resource, _, _):
          resultString += "[Resource: \(resource.uri), \(resource.mimeType ?? "unknown")]"
          if let text = resource.text {
            resultString += " \(text)"
          }
        case let .resourceLink(uri, name, _, _, mimeType, _):
          resultString += "[ResourceLink: \(uri), \(name), \(mimeType ?? "unknown")]"
        }
      }

      if response.isError == true {
        resultString = "Error: " + resultString
      }

      logger.debug("result: \(resultString)")
      return resultString
    } catch {
      // Handle JSON parsing or other errors
      let errorMessage = "Error calling MCP tool '\(toolName)': \(error.localizedDescription). Invalid JSON: \(jsonString)"
      logger.error("\(errorMessage)")
      return errorMessage
    }
  }
}
