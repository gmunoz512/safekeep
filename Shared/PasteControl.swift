import SwiftUI
import UIKit

/// System paste button (UIPasteControl). Tapping it pastes WITHOUT the "Allow Paste" prompt.
/// It is enabled only when the clipboard holds one of the accepted type identifiers.
struct AudioPasteButton: UIViewRepresentable {
    var onPaste: ([NSItemProvider]) -> Void

    func makeUIView(context: Context) -> PasteHostView {
        let v = PasteHostView(frame: .zero)
        v.onPaste = onPaste
        return v
    }

    func updateUIView(_ v: PasteHostView, context: Context) { v.onPaste = onPaste }
}

final class PasteHostView: UIView {
    var onPaste: (([NSItemProvider]) -> Void)?
    private let control: UIPasteControl

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
    }

    required init?(coder: NSCoder) { fatalError() }

    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool { true }

    override func paste(itemProviders: [NSItemProvider]) { onPaste?(itemProviders) }
}
