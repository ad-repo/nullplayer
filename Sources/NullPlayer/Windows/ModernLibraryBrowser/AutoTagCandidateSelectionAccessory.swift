import AppKit

final class AutoTagCandidateSelectionAccessory: NSObject {
    let view: NSView

    private let popup: NSPopUpButton
    private let detailsContainer: MetadataFormContainerView
    private let detailsLabel: NSTextField
    private let detailProvider: (Int) -> String

    init(optionTitles: [String], detailProvider: @escaping (Int) -> String) {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 260))
        self.popup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.detailsContainer = MetadataFormContainerView(frame: .zero)
        self.detailsLabel = NSTextField(wrappingLabelWithString: "")
        self.detailProvider = detailProvider
        super.init()

        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItems(withTitles: optionTitles)
        popup.target = self
        popup.action = #selector(selectionChanged)
        view.addSubview(popup)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.verticalLineScroll = 16
        scrollView.verticalPageScroll = 96
        view.addSubview(scrollView)

        detailsContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = detailsContainer

        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        detailsLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsLabel.lineBreakMode = .byWordWrapping
        detailsLabel.maximumNumberOfLines = 0
        detailsContainer.addSubview(detailsLabel)

        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            popup.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 220)
        ])

        NSLayoutConstraint.activate([
            detailsContainer.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            detailsContainer.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            detailsContainer.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            detailsContainer.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor),
            detailsContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            detailsLabel.leadingAnchor.constraint(equalTo: detailsContainer.leadingAnchor, constant: 8),
            detailsLabel.trailingAnchor.constraint(equalTo: detailsContainer.trailingAnchor, constant: -8),
            detailsLabel.topAnchor.constraint(equalTo: detailsContainer.topAnchor, constant: 8),
            detailsContainer.bottomAnchor.constraint(equalTo: detailsLabel.bottomAnchor, constant: 8)
        ])

        updateDetails()
    }

    var selectedIndex: Int {
        let index = popup.indexOfSelectedItem
        return index >= 0 ? index : 0
    }

    @objc private func selectionChanged() {
        updateDetails()
    }

    private func updateDetails() {
        detailsLabel.stringValue = detailProvider(selectedIndex)
        detailsContainer.layoutSubtreeIfNeeded()
        detailsContainer.invalidateIntrinsicContentSize()
        detailsContainer.enclosingScrollView?.contentView.scroll(to: .zero)
        detailsContainer.enclosingScrollView?.reflectScrolledClipView(detailsContainer.enclosingScrollView!.contentView)
    }
}
