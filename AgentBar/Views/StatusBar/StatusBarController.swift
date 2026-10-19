import Cocoa
import SwiftUI
import Combine

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<StackedBarView>?
    private var cancellables: Set<AnyCancellable> = []
    private var setupRetryCount = 0
    private let maxSetupRetries = 10

    private let viewModel: UsageViewModel

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    func setup() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: 90)
        }

        guard let button = statusItem?.button else {
            retrySetup()
            return
        }

        setupRetryCount = 0
        hostingView?.removeFromSuperview()

        let barView = StackedBarView(services: viewModel.usageData)
        let hosting = NSHostingView(rootView: barView)
        hosting.frame = button.bounds.insetBy(dx: 3, dy: 0)
        hosting.autoresizingMask = [.width, .height]
        button.addSubview(hosting)
        self.hostingView = hosting

        if cancellables.isEmpty {
            // Observe ViewModel changes
            viewModel.$usageData
                .combineLatest(viewModel.$lastError)
                .receive(on: RunLoop.main)
                .sink { [weak self] data, error in
                    self?.hostingView?.rootView = StackedBarView(
                        services: data,
                        hasError: error != nil
                    )
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .serviceColorsChanged)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.hostingView?.rootView = StackedBarView(
                        services: self.viewModel.usageData,
                        hasError: self.viewModel.lastError != nil
                    )
                }
                .store(in: &cancellables)
        }

        // Click action — toggle popover
        button.target = self
        button.action = #selector(statusItemClicked)
    }

    private func retrySetup() {
        guard setupRetryCount < maxSetupRetries else { return }
        setupRetryCount += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.setup()
        }
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        PopoverController.shared.toggle(relativeTo: button, viewModel: viewModel)
    }
}
