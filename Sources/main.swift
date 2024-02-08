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

@main
struct VMCli: ParsableCommand {
  // @Option(help: "Kernel path.")
  // var kernel: String?

  // @Option(help: "Kernel command line arguments.")
  // var kernelCommandLineArguments: String?

  // @Option(help: "Initial ramdisk path.")
  // var initialRamdisk: String?

  // @Option(help: "EFI variable store path.")
  // var efiVariableStore: String?

  @Option(
    help:
      "Configuration of guest system to boot when the VM starts.\ntype=efi,variableStore=/path/to/variableStore\ntype=linux,kernel=/path/to/kernel[,commandLine=string][,initialRamdisk=/path/to/initialRamdisk]"
  )
  var bootLoader: String

  @Option(
    help:
      "Configuration of storage devices that you expose to the guest operating system.\npath=/path/to/disk[,readOnly=true|false]"
  )
  var disk: [String] = []

  @Option(
    help:
      "The amount of physical memory the guest operating system recognizes in MiB, min \(VZVirtualMachineConfiguration.minimumAllowedMemorySize / 1024 / 1024) MiB, max \(VZVirtualMachineConfiguration.maximumAllowedMemorySize / 1024 / 1024) MiB."
  )
  var memory: Int = 2024

  @Option(
    help:
      "The number of CPUs you make available to the guest operating system, min \(VZVirtualMachineConfiguration.minimumAllowedCPUCount), max \(VZVirtualMachineConfiguration.maximumAllowedCPUCount)."
  )
  var cpus: Int = 2

  @Option(
    help:
      "Configuration of network devices that you expose to the guest operating system.\ntype=nat[,macAddress=string]"
  )
  var network: [String] = []

  static var configuration = CommandConfiguration(commandName: "vmcli")

  public func run() throws {
    let configuration = VZVirtualMachineConfiguration()

    // Configure CPU and memory.
    configuration.cpuCount = self.cpus
    configuration.memorySize = UInt64(self.memory * 1024 * 1024)

    // Configure boot loader.
    // if self.bootLoader != nil {
    let bootLoaderParts = self.bootLoader.split(separator: ",")

    var type: String?
    var variableStore: String?
    var kernel: String?
    var commandLine: String?
    var initialRamdisk: String?

    for bootLoaderPart in bootLoaderParts {
      let nameAndValue = bootLoaderPart.split(separator: "=", maxSplits: 1)

      switch nameAndValue[0] {
      case "type":
        type = String(nameAndValue[1])
        break

      case "variableStore":
        variableStore = String(nameAndValue[1])
        break

      case "kernel":
        kernel = String(nameAndValue[1])
        break

      case "commandLine":
        commandLine = String(nameAndValue[1])
        break

      case "initialRamdisk":
        initialRamdisk = String(nameAndValue[1])
        break

      default:
        break
      }
    }

    if type == nil {
      throw ValidationError("Boot loader requires a type.")
    }

    switch type {
    case "efi":
      if variableStore == nil {
        throw ValidationError("EFI boot loader requires a variable store.")
      }

      print("Configuring EFI boot loader.")

      let efiBootLoader = VZEFIBootLoader()
      var efiVariableStore: VZEFIVariableStore

      if FileManager.default.fileExists(atPath: variableStore!) {
        print("Using existing EFI variable store at \(variableStore!).")
        efiVariableStore = VZEFIVariableStore(url: URL(fileURLWithPath: variableStore!))
      } else {
        print("Creating new EFI variable store at \(variableStore!).")
        efiVariableStore = try VZEFIVariableStore(
          creatingVariableStoreAt: URL(fileURLWithPath: variableStore!))
      }

      efiBootLoader.variableStore = efiVariableStore
      configuration.bootLoader = efiBootLoader
      break

    case "linux":
      if kernel == nil {
        throw ValidationError("Linux boot loader requires a kernel.")
      }

      print("Configuring Linux boot loader.")

      let linuxBootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: kernel!))

      if commandLine != nil {
        print("Using kernel command line \"\(commandLine!)\".")
        linuxBootLoader.commandLine = commandLine!
      }

      if initialRamdisk != nil {
        print("Using initial ramdisk at \(initialRamdisk!).")
        linuxBootLoader.initialRamdiskURL = URL(fileURLWithPath: initialRamdisk!)
      }

      configuration.bootLoader = linuxBootLoader
      break

    default:
      throw ValidationError("Invalid boot loader type \"\(type!)\".")
    }

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

    // Configure storage devices.
    for disk in self.disk {
      let diskParts = disk.split(separator: ",")

      var path: String?
      var readOnly = false

      for diskPart in diskParts {
        let nameAndValue = diskPart.split(separator: "=", maxSplits: 1)

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

      if path == nil {
        throw ValidationError("Storage device requires a path.")
      }

      let storageAttachment = try VZDiskImageStorageDeviceAttachment(
        url: URL(fileURLWithPath: path!), readOnly: readOnly)
      let storageDevice = VZVirtioBlockDeviceConfiguration(attachment: storageAttachment)

      configuration.storageDevices.append(storageDevice)
    }

    // Configure network.
    for network in self.network {
      let networkParts = network.split(separator: ",")

      var type: String?
      var macAddress: String?

      for networkPart in networkParts {
        let nameAndValue = networkPart.split(separator: "=", maxSplits: 1)

        switch nameAndValue[0] {
        case "type":
          type = String(nameAndValue[1])
          break

        case "macAddress":
          macAddress = String(nameAndValue[1])
          break

        default:
          break
        }
      }

      if type == nil {
        throw ValidationError("Network device requires a type.")
      }

      let networkDevice = VZVirtioNetworkDeviceConfiguration()

      switch type {
      case "nat":
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        break

      default:
        throw ValidationError("Invalid network type \"\(type!)\".")
      }

      if macAddress != nil {
        guard let parsedMacAddress = VZMACAddress.init(string: macAddress!) else {
          throw ValidationError("Invalid MAC address \"\(macAddress!)\".")
        }

        networkDevice.macAddress = parsedMacAddress
      }

      configuration.networkDevices.append(networkDevice)
    }

    // Configure platform.
    let platform = VZGenericPlatformConfiguration()
    configuration.platform = platform

    // Configure entropy devices.
    configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

    // Configure graphics devices.
    let graphicsDevice = VZVirtioGraphicsDeviceConfiguration()
    graphicsDevice.scanouts = [
      VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1280, heightInPixels: 720)
    ]

    configuration.graphicsDevices = [graphicsDevice]

    // Configure console devices.
    let consoleDevice = VZVirtioConsoleDeviceConfiguration()

    let spiceAgentPort = VZVirtioConsolePortConfiguration()
    spiceAgentPort.name = VZSpiceAgentPortAttachment.spiceAgentPortName
    spiceAgentPort.attachment = VZSpiceAgentPortAttachment()
    consoleDevice.ports[0] = spiceAgentPort

    configuration.consoleDevices = [consoleDevice]

    // Configure keyboards and pointing devices.
    configuration.keyboards = [VZUSBKeyboardConfiguration()]
    configuration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

    // Validate the configuration.
    try configuration.validate()

    // Start the virtual machine.
    let virtualMachine = VZVirtualMachine(configuration: configuration)

    let delegate = VirtualMachineDelegate()
    virtualMachine.delegate = delegate

    virtualMachine.start { (result) in
      if case let .failure(error) = result {
        fatalError("Failed to start the virtual machine. \(error)")
      }
    }

    let virtualMachineView = VZVirtualMachineView(
      frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
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
  }
}
