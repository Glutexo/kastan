import AppKit
import Foundation
import Kastan
import SwiftUI

/// Opens one generated email attachment in the user's default macOS application.
@MainActor
protocol ConnectionEmailAttachmentOpening {
    func open(data: Data, fileName: String) throws
}

/// Preserves the IDOS attachment name in an isolated temporary directory before handing the file to macOS.
@MainActor
struct WorkspaceConnectionEmailAttachmentOpener: ConnectionEmailAttachmentOpening {
    func open(data: Data, fileName: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kastan", isDirectory: true)
            .appendingPathComponent("EmailAttachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appendingPathComponent(
            ConnectionEmailAttachmentFileName.safeValue(fileName)
        )
        try data.write(to: file, options: .atomic)

        guard NSWorkspace.shared.open(file) else {
            throw ConnectionEmailAttachmentOpenError.cannotOpen
        }
    }
}

/// Removes path components and reserved separators while retaining a readable IDOS attachment name.
enum ConnectionEmailAttachmentFileName {
    static func safeValue(_ value: String) -> String {
        let leafName = value
            .components(separatedBy: CharacterSet(charactersIn: "/\\"))
            .last ?? value
        var reservedCharacters = CharacterSet(charactersIn: ":")
        reservedCharacters.formUnion(.newlines)
        var trimmingCharacters = CharacterSet.whitespacesAndNewlines
        trimmingCharacters.insert(charactersIn: ".")
        let safeName = leafName
            .components(separatedBy: reservedCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: trimmingCharacters)
        return safeName.isEmpty ? "attachment" : safeName
    }
}

enum ConnectionEmailAttachmentOpenError: LocalizedError {
    case cannotOpen

    var errorDescription: String? {
        AppLocalization.string("No application could open the attachment.")
    }
}

private enum ConnectionEmailAttachmentKind {
    case pdf
    case calendar

    init?(fileName: String) {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "pdf":
            self = .pdf
        case "ics":
            self = .calendar
        default:
            return nil
        }
    }
}

/// Owns one user-confirmed IDOS email delivery without retaining the recipient after the sheet closes.
@MainActor
final class ConnectionEmailViewModel: ObservableObject {
    static let maximumRecipientLength = 320
    static let maximumMessageLength = 1_024
    private static let emailPattern = #"^[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$"#

    @Published var recipient = ""
    @Published var message = ""
    @Published private(set) var draft: IDOSConnectionEmailDraft?
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var openingAttachmentFileName: String?
    @Published private(set) var sentRecipient: String?
    @Published private(set) var errorMessage: String?

    let connection: IDOSConnection
    let timetable: IDOSTimetable
    private let client: any IDOSClienting
    private let attachmentOpener: any ConnectionEmailAttachmentOpening

    init(
        connection: IDOSConnection,
        timetable: IDOSTimetable,
        client: any IDOSClienting,
        attachmentOpener: any ConnectionEmailAttachmentOpening = WorkspaceConnectionEmailAttachmentOpener()
    ) {
        self.connection = connection
        self.timetable = timetable
        self.client = client
        self.attachmentOpener = attachmentOpener
    }

    var canSend: Bool {
        draft != nil && normalizedRecipient != nil && !messageIsTooLong &&
            !isLoading && !isSending && openingAttachmentFileName == nil && sentRecipient == nil
    }

    var recipientIsTooLong: Bool {
        recipient.count > Self.maximumRecipientLength
    }

    var recipientHasInvalidAddress: Bool {
        let recipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        return recipient.count <= Self.maximumRecipientLength &&
            !recipient.isEmpty && normalizedRecipient == nil
    }

    var messageIsTooLong: Bool {
        // HTML maxlength and IDOS's .NET backend count UTF-16 code units rather than grapheme clusters.
        message.utf16.count > Self.maximumMessageLength
    }

    /// Accepts the same comma- or semicolon-separated address list as IDOS and normalizes it for delivery.
    private var normalizedRecipient: String? {
        let value = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= Self.maximumRecipientLength else { return nil }

        let addresses = value
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !addresses.isEmpty,
              addresses.allSatisfy({ $0.range(of: Self.emailPattern, options: .regularExpression) != nil })
        else {
            return nil
        }
        return addresses.joined(separator: ", ")
    }

    /// Fetches the same localized message and attachment labels shown by IDOS before delivery.
    func load() async {
        guard draft == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let draft = try await client.connectionEmailDraft(
                for: connection,
                timetable: timetable,
                language: AppLanguagePreference.idosLanguage
            )
            guard !Task.isCancelled else { return }
            self.draft = draft
            message = draft.message
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Sends only after the user has supplied a recipient and explicitly confirmed the prepared message.
    func send() async {
        guard canSend, let recipient = normalizedRecipient else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            try await client.sendConnectionByEmail(
                connection,
                to: recipient,
                message: message,
                timetable: timetable,
                language: AppLanguagePreference.idosLanguage
            )
            guard !Task.isCancelled else { return }
            sentRecipient = recipient
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Downloads the selected generated attachment without sending or retaining any email recipient data.
    func openAttachment(named fileName: String) async {
        guard draft?.attachmentFileNames.contains(fileName) == true,
              let kind = ConnectionEmailAttachmentKind(fileName: fileName),
              openingAttachmentFileName == nil,
              !isLoading,
              !isSending
        else {
            return
        }

        openingAttachmentFileName = fileName
        errorMessage = nil
        defer { openingAttachmentFileName = nil }

        do {
            let data: Data
            switch kind {
            case .pdf:
                data = try await client.connectionPDF(
                    for: connection,
                    timetable: timetable,
                    language: AppLanguagePreference.idosLanguage
                )
            case .calendar:
                let calendar = try await client.connectionCalendar(
                    for: connection,
                    timetable: timetable,
                    language: AppLanguagePreference.idosLanguage
                )
                data = Data(calendar.utf8)
            }

            guard !Task.isCancelled else { return }
            try attachmentOpener.open(data: data, fileName: fileName)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    func canOpenAttachment(named fileName: String) -> Bool {
        ConnectionEmailAttachmentKind(fileName: fileName) != nil
    }
}

/// Presents the recipient, editable IDOS message, and openable generated PDF and calendar attachments.
struct ConnectionEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ConnectionEmailViewModel
    @FocusState private var recipientIsFocused: Bool

    init(
        connection: IDOSConnection,
        timetable: IDOSTimetable,
        client: any IDOSClienting
    ) {
        _model = StateObject(wrappedValue: ConnectionEmailViewModel(
            connection: connection,
            timetable: timetable,
            client: client
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Send Connection by Email")
                    .font(.title2.bold())
                Text("\(model.connection.departureStation) → \(model.connection.arrivalStation)")
                    .foregroundStyle(.secondary)
            }

            if let sentRecipient = model.sentRecipient {
                successContent(recipient: sentRecipient)
            } else if model.isLoading {
                ProgressView("Preparing email…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if model.draft == nil {
                unavailableContent
            } else {
                emailEditor
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(model.isSending || model.openingAttachmentFileName != nil)
        .task {
            await model.load()
            if model.draft != nil {
                recipientIsFocused = true
            }
        }
    }

    private var emailEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recipient Email")
                TextField("name@example.com", text: $model.recipient)
                    .textFieldStyle(.roundedBorder)
                    .focused($recipientIsFocused)
                    .onSubmit {
                        guard model.canSend else { return }
                        Task { await model.send() }
                    }
                if model.recipientIsTooLong {
                    Label(
                        "Email address can contain at most 320 characters.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                } else if model.recipientHasInvalidAddress {
                    Label("Enter a valid email address.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Message")
                TextEditor(text: $model.message)
                    .font(.body)
                    .frame(minHeight: 110)
                    .padding(5)
                    .background(.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    }
                if model.messageIsTooLong {
                    Label("Message can contain at most 1,024 characters.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let draft = model.draft {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Attachments")
                        .font(.headline)
                    ForEach(draft.attachmentFileNames, id: \.self) { fileName in
                        attachmentControl(fileName: fileName)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isSending || model.openingAttachmentFileName != nil)
                Button {
                    Task { await model.send() }
                } label: {
                    if model.isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Send")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSend)
            }
        }
    }

    private var unavailableContent: some View {
        VStack(spacing: 16) {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Try Again") {
                    Task { await model.load() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func successContent(recipient: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Email Sent")
                .font(.title3.bold())
            Text(AppLocalization.string("The connection was sent to %@.", recipient))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    @ViewBuilder
    private func attachmentControl(fileName: String) -> some View {
        if model.canOpenAttachment(named: fileName) {
            Button {
                Task { await model.openAttachment(named: fileName) }
            } label: {
                HStack(spacing: 9) {
                    if model.openingAttachmentFileName == fileName {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18)
                    } else {
                        Image(systemName: attachmentSymbol(for: fileName))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)
                    }
                    Text(fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(model.openingAttachmentFileName != nil || model.isSending)
            .help(AppLocalization.string("Open attachment %@", fileName))
            .accessibilityLabel(AppLocalization.string("Open attachment %@", fileName))
            .accessibilityHint("Opens in the default application")
        } else {
            Label(fileName, systemImage: attachmentSymbol(for: fileName))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func attachmentSymbol(for fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "pdf":
            "doc.richtext"
        case "ics":
            "calendar"
        default:
            "paperclip"
        }
    }
}
