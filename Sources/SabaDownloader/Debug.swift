
import Foundation

func printIfDebug(_ value: Any?) {
    #if DEBUG
    print(value ?? "nil")
    #endif
}
