//
//  UIControl+Vendor.swift
//  ExtensionKit
//
//  Created by Moch Xiao on 1/5/16.
//  Copyright © @2016 Moch Xiao (https://github.com/cuzv).
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import UIKit
import SnapKit
import ReactiveCocoa

// MARK: - SegmentedToggleControl

final public class SegmentedToggleControl: UIControl {
    private var items: [String]
    private var buttons: [UIButton] = []
    private let normalTextColor: UIColor
    private let selectedTextColor: UIColor
    
    private var font: UIFont!
    private var lastSelectedIndex = 0
    private var firstTime: Bool = true

    public var selectedSegmentIndex: Int = 0 {
        didSet {
            selectedSegmentIndex = selectedSegmentIndex >= items.count ? items.count - 1 : selectedSegmentIndex
            rac_index.value = selectedSegmentIndex
            updateAppearance()
        }
    }
    public var rac_index: MutableProperty<Int> = MutableProperty(0)
    public var autoComputeLineWidth: Bool = true
    
    let lineView: UIView = {
        let view = UIView()
        return view
    }()
    
    public init(
        items: [String],
        normalTextColor: UIColor = UIColor.blackColor(),
        selectedTextColor: UIColor = UIColor.tintColor)
    {
        if items.count < 2 {
            fatalError("items.count can not less 2.")
        }
        
        self.items = items
        self.normalTextColor = normalTextColor
        self.selectedTextColor = selectedTextColor
        super.init(frame: CGRectZero)
        setup()
    }
    
    override private init(frame: CGRect) {
        fatalError("Use init(actionHandler:) instead.")
    }
    
    private init() {
        fatalError("Use init(actionHandler:) instead.")
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func intrinsicContentSize() -> CGSize {
        // Calculate text size
        let str = items.reduce("") { (str1, str2) -> String in
            return "\(str1)\(str2)"
        }
        if let font = font {
            var size = str.sizeFrom(font: font)
            size.width += CGFloat(items.count * 12)
            size.height = size.height >= 44 ? size.height : 44
            return size
        } else {
            return CGSizeMake(60, 44)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        
        if !autoComputeLineWidth && firstTime {
            lineView.snp_remakeConstraints(closure: { (make) -> Void in
                make.width.equalTo(lineViewWidthForIndex(selectedSegmentIndex))
                make.height.equalTo(1)
                make.bottom.equalTo(self)
                let currentButton = buttons[selectedSegmentIndex]
                make.centerX.equalTo(currentButton)
            })
            firstTime = false
        }
    }
}

public extension SegmentedToggleControl {
    private func setup() {
        let blurBackgroundView = UIToolbar(frame: CGRectZero)
        blurBackgroundView.barStyle = .Default
        blurBackgroundView.translucent = true
        blurBackgroundView.clipsToBounds = true
        addSubview(blurBackgroundView)
        blurBackgroundView.snp_makeConstraints { (make) in
            make.edges.equalTo(self)
        }
        
        var lastButton: UIButton!
        let count = items.count
        for i in 0 ..< count {
            // Make button
            let button = UIButton(type: .System)
            button.tag = i
            button.addTarget(self, action: #selector(SegmentedToggleControl.hanleClickAction(_:)), forControlEvents: .TouchUpInside)
            button.title = items[i]
            button.setTitleColor(normalTextColor, forState: .Normal)
            button.setTitleColor(selectedTextColor, forState: .Selected)
            button.tintColor = UIColor.clearColor()
            button.backgroundColor = UIColor.clearColor()
            addSubview(button)
            
            // Set position
            button.snp_makeConstraints(closure: { (make) -> Void in
                make.top.equalTo(self)
                make.bottom.equalTo(self)
                if let lastButton = lastButton {
                    make.left.equalTo(lastButton.snp_right)
                    make.width.equalTo(lastButton.snp_width)
                } else {
                    make.left.equalTo(self)
                }
                
                if i == count - 1 {
                    make.right.equalTo(self)
                }
            })
            
            lastButton = button
            
            buttons.append(button)
        }
        
        font = lastButton.titleLabel?.font
        
        if let firstButton = buttons.first {
            firstButton.selected = true
            
            addSubview(lineView)
            lineView.backgroundColor = selectedTextColor
            lineView.snp_makeConstraints { (make) -> Void in
                make.width.equalTo(lineViewWidthForIndex(0))
                make.height.equalTo(1)
                make.centerX.equalTo(firstButton)
                make.bottom.equalTo(self)
            }
        }
    }
    
    private func updateAppearance() {
        let sender  = buttons[selectedSegmentIndex]
        // toggle selected button
        buttons.forEach { (button) -> () in
            button.selected = false
        }
        sender.selected = true
        
        // Move lineView
        if let index = buttons.indexOf(sender) {
            remakeLineViewConstraintsForIndex(index)
        }
        
        // Send action
        sendActionsForControlEvents(.ValueChanged)
    }
    
    internal func hanleClickAction(sender: UIButton) {
        selectedSegmentIndex = sender.tag
    }
    
    private func remakeLineViewConstraintsForIndex(index: Int) {
        lineView.snp_remakeConstraints(closure: { (make) -> Void in
            make.width.equalTo(lineViewWidthForIndex(index))
            make.height.equalTo(1)
            make.bottom.equalTo(self)
            let currentButton = buttons[index]
            make.centerX.equalTo(currentButton)
        })
        
        let duration: NSTimeInterval = fabs(Double(lastSelectedIndex - index)) * 0.1
        if duration <= 0 {
            setNeedsLayout()
            layoutIfNeeded()
        } else {
            UIView.animateWithDuration(duration, animations: { () -> Void in
                self.setNeedsLayout()
                self.layoutIfNeeded()
            })
        }
        
        lastSelectedIndex = selectedSegmentIndex
    }
    
    private func lineViewWidthForIndex(index: Int) -> CGFloat {
        if autoComputeLineWidth {
            return items[index].sizeFrom(font: font).width
        } else {
            return (CGRectGetWidth(bounds) / CGFloat(items.count)).ceilly
        }
    }
}

public extension SegmentedToggleControl {
    /// can only have image or title, not both. must be 0..#segments - 1 (or ignored). default is nil
    public func set(title title: String, forSegmentAtIndex segment: Int) {
        if items.count <= segment {
            debugPrint("Index beyound the boundary.")
            return
        }
        
        let button = buttons[segment]
        button.title = title
        button.image = nil
        
        items.replace(atIndex: segment, with: title)
        remakeLineViewConstraintsForIndex(segment)
    }
    
    public func titleForSegmentAtIndex(segment: Int) -> String? {
        if items.count <= segment {
            return nil
        }
        
        return items[segment]
    }

    /// can only have image or title, not both. must be 0..#segments - 1 (or ignored). default is nil
    public func set(image image: UIImage, forSegmentAtIndex segment: Int) {
        if items.count <= segment {
            debugPrint("Index beyound the boundary.")
            return
        }
        
        let button = buttons[segment]
        button.image = image
        button.title = nil
    }
    
    public func imageForSegmentAtIndex(segment: Int) -> UIImage? {
        if items.count <= segment {
            return nil
        }
        
        return buttons[segment].image
    }
}