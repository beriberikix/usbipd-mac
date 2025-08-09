// main.swift
// System Extension executable entry point

import Foundation
import Common

/// System Extension main entry point
@main
struct SystemExtensionMain {
    /// Entry point for the System Extension executable
    static func main() {
        // Initialize logger for System Extension
        let logger = Logger(
            config: LoggerConfig(level: .info),
            subsystem: "com.usbipd.mac.system-extension",
            category: "main"
        )
        
        logger.info("System Extension starting")
        
        do {
            // Initialize System Extension manager
            let manager = SystemExtensionManager()
            
            // Set up signal handling for graceful shutdown
            setupSignalHandling(manager: manager, logger: logger)
            
            // Start the System Extension
            try manager.start()
            
            logger.info("System Extension started successfully")
            
            // Keep the extension running
            RunLoop.main.run()
            
        } catch {
            logger.critical("Failed to start System Extension", context: [
                "error": error.localizedDescription
            ])
            exit(1)
        }
    }
    
    /// Set up signal handling for graceful shutdown
    /// - Parameters:
    ///   - manager: System Extension manager to shutdown
    ///   - logger: Logger for shutdown messages
    private static func setupSignalHandling(manager: SystemExtensionManager, logger: Logger) {
        let signalSource = DispatchSource.makeSignalSource(
            signal: SIGTERM,
            queue: DispatchQueue.main
        )
        
        signalSource.setEventHandler {
            logger.info("Received SIGTERM, shutting down gracefully")
            
            do {
                try manager.stop()
                logger.info("System Extension stopped successfully")
                exit(0)
            } catch {
                logger.error("Error during graceful shutdown", context: [
                    "error": error.localizedDescription
                ])
                exit(1)
            }
        }
        
        signalSource.resume()
        signal(SIGTERM, SIG_IGN)
        
        // Also handle SIGINT (Ctrl+C) for development
        let sigintSource = DispatchSource.makeSignalSource(
            signal: SIGINT,
            queue: DispatchQueue.main
        )
        
        sigintSource.setEventHandler {
            logger.info("Received SIGINT, shutting down gracefully")
            
            do {
                try manager.stop()
                logger.info("System Extension stopped successfully")
                exit(0)
            } catch {
                logger.error("Error during graceful shutdown", context: [
                    "error": error.localizedDescription
                ])
                exit(1)
            }
        }
        
        sigintSource.resume()
        signal(SIGINT, SIG_IGN)
    }
}