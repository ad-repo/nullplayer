import AppKit
import CAvsCore

/// The right pane of the AVS editor: one component's parameters, as controls built from libavs's
/// own metadata (`avs_parameter_info`), so every effect is editable without code of its own.
///
/// | Type | Control |
/// |---|---|
/// | bool | checkbox |
/// | int, float | slider and field (field only when unbounded) |
/// | color | colour well |
/// | string | monospaced text view (EEL code, file paths) |
/// | select, resource | popup |
/// | list | one box per element, with remove / move, and an add button |
/// | action | button |
///
/// Every libavs call goes through `AvsCore.withHandle`. A value write shows in the next frame; a
/// write that changes structure (a list element, an action) rebuilds the pane.
final class AvsParameterInspector: NSView {
    private let core: AvsCore
    private let stack = NSStackView()
    private var component: AVS_Component_Handle = 0
    /// Controls keep their writer here, keyed by the control, so actions stay one selector each.
    private var writers: [ObjectIdentifier: (NSControl) -> Void] = [:]
    private var codeWriters: [ObjectIdentifier: (String) -> Void] = [:]

    init(core: AvsCore) {
        self.core = core
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    func show(_ component: AVS_Component_Handle) {
        self.component = component
        rebuild()
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        writers = [:]
        codeWriters = [:]
        guard component != 0 else { return }
        let (info, parameters) = core.withHandle { handle -> (AVS_Effect_Info, [AVS_Parameter_Handle]) in
            var info = AVS_Effect_Info()
            guard avs_effect_info(handle, avs_component_effect(handle, component), &info) else { return (info, []) }
            return (info, Array(UnsafeBufferPointer(start: info.parameters, count: Int(info.parameters_length))))
        }
        guard let name = info.name else { return }
        let title = NSTextField(labelWithString: String(cString: name))
        title.font = .boldSystemFont(ofSize: 14)
        stack.addArrangedSubview(title)
        if let help = info.help, help.pointee != 0 {
            let label = NSTextField(wrappingLabelWithString: String(cString: help))
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = 420
            stack.addArrangedSubview(label)
        }
        for parameter in parameters { addControls(for: parameter, path: [], to: stack) }
    }

    // MARK: - Controls

    private func parameterInfo(_ parameter: AVS_Parameter_Handle) -> AVS_Parameter_Info? {
        core.withHandle { handle in
            var info = AVS_Parameter_Info()
            return avs_parameter_info(handle, avs_component_effect(handle, component), parameter, &info) ? info : nil
        }
    }

    /// Runs `body` with the handle and a list path in libavs's (depth, indices) form.
    private func call<T>(_ path: [Int64], _ body: (AVS_Handle, UInt32, UnsafeMutablePointer<Int64>?) -> T) -> T {
        var indices = path
        return core.withHandle { handle in
            indices.withUnsafeMutableBufferPointer { body(handle, UInt32(path.count), $0.baseAddress) }
        }
    }

    private func addControls(for parameter: AVS_Parameter_Handle, path: [Int64], to container: NSStackView) {
        guard let info = parameterInfo(parameter) else { return }
        let name = info.name.map { String(cString: $0) } ?? "?"
        let component = self.component
        switch info.type {
        case AVS_PARAM_BOOL:
            let value = call(path) { avs_parameter_get_bool($0, component, parameter, $1, $2) }
            let box = NSButton(checkboxWithTitle: name, target: self, action: #selector(controlChanged(_:)))
            box.state = value ? .on : .off
            register(box) { [unowned self] control in
                _ = call(path) { avs_parameter_set_bool($0, component, parameter, (control as! NSButton).state == .on, $1, $2) }
            }
            container.addArrangedSubview(box)

        case AVS_PARAM_INT, AVS_PARAM_FLOAT:
            let isInt = info.type == AVS_PARAM_INT
            let value = isInt
                ? Double(call(path) { avs_parameter_get_int($0, component, parameter, $1, $2) })
                : call(path) { avs_parameter_get_float($0, component, parameter, $1, $2) }
            let (lower, upper) = isInt ? (Double(info.int_min), Double(info.int_max)) : (info.float_min, info.float_max)
            let field = NSTextField(string: isInt ? String(Int64(value)) : String(format: "%.4g", value))
            field.widthAnchor.constraint(equalToConstant: 80).isActive = true
            var views: [NSView] = [NSTextField(labelWithString: name)]
            var slider: NSSlider?
            if lower < upper, upper - lower < 1e9 {
                let s = NSSlider(value: value, minValue: lower, maxValue: upper, target: self, action: #selector(controlChanged(_:)))
                s.widthAnchor.constraint(equalToConstant: 220).isActive = true
                s.isContinuous = true
                views.append(s)
                slider = s
            }
            views.append(field)
            field.target = self
            field.action = #selector(controlChanged(_:))
            let write: (Double) -> Void = { [unowned self] newValue in
                let stored: Double = call(path) { handle, depth, indices in
                    if isInt {
                        _ = avs_parameter_set_int(handle, component, parameter, Int64(newValue.rounded()), depth, indices)
                        return Double(avs_parameter_get_int(handle, component, parameter, depth, indices))
                    }
                    _ = avs_parameter_set_float(handle, component, parameter, newValue, depth, indices)
                    return avs_parameter_get_float(handle, component, parameter, depth, indices)
                }
                slider?.doubleValue = stored
                field.stringValue = isInt ? String(Int64(stored)) : String(format: "%.4g", stored)
            }
            register(field) { write(($0 as! NSTextField).doubleValue) }
            if let slider { register(slider) { write(($0 as! NSSlider).doubleValue) } }
            container.addArrangedSubview(NSStackView(views: views))

        case AVS_PARAM_COLOR:
            let rgb = call(path) { avs_parameter_get_color($0, component, parameter, $1, $2) }
            let well = NSColorWell(style: .minimal)
            well.color = NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                                 blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
            well.target = self
            well.action = #selector(controlChanged(_:))
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            register(well) { [unowned self] control in
                // Colours are the framebuffer's 0x00RRGGBB.
                guard let c = (control as! NSColorWell).color.usingColorSpace(.sRGB) else { return }
                let value = UInt64((c.redComponent * 255).rounded()) << 16
                    | UInt64((c.greenComponent * 255).rounded()) << 8 | UInt64((c.blueComponent * 255).rounded())
                _ = call(path) { avs_parameter_set_color($0, component, parameter, value, $1, $2) }
            }
            container.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: name), well]))

        case AVS_PARAM_STRING:
            let text = call(path) { avs_parameter_get_string($0, component, parameter, $1, $2) }.map { String(cString: $0) } ?? ""
            container.addArrangedSubview(NSTextField(labelWithString: name))
            container.addArrangedSubview(codeEditor(text) { [unowned self] newText in
                // An EEL string recompiles under the core lock: one frame's stall at most.
                _ = call(path) { avs_parameter_set_string($0, component, parameter, newText, $1, $2) }
            })

        case AVS_PARAM_SELECT, AVS_PARAM_RESOURCE:
            let options = (0..<Int(max(0, info.options_length))).compactMap { info.options?[$0].map { String(cString: $0) } }
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: options)
            popup.target = self
            popup.action = #selector(controlChanged(_:))
            if info.type == AVS_PARAM_SELECT {
                let index = Int(call(path) { avs_parameter_get_int($0, component, parameter, $1, $2) })
                if options.indices.contains(index) { popup.selectItem(at: index) } else { popup.select(nil) }
                register(popup) { [unowned self] control in
                    _ = call(path) { avs_parameter_set_int($0, component, parameter, Int64((control as! NSPopUpButton).indexOfSelectedItem), $1, $2) }
                }
            } else {
                let current = call(path) { avs_parameter_get_string($0, component, parameter, $1, $2) }.map { String(cString: $0) } ?? ""
                if !options.contains(current), !current.isEmpty { popup.addItem(withTitle: current) }
                popup.selectItem(withTitle: current)
                register(popup) { [unowned self] control in
                    guard let title = (control as! NSPopUpButton).titleOfSelectedItem else { return }
                    _ = call(path) { avs_parameter_set_string($0, component, parameter, title, $1, $2) }
                }
            }
            container.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: name), popup]))

        case AVS_PARAM_ACTION:
            let button = NSButton(title: name, target: self, action: #selector(controlChanged(_:)))
            register(button) { [unowned self] _ in
                _ = call(path) { avs_parameter_run_action($0, component, parameter, $1, $2) }
                rebuild()
            }
            container.addArrangedSubview(button)

        case AVS_PARAM_LIST:
            addList(info, parameter: parameter, name: name, path: path, to: container)

        default:
            // The read-only arrays (int / float / colour) are effect output, not settings.
            break
        }
    }

    private func addList(_ info: AVS_Parameter_Info, parameter: AVS_Parameter_Handle, name: String,
                         path: [Int64], to container: NSStackView) {
        let component = self.component
        let children = Array(UnsafeBufferPointer(start: info.children, count: Int(info.children_length)))
        let count = call(path) { avs_parameter_list_length($0, component, parameter, $1, $2) }
        for index in 0..<count {
            let box = NSStackView()
            box.orientation = .vertical
            box.alignment = .leading
            box.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 6)
            box.wantsLayer = true
            box.layer?.borderWidth = 1
            box.layer?.borderColor = NSColor.separatorColor.cgColor
            box.layer?.cornerRadius = 4
            let header = NSStackView(views: [NSTextField(labelWithString: "\(name) \(index + 1)")])
            for (title, move) in [("↑", -1), ("↓", 1)] where (0..<count).contains(index + Int64(move)) {
                let button = NSButton(title: title, target: self, action: #selector(controlChanged(_:)))
                register(button) { [unowned self] _ in
                    _ = call(path) { avs_parameter_list_element_move($0, component, parameter, index, index + Int64(move), $1, $2) }
                    rebuild()
                }
                header.addArrangedSubview(button)
            }
            if count > Int64(info.children_length_min) {
                let remove = NSButton(title: "Remove", target: self, action: #selector(controlChanged(_:)))
                register(remove) { [unowned self] _ in
                    _ = call(path) { avs_parameter_list_element_remove($0, component, parameter, index, $1, $2) }
                    rebuild()
                }
                header.addArrangedSubview(remove)
            }
            box.addArrangedSubview(header)
            for child in children { addControls(for: child, path: path + [index], to: box) }
            container.addArrangedSubview(box)
        }
        if info.children_length_max == 0 || count < Int64(info.children_length_max) {
            let add = NSButton(title: "Add \(name)", target: self, action: #selector(controlChanged(_:)))
            register(add) { [unowned self] _ in
                _ = call(path) { avs_parameter_list_element_add($0, component, parameter, .max, 0, nil, $1, $2) }
                rebuild()
            }
            container.addArrangedSubview(add)
        }
    }

    private func register(_ control: NSControl, _ write: @escaping (NSControl) -> Void) {
        writers[ObjectIdentifier(control)] = write
    }

    @objc private func controlChanged(_ sender: NSControl) {
        writers[ObjectIdentifier(sender)]?(sender)
    }

    // MARK: - Code

    /// A monospaced editor that writes back when it loses focus, not per keystroke: every EEL
    /// write recompiles.
    private func codeEditor(_ text: String, write: @escaping (String) -> Void) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.string = text
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.delegate = self
        codeWriters[ObjectIdentifier(view)] = write
        scroll.borderType = .bezelBorder
        let lines = max(2, min(10, text.split(separator: "\n", omittingEmptySubsequences: false).count + 1))
        scroll.heightAnchor.constraint(equalToConstant: CGFloat(lines) * 15 + 8).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 440).isActive = true
        return scroll
    }
}

extension AvsParameterInspector: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        guard let view = notification.object as? NSTextView else { return }
        codeWriters[ObjectIdentifier(view)]?(view.string)
    }
}
