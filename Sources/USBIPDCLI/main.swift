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
/// Check if arguments require early exit (help, version, etc.)
private func shouldExitEarly(_ arguments: [String]) -> Bool {
    let args = Array(arguments.dropFirst())
    if args.isEmpty { return true }  // No arguments, will show help
    let command = args[0]
    return command == "--help" || command == "-h" || command == "help" || command == "--version" || command == "-v"
}

/// Handle early exit commands without system initialization
private func handleEarlyExit(_ arguments: [String]) {
    let args = Array(arguments.dropFirst())
    
    if args.isEmpty || args[0] == "--help" || args[0] == "-h" || args[0] == "help" {
        print("USB/IP Daemon for macOS")
        print("Usage: usbipd <command> [options]")
        print("")
        print("Commands:")
        print("  list                    List USB devices")
        print("  bind <device-id>        Bind a device for sharing")
        print("  unbind <device-id>      Unbind a previously bound device")
        print("  daemon [options]        Start the USB/IP daemon")
        print("  status                  Show daemon status")
        print("  help                    Show this help message")
        print("")
        print("Options:")
        print("  -v, --version          Show version information")
        print("  -h, --help             Show help message")
        print("")
        print("For more information about a specific command, use: usbipd <command> --help")
        return
    }
    
    if args[0] == "--version" || args[0] == "-v" {
        print("USB/IP Daemon for macOS")
        print("Version: \(USBIPDVersion.current)")
        print("Build: \(USBIPDVersion.build)")
        return
    }
}

/// Main entry point
func main() {
    setupLogging()
    setupSignalHandlers()
    
    // Handle help/version commands early to avoid heavy initialization
    if shouldExitEarly(CommandLine.arguments) {
        handleEarlyExit(CommandLine.arguments)
        return
    }
    
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
    
    // The System Extension bundle detector is not run.
    //
    // It walked the filesystem on every invocation looking for a bundle, including the
    // developer's own .build directory — a Homebrew-installed binary was scanning
    // /Users/<someone>/code/usbipd-mac/.build and adopting a debug bundle it found
    // there. That work is pointless: no shipping path can activate a System Extension,
    // because OSSystemExtensionRequest resolves extensions inside the calling app's
    // bundle and requires that bundle to live in /Applications.
    //
    // See Sources/USBIPDCore/SystemExtension/README.md.

    // The daemon's output goes to a log file, where detail is wanted; a CLI command's
    // goes to someone's terminal, where it is noise. Raise the floor for the daemon
    // only — an earlier attempt raised it here unconditionally, which put every INFO
    // line back into `usbipd list`. An explicit USBIPD_LOG_LEVEL always wins.
    if ProcessInfo.processInfo.environment["USBIPD_LOG_LEVEL"] == nil,
       CommandLine.arguments.dropFirst().first == "daemon" {
        Logger.globalLevel = .info
    }

    // Create network service
    let networkService = TCPServer(maxConnections: serverConfig.maxConnections,
                                  connectionTimeout: serverConfig.connectionTimeout)
    logger.debug("Created TCPServer instance")
    
    // The System Extension manager is still constructed because the claim manager and
    // several commands are typed against it, but it is no longer started here.
    //
    // Starting it restored persisted claim state and spun up health checking on every
    // invocation of every command, including `usbipd list`. None of that can lead
    // anywhere: the extension cannot be activated from a Homebrew install, so the
    // claims it restores are bookkeeping over a subsystem that never runs.
    let systemExtensionManager = USBIPDCore.SystemExtensionManager()
    let deviceClaimManager = SystemExtensionClaimAdapter(systemExtensionManager: systemExtensionManager)
    
    // Create server coordinator with System Extension parameters if available
    let server = ServerCoordinator(
        networkService: networkService,
        deviceDiscovery: deviceDiscovery,
        deviceClaimManager: deviceClaimManager,
        config: serverConfig,
        systemExtensionBundlePath: serverConfig.getSystemExtensionBundlePath(),
        systemExtensionBundleIdentifier: serverConfig.getSystemExtensionBundleIdentifier()
    )
    logger.debug("Created ServerCoordinator instance with DeviceClaimManager")
    
    // Set up server error handling
    server.onError = { (error: Error) in
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
        systemExtensionManager: systemExtensionManager
    )
    logger.debug("Created CommandLineParser with System Extension Manager integration")
    
    do {
        logger.debug("Parsing command line arguments")
        try parser.parse(arguments: CommandLine.arguments)
        
        // Keep the process alive only if a server is actually running. Testing argv
        // for "daemon" answered a different question: `daemon --help` printed help and
        // then blocked forever, and `daemon` with a bad option would have too.
        if DaemonRuntime.serverDidStart {
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