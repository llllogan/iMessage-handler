import CalendarHandlerCore
import Foundation

do {
    let runtime = try CalendarHandlerRuntime()
    try runtime.startBlocking()
} catch {
    fputs("fatal: \(error.localizedDescription)\n", stderr)
    exit(1)
}
