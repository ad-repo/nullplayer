#if os(Linux)
import Foundation

LinuxAppLifecycle().run()
#else
import Foundation

print("NullPlayerLinuxUI is only available when built on Linux.")
#endif
