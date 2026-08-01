import Foundation
import Kastan
import SwiftUI

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
    @Published private(set) var sentRecipient: String?
    @Published private(set) var errorMessage: String?

    let connection: IDOSConnection
    let timetable: IDOSTimetable
    private let client: any IDOSClienting

    init(
        connection: IDOSConnection,
        timetable: IDOSTimetable,
        client: any IDOSClienting
    ) {
        self.connection = connection
        self.timetable = timetable
        self.client = client
    }

    var canSend: Bool {
        draft != nil && normalizedRecipient != nil && !messageIsTooLong &&
            !isLoading && !isSending && sentRecipient == nil
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
}

/// Presents the recipient, editable IDOS message, and generated PDF and calendar attachment names.
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
        .interactiveDismissDisabled(model.isSending)
        .task {
            await model.load()
            if model.draft != nil {
                recipientIsFocused = true
            }
        }
    }

    private var emailEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Recipient Email")
                    .frame(width: 105, alignment: .trailing)
                TextField("name@example.com", text: $model.recipient)
                    .textFieldStyle(.roundedBorder)
                    .focused($recipientIsFocused)
                    .onSubmit {
                        guard model.canSend else { return }
                        Task { await model.send() }
                    }
            }

            if model.recipientIsTooLong {
                Label("Email address can contain at most 320 characters.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if model.recipientHasInvalidAddress {
                Label("Enter a valid email address.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
                        Label(fileName, systemImage: attachmentSymbol(for: fileName))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
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
