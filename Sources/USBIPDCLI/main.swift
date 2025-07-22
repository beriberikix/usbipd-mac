// main.swift
// Entry point for the USB/IP command-line interface

import Foundation
import USBIPDCore
import Common

// Set up logging for the CLI
func setupLogging() {
    // Log startup information using the shared logger
    logInfo("USB/IP CLI starting")
    logDebug("Command line arguments: \(CommandLine.arguments)")
}

// Main entry point
func main() {
    setupLogging()
    
    // Create and use the command-line parser
    let parser = CommandLineParser()
    
    do {
        logDebug("Parsing command line arguments")
        try parser.parse(arguments: CommandLine.arguments)
        logInfo("Command executed successfully")
    } catch let handlerError as CommandHandlerError {
        // Handle specific command handler errors
        logError("Command handler error: \(handlerError.localizedDescription)")
        print("Error: \(handlerError.localizedDescription)")
        exit(1)
    } catch {
        // Handle general errors
        logError("Unexpected error: \(error.localizedDescription)")
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

// Run the main function
main()