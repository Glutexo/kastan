import Foundation

@main
struct JizdniNeradyApp {
    static func main() {
        let runner = CommandRunner()
        print(runner.output(for: CommandLine.arguments.dropFirst()))
    }
}

struct CommandRunner {
    let version = "0.1.0"

    func output<S: Sequence<String>>(for arguments: S) -> String {
        let arguments = Array(arguments)

        if arguments.contains("--help") || arguments.contains("-h") {
            return helpText
        }

        if arguments.contains("--version") {
            return version
        }

        return """
        Jízdní neřády

        Základ nové Swift CLI aplikace.
        """
    }

    private var helpText: String {
        """
        Použití:
          jizdni-nerady [volby]

        Volby:
          -h, --help     Zobrazí nápovědu
          --version      Zobrazí verzi aplikace
        """
    }
}
