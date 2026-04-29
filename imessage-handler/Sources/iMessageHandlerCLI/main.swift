import Foundation
import iMessageHandlerCore

do {
    let runtime = try IMessageHandlerRuntime()
    try runtime.startBlocking()
} catch {
    fputs("fatal: \(error.localizedDescription)\n", stderr)
    exit(1)
}
