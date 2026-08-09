import Foundation
import USBIPDCore
import Common

// Logger for command operations
private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "cli-commands")

/// Reports how devices are accessed and which ones are currently shared.
///
/// This used to be 700 lines reporting on a System Extension: its health, the devices
/// it had claimed, its installation state and its lifecycle. All of it sat behind
/// `guard let claimManager = deviceClaimManager else { … return }`, and the command was
/// always constructed with nil, so none of it ever ran. The subsystem it described has
/// since been removed outright.
public class StatusCommand: Command {
    public let name = "status"
    public let description = "Show how devices are accessed and which are shared"

    private let boundDevices: BoundDeviceStore

    public init(boundDevices: BoundDeviceStore = BoundDeviceStore()) {
        self.boundDevices = boundDevices
    }

    public func execute(with arguments: [String]) throws {
        logger.debug("Executing status command", context: ["arguments": arguments.joined(separator: " ")])

        var showDetailed = false

        for arg in arguments {
            switch arg {
            case "-d", "--detailed":
                showDetailed = true
            case "--health":
                // Retained so existing invocations and shell completions keep working.
                // It used to run a System Extension health check; there is no extension
                // to check, and the report below is the whole of what can be said.
                break
            case "-h", "--help":
                printHelp()
                return
            default:
                logger.error("Unknown option for status command", context: ["option": arg])
                throw CommandLineError.invalidArguments("Unknown option: \(arg)")
            }
        }

        // This used to tell people to install and approve a System Extension. They
        // cannot: OSSystemExtensionRequest resolves extensions inside the calling app's
        // bundle and requires that bundle to live in /Applications, so a Homebrew
        // install is never consulted. It is also unnecessary — nothing usbipd can serve
        // needs one.
        print("Device access: userspace (IOKit), no System Extension")
        print("")
        print("Devices macOS has not bound a driver to can be shared: debug probes,")
        print("boards in DFU or bootloader mode, Android in ADB mode, USB-serial")
        print("adapters using FTDI or CP210x, and other vendor-specific interfaces.")
        print("No entitlement is required for these.")
        print("")
        print("Devices whose interfaces macOS holds — HID, mass storage, audio, cameras,")
        print("and the control interface of CDC-ACM serial devices — cannot be shared.")
        print("'usbipd bind' refuses them and names the owner. Releasing them needs a")
        print("DriverKit entitlement Apple must grant.")

        let shared = boundDevices.boundDevices()
        print("")
        if shared.isEmpty {
            print("No devices are currently shared. Use 'usbipd bind <busid>' to share one.")
        } else {
            print("Shared devices (\(shared.count)):")
            for busid in shared.sorted() {
                print("  \(busid)")
            }
        }

        if showDetailed {
            print("")
            print("Bound-device list: \(boundDevices.filePath)")
            print("Configuration:     \(ServerConfig.defaultConfigPath())")
        }
    }

    private func printHelp() {
        print("Usage: usbipd status [options]")
        print("")
        print("Show how usbipd accesses devices and which devices are currently shared.")
        print("")
        print("Options:")
        print("  -d, --detailed  Also show where state and configuration are kept")
        print("  --health        Accepted for compatibility; there is nothing further")
        print("                  to check now that the System Extension is gone")
        print("  -h, --help      Show this help message")
    }
}
