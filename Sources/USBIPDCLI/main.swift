// main.swift
// Entry point for the USB/IP command-line interface

import Foundation
import USBIPDCore
import Common

/// Global server instance for signal handling
private var globalServer: USBIPServer?

/// Global logger for main application
private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "main")

/// Signal handler for graceful shutdown
private func setupSignalHandlers() {
    // Handle SIGINT (Ctrl+C) and SIGTERM for graceful shutdown
    signal(SIGINT) { _ in
        logger.info("Received SIGINT, shutting down gracefully")
        shutdownGracefully()
    }
    
    signal(SIGTERM) { _ in
        logger.info("Received SIGTERM, shutting down gracefully")
        shutdownGracefully()
    }
}

/// Graceful shutdown handler
private func shutdownGracefully() {
    if let server = globalServer, server.isRunning() {
        logger.info("Stopping USB/IP server")
        do {
            try server.stop()
            logger.info("USB/IP server stopped successfully")
        } catch {
            logger.error("Failed to stop server gracefully", context: ["error": error.localizedDescription])
        }
    }
    exit(0)
}

/// Set up logging for the CLI
private func setupLogging() {
    // Log startup information using the shared logger
    logger.info("USB/IP CLI starting")
    logger.debug("Command line arguments", context: ["arguments": CommandLine.arguments.joined(separator: " ")])
}

/// Check if the command is daemon mode
private func isDaemonCommand(_ arguments: [String]) -> Bool {
    let args = Array(arguments.dropFirst())
    return !args.isEmpty && args[0] == "daemon"
}

/// Main entry point
func main() {
    setupLogging()
    setupSignalHandlers()
    
    // Create core dependencies
    let deviceDiscovery = IOKitDeviceDiscovery()
    logger.debug("Created IOKitDeviceDiscovery instance")
    
    // Load or create default server config
    let serverConfig: ServerConfig
    do {
        logger.debug("Loading server configuration")
        serverConfig = try ServerConfig.load()
        logger.info("Loaded server configuration", context: [
            "port": serverConfig.port,
            "logLevel": serverConfig.logLevel.rawValue,
            "debugMode": serverConfig.debugMode ? "enabled" : "disabled"
        ])
    } catch {
        logger.warning("Failed to load server configuration", context: ["error": error.localizedDescription])
        print("Warning: Failed to load server configuration: \(error.localizedDescription)")
        print("Using default configuration.")
        serverConfig = ServerConfig()
        logger.info("Using default server configuration")
    }
    
    // Create network service
    let networkService = TCPServer()
    logger.debug("Created TCPServer instance")
    
    // Create System Extension manager and device claim manager
    let systemExtensionManager = SystemExtensionManager()
    let deviceClaimManager = SystemExtensionClaimAdapter(systemExtensionManager: systemExtensionManager)
    logger.debug("Created SystemExtensionManager and DeviceClaimManager")
    
    // Create server coordinator
    let server = ServerCoordinator(
        networkService: networkService,
        deviceDiscovery: deviceDiscovery,
        deviceClaimManager: deviceClaimManager,
        config: serverConfig
    )
    logger.debug("Created ServerCoordinator instance with DeviceClaimManager")
    
    // Set up server error handling
    server.onError = { error in
        logger.error("Server error", context: ["error": error.localizedDescription])
        
        // For critical errors, attempt graceful shutdown
        if case ServerError.initializationFailed = error {
            logger.critical("Critical server error, initiating shutdown")
            shutdownGracefully()
        }
    }
    
    // Store server reference for signal handling
    globalServer = server
    logger.debug("Set up global server reference for signal handling")
    
    // Create command-line parser with dependencies
    let parser = CommandLineParser(
        deviceDiscovery: deviceDiscovery,
        serverConfig: serverConfig,
        server: server,
        deviceClaimManager: deviceClaimManager
    )
    logger.debug("Created CommandLineParser with System Extension integration")
    
    do {
        logger.debug("Parsing command line arguments")
        try parser.parse(arguments: CommandLine.arguments)
        
        // If this was a daemon command, keep the process running
        if isDaemonCommand(CommandLine.arguments) {
            logger.info("Daemon mode detected, keeping process alive")
            
            // Check if we're running in foreground mode
            let args = Array(CommandLine.arguments.dropFirst())
            let foregroundMode = args.contains("-f") || args.contains("--foreground")
            
            if foregroundMode {
                logger.info("Running in foreground mode")
                print("USB/IP daemon running in foreground. Press Ctrl+C to stop.")
                
                // Keep the main thread alive
                RunLoop.main.run()
            } else {
                logger.info("Running in background mode")
                print("USB/IP daemon started in background mode.")
                
                // For background mode, we would typically daemonize the process
                // For the MVP, we'll just keep the process running
                RunLoop.main.run()
            }
        } else {
            logger.info("Command executed successfully")
        }
    } catch let handlerError as CommandHandlerError {
        // Handle specific command handler errors
        logger.error("Command handler error", context: ["error": handlerError.localizedDescription])
        print("Error: \(handlerError.localizedDescription)")
        exit(1)
    } catch let commandLineError as CommandLineError {
        // Handle command-line parsing errors
        logger.error("Command line error", context: ["error": commandLineError.localizedDescription])
        print("Error: \(commandLineError.localizedDescription)")
        exit(1)
    } catch {
        // Handle general errors
        logger.error("Unexpected error", context: ["error": error.localizedDescription])
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

// Run the main function
main()