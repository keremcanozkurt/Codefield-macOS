import Foundation

// Runs git clone outside the app's sandbox, so git and ssh can use the
// user's keys, agent, known_hosts and credential helpers as they do in
// Terminal. The app never reads any of them; this process never analyzes
// or opens a repository. Only the app that embeds it can connect.

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement("identifier \"com.keremcanozkurt.Codefield\"")
        let service = GitCloneService()
        connection.exportedInterface = NSXPCInterface(with: GitCloneServiceProtocol.self)
        connection.exportedObject = service
        // The app quit or closed the clone sheet: stop git with it.
        connection.invalidationHandler = { service.cancel() }
        connection.interruptionHandler = { service.cancel() }
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
