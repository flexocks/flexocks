import SwiftUI
import AppKit
import Foundation
import CryptoKit
import Security
import Dispatch

struct Configuration: Codable {
    var host: String
    var puertoLocal: String
    var puertoRemoto: String
    var usuario: String
    var contrasena: String
    var extrassh: String

    static let filename = "config.json"
    static var fileURL: URL? {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let applicationSupportURL = urls.last else { return nil }
        let appDirectoryURL = applicationSupportURL.appendingPathComponent("Flexocks")
        if !fileManager.fileExists(atPath: appDirectoryURL.path) {
            try? fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        return appDirectoryURL.appendingPathComponent(filename)
    }

    static func loadFromFile() -> Configuration? {
        guard let url = fileURL else {
            writeToLog(message: "Error: no se encuentra el archivo config.json.")
            return nil
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            let emptyConfig = Configuration(host: "", puertoLocal: "", puertoRemoto: "", usuario: "", contrasena: "", extrassh: "")
            emptyConfig.saveToFile()
            return emptyConfig
        }

        do {
            let data = try Data(contentsOf: url)
            var configuration = try JSONDecoder().decode(Configuration.self, from: data)

            if let contrasenaCifradaData = leerClaveKeychain(account: "com.Flexocks.PasswordConexion"),
               let contrasenaCifrada = String(data: contrasenaCifradaData, encoding: .utf8) {
                if let contrasenaDescifrada = descifrar(input: contrasenaCifrada, using: leerSymmetricKey()!) {
                    configuration.contrasena = contrasenaDescifrada
                } else {
                    writeToLog(message: "Error al descifrar la contraseña.")
                    configuration.contrasena = ""
                }
            } else {
                writeToLog(message: "Error al obtener la contraseña desde el Keychain.")
                configuration.contrasena = ""
            }

            return configuration
        } catch {
            writeToLog(message: "Error al cargar la configuración: \(error)")
            return nil
        }
    }

    func saveToFile() {
        guard let fileURL = Configuration.fileURL else {
            writeToLog(message: "Error: URL del archivo no definida.")
            return
        }

        do {
            let configMasked = Configuration(host: host, puertoLocal: puertoLocal, puertoRemoto: puertoRemoto, usuario: usuario, contrasena: "[OCULTA]", extrassh: extrassh)
            let data = try JSONEncoder().encode(configMasked)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            writeToLog(message: "Error al guardar la configuración: \(error)")
        }
    }
}

class AppManager: ObservableObject {
    static let shared = AppManager()
    @Published var configurationPopover: NSPopover?
    @Published var configuration: Configuration?
    @Published var showingConfiguration: Bool = false {
        didSet {
            if !showingConfiguration {
                configurationPopover?.close()
                configuration = Configuration.loadFromFile()
            }
        }
    }
    @Published var status: flexocksAction = .stop {
        didSet {
            DispatchQueue.main.async {
                self.updateMenuBarIcon()
                self.statusItem?.menu = self.getMenu()
            }
        }
    }

    var statusItem: NSStatusItem?

    init() {
        configuration = Configuration.loadFromFile()

        DispatchQueue.main.async {
            self.setupMenuBar()
            self.checkStatus()

            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                self.checkStatus()
            }
        }
    }

    func configureApp(host: String, puertoLocal: String, puertoRemoto: String, usuario: String, contrasena: String, extrassh: String) {
        if let symmetricKey = leerSymmetricKey() {
            if let contrasenaCifrada = cifrar(input: contrasena, using: symmetricKey) {
                let newConfig = Configuration(host: host, puertoLocal: puertoLocal, puertoRemoto: puertoRemoto, usuario: usuario, contrasena: contrasenaCifrada, extrassh: extrassh)
                newConfig.saveToFile()
                self.configuration = newConfig
            } else {
                writeToLog(message: "Error cifrando la contraseña durante la configuración.")
            }
        } else {
            writeToLog(message: "Error obteniendo la clave simétrica durante la configuración.")
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateMenuBarIcon()
        statusItem?.menu = getMenu()
    }

    private func updateMenuBarIcon() {
        let imageName: String
        switch status {
        case .start: imageName = "wave_verde"
        case .stop: imageName = "wave_roja"
        case .status: imageName = "wave_int"
        }
        let image = NSImage(named: imageName)
        image?.size = NSSize(width: 16.0, height: 16.0)
        statusItem?.button?.image = image
    }

    func checkStatus() {
        guard let configuration = configuration else { return }

        if configuration.host.isEmpty || configuration.puertoLocal.isEmpty || configuration.puertoRemoto.isEmpty {
            DispatchQueue.main.async { self.status = .stop }
            return
        }

        let flexocksParamsMasked = "-h \(configuration.host) -l \(configuration.puertoLocal) -r \(configuration.puertoRemoto) -o \(configuration.extrassh) -u \(configuration.usuario) -c [OCULTA]"
        writeToLog(message: "Check status: \(flexocksParamsMasked)")

        let realFlexocksParams = flexocksParamsMasked.replacingOccurrences(of: "-c [OCULTA]", with: "-c \(configuration.contrasena)")
        let result = executeflexocksAction(.status, params: realFlexocksParams)

        DispatchQueue.main.async {
            if result.output == "0" { self.status = .start }
            else if result.output == "1" { self.status = .stop }
            else if result.output == "2" { self.status = .status }
        }
    }

    private func resizedImage(named imageName: String, toSize size: NSSize) -> NSImage? {
        guard let image = NSImage(named: imageName) else { return nil }
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    func getMenu() -> NSMenu {
        let menu = NSMenu()
        let iconSize = NSSize(width: 42.0, height: 42.0)

        let connectItem: NSMenuItem
        switch status {
        case .start:
            connectItem = NSMenuItem()
            connectItem.image = resizedImage(named: "pi_on", toSize: iconSize)
            connectItem.action = #selector(stopConnection)
            connectItem.target = self
            connectItem.title = ""
        case .stop:
            connectItem = NSMenuItem()
            connectItem.image = resizedImage(named: "pi_off", toSize: iconSize)
            connectItem.action = #selector(startConnection)
            connectItem.target = self
            connectItem.title = ""
        case .status:
            connectItem = NSMenuItem()
            connectItem.image = resizedImage(named: "pi_int", toSize: iconSize)
            connectItem.action = nil
            connectItem.title = ""
        }

        let configureItem = NSMenuItem()
        configureItem.image = resizedImage(named: "config", toSize: iconSize)
        configureItem.action = #selector(showConfigurationPopover)
        configureItem.target = self
        configureItem.title = ""

        let firefoxItem = NSMenuItem()
        firefoxItem.image = resizedImage(named: "ffox", toSize: iconSize)
        firefoxItem.action = #selector(restartFirefox)
        firefoxItem.target = self
        firefoxItem.title = ""

        let exitItem = NSMenuItem()
        exitItem.image = resizedImage(named: "salir", toSize: iconSize)
        exitItem.action = #selector(exitApp)
        exitItem.target = self
        exitItem.title = ""

        menu.addItem(connectItem)
        menu.addItem(configureItem)
        menu.addItem(firefoxItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(exitItem)

        return menu
    }

    @objc func startConnection() {
        guard let configuration = configuration else { return }
        guard !configuration.host.isEmpty, !configuration.puertoRemoto.isEmpty, !configuration.puertoLocal.isEmpty else {
            writeToLog(message: "Parámetros requeridos vacíos.")
            return
        }

        var contrasenaDescifrada: String? = nil
        if let contrasenaCifradaData = leerClaveKeychain(account: "com.Flexocks.PasswordConexion"),
           let contrasenaCifrada = String(data: contrasenaCifradaData, encoding: .utf8) {
            contrasenaDescifrada = descifrar(input: contrasenaCifrada, using: leerSymmetricKey()!)
            if contrasenaDescifrada == nil {
                writeToLog(message: "Error al descifrar la contraseña desde el Keychain.")
            }
        } else {
            writeToLog(message: "Error al obtener la contraseña cifrada desde el Keychain.")
        }

        let extrasshValue = configuration.extrassh.isEmpty ? "NONE" : configuration.extrassh
        let flexocksParamsMasked = "-h \(configuration.host) -l \(configuration.puertoLocal) -r \(configuration.puertoRemoto) -o \(extrasshValue) -u \(configuration.usuario) -c [OCULTA]"
        let flexocksParams = "-h \(configuration.host) -l \(configuration.puertoLocal) -r \(configuration.puertoRemoto) -o \(extrasshValue) -u \(configuration.usuario) -c \(contrasenaDescifrada ?? "")"

        _ = executeflexocksAction(.start, params: flexocksParams)
        writeToLog(message: flexocksParamsMasked)
        checkStatus()
    }

    @objc func stopConnection() {
        guard let configuration = configuration else { return }
        guard !configuration.host.isEmpty, !configuration.puertoRemoto.isEmpty, !configuration.puertoLocal.isEmpty else {
            writeToLog(message: "Parámetros requeridos vacíos.")
            return
        }

        let flexocksParams = "-h \(configuration.host) -l \(configuration.puertoLocal) -r \(configuration.puertoRemoto) -u \(configuration.usuario)"
        _ = executeflexocksAction(.stop, params: flexocksParams)
        writeToLog(message: "Conexión detenida: \(flexocksParams)")
        checkStatus()
    }

    @objc func showConfigurationPopover() {
        NotificationCenter.default.post(name: NSNotification.Name("ShowConfiguration"), object: nil)
    }

    @objc func restartFirefox() {
        DispatchQueue.global().async {
            let scriptClose = NSAppleScript(source: "tell application \"Firefox\" to quit")
            let scriptOpen = NSAppleScript(source: "tell application \"Firefox\" to activate")
            scriptClose?.executeAndReturnError(nil)
            writeToLog(message: "Parando Firefox")
            Thread.sleep(forTimeInterval: 3.0)
            scriptOpen?.executeAndReturnError(nil)
            writeToLog(message: "Iniciando Firefox")
        }
    }

    @objc func exitApp() {
        writeToLog(message: "Exit")
        self.stopConnection()
        NSApplication.shared.terminate(nil)
    }

    func executeflexocksAction(_ action: flexocksAction, params: String) -> (success: Bool, output: String) {
        let task = Process()
        task.launchPath = "/bin/bash"

        guard let scriptPath = Bundle.main.path(forResource: "flexocks", ofType: "sh") else {
            let errorMsg = "Error: El script flexocks.sh no se encontró."
            writeToLog(message: errorMsg)
            return (false, errorMsg)
        }

        task.arguments = ["-c", "\(scriptPath) \(action.stringValue) \(params)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        task.waitUntilExit()

        writeToLog(message: "Output flexocks.sh: \(output)")
        return (task.terminationStatus == 0, output)
    }
}

let keychainAccount = "com.Flexocks.claveSimetrica"

extension SymmetricKey {
    var dataRepresentation: Data {
        return withUnsafeBytes { Data($0) }
    }
}

func leerClaveKeychain(account: String) -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account,
        kSecReturnData as String: kCFBooleanTrue!,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var dataTypeRef: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
    if status == errSecSuccess, let data = dataTypeRef as? Data { return data }
    return nil
}

func leerSymmetricKey() -> SymmetricKey? {
    if let keyData = leerClaveKeychain(account: keychainAccount) {
        return SymmetricKey(data: keyData)
    }
    return generaClaveKeychain()
}

func cifrar(input: String, using key: SymmetricKey) -> String? {
    guard let data = input.data(using: .utf8) else {
        writeToLog(message: "Error convirtiendo contraseña para cifrado")
        return nil
    }
    do {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined?.base64EncodedString()
    } catch {
        writeToLog(message: "Error cifrando")
        return nil
    }
}

func descifrar(input: String, using key: SymmetricKey) -> String? {
    guard let data = Data(base64Encoded: input) else {
        writeToLog(message: "Error decodificando contraseña cifrada")
        return nil
    }
    do {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        return String(data: decryptedData, encoding: .utf8)
    } catch {
        writeToLog(message: "Error descifrando")
        return nil
    }
}

func crearPaswordKeychain(key: Data, account: String) -> OSStatus {
    writeToLog(message: "Guardando clave en Keychain")
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account,
        kSecValueData as String: key
    ]
    var status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
        status = SecItemUpdate(query as CFDictionary, [(kSecValueData as String): key] as CFDictionary)
    }
    return status
}

func generaClaveKeychain() -> SymmetricKey {
    let symmetricKey = SymmetricKey(size: .bits256)
    writeToLog(message: "Generando clave simetrica aleatoria")
    let status = crearPaswordKeychain(key: symmetricKey.dataRepresentation, account: keychainAccount)
    if status != errSecSuccess {
        writeToLog(message: "Error al guardar la clave simetrica en el Keychain: \(status)")
    }
    return symmetricKey
}

func writeToLog(message: String) {
    guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    let flexocksDir = appSupportDir.appendingPathComponent("Flexocks")
    if !FileManager.default.fileExists(atPath: flexocksDir.path) {
        try? FileManager.default.createDirectory(at: flexocksDir, withIntermediateDirectories: true, attributes: nil)
    }
    let logFileURL = flexocksDir.appendingPathComponent("flexocks.log")
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let logMessage = "[\(dateFormatter.string(from: Date()))] \(message)\n"
    if let outputStream = OutputStream(url: logFileURL, append: true) {
        outputStream.open()
        let data = Data(logMessage.utf8)
        _ = data.withUnsafeBytes { outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count) }
        outputStream.close()
    }
}

enum flexocksAction {
    case start
    case stop
    case status

    var stringValue: String {
        switch self {
        case .start: return "start"
        case .stop: return "stop"
        case .status: return "status"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appManager: AppManager
    @State private var host: String = ""
    @State private var puertoLocal: String = ""
    @State private var puertoRemoto: String = ""
    @State private var usuario: String = ""
    @State private var contrasena: String = ""
    @State private var extrassh: String = ""
    @State private var originalConfiguration: Configuration?
    @State private var hasChanges: Bool = false
    @State private var isExtraSSHEnabled: Bool = false

    func loadConfigurationData() {
        if let currentConfig = Configuration.loadFromFile() {
            host = currentConfig.host
            puertoLocal = currentConfig.puertoLocal
            puertoRemoto = currentConfig.puertoRemoto
            usuario = currentConfig.usuario
            contrasena = currentConfig.contrasena
            extrassh = currentConfig.extrassh
        }
    }

    func saveConfiguration() {
        guard appManager.configuration != nil else { return }

        let passwordChanged = contrasena != originalConfiguration?.contrasena
        let hasChanges = host != originalConfiguration?.host ||
                         puertoLocal != originalConfiguration?.puertoLocal ||
                         puertoRemoto != originalConfiguration?.puertoRemoto ||
                         usuario != originalConfiguration?.usuario ||
                         extrassh != originalConfiguration?.extrassh ||
                         passwordChanged

        if hasChanges {
            writeToLog(message: "Cambios detectados: cerrando conexion")
            appManager.stopConnection()

            if passwordChanged {
                if let contrasenaCifrada = cifrar(input: contrasena, using: leerSymmetricKey()!),
                   let contrasenaCifradaData = contrasenaCifrada.data(using: .utf8) {
                    _ = crearPaswordKeychain(key: contrasenaCifradaData, account: "com.Flexocks.PasswordConexion")
                    writeToLog(message: "Contrasena cifrada guardada en Keychain")
                } else {
                    writeToLog(message: "Error cifrando la contrasena.")
                }
            }
        } else {
            writeToLog(message: "Sin cambios")
        }

        appManager.configureApp(host: host, puertoLocal: puertoLocal, puertoRemoto: puertoRemoto, usuario: usuario, contrasena: contrasena, extrassh: extrassh)
        self.hasChanges = hasChanges
        AppManager.shared.configurationPopover?.close()
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Host:")
                    .frame(width: 100, alignment: .trailing)
                TextField("", text: $host)
                    .border(Color.gray, width: 1)
            }
            HStack {
                Text("Puerto Local:")
                    .frame(width: 100, alignment: .trailing)
                TextField("", text: $puertoLocal)
                    .border(Color.gray, width: 1)
            }
            HStack {
                Text("Puerto Remoto:")
                    .frame(width: 100, alignment: .trailing)
                TextField("", text: $puertoRemoto)
                    .border(Color.gray, width: 1)
            }
            HStack {
                Text("Usuario:")
                    .frame(width: 100, alignment: .trailing)
                TextField("", text: $usuario)
                    .border(Color.gray, width: 1)
            }
            HStack {
                Text("Contrasena:")
                    .frame(width: 100, alignment: .trailing)
                SecureField("", text: $contrasena)
                    .border(Color.gray, width: 1)
            }
            HStack {
                Text("Opciones SSH extra:")
                    .frame(width: 100, alignment: .trailing)
                TextField("", text: $extrassh)
                    .border(Color.gray, width: 1)
                    .disabled(!isExtraSSHEnabled)
                Toggle("", isOn: $isExtraSSHEnabled)
            }
            HStack(spacing: 15) {
                Button("Cancelar") {
                    loadConfigurationData()
                    appManager.showingConfiguration = false
                    appManager.configurationPopover?.close()
                }
                Button("Guardar") {
                    saveConfiguration()
                }
                .padding([.leading, .trailing], 10)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .padding([.leading, .bottom, .trailing])
        .padding(.top, 50)
        .background(Color(red: 224/255, green: 225/255, blue: 227/255))
        .onAppear {
            if let currentConfig = appManager.configuration {
                host = currentConfig.host
                puertoLocal = currentConfig.puertoLocal
                puertoRemoto = currentConfig.puertoRemoto
                usuario = currentConfig.usuario
                contrasena = currentConfig.contrasena
                extrassh = currentConfig.extrassh
                originalConfiguration = currentConfig
            }
        }
    }
}

extension Configuration: CustomStringConvertible {
    var description: String {
        return "Configuration(host: \(host), puertoLocal: \(puertoLocal), puertoRemoto: \(puertoRemoto), extrassh: \(extrassh), usuario: \(usuario), contrasena: [OCULTA])"
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var appManager = AppManager.shared
    var configurationPopover: NSPopover?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(showConfigurationPopover), name: NSNotification.Name("ShowConfiguration"), object: nil)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        cleanLogFile()
        writeToLog(message: "Inicia conexion")
        runShellScript()
    }

    func cleanLogFile() {
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let logFileURL = appSupportDir.appendingPathComponent("Flexocks/flexocks.log")
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            try? FileManager.default.removeItem(at: logFileURL)
        }
    }

    func isProgramInstalled(_ program: String) -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = [program]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.launch()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        if output?.contains(program) ?? false { return true }
        let commonPaths = ["/usr/local/bin/", "/opt/homebrew/bin/", "/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/"]
        return commonPaths.contains { FileManager.default.fileExists(atPath: $0 + program) }
    }

    func openTerminalAndInstallBrew(completion: @escaping (Bool) -> Void) {
        guard let scriptPath = Bundle.main.path(forResource: "installbrew", ofType: "sh") else {
            writeToLog(message: "No se encontro installbrew.sh")
            completion(false)
            return
        }
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["/usr/bin/open", "-a", "Terminal.app", scriptPath]
        task.launch()
        task.waitUntilExit()
        completion(task.terminationStatus == 0)
    }

    func runShellScript() {
        if isProgramInstalled("brew") && isProgramInstalled("autossh") && isProgramInstalled("expect") {
            writeToLog(message: "Todos los programas ya estan instalados.")
            return
        }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.openTerminalAndInstallBrew { success in
                writeToLog(message: success ? "Homebrew, autossh y expect instalados." : "Error durante la instalacion.")
            }
        }
    }

    @objc func showConfigurationPopover() {
        NSApp.activate(ignoringOtherApps: true)
        guard let button = appManager.statusItem?.button else { return }
        if appManager.configurationPopover == nil {
            appManager.configurationPopover = NSPopover()
            appManager.configurationPopover?.behavior = .transient
            appManager.configurationPopover?.contentSize = NSSize(width: 380, height: 320)
            let contentView = ContentView().environmentObject(appManager)
            appManager.configurationPopover?.contentViewController = NSHostingController(rootView: contentView)
        }
        if let popover = appManager.configurationPopover {
            if popover.isShown {
                popover.close()
            } else {
                let positioningRect = NSRect(x: button.bounds.midX, y: button.bounds.minY, width: 0, height: 0)
                popover.show(relativeTo: positioningRect, of: button, preferredEdge: .minY)
            }
        }
    }
}

@main
struct flexocksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
