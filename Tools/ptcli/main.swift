import Foundation

// Command line harness for the Core layer (Linux / macOS). Run via Tools/linux_build.sh.
let args = Array(CommandLine.arguments.dropFirst())
print("ptcli", args)
