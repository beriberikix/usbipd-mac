// main.swift
// Entry point for the USB/IP command-line interface

import Foundation
import USBIPDCore
import Common

// Set up logging for the CLI
func setupLogging() {
    // Configure date formatter for log messages
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    
    // Log startup information
    let timestamp = dateFormatter.string(from: Date())
    print("\(timestamp) [INFO] USB/IP CLI starting")
}

// Main entry point
func main() {
    setupLogging()
    
    // Create and use the command-line parser
    let parser = CommandLineParser()
    
    do {
        try parser.parse(arguments: CommandLine.arguments)
    } catch let handlerError as CommandHandlerError {
        // Handle specific command handler errors
        print("Error: \(handlerError.localizedDescription)")
        exit(1)
    } catch {
        // Handle general errors
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

// Run the main function
main()