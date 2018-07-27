public enum NavigationBarDisplayType {
    case backVisible
    case largeTitle
    case modal
}
@objc(WMFNavigationBar)
public class NavigationBar: SetupView, FakeProgressReceiving, FakeProgressDelegate {
    fileprivate let statusBarUnderlay: UIView =  UIView()
    private let titleBar: UIToolbar = UIToolbar()
    private let bar: UINavigationBar = UINavigationBar()
    private let underBarView: UIView = UIView() // this is always visible below the navigation bar
    private let extendedView: UIView = UIView()
    fileprivate let shadow: UIView = UIView()
    fileprivate let progressView: UIProgressView = UIProgressView()
    fileprivate let backgroundView: UIView = UIView()
    public var underBarViewPercentHiddenForShowingTitle: CGFloat?
    public var title: String?
    
    public var isShadowHidingEnabled: Bool = false // turn on/off shadow alpha adjusment
    public var isTitleShrinkingEnabled: Bool = false
    public var isInteractiveHidingEnabled: Bool = true // turn on/off any interactive adjustment of bar or view visibility
    @objc public var isShadowBelowUnderBarView: Bool = false {
        didSet {
            updateShadowConstraints()
        }
    }
    
    @objc public var isTopSpacingHidingEnabled: Bool = true
    @objc public var isBarHidingEnabled: Bool = true
    @objc public var isUnderBarViewHidingEnabled: Bool = false
    @objc public var isExtendedViewHidingEnabled: Bool = false
    @objc public var isExtendedViewFadingEnabled: Bool = true // fade out extended view as it hides
    public var shouldTransformUnderBarViewWithBar: Bool = false // hide/show underbar view when bar is hidden/shown // TODO: change this stupid name
    
    private var theme = Theme.standard
    
    /// back button presses will be forwarded to this nav controller
    @objc public weak var delegate: UIViewController? {
        didSet {
            updateNavigationItems()
        }
    }
    
    public var displayType: NavigationBarDisplayType = .backVisible {
        didSet {
            isTitleShrinkingEnabled = displayType == .largeTitle
            updateTitleBarConstraints()
            updateNavigationItems()
        }
    }
    
    @objc public func updateNavigationItems() {
        var items: [UINavigationItem] = []
        if displayType == .backVisible {
            if let vc = delegate, let nc = vc.navigationController, let index = nc.viewControllers.index(of: vc), index > 0 {
                items.append(nc.viewControllers[index - 1].navigationItem)
            } else {
                items.append(UINavigationItem())
            }
        }
        
        if let item = delegate?.navigationItem {
            items.append(item)
        }
        
        if displayType == .largeTitle, let navigationItem = items.last {
            configureTitleBar(with: navigationItem)
        } else {
            bar.setItems(items, animated: false)
        }
        apply(theme: theme)
    }
    
    private var cachedTitleViewItem: UIBarButtonItem?
    private var titleView: UIView?
    
    private func configureTitleBar(with navigationItem: UINavigationItem) {
        var titleBarItems: [UIBarButtonItem] = []
        if let titleView = navigationItem.titleView {
            if let cachedTitleViewItem = cachedTitleViewItem {
                titleBarItems.append(cachedTitleViewItem)
            } else {
                let titleItem = UIBarButtonItem(customView: titleView)
                titleBarItems.append(titleItem)
                cachedTitleViewItem = titleItem
            }
        } else if let title = navigationItem.title {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = UIFont.wmf_font(.boldTitle1, compatibleWithTraitCollection: traitCollection)
            titleLabel.sizeToFit()
            titleView = titleLabel
            let titleItem = UIBarButtonItem(customView: titleLabel)
            titleBarItems.append(titleItem)
        }
        
        titleBarItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        
        if let item = navigationItem.leftBarButtonItem {
            var leftBarButtonItem  = item
            if #available(iOS 11.0, *) {
                leftBarButtonItem = barButtonItem(from: item)
            }
            titleBarItems.append(leftBarButtonItem)
        }
        
        if let item = navigationItem.rightBarButtonItem {
            var rightBarButtonItem = item
            if #available(iOS 11.0, *) {
                rightBarButtonItem = barButtonItem(from: item)
            }
            titleBarItems.append(rightBarButtonItem)
        }
        titleBar.setItems(titleBarItems, animated: false)
    }
    
    // HAX: barButtonItem that we're getting from the navigationItem will not be shown on iOS 11 so we need to recreate it
    private func barButtonItem(from item: UIBarButtonItem) -> UIBarButtonItem {
        let barButtonItem: UIBarButtonItem
        if let title = item.title {
            barButtonItem = UIBarButtonItem(title: title, style: item.style, target: item.target, action: item.action)
        } else if let systemBarButton = item as? SystemBarButton, let systemItem = systemBarButton.systemItem {
            barButtonItem = SystemBarButton(with: systemItem, target: systemBarButton.target, action: systemBarButton.action)
        } else {
            assert(item.image != nil, "barButtonItem must have title OR be of type SystemBarButton OR have image")
            barButtonItem = item
        }
        barButtonItem.isEnabled = item.isEnabled
        return barButtonItem
    }
    
    private var underBarViewHeightConstraint: NSLayoutConstraint!
    
    private var shadowTopUnderBarViewBottomConstraint: NSLayoutConstraint!
    private var shadowTopExtendedViewBottomConstraint: NSLayoutConstraint!

    private var shadowHeightConstraint: NSLayoutConstraint!
    private var extendedViewHeightConstraint: NSLayoutConstraint!
    
    private var titleBarTopConstraint: NSLayoutConstraint!
    private var barTopConstraint: NSLayoutConstraint!
    var barTopSpacing: CGFloat = 0 {
        didSet {
            titleBarTopConstraint.constant = barTopSpacing
            barTopConstraint.constant = barTopSpacing
            setNeedsLayout()
        }
    }
    
    /// Remove this when dropping iOS 10
    fileprivate var statusBarHeightConstraint: NSLayoutConstraint?
    /// Remove this when dropping iOS 10
    /// `statusBarHeight` only used on iOS 10 due to lack of safeAreaLayoutGuide
    @objc public var statusBarHeight: CGFloat = 0 {
        didSet {
            statusBarHeightConstraint?.constant = statusBarHeight
            setNeedsLayout()
        }
    }
    
    var underBarViewTopBarBottomConstraint: NSLayoutConstraint!
    var underBarViewTopTitleBarBottomConstraint: NSLayoutConstraint!
    
    override open func setup() {
        super.setup()
        translatesAutoresizingMaskIntoConstraints = false
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        statusBarUnderlay.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        underBarView.translatesAutoresizingMaskIntoConstraints = false
        extendedView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.alpha = 0
        shadow.translatesAutoresizingMaskIntoConstraints = false
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(backgroundView)
        addSubview(extendedView)
        addSubview(underBarView)
        addSubview(bar)
        addSubview(titleBar)
        addSubview(progressView)
        addSubview(statusBarUnderlay)
        addSubview(shadow)

        
        accessibilityElements = [extendedView, underBarView, bar]
        
        bar.delegate = self
        
        shadowHeightConstraint = shadow.heightAnchor.constraint(equalToConstant: 0.5)
        shadowHeightConstraint.priority = .defaultHigh
        shadow.addConstraint(shadowHeightConstraint)
        
        var updatedConstraints: [NSLayoutConstraint] = []
        
        let statusBarUnderlayTopConstraint = topAnchor.constraint(equalTo: statusBarUnderlay.topAnchor)
        updatedConstraints.append(statusBarUnderlayTopConstraint)
        
        var safeArea: UILayoutGuide?
        if #available(iOS 11.0, *) {
            safeArea = safeAreaLayoutGuide
        }
        
        if let safeArea = safeArea {
            let statusBarUnderlayBottomConstraint = safeArea.topAnchor.constraint(equalTo: statusBarUnderlay.bottomAnchor)
            updatedConstraints.append(statusBarUnderlayBottomConstraint)
        } else {
            let underlayHeightConstraint = statusBarUnderlay.heightAnchor.constraint(equalToConstant: 0)
            statusBarHeightConstraint = underlayHeightConstraint
            statusBarUnderlay.addConstraint(underlayHeightConstraint)
        }
        
        let statusBarUnderlayLeadingConstraint = leadingAnchor.constraint(equalTo: statusBarUnderlay.leadingAnchor)
        updatedConstraints.append(statusBarUnderlayLeadingConstraint)
        let statusBarUnderlayTrailingConstraint = trailingAnchor.constraint(equalTo: statusBarUnderlay.trailingAnchor)
        updatedConstraints.append(statusBarUnderlayTrailingConstraint)
        
        titleBarTopConstraint = titleBar.topAnchor.constraint(equalTo: statusBarUnderlay.bottomAnchor, constant: barTopSpacing)
        let titleBarLeadingConstraint = leadingAnchor.constraint(equalTo: titleBar.leadingAnchor)
        let titleBarTrailingConstraint = trailingAnchor.constraint(equalTo: titleBar.trailingAnchor)
        
        barTopConstraint = bar.topAnchor.constraint(equalTo: statusBarUnderlay.bottomAnchor, constant: barTopSpacing)
        let barLeadingConstraint = leadingAnchor.constraint(equalTo: bar.leadingAnchor)
        let barTrailingConstraint = trailingAnchor.constraint(equalTo: bar.trailingAnchor)
        
        underBarViewHeightConstraint = underBarView.heightAnchor.constraint(equalToConstant: 0)
        underBarView.addConstraint(underBarViewHeightConstraint)
        
        underBarViewTopBarBottomConstraint = bar.bottomAnchor.constraint(equalTo: underBarView.topAnchor)
        underBarViewTopTitleBarBottomConstraint = titleBar.bottomAnchor.constraint(equalTo: underBarView.topAnchor)
        
        let underBarViewLeadingConstraint = leadingAnchor.constraint(equalTo: underBarView.leadingAnchor)
        let underBarViewTrailingConstraint = trailingAnchor.constraint(equalTo: underBarView.trailingAnchor)
        
        extendedViewHeightConstraint = extendedView.heightAnchor.constraint(equalToConstant: 0)
        extendedView.addConstraint(extendedViewHeightConstraint)
        
        let extendedViewTopConstraint = underBarView.bottomAnchor.constraint(equalTo: extendedView.topAnchor)
        let extendedViewLeadingConstraint = leadingAnchor.constraint(equalTo: extendedView.leadingAnchor)
        let extendedViewTrailingConstraint = trailingAnchor.constraint(equalTo: extendedView.trailingAnchor)
        let extendedViewBottomConstraint = extendedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        
        let backgroundViewTopConstraint = topAnchor.constraint(equalTo: backgroundView.topAnchor)
        let backgroundViewLeadingConstraint = leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor)
        let backgroundViewTrailingConstraint = trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor)
        let backgroundViewBottomConstraint = extendedView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        
        let progressViewBottomConstraint = shadow.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 1)
        let progressViewLeadingConstraint = leadingAnchor.constraint(equalTo: progressView.leadingAnchor)
        let progressViewTrailingConstraint = trailingAnchor.constraint(equalTo: progressView.trailingAnchor)
        
        let shadowLeadingConstraint = leadingAnchor.constraint(equalTo: shadow.leadingAnchor)
        let shadowTrailingConstraint = trailingAnchor.constraint(equalTo: shadow.trailingAnchor)
        
        shadowTopExtendedViewBottomConstraint = extendedView.bottomAnchor.constraint(equalTo: shadow.topAnchor)
        shadowTopUnderBarViewBottomConstraint = underBarView.bottomAnchor.constraint(equalTo: shadow.topAnchor)
        

        updatedConstraints.append(contentsOf: [titleBarTopConstraint, titleBarLeadingConstraint, titleBarTrailingConstraint, underBarViewTopTitleBarBottomConstraint, barTopConstraint, barLeadingConstraint, barTrailingConstraint, underBarViewTopBarBottomConstraint, underBarViewLeadingConstraint, underBarViewTrailingConstraint, extendedViewTopConstraint, extendedViewLeadingConstraint, extendedViewTrailingConstraint, extendedViewBottomConstraint, backgroundViewTopConstraint, backgroundViewLeadingConstraint, backgroundViewTrailingConstraint, backgroundViewBottomConstraint, progressViewBottomConstraint, progressViewLeadingConstraint, progressViewTrailingConstraint, shadowTopUnderBarViewBottomConstraint, shadowTopExtendedViewBottomConstraint, shadowLeadingConstraint, shadowTrailingConstraint])
        addConstraints(updatedConstraints)
        
        updateTitleBarConstraints()
        updateShadowConstraints()

        setNavigationBarPercentHidden(0, underBarViewPercentHidden: 0, extendedViewPercentHidden: 0, topSpacingPercentHidden: 0, animated: false)
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.displayScale > 0 else {
            return
        }
        shadowHeightConstraint.constant = 1.0 / traitCollection.displayScale
    }
    
    
    fileprivate var _topSpacingPercentHidden: CGFloat = 0
    @objc public var topSpacingPercentHidden: CGFloat {
        get {
            return _topSpacingPercentHidden
        }
        set {
            setNavigationBarPercentHidden(_navigationBarPercentHidden, underBarViewPercentHidden: _underBarViewPercentHidden, extendedViewPercentHidden: _extendedViewPercentHidden, topSpacingPercentHidden: topSpacingPercentHidden, animated: false)
        }
    }
    
    fileprivate var _navigationBarPercentHidden: CGFloat = 0
    @objc public var navigationBarPercentHidden: CGFloat {
        get {
            return _navigationBarPercentHidden
        }
        set {
            setNavigationBarPercentHidden(newValue, underBarViewPercentHidden: _underBarViewPercentHidden, extendedViewPercentHidden: _extendedViewPercentHidden, topSpacingPercentHidden: _topSpacingPercentHidden, animated: false)
        }
    }
    
    private var _underBarViewPercentHidden: CGFloat = 0
    @objc public var underBarViewPercentHidden: CGFloat {
        get {
            return _underBarViewPercentHidden
        }
        set {
            setNavigationBarPercentHidden(_navigationBarPercentHidden, underBarViewPercentHidden: newValue, extendedViewPercentHidden: _extendedViewPercentHidden, topSpacingPercentHidden: _topSpacingPercentHidden, animated: false)
        }
    }
    
    fileprivate var _extendedViewPercentHidden: CGFloat = 0
    @objc public var extendedViewPercentHidden: CGFloat {
        get {
            return _extendedViewPercentHidden
        }
        set {
            setNavigationBarPercentHidden(_navigationBarPercentHidden, underBarViewPercentHidden: _underBarViewPercentHidden, extendedViewPercentHidden: newValue, topSpacingPercentHidden: _topSpacingPercentHidden, animated: false)
        }
    }
    
    @objc public var visibleHeight: CGFloat = 0
    
    public var shadowAlpha: CGFloat {
        get {
            return shadow.alpha
        }
        set {
            shadow.alpha = newValue
        }
    }
    
    @objc public func setNavigationBarPercentHidden(_ navigationBarPercentHidden: CGFloat, underBarViewPercentHidden: CGFloat, extendedViewPercentHidden: CGFloat, topSpacingPercentHidden: CGFloat, shadowAlpha: CGFloat = -1, animated: Bool, additionalAnimations: (() -> Void)? = nil) {
        layoutIfNeeded()
        if isTopSpacingHidingEnabled {
            _topSpacingPercentHidden = topSpacingPercentHidden
        }

        if isBarHidingEnabled {
            _navigationBarPercentHidden = navigationBarPercentHidden
        }
        
        if isUnderBarViewHidingEnabled {
            _underBarViewPercentHidden = underBarViewPercentHidden
        }
        
        if isExtendedViewHidingEnabled {
            _extendedViewPercentHidden = extendedViewPercentHidden
        }
        
        setNeedsLayout()
        //print("nb: \(navigationBarPercentHidden) ev: \(extendedViewPercentHidden)")
        let applyChanges = {
            let changes = {
                if shadowAlpha >= 0  {
                    self.shadowAlpha = shadowAlpha
                }
                self.layoutSubviews()
                additionalAnimations?()
            }
            if animated {
                UIView.animate(withDuration: 0.2, animations: changes)
            } else {
                changes()
            }
        }
        
        if let underBarViewPercentHiddenForShowingTitle = self.underBarViewPercentHiddenForShowingTitle {
            UIView.animate(withDuration: 0.2, animations: {
                self.delegate?.title = underBarViewPercentHidden >= underBarViewPercentHiddenForShowingTitle ? self.title : nil
            }, completion: { (_) in
                applyChanges()
            })
        } else {
            applyChanges()
        }
    }
    
    private func updateTitleBarConstraints() {
        let isUsingTitleBarInsteadOfNavigationBar = displayType == .largeTitle
        underBarViewTopTitleBarBottomConstraint.isActive = isUsingTitleBarInsteadOfNavigationBar
        underBarViewTopBarBottomConstraint.isActive = !isUsingTitleBarInsteadOfNavigationBar
        bar.isHidden = isUsingTitleBarInsteadOfNavigationBar
        titleBar.isHidden = !isUsingTitleBarInsteadOfNavigationBar
        barTopSpacing = isUsingTitleBarInsteadOfNavigationBar ? 30 : 0
        setNeedsUpdateConstraints()
    }
    
    private func updateShadowConstraints() {
        shadowTopUnderBarViewBottomConstraint.isActive = isShadowBelowUnderBarView
        shadowTopExtendedViewBottomConstraint.isActive = !isShadowBelowUnderBarView
        setNeedsUpdateConstraints()
    }
    
    var barHeight: CGFloat {
        return (displayType == .largeTitle ? titleBar.frame.height : bar.frame.height)
    }
    
    var underBarViewHeight: CGFloat {
        return underBarView.frame.size.height
    }
    
    var extendedViewHeight: CGFloat {
        return extendedView.frame.size.height
    }
    
    var hideableHeight: CGFloat {
        var totalHideableHeight: CGFloat = barTopSpacing
        
        if isBarHidingEnabled {
            totalHideableHeight += barHeight
        }
        
        if isUnderBarViewHidingEnabled {
            totalHideableHeight += underBarViewHeight
        }
        
        if isExtendedViewHidingEnabled {
            totalHideableHeight += extendedViewHeight
        }
        
        return totalHideableHeight
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        let navigationBarPercentHidden = _navigationBarPercentHidden
        let extendedViewPercentHidden = _extendedViewPercentHidden
        let underBarViewPercentHidden = _underBarViewPercentHidden
        let topSpacingPercentHidden = _topSpacingPercentHidden
        
        let underBarViewHeight = underBarView.frame.height
        let barHeight = self.barHeight
        let extendedViewHeight = extendedView.frame.height
        
        visibleHeight = statusBarUnderlay.frame.size.height + barHeight * (1.0 - navigationBarPercentHidden) + extendedViewHeight * (1.0 - extendedViewPercentHidden) + underBarViewHeight * (1.0 - underBarViewPercentHidden) + (barTopSpacing * (1.0 - topSpacingPercentHidden))
        
        let spacingTransformHeight = barTopSpacing * topSpacingPercentHidden
        let barTransformHeight = barHeight * navigationBarPercentHidden + spacingTransformHeight
        let extendedViewTransformHeight = extendedViewHeight * extendedViewPercentHidden
        let underBarTransformHeight = underBarViewHeight * underBarViewPercentHidden
        
        let barTransform = CGAffineTransform(translationX: 0, y: 0 - barTransformHeight)
        let barScaleTransform = CGAffineTransform(scaleX: 1.0 - navigationBarPercentHidden * navigationBarPercentHidden, y: 1.0 - navigationBarPercentHidden * navigationBarPercentHidden)
        
        self.bar.transform = barTransform
        self.titleBar.transform = barTransform
        
        if isTitleShrinkingEnabled {
            let titleScale: CGFloat = 1.0 - 0.2 * topSpacingPercentHidden
            self.titleView?.transform = CGAffineTransform(scaleX: titleScale, y: titleScale)
        }
        
        for subview in self.bar.subviews {
            for subview in subview.subviews {
                subview.transform = barScaleTransform
            }
        }
        self.bar.alpha = min(backgroundAlpha, (1.0 - 2.0 * navigationBarPercentHidden).wmf_normalizedPercentage)
        self.titleBar.alpha = self.bar.alpha
        
        let totalTransform = CGAffineTransform(translationX: 0, y: 0 - barTransformHeight - extendedViewTransformHeight - underBarTransformHeight)
        self.backgroundView.transform = totalTransform
        
        let underBarTransform = CGAffineTransform(translationX: 0, y: 0 - barTransformHeight - underBarTransformHeight)
        self.underBarView.transform = underBarTransform
        self.underBarView.alpha = 1.0 - underBarViewPercentHidden
        
        self.extendedView.transform = totalTransform
        
        if isExtendedViewFadingEnabled {
            self.extendedView.alpha = min(backgroundAlpha, 1.0 - extendedViewPercentHidden)
        } else {
            self.extendedView.alpha = CGFloat(1).isLessThanOrEqualTo(extendedViewPercentHidden) ? 0 : backgroundAlpha
        }
        
        self.progressView.transform = isShadowBelowUnderBarView ? underBarTransform : totalTransform
        self.shadow.transform = isShadowBelowUnderBarView ? underBarTransform : totalTransform
    }
    
    
    @objc public func setProgressHidden(_ hidden: Bool, animated: Bool) {
        let changes = {
            self.progressView.alpha = min(hidden ? 0 : 1, self.backgroundAlpha)
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }
    
    @objc public func setProgress(_ progress: Float, animated: Bool) {
        progressView.setProgress(progress, animated: animated)
    }
    
    @objc public var progress: Float {
        get {
            return progressView.progress
        }
        set {
            progressView.progress = progress
        }
    }
    
    @objc public func addExtendedNavigationBarView(_ view: UIView) {
        guard extendedView.subviews.first == nil else {
            return
        }
        extendedViewHeightConstraint.isActive = false
        extendedView.wmf_addSubviewWithConstraintsToEdges(view)
    }
    
    @objc public func removeExtendedNavigationBarView() {
        guard let subview = extendedView.subviews.first else {
            return
        }
        subview.removeFromSuperview()
        extendedViewHeightConstraint.isActive = true
    }
    
    @objc public func addUnderNavigationBarView(_ view: UIView) {
        guard underBarView.subviews.first == nil else {
            return
        }
        underBarViewHeightConstraint.isActive = false
        underBarView.wmf_addSubviewWithConstraintsToEdges(view)
    }
    
    @objc public func removeUnderNavigationBarView() {
        guard let subview = extendedView.subviews.first else {
            return
        }
        subview.removeFromSuperview()
        underBarViewHeightConstraint.isActive = true
    }
    
    @objc public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return point.y <= visibleHeight
    }
    
    public var backgroundAlpha: CGFloat = 1 {
        didSet {
            statusBarUnderlay.alpha = backgroundAlpha
            backgroundView.alpha = backgroundAlpha
            bar.alpha = backgroundAlpha
            titleBar.alpha = backgroundAlpha
            extendedView.alpha = backgroundAlpha
            if backgroundAlpha < progressView.alpha {
                progressView.alpha = backgroundAlpha
            }
        }
    }
}

extension NavigationBar: Themeable {
    public func apply(theme: Theme) {
        self.theme = theme
        
        backgroundColor = .clear
        
        statusBarUnderlay.backgroundColor = theme.colors.paperBackground
        backgroundView.backgroundColor = theme.colors.paperBackground
        
        titleBar.setBackgroundImage(theme.navigationBarBackgroundImage, forToolbarPosition: .any, barMetrics: .default)
        titleBar.isTranslucent = false
        titleBar.tintColor = theme.colors.primaryText
        titleBar.setShadowImage(theme.navigationBarShadowImage, forToolbarPosition: .any)
        titleBar.barTintColor = theme.colors.chromeBackground
        if let items = titleBar.items {
            for item in items {
                if let label = item.customView as? UILabel {
                    label.textColor = theme.colors.primaryText
                } else if item.image == nil {
                    item.tintColor = theme.colors.link
                }
            }
        }
        
        bar.setBackgroundImage(theme.navigationBarBackgroundImage, for: .default)
        bar.titleTextAttributes = theme.navigationBarTitleTextAttributes
        bar.isTranslucent = false
        bar.barTintColor = theme.colors.chromeBackground
        bar.shadowImage = theme.navigationBarShadowImage
        bar.tintColor = theme.colors.primaryText
        
        extendedView.backgroundColor = .clear
        underBarView.backgroundColor = .clear
        
        shadow.backgroundColor = theme.colors.chromeShadow
        
        progressView.progressViewStyle = .bar
        progressView.trackTintColor = .clear
        progressView.progressTintColor = theme.colors.link
    }
}

extension NavigationBar: UINavigationBarDelegate {
    public func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool {
        delegate?.navigationController?.popViewController(animated: true)
        return false
    }
}
