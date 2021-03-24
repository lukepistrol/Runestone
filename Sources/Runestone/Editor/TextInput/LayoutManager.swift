//
//  LayoutManager.swift
//  
//
//  Created by Simon Støvring on 25/01/2021.
//

import UIKit

protocol LayoutManagerDelegate: AnyObject {
    func layoutManagerDidInvalidateContentSize(_ layoutManager: LayoutManager)
    func layoutManager(_ layoutManager: LayoutManager, didProposeContentOffsetAdjustment contentOffsetAdjustment: CGPoint)
    func layoutManagerDidUpdateGutterWidth(_ layoutManager: LayoutManager)
}

final class LayoutManager {
    // MARK: - Public
    weak var delegate: LayoutManagerDelegate?
    weak var editorView: UIView? {
        didSet {
            if editorView != oldValue {
                setupViewHierarchy()
            }
        }
    }
    weak var textInputView: UIView? {
        didSet {
            if textInputView != oldValue {
                setupViewHierarchy()
            }
        }
    }
    var lineManager: LineManager {
        didSet {
            if lineManager !== oldValue {
                shouldResetLineWidths = true
            }
        }
    }
    var stringView: StringView
    var scrollViewWidth: CGFloat = 0 {
        didSet {
            if scrollViewWidth != oldValue {
                if isLineWrappingEnabled {
                    invalidateContentSize()
                    invalidateLines()
                }
            }
        }
    }
    var viewport: CGRect = .zero
    var contentSize: CGSize {
        return CGSize(width: contentWidth, height: contentHeight)
    }
    var languageMode: LanguageMode {
        didSet {
            if languageMode !== oldValue {
                for (_, lineController) in lineControllers {
                    lineController.syntaxHighlighter = languageMode.createLineSyntaxHighlighter()
                    lineController.syntaxHighlighter?.theme = theme
                    lineController.invalidate()
                }
            }
        }
    }
    var theme: EditorTheme = DefaultEditorTheme() {
        didSet {
            if theme !== oldValue {
                gutterBackgroundView.backgroundColor = theme.gutterBackgroundColor
                gutterBackgroundView.hairlineColor = theme.gutterHairlineColor
                gutterBackgroundView.hairlineWidth = theme.gutterHairlineWidth
                invisibleCharacterConfiguration.font = theme.font
                invisibleCharacterConfiguration.textColor = theme.invisibleCharactersColor
                gutterSelectionBackgroundView.backgroundColor = theme.selectedLinesGutterBackgroundColor
                lineSelectionBackgroundView.backgroundColor = theme.selectedLineBackgroundColor
                for (_, lineController) in lineControllers {
                    lineController.estimatedLineFragmentHeight = theme.font.lineHeight
                    lineController.syntaxHighlighter?.theme = theme
                    lineController.invalidate()
                }
            }
        }
    }
    var isEditing = false {
        didSet {
            if isEditing != oldValue {
                updateShownViews()
                updateLineNumberColors()
            }
        }
    }
    var showLineNumbers = false {
        didSet {
            if showLineNumbers != oldValue {
                updateShownViews()
                if showLineNumbers {
                    updateLineNumberWidth()
                }
            }
        }
    }
    var showSelectedLines = false {
        didSet {
            if showSelectedLines != oldValue {
                updateShownViews()
            }
        }
    }
    var invisibleCharacterConfiguration = InvisibleCharacterConfiguration()
    var tabWidth: CGFloat = 10 {
        didSet {
            if tabWidth != oldValue {
                invalidateContentSize()
                invalidateLines()
            }
        }
    }
    var isLineWrappingEnabled = true {
        didSet {
            if isLineWrappingEnabled != oldValue {
                invalidateContentSize()
                invalidateLines()
            }
        }
    }
    var gutterLeadingPadding: CGFloat = 3 {
        didSet {
            if gutterLeadingPadding != oldValue {
                invalidateContentSize()
            }
        }
    }
    var gutterTrailingPadding: CGFloat = 3 {
        didSet {
            if gutterTrailingPadding != oldValue {
                invalidateContentSize()
            }
        }
    }
    var textContainerInset: UIEdgeInsets = .zero {
        didSet {
            if textContainerInset != oldValue {
                invalidateContentSize()
            }
        }
    }
    var selectedRange: NSRange? {
        didSet {
            if selectedRange != oldValue {
                updateShownViews()
            }
        }
    }
    var gutterWidth: CGFloat {
        if showLineNumbers {
            return lineNumberWidth + gutterLeadingPadding + gutterTrailingPadding + safeAreaInsets.left
        } else {
            return 0
        }
    }
    var lineHeightMultiplier: CGFloat = 1 {
        didSet {
            if lineHeightMultiplier != oldValue {
                invalidateContentSize()
                invalidateLines()
            }
        }
    }

    // MARK: - Views
    let gutterContainerView = UIView()
    private var lineFragmentViewReuseQueue = ViewReuseQueue<LineFragmentID, LineFragmentView>()
    private var lineNumberLabelReuseQueue = ViewReuseQueue<DocumentLineNodeID, LineNumberView>()
    private var visibleLineIDs: Set<DocumentLineNodeID> = []
    private let linesContainerView = UIView()
    private let gutterBackgroundView = GutterBackgroundView()
    private let lineNumbersContainerView = UIView()
    private let gutterSelectionBackgroundView = UIView()
    private let lineSelectionBackgroundView = UIView()

    // MARK: - Sizing
    private var contentWidth: CGFloat {
        if isLineWrappingEnabled {
            return scrollViewWidth
        } else {
            return textContentWidth + leadingLineSpacing + textContainerInset.right + lineBreakInvisibleSymbolWidth
        }
    }
    private var contentHeight: CGFloat {
        return textContentHeight + textContainerInset.top + textContainerInset.bottom
    }
    private var textContentWidth: CGFloat {
        if let textContentWidth = _textContentWidth {
            return textContentWidth
        } else if let lineIDTrackingWidth = lineIDTrackingWidth, let lineWidth = lineWidths[lineIDTrackingWidth] {
            let textContentWidth = lineWidth
            _textContentWidth = textContentWidth
            return textContentWidth
        } else {
            lineIDTrackingWidth = nil
            var maximumWidth: CGFloat?
            for (lineID, lineWidth) in lineWidths {
                if let _maximumWidth = maximumWidth {
                    if lineWidth > _maximumWidth {
                        lineIDTrackingWidth = lineID
                        maximumWidth = lineWidth
                    }
                } else {
                    lineIDTrackingWidth = lineID
                    maximumWidth = lineWidth
                }
            }
            let textContentWidth = maximumWidth ?? scrollViewWidth
            _textContentWidth = textContentWidth
            return textContentWidth
        }
    }
    private var textContentHeight: CGFloat {
        if let contentHeight = _textContentHeight {
            return contentHeight
        } else {
            let contentHeight = lineManager.contentHeight
            _textContentHeight = contentHeight
            return contentHeight
        }
    }
    private var _textContentWidth: CGFloat?
    private var _textContentHeight: CGFloat?
    private var lineNumberWidth: CGFloat = 0
    private var previousGutterWidthUpdateLineCount: Int?
    private var safeAreaInsets: UIEdgeInsets {
        return editorView?.safeAreaInsets ?? .zero
    }
    private var leadingLineSpacing: CGFloat {
        if showLineNumbers {
            return gutterWidth + textContainerInset.left
        } else {
            return textContainerInset.left
        }
    }
    // Reset the line widths when changing the line manager to measure the
    // longest line and use it to determine the content width.
    private var shouldResetLineWidths = true

    // MARK: - Rendering
    private var lineControllers: [DocumentLineNodeID: LineController] = [:]
    private var needsLayout = false
    private var needsLayoutSelection = false
    private var lineWidths: [DocumentLineNodeID: CGFloat] = [:]
    private var lineIDTrackingWidth: DocumentLineNodeID?
    private var maximumLineWidth: CGFloat {
        if isLineWrappingEnabled {
            return scrollViewWidth - leadingLineSpacing - textContainerInset.right
        } else {
            // Rendering multiple very long lines is very expensive. In order to let the editor remain useable,
            // we set a very high maximum line width when line wrapping is disabled.
            return 10000
        }
    }
    private var lineBreakInvisibleSymbolWidth: CGFloat {
        if invisibleCharacterConfiguration.showLineBreaks {
            return invisibleCharacterConfiguration.lineBreakSymbolSize.width
        } else {
            return 0
        }
    }

    init(lineManager: LineManager, languageMode: LanguageMode, stringView: StringView) {
        self.lineManager = lineManager
        self.languageMode = languageMode
        self.stringView = stringView
        self.linesContainerView.isUserInteractionEnabled = false
        self.lineNumbersContainerView.isUserInteractionEnabled = false
        self.gutterContainerView.isUserInteractionEnabled = false
        self.gutterBackgroundView.isUserInteractionEnabled = false
        self.gutterSelectionBackgroundView.isUserInteractionEnabled = false
        self.lineSelectionBackgroundView.isUserInteractionEnabled = false
        self.updateShownViews()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning(_:)),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil)
    }

    func invalidateContentSize() {
        _textContentWidth = nil
        _textContentHeight = nil
    }

    func removeLine(withID lineID: DocumentLineNodeID) {
        lineWidths.removeValue(forKey: lineID)
        lineControllers.removeValue(forKey: lineID)
        if lineID == lineIDTrackingWidth {
            lineIDTrackingWidth = nil
            _textContentWidth = nil
            delegate?.layoutManagerDidInvalidateContentSize(self)
        }
    }

    func updateLineNumberWidth() {
        guard showLineNumbers else {
            return
        }
        let lineCount = lineManager.lineCount
        if lineCount != previousGutterWidthUpdateLineCount {
            previousGutterWidthUpdateLineCount = lineCount
            let characterCount = "\(lineCount)".count
            let wideLineNumberString = String(repeating: "8", count: characterCount)
            let wideLineNumberNSString = wideLineNumberString as NSString
            let size = wideLineNumberNSString.size(withAttributes: [.font: theme.lineNumberFont])
            let oldLineNumberWidth = lineNumberWidth
            lineNumberWidth = ceil(size.width) + gutterLeadingPadding + gutterTrailingPadding
            if lineNumberWidth != oldLineNumberWidth {
                delegate?.layoutManagerDidUpdateGutterWidth(self)
                _textContentWidth = nil
                delegate?.layoutManagerDidInvalidateContentSize(self)
            }
        }
    }

    func typeset(_ lines: Set<DocumentLineNode>) {
        for line in lines {
            if let lineController = lineControllers[line.id] {
                lineController.typeset()
            }
        }
    }

    func syntaxHighlight(_ lines: Set<DocumentLineNode>) {
        for line in lines {
            if let lineController = lineControllers[line.id] {
                lineController.syntaxHighlight()
            }
        }
    }
    
    func invalidateLines() {
        for (_, lineController) in lineControllers {
            lineController.lineFragmentHeightMultiplier = lineHeightMultiplier
            lineController.tabWidth = tabWidth
            lineController.invalidate()
        }
    }
}

// MARK: - UITextInput
extension LayoutManager {
    func caretRect(at location: Int) -> CGRect {
        let line = lineManager.line(containingCharacterAt: location)!
        let lineController = lineController(for: line)
        let localLocation = location - line.location
        let localCaretRect = lineController.caretRect(atIndex: localLocation)
        let globalYPosition = line.yPosition + localCaretRect.minY
        let globalRect = CGRect(x: localCaretRect.minX, y: globalYPosition, width: localCaretRect.width, height: localCaretRect.height)
        return globalRect.offsetBy(dx: leadingLineSpacing, dy: textContainerInset.top)
    }

    func firstRect(for range: NSRange) -> CGRect {
        guard let line = lineManager.line(containingCharacterAt: range.location) else {
            fatalError("Cannot find first rect.")
        }
        let lineController = lineController(for: line)
        let localRange = NSRange(location: range.location - line.location, length: min(range.length, line.value))
        let lineContentsRect = lineController.firstRect(for: localRange)
        let globalLineContentsYPosition = line.yPosition + lineContentsRect.minY
        let visibleWidth = viewport.width - gutterWidth
        let width: CGFloat
        let rangeContainsLineBreak = range.location + range.length > line.location + line.data.length
        if rangeContainsLineBreak {
            // The range contains the line break so we extend the rect past the contents of the line.
            // When the contents of the line can otherwise be contained within the visible width,
            // i.e. without scrolling the text view, we limit the width of the rect to the visible width.
            // This makes the scrolling performed by UIKit a bit better when selecting text using UITextInteraction.
            if lineContentsRect.minX <= visibleWidth && lineContentsRect.maxX <= visibleWidth {
                width = visibleWidth - lineContentsRect.minX
            } else {
                width = contentWidth - lineContentsRect.minX
            }
        } else {
            width = lineContentsRect.width
        }
        let cappedWidth = min(width, visibleWidth)
        return CGRect(x: lineContentsRect.minX, y: globalLineContentsYPosition, width: cappedWidth, height: lineContentsRect.height)
    }

    func selectionRects(in range: NSRange) -> [TextSelectionRect] {
        guard let startLine = lineManager.line(containingCharacterAt: range.location) else {
            return []
        }
        guard let endLine = lineManager.line(containingCharacterAt: range.location + range.length) else {
            return []
        }
        var selectionRects: [TextSelectionRect] = []
        let startLineIndex = startLine.index
        let endLineIndex = endLine.index
        let lineIndexRange = startLineIndex ..< endLineIndex + 1
        for lineIndex in lineIndexRange {
            let line = lineManager.line(atRow: lineIndex)
            let lineController = lineController(for: line)
            let lineStartLocation = line.location
            let lineEndLocation = lineStartLocation + line.data.totalLength
            let localRangeLocation = max(range.location, lineStartLocation) - lineStartLocation
            let localRangeLength = min(range.location + range.length, lineEndLocation) - lineStartLocation - localRangeLocation
            let localRange = NSRange(location: localRangeLocation, length: localRangeLength)
            let rendererSelectionRects = lineController.selectionRects(in: localRange)
            let textSelectionRects: [TextSelectionRect] = rendererSelectionRects.map { rendererSelectionRect in
                let containsStart = lineIndex == startLineIndex
                let containsEnd = lineIndex == endLineIndex
                var screenRect = rendererSelectionRect.rect
                screenRect.origin.x += leadingLineSpacing
                screenRect.origin.y = textContainerInset.top + line.yPosition + rendererSelectionRect.rect.minY
                if !containsEnd {
                    // If the following lines are selected, we make sure that the selections extends the entire line.
                    screenRect.size.width = max(contentWidth, scrollViewWidth) - screenRect.minX
                }
                return TextSelectionRect(rect: screenRect, writingDirection: .leftToRight, containsStart: containsStart, containsEnd: containsEnd)
            }
            selectionRects.append(contentsOf: textSelectionRects)
        }
        return selectionRects.ensuringYAxisAlignment()
    }

    func closestIndex(to point: CGPoint) -> Int? {
        let adjustedXPosition = point.x - leadingLineSpacing
        let adjustedYPosition = point.y - textContainerInset.top
        let adjustedPoint = CGPoint(x: adjustedXPosition, y: adjustedYPosition)
        if let line = lineManager.line(containingYOffset: adjustedPoint.y), let lineController = lineControllers[line.id] {
            return closestIndex(to: adjustedPoint, in: lineController, showing: line)
        } else if adjustedPoint.y <= 0 {
            let firstLine = lineManager.firstLine
            if let textRenderer = lineControllers[firstLine.id] {
                return closestIndex(to: adjustedPoint, in: textRenderer, showing: firstLine)
            } else {
                return 0
            }
        } else {
            let lastLine = lineManager.lastLine
            if adjustedPoint.y >= lastLine.yPosition, let textRenderer = lineControllers[lastLine.id] {
                return closestIndex(to: adjustedPoint, in: textRenderer, showing: lastLine)
            } else {
                return stringView.string.length
            }
        }
    }

    private func closestIndex(to point: CGPoint, in lineController: LineController, showing line: DocumentLineNode) -> Int {
        let localPoint = CGPoint(x: point.x, y: point.y - line.yPosition)
        let index = lineController.closestIndex(to: localPoint)
        if index >= line.data.length && index <= line.data.totalLength && line != lineManager.lastLine {
            return line.location + line.data.length
        } else {
            return line.location + index
        }
    }
}

// MARK: - Layout
extension LayoutManager {
    func setNeedsLayout() {
        needsLayout = true
    }

    func layoutIfNeeded() {
        if needsLayout {
            needsLayout = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            resetLineWidthsIfNecessary()
            layoutGutter()
            layoutSelection()
            layoutLines()
            updateLineNumberColors()
            CATransaction.commit()
        }
    }

    func setNeedsLayoutSelection() {
        needsLayoutSelection = true
    }

    func layoutSelectionIfNeeded() {
        if needsLayoutSelection {
            needsLayoutSelection = true
            CATransaction.begin()
            CATransaction.setDisableActions(false)
            layoutSelection()
            updateLineNumberColors()
            CATransaction.commit()
        }
    }

    private func layoutGutter() {
        gutterContainerView.frame = CGRect(x: viewport.minX, y: 0, width: gutterWidth, height: contentSize.height)
        gutterBackgroundView.frame = CGRect(x: 0, y: viewport.minY, width: gutterWidth, height: viewport.height)
        lineNumbersContainerView.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: contentSize.height)
    }

    private func layoutSelection() {
        guard showSelectedLines, let selectedRange = selectedRange else {
            return
        }
        let startLocation = selectedRange.location
        let endLocation = selectedRange.location + selectedRange.length
        let selectedRect: CGRect
        if selectedRange.length > 0 {
            let startLine = lineManager.line(containingCharacterAt: startLocation)!
            let endLine = lineManager.line(containingCharacterAt: endLocation)!
            let startLineMinYPosition = textContainerInset.top + startLine.yPosition
            let endLineMaxYPosition = textContainerInset.top + endLine.yPosition + endLine.data.lineHeight
            let height = endLineMaxYPosition - startLineMinYPosition
            selectedRect = CGRect(x: 0, y: startLineMinYPosition, width: scrollViewWidth, height: height)
        } else {
            let line = lineManager.line(containingCharacterAt: startLocation)!
            selectedRect = CGRect(x: 0, y: textContainerInset.top + line.yPosition, width: scrollViewWidth, height: line.data.lineHeight)
        }
        gutterSelectionBackgroundView.frame = CGRect(x: 0, y: selectedRect.minY, width: gutterWidth, height: selectedRect.height)
        lineSelectionBackgroundView.frame = CGRect(x: viewport.minX + gutterWidth, y: selectedRect.minY, width: scrollViewWidth - gutterWidth, height: selectedRect.height)
    }

    private func layoutLines() {
        let oldVisibleLineIDs = visibleLineIDs
        let oldVisibleLineFragmentIDs = Set(lineFragmentViewReuseQueue.visibleViews.keys)
        // Layout lines until we have filled the viewport.
        var nextLine = lineManager.line(containingYOffset: viewport.minY)
        var appearedLineIDs: Set<DocumentLineNodeID> = []
        var appearedLineFragmentIDs: Set<LineFragmentID> = []
        var maxY = viewport.minY
        var contentOffsetAdjustmentY: CGFloat = 0
        while let line = nextLine, maxY < viewport.maxY {
            appearedLineIDs.insert(line.id)
            // Prepare to line controller to display text.
            let lineController = lineController(for: line)
            lineController.constrainingWidth = maximumLineWidth
            lineController.willDisplay()
            // Layout the line number.
            layoutLineNumberView(for: line)
            // Layout line fragments ("sublines") in the line until we have filled the viewport.
            let lineYPosition = line.yPosition
            let lineFragmentControllers = lineController.lineFragmentControllers(in: viewport)
            for lineFragmentController in lineFragmentControllers {
                let lineFragment = lineFragmentController.lineFragment
                appearedLineFragmentIDs.insert(lineFragment.id)
                layoutLineFragmentView(for: lineFragmentController, lineYPosition: lineYPosition, maxY: &maxY)
            }
            var localContentOffsetAdjustmentY: CGFloat = 0
            updateSize(of: lineController, contentOffsetAdjustmentY: &localContentOffsetAdjustmentY)
            contentOffsetAdjustmentY += localContentOffsetAdjustmentY
            if line.index < lineManager.lineCount - 1 {
                nextLine = lineManager.line(atRow: line.index + 1)
            } else {
                nextLine = nil
            }
        }
        // Update the visible lines and line fragments. Clean up everything that is not in the viewport anymore.
        visibleLineIDs = appearedLineIDs
        let disappearedLineIDs = oldVisibleLineIDs.subtracting(appearedLineIDs)
        let disappearedLineFragmentIDs = oldVisibleLineFragmentIDs.subtracting(appearedLineFragmentIDs)
        for disapparedLineID in disappearedLineIDs {
            let lineController = lineControllers[disapparedLineID]
            lineController?.didEndDisplaying()
        }
        lineNumberLabelReuseQueue.enqueueViews(withKeys: disappearedLineIDs)
        lineFragmentViewReuseQueue.enqueueViews(withKeys: disappearedLineFragmentIDs)
        // Update content size if necessary.
        if _textContentWidth == nil || _textContentHeight == nil {
            delegate?.layoutManagerDidInvalidateContentSize(self)
        }
        // Adjust the content offset on the Y-axis if necessary.
        if contentOffsetAdjustmentY != 0 {
            let contentOffsetAdjustment = CGPoint(x: 0, y: contentOffsetAdjustmentY)
            delegate?.layoutManager(self, didProposeContentOffsetAdjustment: contentOffsetAdjustment)
        }
    }

    private func layoutLineNumberView(for line: DocumentLineNode) {
        let lineNumberView = lineNumberLabelReuseQueue.dequeueView(forKey: line.id)
        if lineNumberView.superview == nil {
            lineNumbersContainerView.addSubview(lineNumberView)
        }
        let lineHeight = theme.font.lineHeight
        let scaledLineHeight = lineHeight * lineHeightMultiplier
        let yOffset = (scaledLineHeight - lineHeight) / 2
        let origin = CGPoint(x: safeAreaInsets.left + gutterLeadingPadding, y: textContainerInset.top + line.yPosition + yOffset)
        let size = CGSize(width: lineNumberWidth, height: scaledLineHeight)
        lineNumberView.text = "\(line.index + 1)"
        lineNumberView.font = theme.font
        lineNumberView.textColor = theme.lineNumberColor
        lineNumberView.frame = CGRect(origin: origin, size: size)
    }

    private func layoutLineFragmentView(for lineFragmentController: LineFragmentController, lineYPosition: CGFloat, maxY: inout CGFloat) {
        let lineFragment = lineFragmentController.lineFragment
        let lineFragmentView = lineFragmentViewReuseQueue.dequeueView(forKey: lineFragment.id)
        if lineFragmentView.superview == nil {
            linesContainerView.addSubview(lineFragmentView)
        }
        lineFragmentController.invisibleCharacterConfiguration = invisibleCharacterConfiguration
        lineFragmentController.lineFragmentView = lineFragmentView
        let lineFragmentOrigin = CGPoint(x: leadingLineSpacing, y: textContainerInset.top + lineYPosition + lineFragment.yPosition)
        let lineFragmentSize = CGSize(width: lineFragment.scaledSize.width + lineBreakInvisibleSymbolWidth, height: lineFragment.scaledSize.height)
        let lineFragmentFrame = CGRect(origin: lineFragmentOrigin, size: lineFragmentSize)
        lineFragmentView.frame = lineFragmentFrame
        maxY = lineFragmentFrame.maxY
    }

    private func updateSize(of lineController: LineController, contentOffsetAdjustmentY: inout CGFloat) {
        let line = lineController.line
        let lineWidth = lineController.lineWidth
        if lineWidths[line.id] != lineWidth {
            lineWidths[line.id] = lineWidth
            if let lineIDTrackingWidth = lineIDTrackingWidth {
                let maximumLineWidth = lineWidths[lineIDTrackingWidth] ?? 0
                if line.id == lineIDTrackingWidth || lineWidth > maximumLineWidth {
                    self.lineIDTrackingWidth = line.id
                    _textContentWidth = nil
                }
            } else if !isLineWrappingEnabled {
                _textContentWidth = nil
            }
        }
        let oldLineHeight = line.data.lineHeight
        let newLineHeight = lineController.lineHeight
        let didUpdateHeight = lineManager.setHeight(of: line, to: newLineHeight)
        if didUpdateHeight {
            _textContentHeight = nil
            // Updating the height of a line that's above the current content offset will cause the content below it to move up or down.
            // This happens when layout information above the content offset is invalidated and the user is scrolling upwards, e.g. after
            // changing the line height. To accommodate this change and reduce the "jump", we ask the scroll view to adjust the content offset
            // by the amount that the line height has changed. The solution is borrowed from https://github.com/airbnb/MagazineLayout/pull/11
            let isSizingElementAboveTopEdge = line.yPosition < viewport.minY + textContainerInset.top
            if isSizingElementAboveTopEdge {
                contentOffsetAdjustmentY = newLineHeight - oldLineHeight
            }
        }
    }

    private func updateLineNumberColors() {
        let visibleViews = lineNumberLabelReuseQueue.visibleViews
        let selectionFrame = gutterSelectionBackgroundView.frame
        let isSelectionVisible = !gutterSelectionBackgroundView.isHidden
        for (_, lineNumberView) in visibleViews {
            if isSelectionVisible {
                let lineNumberFrame = lineNumberView.frame
                let isInSelection = lineNumberFrame.midY >= selectionFrame.minY && lineNumberFrame.midY <= selectionFrame.maxY
                lineNumberView.textColor = isInSelection && isEditing ? theme.selectedLinesLineNumberColor : theme.lineNumberColor
            } else {
                lineNumberView.textColor = theme.lineNumberColor
            }
        }
    }

    private func setupViewHierarchy() {
        // Remove views from view hierarchy
        gutterBackgroundView.removeFromSuperview()
        lineNumbersContainerView.removeFromSuperview()
        gutterSelectionBackgroundView.removeFromSuperview()
        lineSelectionBackgroundView.removeFromSuperview()
        let allLineNumberKeys = lineFragmentViewReuseQueue.visibleViews.keys
        lineFragmentViewReuseQueue.enqueueViews(withKeys: Set(allLineNumberKeys))
        // Add views to view hierarchy
        textInputView?.addSubview(lineSelectionBackgroundView)
        textInputView?.addSubview(linesContainerView)
        editorView?.addSubview(gutterContainerView)
        gutterContainerView.addSubview(gutterBackgroundView)
        gutterContainerView.addSubview(gutterSelectionBackgroundView)
        gutterContainerView.addSubview(lineNumbersContainerView)
    }

    private func updateShownViews() {
        let selectedLength = selectedRange?.length ?? 0
        gutterBackgroundView.isHidden = !showLineNumbers
        lineNumbersContainerView.isHidden = !showLineNumbers
        gutterSelectionBackgroundView.isHidden = !showSelectedLines || !showLineNumbers || !isEditing
        lineSelectionBackgroundView.isHidden = !showSelectedLines || !isEditing || selectedLength > 0
    }

    // Resetting the line widths clears all recorded line widths, asks the line manager for the longest line,
    // measures the width of the line and uses it to determine the width of content.
    // This is used when first opening the text editor to make a fairly accurate guess of the content width.
    private func resetLineWidthsIfNecessary() {
        if shouldResetLineWidths {
            shouldResetLineWidths = false
            lineWidths = [:]
            if let longestLine = lineManager.initialLongestLine {
                lineIDTrackingWidth = longestLine.id
                let lineController = lineController(for: longestLine)
                lineController.typeset()
                lineWidths[longestLine.id] = lineController.lineWidth
                if !isLineWrappingEnabled {
                    _textContentWidth = nil
                }
            }
        }
    }

    private func lineController(for line: DocumentLineNode) -> LineController {
        let lineController: LineController
        if let cachedLineController = lineControllers[line.id] {
            lineController = cachedLineController
        } else {
            lineController = LineController(line: line, stringView: stringView)
            lineControllers[line.id] = lineController
        }
        lineController.constrainingWidth = maximumLineWidth
        lineController.estimatedLineFragmentHeight = theme.font.lineHeight
        lineController.lineFragmentHeightMultiplier = lineHeightMultiplier
        lineController.tabWidth = tabWidth
        lineController.syntaxHighlighter = languageMode.createLineSyntaxHighlighter()
        lineController.syntaxHighlighter?.theme = theme
        return lineController
    }
}

// MARK: - Line Movement
extension LayoutManager {
    func numberOfLineFragments(in line: DocumentLineNode) -> Int {
        return lineController(for: line).numberOfLineFragments
    }

    func lineFragmentNode(atIndex index: Int, in line: DocumentLineNode) -> LineFragmentNode {
        return lineController(for: line).lineFragmentNode(atIndex: index)
    }

    func lineFragmentNode(containingCharacterAt location: Int, in line: DocumentLineNode) -> LineFragmentNode {
        return lineController(for: line).lineFragmentNode(containingCharacterAt: location)
    }
}

// MARK: - Memory Management
private extension LayoutManager {
    @objc private func didReceiveMemoryWarning(_ notification: Notification) {
        let allLineIDs = Set(lineControllers.keys)
        let lineIDsToRelease = allLineIDs.subtracting(visibleLineIDs)
        for lineID in lineIDsToRelease {
            lineControllers.removeValue(forKey: lineID)
        }
    }
}
