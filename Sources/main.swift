import ArgumentParser
import Foundation
import Virtualization

class VirtualMachineDelegate: NSObject {
}

extension VirtualMachineDelegate: VZVirtualMachineDelegate {
  func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    print("Virtual machine stopped from guest. Exiting.")
    exit(EXIT_SUCCESS)
  }

  func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
    print("Virtual machine stopped with error. \(error)")
    exit(EXIT_FAILURE)
  }

  func virtualMachine(
    _ virtualMachine: VZVirtualMachine, networkDevice: VZNetworkDevice,
    attachmentWasDisconnectedWithError error: Error
  ) {
    print(
      "Virtual machine network device \"\(networkDevice)\" was disconnected with error. \(error)")
    exit(EXIT_FAILURE)
  }
}

struct Options: ParsableCommand {
  // @Option(help: "Kernel path.")
  // var kernel: String?

  // @Option(help: "Kernel command line arguments.")
  // var kernelCommandLineArguments: String?

  // @Option(help: "Initial ramdisk path.")
  // var initialRamdisk: String?

  // @Option(help: "EFI variable store path.")
  // var efiVariableStore: String?

  @Option(help: "Bootloader configuration. (type=efi|linux)")
  var bootloader: String?

  @Option(help: "Disks configuration. (path=/path/to/disk[,readOnly=true|false])")
  var disk: [String] = []

  @Option(help: "Memory in GiB.")
  var memory: Int = 2

  @Option(help: "CPU units.")
  var cpus: Int = 1

  @Option(help: "Network configuration. (type=nat[,macAddress=string])")
  var network: [String] = []

  static var configuration = CommandConfiguration(commandName: "vmcli")
}

let options = Options.parseOrExit()

let configuration = VZVirtualMachineConfiguration()
configuration.cpuCount = options.cpus
configuration.memorySize = UInt64(options.memory * 1024 * 1024 * 1024)

// Configure bootloader.
if options.bootloader != nil {
  let bootloaderParts = options.bootloader!.split(separator: ",")

  for bootloaderPart in bootloaderParts {
    let nameAndValue = bootloaderPart.split(separator: "=")

    switch nameAndValue[0] {
    case "type":
      let type = String(nameAndValue[1])

      switch type {
      case "efi":

        break

      default:
        print("Invalid bootloader type \"\(type)\"")
        exit(EXIT_FAILURE)
        break
      }
      break

    default:
      break
    }
  }

  // if options.kernel != nil {
  //   // Configure the linux bootloader.
  //   let kernelURL = URL(fileURLWithPath: options.kernel!, isDirectory: false)
  //   let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)

  //   if options.kernelCommandLineArguments != nil {
  //     bootLoader.commandLine = options.kernelCommandLineArguments!
  //   }

  //   if options.initialRamdisk != nil {
  //     let initialRamdiskURL = URL(fileURLWithPath: options.initialRamdisk!, isDirectory: false)
  //     bootLoader.initialRamdiskURL = initialRamdiskURL
  //   }

  //   configuration.bootLoader = bootLoader
  // } else {
  let bootloader = VZEFIBootLoader()

  guard
    let variableStore = try? VZEFIVariableStore(
      creatingVariableStoreAt: URL(fileURLWithPath: "nvram"))
  else {
    fatalError("Failed to create the EFI variable store.")
  }

  bootloader.variableStore = variableStore

  configuration.bootLoader = bootloader
  // }
}

// Configure platform.
let platform = VZGenericPlatformConfiguration()
configuration.platform = platform

// // Configure standard io serial port.
// let consoleConfiguration = VZVirtioConsoleDeviceSerialPortConfiguration()

// let inputFileHandle = FileHandle.standardInput
// let outputFileHandle = FileHandle.standardOutput

// // Put stdin into raw mode, disabling local echo, input canonicalization, and CR-NL mapping.
// var attributes = termios()
// tcgetattr(inputFileHandle.fileDescriptor, &attributes)
// attributes.c_iflag &= ~tcflag_t(ICRNL)
// attributes.c_lflag &= ~tcflag_t(ICANON | ECHO)
// tcsetattr(inputFileHandle.fileDescriptor, TCSANOW, &attributes)

// let stdioAttachment = VZFileHandleSerialPortAttachment(
//   fileHandleForReading: inputFileHandle,
//   fileHandleForWriting: outputFileHandle
// )

// consoleConfiguration.attachment = stdioAttachment

// configuration.serialPorts = [consoleConfiguration]

// Configure disks.
for disk in options.disk {
  // print(disk)

  var path = ""
  var readOnly = false

  let diskParts = disk.split(separator: ",")

  for diskPart in diskParts {
    let nameAndValue = diskPart.split(separator: "=")

    switch nameAndValue[0] {
    case "path":
      path = String(nameAndValue[1])
      break

    case "readOnly":
      if String(nameAndValue[1]) == "true" || String(nameAndValue[1]) == "1" {
        readOnly = true
      }
      break

    default:
      break
    }
  }

  let storageURL = URL(fileURLWithPath: path)
  let storageAttachment = try VZDiskImageStorageDeviceAttachment(
    url: storageURL, readOnly: readOnly)
  let storageDevice = VZVirtioBlockDeviceConfiguration(attachment: storageAttachment)

  configuration.storageDevices.append(storageDevice)
}

// Configure network.
for network in options.network {
  // print(network)

  let networkDevice = VZVirtioNetworkDeviceConfiguration()
  let networkParts = network.split(separator: ",")

  for networkPart in networkParts {
    let nameAndValue = networkPart.split(separator: "=")

    switch nameAndValue[0] {
    case "type":
      let type = String(nameAndValue[1])

      switch type {
      case "nat":
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        break

      default:
        print("Invalid network type \"\(type)\"")
        exit(EXIT_FAILURE)
        break
      }
      break

    case "macAddress":
      let macAddress = String(nameAndValue[1])

      guard let parsedMacAddress = VZMACAddress.init(string: macAddress) else {
        print("Unable to parse MAC address \"\(macAddress)\".")
        exit(EXIT_FAILURE)
      }

      networkDevice.macAddress = parsedMacAddress

    default:
      break
    }
  }

  configuration.networkDevices.append(networkDevice)
}

// Configure entropy.
configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

// Configure graphics.
let graphicsDevice = VZVirtioGraphicsDeviceConfiguration()
graphicsDevice.scanouts = [
  VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1280, heightInPixels: 720)
]

configuration.graphicsDevices = [graphicsDevice]

// Configure console.
let consoleDevice = VZVirtioConsoleDeviceConfiguration()

let spiceAgentPort = VZVirtioConsolePortConfiguration()
spiceAgentPort.name = VZSpiceAgentPortAttachment.spiceAgentPortName
spiceAgentPort.attachment = VZSpiceAgentPortAttachment()
consoleDevice.ports[0] = spiceAgentPort

configuration.consoleDevices = [consoleDevice]

// Configure keyboards and pointing devices.
configuration.keyboards = [VZUSBKeyboardConfiguration()]
configuration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

// Validate configuration.
do {
  try configuration.validate()
} catch {
  print("Failed to validate the virtual machine configuration. \(error)")
  exit(EXIT_FAILURE)
}

// Start virtual machine.
let virtualMachine = VZVirtualMachine(configuration: configuration)

let delegate = VirtualMachineDelegate()
virtualMachine.delegate = delegate

virtualMachine.start { (result) in
  if case let .failure(error) = result {
    print("Failed to start the virtual machine. \(error)")
    exit(EXIT_FAILURE)
  }
}

let virtualMachineView = VZVirtualMachineView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
virtualMachineView.virtualMachine = virtualMachine

let window = NSWindow()
window.setContentSize(NSSize(width: 1280, height: 720))
window.title = "vmcli"
window.styleMask = [.titled]
window.contentView?.addSubview(virtualMachineView)

window.center()
window.makeKeyAndOrderFront(window)

let nsapp = NSApplication.shared
nsapp.setActivationPolicy(NSApplication.ActivationPolicy.regular)
nsapp.activate(ignoringOtherApps: true)
nsapp.run()

// RunLoop.main.run(until: Date.distantFuture)
