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


    static let filename = "config.json"
    static var fileURL: URL? {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let applicationSupportURL = urls.last else { return nil }
        let appDirectoryName = "Flexocks"
        let appDirectoryURL = applicationSupportURL.appendingPathComponent(appDirectoryName)
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
            let emptyConfig = Configuration(host: "", puertoLocal: "", puertoRemoto: "", usuario: "", contrasena: "")
            emptyConfig.saveToFile()
            return emptyConfig
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            var configuration = try decoder.decode(Configuration.self, from: data)

            if let contrasenaCifradaData = leerClaveKeychain(account: "com.Flexocks.PasswordConexion"),
               let contrasenaCifrada = String(data: contrasenaCifradaData, encoding: .utf8) {
                if let contrasenaDescifrada = descifrar(input: contrasenaCifrada, using: leerSymmetricKey()!) {
                    configuration.contrasena = contrasenaDescifrada
                    // Para debug:
                    //writeToLog(message: "Contraseña cifrada: \(contrasenaCifrada)")
                    //writeToLog(message: "Contraseña descifrada: \(contrasenaDescifrada)")
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
            writeToLog(message: "Error al cargar la configuración desde el archivo: \(error)")
            return nil
        }
    }

    func saveToFile() {
        guard let fileURL = Configuration.fileURL else {
            writeToLog(message: "Error: URL del archivo no definida.")
            return
        }

        do {
            let configMasked = Configuration(host: self.host, puertoLocal: self.puertoLocal, puertoRemoto: self.puertoRemoto, usuario: self.usuario, contrasena: "[OCULTA]")

            let encoder = JSONEncoder()
            let data = try encoder.encode(configMasked)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            writeToLog(message: "Error al guardar la configuración: \(error)")
        }
    }
}

class Logger {
    static let shared = Logger()
    private let logFilename = "flexocks.log"
    private var fileURL: URL? {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let applicationSupportURL = urls.last else { return nil }
        let appDirectoryName = "Flexocks"
        let appDirectoryURL = applicationSupportURL.appendingPathComponent(appDirectoryName)
        if !fileManager.fileExists(atPath: appDirectoryURL.path) {
            try? fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        return appDirectoryURL.appendingPathComponent(logFilename)
    }

    func log(_ message: String) {
        print("Intentando loguear: \(message)")
        print(message)  // imprimir en la consola
        guard let url = fileURL else { return }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .long)
        let fullMessage = "[\(timestamp)] \(message)\n"
        let data = Data(fullMessage.utf8)

        if FileManager.default.fileExists(atPath: url.path) {
            if let fileHandle = try? FileHandle(forWritingTo: url) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: url)
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

    func configureApp(host: String, puertoLocal: String, puertoRemoto: String, usuario: String, contrasena: String) {
        if let symmetricKey = leerSymmetricKey() {
            if let contrasenaCifrada = cifrar(input: contrasena, using: symmetricKey) {
                let newConfig = Configuration(host: host, puertoLocal: puertoLocal, puertoRemoto: puertoRemoto, usuario: usuario, contrasena: contrasenaCifrada)
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
        case .start:
            imageName = "wave_verde"
        case .stop:
            imageName = "wave_roja"
        case .status:
            imageName = "wave_int"
        }
        let image = NSImage(named: imageName)
        image?.size = NSSize(width: 16.0, height: 16.0)
        statusItem?.button?.image = image
    }

    func checkStatus() {
        guard let configuration = configuration else {
            return
        }

        if configuration.host.isEmpty || configuration.puertoLocal.isEmpty || configuration.puertoRemoto.isEmpty {
            DispatchQueue.main.async {
                self.status = .stop
            }
            return
        }

        let flexocksParamsMasked = "-h \(configuration.host) -l \(configuration.puertoLocal) -r \(configuration.puertoRemoto) -u \(configuration.usuario) -c [OCULTA]"

        writeToLog(message: "Check status de conexión con Flexocks params: \(flexocksParamsMasked)")

        let realFlexocksParams = flexocksParamsMasked.replacingOccurrences(of: "-c [OCULTA]", with: "-c \(configuration.contrasena)")
        let result = executeflexocksAction(.status, params: realFlexocksParams)

        DispatchQueue.main.async {
            if result.output == "0" {
                self.status = .start
            } else if result.output == "1" {
                self.status = .stop
            } else if result.output == "2" {
                self.status = .status
            }
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
         let configureItem: NSMenuItem
         let firefoxItem: NSMenuItem
         let exitItem = NSMenuItem()

         exitItem.image = resizedImage(named: "salir", toSize: iconSize)
         exitItem.action = #selector(exitApp)
         exitItem.target = self
         exitItem.title = ""

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
         configureItem = NSMenuItem()
         configureItem.image = resizedImage(named: "config", toSize: iconSize)
         configureItem.action = #selector(showConfigurationPopover)
         configureItem.target = self
         configureItem.title = ""

         firefoxItem = NSMenuItem()
         firefoxItem.image = resizedImage(named: "ffox", toSize: iconSize)
         firefoxItem.action = #selector(restartFirefox)
         firefoxItem.target = self
         firefoxItem.title = ""

         menu.addItem(connectItem)
         menu.addItem(configureItem)
         menu.addItem(firefoxItem)
         menu.addItem(NSMenuItem.separator())
         menu.addItem(exitItem)

         return menu
     }

    @objc func startConnection() {
        guard let configuration = configuration else { return }
        guard !configuration.host.isEmpty,
              !configuration.puertoRemoto.isEmpty,
              !configuration.puertoLocal.isEmpty else {
            writeToLog(message: "Parámetros requeridos (host, puerto remoto, puerto local). Al menos uno está vacío.")
            return
        }

        var contrasenaDescifrada: String? = nil

        if let contrasenaCifradaData = leerClaveKeychain(account: "com.Flexocks.PasswordConexion"),
           let contrasenaCifrada = String(data: contrasenaCifradaData, encoding: .utf8) {
            contrasenaDescifrada = descifrar(input: contrasenaCifrada, using: leerSymmetricKey()!)
            if let contrasenaDescifrada = contrasenaDescifrada {
                // Para debug:
                // writeToLog(message: "Contraseña cifrada rescatada de Keychain: \(contrasenaCifrada)")
                // writeToLog(message: "Contraseña descifrada rescatada de Keychain: \(contrasenaDescifrada)")
            } else {
                writeToLog(message: "Error al descifrar la contraseña desde el Keychain.")
            }
        } else {
            writeToLog(message: "Error al obtener la contraseña cifrada desde el Keychain.")
        }

        let flexocksParamsMasked = "-h \(configuration.host) -l \(configuration.puertoLocal) -r \(configuration.puertoRemoto) -u \(configuration.usuario) -c [OCULTA]"
        let flexocksParams = "-h \(configuration.host) -l \(configuration.puertoLocal) -r \(configuration.puertoRemoto) -u \(configuration.usuario) -c \(contrasenaDescifrada ?? "")"

        _ = executeflexocksAction(.start, params: flexocksParams)
        writeToLog(message: flexocksParamsMasked)
        checkStatus()
    }


    @objc func stopConnection() {
        guard let configuration = configuration else { return }

        guard !configuration.host.isEmpty,
              !configuration.puertoRemoto.isEmpty,
              !configuration.puertoLocal.isEmpty else {
            writeToLog(message: "Parámetros requeridos (host, puerto remoto, puerto local). Al menos uno está vacío.")
            return
        }

        let flexocksParams = "-h \(configuration.host) -l \(configuration.puertoLocal) -r \(configuration.puertoRemoto) -u \(configuration.usuario)"

        _ = executeflexocksAction(.stop, params: flexocksParams)
        writeToLog(message: "Se detuvo la conexión con los siguientes parámetros: \(flexocksParams)")
        checkStatus()
    }

     @objc func showConfigurationPopover() {
         NotificationCenter.default.post(name: NSNotification.Name("ShowConfiguration"), object: nil)
     }

    @objc func restartFirefox() {
        DispatchQueue.global().async {
            let appleScriptClose = """
            tell application "Firefox"
                quit
            end tell
            """

            let appleScriptOpen = """
            tell application "Firefox"
                activate
            end tell
            """

            let scriptClose = NSAppleScript(source: appleScriptClose)
            let scriptOpen = NSAppleScript(source: appleScriptOpen)

            scriptClose?.executeAndReturnError(nil)

            DispatchQueue.main.async {
                writeToLog(message: "Parando Firefox" )
            }

            Thread.sleep(forTimeInterval: 3.0)

            scriptOpen?.executeAndReturnError(nil)

            DispatchQueue.main.async {
                writeToLog(message: "Iniciando Firefox" )
            }
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

         let bundle = Bundle.main
         guard let scriptPath = bundle.path(forResource: "flexocks", ofType: "sh") else {
             let errorMsg = "Error: El script 'flexocks.sh' no se encontró."
             print(errorMsg)
             writeToLog(message: errorMsg)
             return (false, "No se encontró el archivo 'flexocks.sh'")
         }

         task.arguments = ["-c", "\(scriptPath) \(action.stringValue) \(params)"]

         let pipe = Pipe()
         task.standardOutput = pipe
         task.standardError = pipe

         task.launch()

         let data = pipe.fileHandleForReading.readDataToEndOfFile()
         let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

         task.waitUntilExit()
         let success = task.terminationStatus == 0

         let logMessage = "Output del script flexocks.sh: \(output)"
         print(logMessage)
         writeToLog(message: logMessage)

         return (success, output)
     }
 }

let keychainAccount = "com.Flexocks.claveSimetrica"

extension SymmetricKey {
    var dataRepresentation: Data {
        return withUnsafeBytes { Data($0) }
    }
}

extension Data {
    var symmetricKey: SymmetricKey {
        return SymmetricKey(data: self)
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

    if status == errSecSuccess {
        if let data = dataTypeRef as? Data {
            return data
        }
    }
    return nil
}

func leerSymmetricKey() -> SymmetricKey? {
    if let keyData = leerClaveKeychain(account: keychainAccount) {
        return SymmetricKey(data: keyData)
    } else {
        return generaClaveKeychain()
    }
}

func cifrar(input: String, using key: SymmetricKey) -> String? {
    guard let data = input.data(using: .utf8) else {
        writeToLog(message: "Error: No se pudo convertir la contraseña en datos para cifrado")
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
        writeToLog(message: "Error: No se pudo decodificar la contraseña cifrada")
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
    // Para debug
    // writeToLog(message: "Intentando guardar la clave en Keychain: \(key.base64EncodedString()) para la cuenta: \(account)")
    writeToLog(message: "Intentando guardar la clave en Keychain")
    let query: [String: Any] = [
        (kSecClass as String): kSecClassGenericPassword,
        (kSecAttrAccount as String): account,
        (kSecValueData as String): key
    ]

    var status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
        status = SecItemUpdate(query as CFDictionary, [(kSecValueData as String): key] as CFDictionary)
    }

    let keyData = leerClaveKeychain(account:(account) )

    if let unwrappedKeyData = keyData {
        // Para debug:
        // writeToLog(message: "Clave recuperada del Keychain:  \(account) \(unwrappedKeyData.base64EncodedString())")
        writeToLog(message: "Clave recuperada del Keychain")
    } else {
        writeToLog(message: "No se pudo recuperar la clave del Keychain.")
    }
    return status
}

func generaClaveKeychain() -> SymmetricKey {
    let symmetricKey = SymmetricKey(size: .bits256)
    let keyDataToStore = symmetricKey.dataRepresentation
    // Para debug:
    // writeToLog(message: "Generando clave simétrica: \(keyDataToStore.base64EncodedString())")
    writeToLog(message: "Generando clave simétrica aleatoria")

    let status = crearPaswordKeychain(key: keyDataToStore, account: keychainAccount)
    if status != errSecSuccess {
        writeToLog(message: "Error al guardar la clave simétrica en el Keychain: \(status)")
    }

    if let keyFromKeychain = leerSymmetricKey() {
        // Para debug:
        // writeToLog(message: "Clave leída del Keychain: \(keyFromKeychain.dataRepresentation.base64EncodedString())")
        writeToLog(message: "Clave leída del Keychain")
    } else {
        writeToLog(message: "No se pudo leer la clave del Keychain.")
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
    let dateStr = dateFormatter.string(from: Date())

    let logMessage = "[\(dateStr)] \(message)\n"

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
 }

 extension flexocksAction {
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
    @State private var originalConfiguration: Configuration?
    @State private var hasChanges: Bool = false

    func loadConfigurationData() {
        if let currentConfig = Configuration.loadFromFile() {
            host = currentConfig.host
            puertoLocal = currentConfig.puertoLocal
            puertoRemoto = currentConfig.puertoRemoto
            usuario = currentConfig.usuario
            contrasena = currentConfig.contrasena
            writeToLog(message: "Configuración cargada")
        }
    }

    func saveConfiguration() {
        guard appManager.configuration != nil else {
            return
        }

        let flexocksParamsMasked = "-h \(host) -l \(puertoLocal) -r \(puertoRemoto) -u \(usuario) -c [OCULTA]"

        var passwordChanged: Bool {
            return contrasena != originalConfiguration?.contrasena
        }

        let hasChanges = host != originalConfiguration?.host ||
                         puertoLocal != originalConfiguration?.puertoLocal ||
                         puertoRemoto != originalConfiguration?.puertoRemoto ||
                         usuario != originalConfiguration?.usuario ||
                         passwordChanged

        if hasChanges {
            writeToLog(message: "Cambios detectados: Cerrando conexión")
            appManager.stopConnection()
            writeToLog(message: "FlexocksParamsMasked: \(flexocksParamsMasked)")

            if passwordChanged {
                if let contrasenaCifrada = cifrar(input: contrasena, using: leerSymmetricKey()!),
                   let contrasenaCufradaData = contrasenaCifrada.data(using: .utf8) {
                    _ = crearPaswordKeychain(key: contrasenaCufradaData, account: "com.Flexocks.PasswordConexion")
                    writeToLog(message: "Contraseña cifrada guardada en Keychain")
                } else {
                    writeToLog(message: "Error cifrando la contraseña o convirtiéndola a Data.")
                }
            }
        } else {
            writeToLog(message: "Sin cambios")
        }

        appManager.configureApp(host: host, puertoLocal: puertoLocal, puertoRemoto: puertoRemoto, usuario: usuario, contrasena: contrasena)
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
                Text("Contraseña:")
                    .frame(width: 100, alignment: .trailing)
                SecureField("", text: $contrasena)
                    .border(Color.gray, width: 1)
            }

            HStack(spacing: 15) {
                Button("Cancelar") {
                    loadConfigurationData()
                    appManager.showingConfiguration = false
                    appManager.configurationPopover?.close()
                    writeToLog(message: "Cancelar")
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
                originalConfiguration = currentConfig
            }
        }
    }
}

struct ConfigurationView: View {
     var body: some View {
         Text("Configuración")
             .padding()
             .frame(maxWidth: .infinity, maxHeight: .infinity)
     }
 }

extension Configuration: CustomStringConvertible {
    var description: String {
        return "Configuration(host: \(host), puertoLocal: \(puertoLocal), puertoRemoto: \(puertoRemoto), usuario: \(usuario), contrasena: [OCULTA])"
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
        // Limpiar el archivo de log al inicio de la aplicación
        cleanLogFile()
        writeToLog(message: " Inicia conexión")
        runShellScript()
    }

    func cleanLogFile() {

        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let logFileURL = appSupportDir.appendingPathComponent("Flexocks/flexocks.log")

        if FileManager.default.fileExists(atPath: logFileURL.path) {
            try? FileManager.default.removeItem(at: logFileURL)
        }
        print(logFileURL)
    }

    func runShellScript() {
        /*
        func isXcodeInstalled() -> Bool {
            let path = "/Applications/Xcode.app"
            let fileManager = FileManager.default
            return fileManager.fileExists(atPath: path)
        }

        func openXcodeInAppStore() {
            if let url = URL(string: "macappstore://apps.apple.com/app/id497799835") {
                NSWorkspace.shared.open(url)
            }
        }

        func isProgramInstalled(_ program: String) -> Bool {
            let checkTask = Process()
            checkTask.launchPath = "/bin/sh"
            checkTask.arguments = ["-l", "-c", "/usr/bin/which \(program)"]

            let pipe = Pipe()
            checkTask.standardOutput = pipe
            checkTask.launch()
            checkTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let isInstalled = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            writeToLog(message: "\(program) está instalado: \(isInstalled)")

            if checkTask.terminationStatus != 0 {
                print("El comando /usr/bin/which falló para \(program).")
                writeToLog(message: "\(program) NO está instalado: \(isInstalled)")
                return false
            }

            return isInstalled
        }

        func installProgram(programName: String, tarURL: String? = nil) {
            if isProgramInstalled(programName) {
                print("\(programName) ya está instalado.")
                writeToLog(message: "\(programName) ya está instalado.")
                return
            }

            let destination: String
            if let tarURL = tarURL, let url = URL(string: tarURL), let data = try? Data(contentsOf: url) {
                destination = "/tmp/\(programName).tar.gz"
                do {
                    try data.write(to: URL(fileURLWithPath: destination))
                } catch {
                    print("Error al descargar y escribir el archivo \(programName).")
                    writeToLog(message: "Error al descargar y escribir el archivo \(programName).")
                    return
                }
            } else if let tarFilePath = Bundle.main.path(forResource: programName, ofType: "tgz") {
                destination = tarFilePath
            } else {
                print("Error: No se encontró el archivo \(programName).tgz y no se proporcionó una URL.")
                writeToLog(message: "Error: No se encontró el archivo \(programName).tgz y no se proporcionó una URL.")
                return
            }

            // Extraer, compilar e instalar con privilegios de administrador
            let compileAndInstallCommands = """
            do shell script "tar -xzf \(destination) -C /tmp && cd /tmp/\(programName) && ./configure && make && sudo make install" with administrator privileges
            """

            if let appleScript = NSAppleScript(source: compileAndInstallCommands) {
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)
                if let actualError = error {
                    print("Error al instalar \(programName): \(actualError)")
                    writeToLog(message: "Error al instalar \(programName).")
                } else {
                    print("Resultado de la instalación de \(programName): \(result.stringValue ?? "Sin salida")")
                    writeToLog(message: "Resultado de la instalación de \(programName): \(result.stringValue ?? "Sin salida")")
                }
            }
        }

        if !isXcodeInstalled() {
            writeToLog(message: "Xcode no está instalado. Abriendo Mac App Store...")
            openXcodeInAppStore()
        } else {
            if !isProgramInstalled("autossh") {
                writeToLog(message: "Instalando autossh.......")
                installProgram(programName: "autossh")
            }

            if !isProgramInstalled("expect") {
                writeToLog(message: "Instalando expect.......")
                installProgram(programName: "expect")
            }
        }
        */

        func isProgramInstalled(_ program: String) -> Bool {
            let checkTask = Process()
            checkTask.launchPath = "/bin/sh"
            checkTask.arguments = ["-l", "-c", "/usr/bin/which \(program)"]

            let pipe = Pipe()
            checkTask.standardOutput = pipe
            checkTask.launch()
            checkTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let isInstalled = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            writeToLog(message: "\(program) está instalado: \(isInstalled)")

            if checkTask.terminationStatus != 0 {
                print("El comando /usr/bin/which falló para \(program).")
                writeToLog(message: "\(program) NO está instalado")
                return false
            }

            return isInstalled
        }

        func isBrewInstalled() -> Bool {
            // Primera comprobación: usando which
            if isProgramInstalled("brew") {
                writeToLog(message: "brew está instalado: true")
                return true
            }

            // Segunda comprobación: comprobando la ubicación en Macs con M1
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: "/opt/homebrew/bin/brew") {
                writeToLog(message: "brew está instalado en /opt/homebrew/bin/: true")
                return true
            }

            // Si ninguna de las comprobaciones anteriores fue exitosa, devolvemos false
            writeToLog(message: "brew está instalado: false")
            return false
        }

        func executeWithAdminPrivileges(command: String) {
            let appleScriptCommand = """
            do shell script "\(command)" with administrator privileges
            """

            if let appleScript = NSAppleScript(source: appleScriptCommand) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let actualError = error {
                    writeToLog(message: "Error al ejecutar comando: \(actualError)")
                }
            }
        }

        func installBrewSilently() {
            let installBrewCommand = "curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | /bin/bash"
            executeWithAdminPrivileges(command: installBrewCommand)
            writeToLog(message: "Intento de instalación de Homebrew completado.")
        }

        func getBrewPath() -> String? {
            // Verifica en las rutas comunes
            let commonPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

            for path in commonPaths {
                if FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }

            return nil
        }

        func installProgramWithBrew(programName: String) {
             guard let brewPath = getBrewPath() else {
                 writeToLog(message: "No se pudo encontrar la ruta de Homebrew.")
                 return
             }

             let brewInstallCommand = "\(brewPath) install \(programName)"

             let installTask = Process()
             installTask.launchPath = "/bin/sh"
             installTask.arguments = ["-l", "-c", brewInstallCommand]

             let pipe = Pipe()
             installTask.standardOutput = pipe
             installTask.launch()
             installTask.waitUntilExit()

             let data = pipe.fileHandleForReading.readDataToEndOfFile()
             let output = String(data: data, encoding: .utf8) ?? ""

             writeToLog(message: "Resultado de instalación de \(programName) con Homebrew: \(output)")

             if installTask.terminationStatus != 0 {
                 writeToLog(message: "Error al instalar \(programName) con Homebrew.")
             } else {
                 writeToLog(message: "Instalación de \(programName) con Homebrew completada exitosamente.")
             }
         }


        DispatchQueue.global(qos: .background).async {
            if !isBrewInstalled() {
                writeToLog(message: "Homebrew no está instalado. Instalando...")
                installBrewSilently()
            }

            if !isProgramInstalled("autossh") {
                writeToLog(message: "Instalando autossh con Homebrew.......")
                installProgramWithBrew(programName: "autossh")
            }

            if !isProgramInstalled("expect") {
                writeToLog(message: "Instalando expect con Homebrew.......")
                installProgramWithBrew(programName: "expect")
            }
        }


    }

    @objc func showConfigurationPopover() {
        NSApp.activate(ignoringOtherApps: true)
        guard let button = appManager.statusItem?.button else { return }
        if appManager.configurationPopover == nil {
            appManager.configurationPopover = NSPopover()
            appManager.configurationPopover?.behavior = .transient
            appManager.configurationPopover?.contentSize = NSSize(width: 350, height: 200)
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
            // Sin contenido aquí
        }
    }
}

struct MainApp {
    static func main() {
        flexocksApp.main()
    }
}
