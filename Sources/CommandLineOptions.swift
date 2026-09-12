import Foundation

struct CommandLineOptions {
    enum Command {
        case list
        case share(index: Int)
        case waitForPane
        case help
    }

    var command: Command = .help

    static func parse(_ arguments: [String]) -> CommandLineOptions {
        var options = CommandLineOptions()
        for argument in arguments.dropFirst() {
            switch argument {
            case "list", "ls":
                options.command = .list
            case "wait":
                options.command = .waitForPane
            case "-h", "--help":
                options.command = .help
            default:
                if let index = Int(argument) { options.command = .share(index: index) }
            }
        }
        return options
    }

    static let usage = """
    parrotpane: mirror one Ghostty pane into a shareable window, with that pane's audio.

      parrotpane open <url>   open the url in this pane and mirror it
      parrotpane list         list every Ghostty pane
      parrotpane <n>          mirror pane <n>

    Share the window titled "ParrotPane" in your meeting app.
    """
}
