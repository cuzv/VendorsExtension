//
//  UIImage+Vendor.swift
//  ExtensionKit
//
//  Created by Moch Xiao on 12/21/15.
//  Copyright © 2015 Moch Xiao (https://github.com/cuzv).
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
import Kingfisher
import Toucan

public extension UIImage {
    /// Crop will resize to fit one dimension, then crop the other.
    public func cropResize(_ size: CGSize) -> UIImage {
        return Toucan(image: self).resize(size, fitMode: Toucan.Resize.FitMode.crop).image
    }
    
    /// Clip will resize so one dimension is equal to the size, the other shrunk down to retain aspect ratio.
    public func clipResize(_ size: CGSize) -> UIImage {
        return Toucan(image: self).resize(size, fitMode: Toucan.Resize.FitMode.clip).image
    }
    
    /// Scale will resize so the image fits exactly, altering the aspect ratio.
    public func scaleResize(_ size: CGSize) -> UIImage {
        return Toucan(image: self).resize(size, fitMode: Toucan.Resize.FitMode.scale).image
    }
    
    /// Demonstrate creating a circular mask -> resizes to a square image then mask with an ellipse.
    /// Mask with borders too!
    public func maskWithEllipse(
        borderWidth: CGFloat = 0,
        borderColor: UIColor = UIColor.white) -> UIImage
    {
        return Toucan(image: self).maskWithEllipse(borderWidth: borderWidth, borderColor: borderColor).image
    }
    
    /// Rounded Rects are all in style.
    /// And can be fancy with borders.
    public func maskWithRoundedRect(
        cornerRadius: CGFloat,
        borderWidth: CGFloat = 0,
        borderColor: UIColor = UIColor.white) -> UIImage
    {
        return Toucan(image: self).maskWithRoundedRect(cornerRadius: cornerRadius, borderWidth: borderWidth, borderColor: borderColor).image
    }
    
    /// Masking with an custom image mask.
    public func maskWithImage(_ maskImage: UIImage)  -> UIImage {
        return Toucan(image: self).maskWithImage(maskImage: maskImage).image
    }
}

public extension UIImageView {
    /// Set a crop resize image With a URLPath, a optional placeholder image.
    public func setCropResizeImage(withURLPath URLPath: String!, placeholderImage: UIImage? = nil) {
        setImage(withURLPath: URLPath, placeholderImage: placeholderImage) {
            $0?.cropResize($1)
        }
    }
    
    /// Set a clip resize image With a URLPath, a optional placeholder image.
    public func setClipResizeImage(withURLPath URLPath: String!, placeholderImage: UIImage? = nil) {
        setImage(withURLPath: URLPath, placeholderImage: placeholderImage) {
            $0?.clipResize($1)
        }
    }
    
    /// Set a clip resize image With a URLPath, a optional placeholder image.
    public func setScaleResizeImage(withURLPath URLPath: String!, placeholderImage: UIImage? = nil) {
        setImage(withURLPath: URLPath, placeholderImage: placeholderImage) {
            $0?.scaleResize($1)
        }
    }
    
    /// Set ellipse image with a URLPath, a optional placeholder image, optional border width, optional border color.
    public func setEllipseImage(
        withURLPath URLPath: String!,
                    resize: CGSize,
        placeholderImage: UIImage? = nil,
        borderWidth: CGFloat = 0,
        borderColor: UIColor = UIColor.white)
    {
        setImage(withURLPath: URLPath, placeholderImage: placeholderImage) {
            [weak self] (image, error, imageURL) -> Void in
            
            guard let this = self else { return }
            this.image = image?.cropResize(resize).maskWithEllipse(borderWidth: borderWidth, borderColor: borderColor)
        }
    }
    
    /// Set rounded image with a URLPath, a optional placeholder image, optional corner radius, optional border width, optional border color.
    public func setRoundedImage(
        withURLPath URLPath: String!,
        placeholderImage: UIImage? = nil,
        cornerRadius: CGFloat = 5,
        borderWidth: CGFloat = 0,
        borderColor: UIColor = UIColor.white)
    {
        setImage(withURLPath: URLPath, placeholderImage: placeholderImage) {
            [weak self] (image, error, imageURL) -> Void in
            
            guard let this = self else { return }
            this.image = image?.maskWithRoundedRect(cornerRadius: cornerRadius, borderWidth: borderWidth, borderColor: borderColor)
        }
    }
    
    /// Set image with a URLPath, a optional placeholder image, an custom image mask.
    public func setImage(
        withURLPath URLPath: String!,
        placeholderImage: UIImage? = nil,
        maskImage: UIImage)
    {
        setImage(withURLPath: URLPath, placeholderImage: placeholderImage) {
            [weak self] (image, error, imageURL) -> Void in
            
            guard let this = self else { return }
            this.image = image?.maskWithImage(maskImage)
        }
    }
    
    // MARK: -
    
    /// Set an image with a URLPath, a placeholder image, a reduceSize closure.
    public func setImage(
        withURLPath URLPath: String!,
        placeholderImage: UIImage? = nil,
        reduceSize: @escaping (_ image: UIImage?, _ size: CGSize) -> UIImage?)
    {
        setImage(withURLPath: URLPath, placeholderImage: placeholderImage) {
            [weak self] (image, error, imageURL) -> Void in
            
            guard let this = self else { return }
            this.image = reduceSize(image, this.bounds.size)
        }
    }
    
    /// Set an image with a URLPath, a placeholder image, progressBlock, completion handler.
    public func setImage(
        withURLPath URLPath: String!,
        placeholderImage: UIImage? = nil,
        progressBlock: ((_ receivedSize: Int64, _ totalSize: Int64) -> Void)? = nil,
        completionHandler: ((_ image: UIImage?, _ error: NSError?, _ imageURL: URL?) -> Void)? = nil)
    {
        guard let URLPath = URLPath, let URL = URL(string: URLPath) else { return }
        
        kf.setImage(with: URL, placeholder: placeholderImage, options: [.transition(ImageTransition.fade(0.5))], progressBlock: progressBlock) { (image, error, cacheType, imageURL) -> () in
            completionHandler?(image, error, imageURL)
        }
    }
    
    public func setImageNoAnimation(withURLPath URLPath: String?) {
        guard let URLPath = URLPath, let URL = URL(string: URLPath) else { return }
        kf.setImage(with: URL)
    }
}
