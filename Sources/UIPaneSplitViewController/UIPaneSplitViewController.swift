//
//  UIPaneSplitViewController.swift
//  NSToolbarTranslationResearch
//
//  Created by yosshi4486 on 2022/08/14.
//

import UIKit

/// A container view controller for importing a mac app's pane split view pattern.
///
/// Although UIKit provide `UISplitViewController`, it only consider primary-supplementary-secondary navigation like a Mail.app.
/// Since Apple add functionalities for desktop class iPad in iPadOS16, I think it is time to release a navigator-content-inspector split view pattern.
/// This view controller provides the functionalities for an iOS/iPadOS environment which the horizontalSizeClass is regular.
///
/// # NavigationController Behavior
/// The navigation and its bar behavior is up to your navigation stack. I'll show recommended ways of composing a navigation stack bellow:
///
/// ## Unified Pattern
/// This pattern can represent a unified navigation bar, but you have to interact with the paneSplitViewController's navigation item instead of accessing a pane's navigation item. You may use opaque styled navigation appearance for scroll edge appearance. This is especially suitable for a document-centric app.
///
/// ```
/// UINavigationController
///   - UIPaneSplitViewController
///     - content
///     - inspector
/// ```
///
/// This derived pattern is good for app that provides a content navigation in the content pane, although you have to manage content pane navigations (go forward / go backward) by yourself.
///
/// ```
/// UINavigationController
///   - UIPaneSplitViewController
///     - UINavitaionController
///       - content
///     - inspector
/// ```
///
/// If you want to use the pane split interface with a search controller, a inline styled search bar (available at iPadOS16 or later) is good for this pattern.
/// https://developer.apple.com/documentation/uikit/uinavigationitem/searchbarplacement/inline
///
/// ## Separated Pattern
/// This pattern can represent a separated navigation bar. You can interact with each view controller's navigation item. Don't push in an inspector, because pusing a view stack in sidebars makes the app complicate and the user confuse.
///
/// ```
/// UIPaneSplitViewController
///   - UINavigationController
///     - content
///   - UINavigationController
///     - inspector
/// ```
///
/// # Combining with UISplitViewController
/// You can use a `UIPaneSplitViewController` with a `UISplitViewController`. The pane split view controller has to be a secondary column of the split view controller.
///
/// IMPORTANT:
/// You should only use this pane split view in a horizontal regular. You should use a `UISplitViewController.Column.compact` column in a compact environment. Although it’s possible to use `UIPaneSplitViewController` in both horizontal environment and change the behaviors, but it makes complicated view hierarchies and makes bugs in my experience.
///
/// A recommended hierarchy's example is bellow:
///
/// ```
/// - UISplitViewController
///
///   - primary: SidebarViewController
///
///   - secondary: UIPaneSplitViewController
///     - content: ContentViewController
///     - inspector: InspectorViewController
///
///   - compact: UINavigationController
///       - root: ContentViewController
///
/// ```
///
/// # Horizontal Compact or Regular
/// The inspector pane and the toggle item are automatically hidden when the `traitCollection.horizontalSizeClass == .compact`, otherwise these are shown.
///
/// This behavior is useful when you use a standalone `UIPaneSplitViewController` without a `UISplitViewController`.
///
/// # Subclassing Note
/// If you choose using a unified pattern, subclassing `UIPaneSplitViewController` is a good place for providing toolbar items and their actions (e.g.) UIBarButtonItem, UIBarButtonItemGroup
///
/// - Note:
/// Pane's APIs in keep consistency with `UISplitViewController`'s column API interfaces. Please check it also.
/// https://developer.apple.com/documentation/uikit/uisplitviewcontroller
///
/// For distincting differences between UIKit and SwiftUI components, I have a policy adding "UI" prefixes to UIKit's components.
open class UIPaneSplitViewController: UIViewController {

    /// Constants that describe the pane within the pane split view interface.
    public enum Pane: Int {

        // TODO: Support navigator pain? but I suppose it has to consider about over, display and beside display styles like a UISplitViewController. The implementations seems tedious 😩

        /// The pane for the content view controller.
        case content

        /// The pane for the inspector view controller.
        case inspector

    }

    /// Posted when an inspector is about to being shown.
    public static let inspectorWillShowNotificationName: Notification.Name = .init("inspectorWillShowNotification")

    /// Posted when an inspector is about to being hidden.
    public static let inspectorWillHideNotificationName: Notification.Name = .init("inspectorWillHideNotification")

    /// Posted when an inspector is just shown.
    public static let inspectorDidShowNotificationName: Notification.Name = .init("inspectorDidShowNotification")

    /// Posted when an inspector is just hidden.
    public static let inspectorDidHideNotificationName: Notification.Name = .init("inspectorDidShowNotification")

    /// Returns a new key command that toggles an inspector.
    ///
    /// You can use this key command in your menu building code. In iOS15 or later, `UIResponder.keyCommands` is not recommended way for implementing a key command.
    /// Please check detailes in https://developer.apple.com/videos/play/wwdc2021/10057/ 17:00~19:00
    ///
    /// Uses the key command in `AppDelegate.buildMenu`like bellow:
    ///
    /// ```
    /// override func buildMenu(with builder: UIMenuBuilder) {
    ///     guard builder.system == .main else {
    ///         return
    ///     }
    ///
    ///     let paneViewMenu = UIMenu(options: .displayInline, children: [
    ///         UIPaneSplitViewController.toggleInspectorKeyCommand
    ///     ])
    ///
    ///     builder.insertChild(paneViewMenu, atEndOfMenu: .view)
    ///
    /// }
    /// ```
    public static var toggleInspectorKeyCommand: UIKeyCommand {

        // The modifierFlags keep same with UISplitViewController's toggle sidebar keycommand.
        return UIKeyCommand(title: String(localized: "Hide Inspector"), action: #selector(UIPaneSplitViewController.toggleInspector), input: "i", modifierFlags: [.command, .control])
    }

    /// Returns a new bar button item that toggles.
    ///
    /// This API is very similar to `UIViewController.editButtonItem`, so you can use this in that way. For example bellow:
    ///
    /// ```
    /// override func viewDidLoad() {
    ///    super.viewDidLoad()
    ///    navigationItem.trailingItemGroups = [paneSplitViewController!.toggleInspectorButtonItem.creatingFixedGroup()]
    /// }
    /// ```
    ///
    /// For best user experience, hides the toggle button when the `traitCollection.horizontalSizeClass` is `.compact`.
    public var toggleInspectorButtonItem: UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(UIPaneSplitViewController.toggleInspector))
        return item
    }

    /// The boolean value indicating whether this view controller automatically handles the inspector's toggle item behavior.
    public var preferAutomaticInspectorToggleBehavior: Bool = true {

        didSet {
            if preferAutomaticInspectorToggleBehavior {
                navigationItem.trailingItemGroups.append(_toggleInspectorButtonItem.creatingFixedGroup())
            } else {
                navigationItem.trailingItemGroups.removeAll(where: { $0.barButtonItems.first == _toggleInspectorButtonItem })
            }
        }

    }

    /// The preferred inspector width value.
    ///
    /// The content pane width fraction is computed as (view.bounds.width - preferredInspectorWidth - dividerWidth).
    open var preferredInspectorWidth: CGFloat = 300 {

        didSet {
            inspectorPaneContainerViewWidthConstraint.constant = preferredInspectorWidth
        }

    }

    /// The divider's color.
    open var dividerColor: UIColor = .opaqueSeparator {

        didSet {
            divider.backgroundColor = dividerColor
        }

    }

    /// The divider's width.
    open var dividerWidth: CGFloat = 0.5 {

        didSet {
            dividerWidthConstraint.constant = dividerWidth
        }

    }

    /// The array of view controllers the pane split view controller manages.
    ///
    /// When the pane split view interface is expanded, this property contains two view controllers, otherwise this property contains only one view controller.
    open var viewControllers: [UIViewController] {

        if isShowingInspector {
            return [contentViewController, inspectorViewController].compactMap({ $0 })
        } else {
            return [contentViewController].compactMap({ $0 })
        }

    }

    /// The boolean value indicating whether the inspactor pane is shown.
    open var isShowingInspector: Bool {
        return !inspectorPaneContainerView.isHidden
    }

    private var _toggleInspectorButtonItem: UIBarButtonItem!

    private var contentViewController: UIViewController?

    private var inspectorViewController: UIViewController?

    private let panesContainerStackView: UIStackView = {

        let view = UIStackView(frame: .zero)
        view.alignment = .bottom
        view.distribution = .fill
        view.axis = .horizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        return view

    }()

    private let contentPaneContainerView: UIView = {

        let view = UIView(frame: .zero)
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view

    }()

    private let inspectorPaneContainerView: UIView = {

        let view = UIView(frame: .zero)
        view.backgroundColor = .systemGroupedBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view

    }()

    private let divider: UIView = {

        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .opaqueSeparator
        return view

    }()

    private var inspectorPaneContainerViewWidthConstraint: NSLayoutConstraint!

    private var dividerWidthConstraint: NSLayoutConstraint!

    open override func viewDidLoad() {

        super.viewDidLoad()

        setupViews()

        _toggleInspectorButtonItem = toggleInspectorButtonItem
        _toggleInspectorButtonItem.accessibilityLabel = String(localized: "Hide Inspector")

        if preferAutomaticInspectorToggleBehavior {
            navigationItem.trailingItemGroups.insert(_toggleInspectorButtonItem.creatingFixedGroup(), at: 0)
        }

        configureInspectorStateFollowingCurrentHorizontalSizeClass()

    }

    // Catalyst related documents well describe about shortcut actions.
    // The article is [here](https://developer.apple.com/documentation/uikit/uicommand/adding_menus_and_shortcuts_to_the_menu_bar_and_user_interface)

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {

        guard preferAutomaticInspectorToggleBehavior, traitCollection.horizontalSizeClass == .regular else {
            return super.canPerformAction(action, withSender: sender)
        }

        if action == #selector(toggleInspector) {
            return true
        }

        return super.canPerformAction(action, withSender: sender)

    }

    open override func validate(_ command: UICommand) {

        if command.action == #selector(toggleInspector) {
            if isShowingInspector {
                command.title = String(localized: "Hide Inspector")
            } else {
                command.title = String(localized: "Show Inspector")
            }
        }

        super.validate(command)

    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if preferAutomaticInspectorToggleBehavior {
            configureInspectorStateFollowingCurrentHorizontalSizeClass()
        }

    }

    /// Presents the provided view controller in the specified pale of the pane split view interface.
    ///
    /// - Parameters:
    ///   - vc: The child view controller to associate with the provided pane of the pane split view interface.
    ///   - pane: The corresponding pane of the pane split interface. See ``UIPaneSplitViewController.Pane`` for values.
    open func setViewController(_ vc: UIViewController?, for pane: UIPaneSplitViewController.Pane) {

        // The official article shows how to implement a custom container in [here](https://developer.apple.com/documentation/uikit/view_controllers/creating_a_custom_container_view_controller)

        switch pane {
        case .content:

            if let previousContentViewController = contentViewController {
                previousContentViewController.willMove(toParent: nil)
                previousContentViewController.view.removeFromSuperview()
                previousContentViewController.removeFromParent()
            }

            if let vc {
                addChild(vc)
                contentPaneContainerView.addSubview(vc.view)
                vc.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate(vc.view.makeFitConstraints(equalToView: contentPaneContainerView))
                vc.didMove(toParent: self)

                // Avoid displaying double navigationBars.
                if let childNav = vc as? UINavigationController {
                    childNav.navigationBar.isHidden = true
                }
            }

            contentViewController = vc

        case .inspector:

            if let previousInspectorViewController = inspectorViewController {
                previousInspectorViewController.willMove(toParent: nil)
                previousInspectorViewController.view.removeFromSuperview()
                previousInspectorViewController.removeFromParent()
            }

            if let vc {
                addChild(vc)
                inspectorPaneContainerView.addSubview(vc.view)
                vc.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate(vc.view.makeFitConstraints(equalToView: inspectorPaneContainerView))
                vc.didMove(toParent: self)

                // Avoid displaying double navigationBars.
                if let childNav = vc as? UINavigationController {
                    childNav.navigationBar.isHidden = true
                }

            }

            inspectorViewController = vc
        }

    }

    /// Returns the view controller associated with the specified pane of the pane split view interface.
    ///
    /// - Parameters:
    ///   - pane: The corresponding pane of the pane split view interface. See ``UIPaneSplitViewController.Pane`` for values.
    ///
    /// - Returns: The corresponding child view controller object.
    open func viewController(for pane: UIPaneSplitViewController.Pane) -> UIViewController? {

        switch pane {

        case .content:
            return contentViewController

        case .inspector:
            return inspectorViewController

        }

    }

    /// Presents the view controller in the given pane of the pane split view interface.
    ///
    /// - Parameter pane: The pane that the pane split view controller shows. `.content`  pane is ignored, because the content pane should always be shown.
    open func show(_ pane: UIPaneSplitViewController.Pane) {

        switch pane {

        case .inspector:

            guard let inspectorViewController else {
                return
            }

            NotificationCenter.default.post(name: UIPaneSplitViewController.inspectorWillShowNotificationName, object: nil)

            _toggleInspectorButtonItem.accessibilityLabel = String(localized: "Hide Inspector")

            // This is a technique for showing/hiding a view controller in a custom container.
            // Repeats adding and removing a view immediately makes a bug that fails presenting the view.
            // These code only add a view controller, while the code doesn't add any view and constraints.

            addChild(inspectorViewController) // This automatically calls willMove(toParent:)
            inspectorViewController.didMove(toParent: self)

            // Use UIView.perform rather than using UIView.animate, because UIView.perform provides a UIKit's standard animation behavior that makes us feel at home, while UIView.animate provides more customizable animation parameters.
            UIView.perform(.delete, on: [], options: [.beginFromCurrentState], animations: { [unowned self] in
                divider.backgroundColor = dividerColor
                inspectorPaneContainerView.isHidden = false
            }, completion: { finish in
                if finish {
                    NotificationCenter.default.post(name: UIPaneSplitViewController.inspectorDidShowNotificationName, object: nil)
                }
            })

        case .content:
            return

        }

    }

    /// Dismiss the view controller in the given pane of the pane split view interface.
    ///
    /// - Parameter pane: The pane that the pane split view controller hides. `.content`  pane is ignored, because the content pane should always be shown.
    open func hide(_ pane: UIPaneSplitViewController.Pane) {

        switch pane {
        case .inspector:

            guard let inspectorViewController else {
                return
            }

            NotificationCenter.default.post(name: UIPaneSplitViewController.inspectorWillHideNotificationName, object: nil)

            _toggleInspectorButtonItem.accessibilityLabel = String(localized: "Show Inspector")

            // This is a technique for showing/hiding a view controller in a custom container.
            // Repeats adding and removing a view immediately makes a bug that fails presenting the view.
            // These code only remove a view controller, while the code doesn't remove any view and constraints.

            inspectorViewController.willMove(toParent: nil)
            inspectorViewController.removeFromParent() // This automatically calls didMove(toParent:)

            // Use UIView.perform rather than using UIView.animate, because UIView.perform provides a UIKit's standard animation behavior that makes us feel at home, while UIView.animate provides more customizable animation parameters.
            UIView.perform(.delete, on: [], options: [.beginFromCurrentState], animations: { [unowned self] in
                divider.backgroundColor = .clear
                inspectorPaneContainerView.isHidden = true
            }, completion: { finish in

                if finish {
                    NotificationCenter.default.post(name: UIPaneSplitViewController.inspectorDidHideNotificationName, object: nil)
                }

            })

        case .content:
            return

        }

    }

    /// Toggles the inspector pane hidden state.
    @objc func toggleInspector(_ sender: Any?) {

        if isShowingInspector {
            hide(.inspector)
        } else {
            show(.inspector)
        }

    }

    private func configureInspectorStateFollowingCurrentHorizontalSizeClass() {

        if traitCollection.horizontalSizeClass == .regular {
            UIView.performWithoutAnimation {
                show(.inspector)
                _toggleInspectorButtonItem.isHidden = false
            }
        } else {
            UIView.performWithoutAnimation {
                hide(.inspector)
                _toggleInspectorButtonItem.isHidden = true
            }
        }

    }


}

extension UIViewController {

    /// The nearest ancestor in the view controller hierarchy that is a pane split view controller.
    public var paneSplitViewController: UIPaneSplitViewController? {
        var aParent: UIViewController? = parent
        while aParent != nil {
            if let destination = aParent as? UIPaneSplitViewController {
                return destination
            }
            aParent = aParent?.parent
        }
        return nil
    }

}

// MARK: - Private Methods

extension UIPaneSplitViewController {

    private func setupViews() {

        view.addSubview(panesContainerStackView)
        panesContainerStackView.addArrangedSubview(contentPaneContainerView)
        panesContainerStackView.addArrangedSubview(divider)
        panesContainerStackView.addArrangedSubview(inspectorPaneContainerView)

        inspectorPaneContainerViewWidthConstraint = inspectorPaneContainerView.widthAnchor.constraint(equalToConstant: preferredInspectorWidth)
        inspectorPaneContainerViewWidthConstraint.priority = .defaultHigh

        // This ensures to avoid too big inspector pane.
        let inspectorPaneMaximumWidthConstraint = inspectorPaneContainerView.widthAnchor.constraint(lessThanOrEqualTo: panesContainerStackView.widthAnchor, multiplier: 0.5)
        inspectorPaneMaximumWidthConstraint.priority = .required

        dividerWidthConstraint = divider.widthAnchor.constraint(equalToConstant: dividerWidth)

        NSLayoutConstraint.activate(

            panesContainerStackView.makeFitConstraints(equalToView: view) +

            [
                contentPaneContainerView.heightAnchor.constraint(equalTo: panesContainerStackView.heightAnchor),
                inspectorPaneContainerView.heightAnchor.constraint(equalTo: panesContainerStackView.heightAnchor),
                divider.heightAnchor.constraint(equalTo: panesContainerStackView.heightAnchor),
                inspectorPaneContainerViewWidthConstraint,
                inspectorPaneMaximumWidthConstraint,
                dividerWidthConstraint
            ]

        )

    }

}

extension UIView {

    func makeFitConstraints(equalToView view: UIView) -> [NSLayoutConstraint] {

        [
            topAnchor.constraint(equalTo: view.topAnchor),
            leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]

    }

}

