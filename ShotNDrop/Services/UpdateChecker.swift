import Foundation
import AppKit

struct ReleaseUpdate: Equatable, Sendable {
    let version: String
    let downloadURL: URL
}

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(currentVersion: String)
    case updateAvailable(ReleaseUpdate)
}

enum UpdateCheckerError: LocalizedError {
    case invalidResponse
    case missingReleaseData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The release service returned an invalid response."
        case .missingReleaseData:
            return "The latest release did not include the required download link."
        }
    }
}

struct UpdateChecker: Sendable {
    static let releasesURL = URL(string: "https://api.github.com/repos/ryanleonduty/shotndrop/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/ryanleonduty/shotndrop/releases/latest")!

    private let session: URLSession
    private let releasesURL: URL
    private let currentVersion: String

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
        releasesURL: URL = UpdateChecker.releasesURL,
        session: URLSession = .shared
    ) {
        self.currentVersion = currentVersion
        self.releasesURL = releasesURL
        self.session = session
    }

    func check() async throws -> UpdateCheckResult {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ShotNDrop Update Checker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckerError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let tagName = release.tagName,
              let htmlURL = URL(string: release.htmlURL),
              htmlURL.scheme == "https" else {
            throw UpdateCheckerError.missingReleaseData
        }

        let version = Self.normalizedVersion(tagName)
        guard !version.isEmpty else { throw UpdateCheckerError.missingReleaseData }

        if Self.isVersion(version, newerThan: currentVersion) {
            return .updateAvailable(ReleaseUpdate(version: version, downloadURL: htmlURL))
        }
        return .upToDate(currentVersion: currentVersion)
    }

    static func normalizedVersion(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^v", with: "", options: .regularExpression)
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        normalizedVersion(candidate).compare(
            normalizedVersion(current),
            options: [.numeric, .caseInsensitive]
        ) == .orderedDescending
    }

    private struct GitHubRelease: Decodable {
        let tagName: String?
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}

@MainActor
public final class UpdateCoordinator: NSObject, NSWindowDelegate {
    private let checker: UpdateChecker
    private var checkTask: Task<Void, Never>?
    private var activeAlert: NSAlert?
    private var alertCompletion: ((NSApplication.ModalResponse) -> Void)?

    public override init() {
        self.checker = UpdateChecker()
        super.init()
    }

    init(checker: UpdateChecker) {
        self.checker = checker
        super.init()
    }

    func checkForUpdates(from parentWindow: NSWindow?) {
        guard let parentWindow, checkTask == nil, activeAlert == nil else { return }

        checkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await checker.check()
                guard !Task.isCancelled else { return }
                checkTask = nil
                present(result, from: parentWindow)
            } catch is CancellationError {
                checkTask = nil
            } catch {
                checkTask = nil
                present(error: error, from: parentWindow)
            }
        }
    }

    private func present(_ result: UpdateCheckResult, from parentWindow: NSWindow) {
        switch result {
        case .upToDate(let currentVersion):
            presentAlert(
                title: "ShotNDrop is up to date",
                message: "You’re running version \(currentVersion).",
                from: parentWindow
            )
        case .updateAvailable(let update):
            let alert = NSAlert()
            alert.messageText = "ShotNDrop \(update.version) is available"
            alert.informativeText = "Download the latest release from GitHub?"
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Not Now")
            present(alert, from: parentWindow) { response in
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(update.downloadURL)
                }
            }
        }
    }

    private func present(error: Error, from parentWindow: NSWindow) {
        presentAlert(
            title: "Couldn’t check for updates",
            message: error.localizedDescription,
            from: parentWindow
        )
    }

    private func presentAlert(
        title: String,
        message: String,
        from parentWindow: NSWindow
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        present(alert, from: parentWindow, completion: nil)
    }

    private func present(
        _ alert: NSAlert,
        from parentWindow: NSWindow,
        completion: ((NSApplication.ModalResponse) -> Void)?
    ) {
        activeAlert = alert
        alertCompletion = completion
        alert.window.delegate = self
        for button in alert.buttons {
            button.target = self
            button.action = #selector(alertButtonClicked(_:))
        }
        alert.window.level = .floating
        alert.window.makeKeyAndOrderFront(nil)
        parentWindow.orderFront(nil)
    }

    @objc private func alertButtonClicked(_ sender: NSButton) {
        let response: NSApplication.ModalResponse = sender === activeAlert?.buttons.first
            ? .alertFirstButtonReturn
            : .alertSecondButtonReturn
        alertCompletion?(response)
        closeActiveAlert()
    }

    public func windowWillClose(_ notification: Notification) {
        closeActiveAlert()
    }

    private func closeActiveAlert() {
        activeAlert?.window.orderOut(nil)
        activeAlert = nil
        alertCompletion = nil
    }
}
