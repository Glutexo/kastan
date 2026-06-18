import Testing
@testable import jizdni_nerady

@Test func defaultOutputNamesApplication() {
    let output = CommandRunner().output(for: [])

    #expect(output.contains("Jízdní neřády"))
}

@Test func helpOutputShowsUsage() {
    let output = CommandRunner().output(for: ["--help"])

    #expect(output.contains("Použití:"))
    #expect(output.contains("--version"))
}

@Test func versionOutputShowsCurrentVersion() {
    let output = CommandRunner().output(for: ["--version"])

    #expect(output == "0.1.0")
}
