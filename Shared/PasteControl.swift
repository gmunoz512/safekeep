import SwiftUI
import UIKit

/// System paste button (UIPasteControl). Tapping it pastes WITHOUT the "Allow Paste" prompt.
/// It is enabled only when the clipboard holds one of the accepted type identifiers.
struct AudioPasteButton: UIViewRepresentable {
    var onPaste: ([NSItemProvider]) -> Void
    /// Called when the control is touched (even if iOS then delivers nothing).
    var onTouch: () -> Void = {}
    /// Reports the control's enabled state (greyed out = iOS sees no matching type on the clipboard).
    var onEnabledChange: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> PasteHostView {
        let v = PasteHostView(frame: .zero)
        update(v)
        return v
    }

    func updateUIView(_ v: PasteHostView, context: Context) { update(v) }

    private func update(_ v: PasteHostView) {
        v.onPaste = onPaste
        v.onTouch = onTouch
        v.onEnabledChange = onEnabledChange
    }
}

final class PasteHostView: UIView {
    var onPaste: (([NSItemProvider]) -> Void)?
    var onTouch: (() -> Void)?
    var onEnabledChange: ((Bool) -> Void)?
    private let control: UIPasteControl
    private var lastEnabled: Bool?
    private var poll: Timer?

    override init(frame: CGRect) {
        let cfg = UIPasteControl.Configuration()
        cfg.displayMode = .iconAndLabel
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = .systemBlue
        cfg.baseForegroundColor = .white
        control = UIPasteControl(configuration: cfg)
        super.init(frame: frame)
        pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: AddSoundModel.pasteTypeIdentifiers)
        control.target = self
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: centerXAnchor),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            control.heightAnchor.constraint(equalToConstant: 48),
            control.widthAnchor.constraint(equalToConstant: 200),
        ])
        control.addTarget(self, action: #selector(touched), for: .touchUpInside)
        // Taps on a disabled control never reach the control, so catch them here too.
        let tap = UITapGestureRecognizer(target: self, action: #selector(touched))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        poll?.invalidate()
        guard window != nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in Task { @MainActor in self?.reportEnabled() } }
        reportEnabled()
    }

    private func reportEnabled() {
        let e = control.isEnabled
        if e != lastEnabled { lastEnabled = e; onEnabledChange?(e) }
    }

    @objc private func touched() { onTouch?() }

    required init?(coder: NSCoder) { fatalError() }

    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool { true }

    override func paste(itemProviders: [NSItemProvider]) { onPaste?(itemProviders) }
}
