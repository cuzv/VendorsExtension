//
//  ReactiveCocoa+Extension.swift
//  ExtensionKit
//
//  Created by Moch Xiao on 12/24/15.
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
import ReactiveCocoa
import enum Result.NoError
import Redes
import TinyCoordinator
import ExtensionKit

// MARK: - SignalProducer

public extension SignalProducer {
    public func ignoreError() -> SignalProducer<Value, NoError> {
        return flatMapError({ _ in SignalProducer<Value, NoError>.empty })
    }
    
    public func observeOnUIScheduler() -> SignalProducer<Value, Error> {
        return observeOn(UIScheduler())
    }
    
    public func skipOnce() -> SignalProducer<Value, Error> {
        return skip(1)
    }
    
    public func takeOnce() -> SignalProducer<Value, Error> {
        return take(1)
    }
    
    public func filterNil() -> SignalProducer<Value, Error> {
        return filter { $0 != nil}
    }
    
    public func filterEmpty() -> SignalProducer<Value, Error> {
        return filter { (value: Value) -> Bool in
            if let arr = value as? [AnyObject] {
                return !arr.isEmpty
            } else if let dict = value as? [String: AnyObject] {
                return !dict.isEmpty
            } else if let globalDataMetric = value as? TCGlobalDataMetric {
                return !globalDataMetric.isEmpty
            } else if let error = value as? NSError {
                return !(error.code == NSError.emptyErrorCode && error.domain == NSError.emptyErrorDomain)
            }
            return true
        }
    }
}

public func merge<Value, Error: ErrorType>(producers: [SignalProducer<Value, Error>]) -> SignalProducer<Value, Error> {
    return SignalProducer<SignalProducer<Value, Error>, Error>(values: producers).flatten(.Merge)
}

extension NSObject {
    /// In common use: SignalProducer.takeUntil(rac_willDeinitProducer)
    public var rac_willDeinitProducer: SignalProducer<(), NoError> {
        return rac_willDeallocSignal().toSignalProducer().ignoreError().map { _ in () }
    }
}

// MARK: - Signal

public func merge<Value, Error: ErrorType>(signals: [Signal<Value, Error>]) -> Signal<Value, Error> {
    return Signal<Value, Error>.merge(signals)
}

public func mergeErrors(errors: [Signal<NSError, NoError>]) -> MutableProperty<NSError> {
    return merge(errors).rac_next(NSError.empty())
}

public func mergeActionsErrors<Input, Output>(actions: [ReactiveCocoa.Action<Input, Output, NSError>]) -> MutableProperty<NSError> {
    return mergeErrors(actions.map { $0.errors })
}

public func mergeValues<Output>(values: [Signal<Output, NoError>], initialValue: Output) -> MutableProperty<Output> {
    return merge(values).rac_next(initialValue)
}

public func mergeActionsValues<Input, Output>(actions: [ReactiveCocoa.Action<Input, Output, NSError>], initialValue: Output) -> MutableProperty<Output> {
    return mergeValues(actions.map( { $0.values }), initialValue: initialValue)
}

public func mergeExecuting(executings: [AnyProperty<Bool>]) -> AnyProperty<Bool> {
    return AnyProperty(initialValue: false, producer: merge(executings.map { $0.producer }))
}

public func mergeActionsExecuting<Input, Output>(actions: [ReactiveCocoa.Action<Input, Output, NSError>]) -> AnyProperty<Bool> {
    return AnyProperty(initialValue: false, producer: merge(actions.map { $0.executing.producer }))
}

// MARK: - Timer

final public class CountdownTimer {
    private let startTime: NSDate
    private let interval: NSTimeInterval
    private let duration: NSTimeInterval
    private var next: ((NSTimeInterval) -> ())
    private var completion: (() -> ())
    
    private var disposable: Disposable?
    
    public init(
        startTime: NSDate = NSDate(),
        interval: NSTimeInterval = 1,
        duration: NSTimeInterval = 60,
        next: ((NSTimeInterval) -> ()),
        completion: (() -> ()))
    {
        self.startTime = startTime
        self.interval = interval
        self.duration = duration
        self.next = next
        self.completion = completion
    }
    
    public func start() {
        disposable = timer(interval, onScheduler: QueueScheduler.mainQueueScheduler).on(
            disposed: {
                self.completion()
            },
            next: {
                let overTimeInterval = $0.timeIntervalSinceDate(self.startTime)
                let leftTimeInterval = fabs(ceil(self.duration - overTimeInterval))
                self.next(leftTimeInterval)
                if leftTimeInterval <= 0 {
                    self.disposable?.dispose()
                }
            }
        ).start()
    }
    
#if DEBUG
    deinit {
        debugPrint("\(#file):\(#line):\(self.dynamicType):\(#function)")
    }
#endif
}

// MARK: - MutableProperty
//  https://github.com/ColinEberhardt/ReactiveTwitterSearch/blob/master/ReactiveTwitterSearch/Util/UIKitExtensions.swift

private struct AssociationKey {
    private static var hidden: String  = "rac_hidden"
    private static var alpha: String   = "rac_alpha"
    private static var text: String    = "rac_text"
    private static var image: String   = "rac_image"
    private static var enabled: String = "rac_enabled"
    private static var index: String = "rac_index"
}

/// Lazily creates a gettable associated property via the given factory.
internal func lazyAssociatedProperty<T: AnyObject>(
    host host: AnyObject,
    key: UnsafePointer<Void>,
    factory: ()->T) -> T
{
    return objc_getAssociatedObject(host, key) as? T ?? {
        let associatedProperty = factory()
        objc_setAssociatedObject(host, key, associatedProperty, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        return associatedProperty
    }()
}

private func lazyMutableProperty<T>(
    host host: AnyObject,
    key: UnsafePointer<Void>,
    setter: T -> (),
    getter: () -> T) -> MutableProperty<T>
{
    return lazyAssociatedProperty(host: host, key: key) {
        let property = MutableProperty<T>(getter())
        property.producer.startWithNext { newValue in
            setter(newValue)
        }
        
        return property
    }
}

public extension UIView {
    public var rac_alpha: MutableProperty<CGFloat> {
        return lazyMutableProperty(
            host: self,
            key: &AssociationKey.alpha,
            setter: { self.alpha = $0 },
            getter: { self.alpha  }
        )
    }
    
    public var rac_hidden: MutableProperty<Bool> {
        return lazyMutableProperty(
            host: self,
            key: &AssociationKey.hidden,
            setter: { self.hidden = $0 },
            getter: { self.hidden  }
        )
    }
}

public extension UILabel {
    public var rac_text: MutableProperty<String> {
        return lazyMutableProperty(
            host: self,
            key: &AssociationKey.text,
            setter: { self.text = $0 },
            getter: { self.text ?? "" }
        )
    }
}

public extension UISegmentedControl {
    public var rac_index: MutableProperty<Int> {
        return lazyAssociatedProperty(host: self, key: &AssociationKey.index) {
            self.addTarget(self, action: #selector(UISegmentedControl.changed), forControlEvents: .ValueChanged)
            
            let property = MutableProperty<Int>(0)
            property.producer.startWithNext{ newValue in
                self.selectedSegmentIndex = newValue
            }
            return property
        }
    }
    
    dynamic internal func changed() {
        rac_index.value = selectedSegmentIndex
    }
}

public extension UITextField {
    public func rac_textSignalProducer() -> SignalProducer<String, NoError> {
        return rac_textSignal().toSignalProducer()
            .map { $0 as! String }
            .ignoreError()
    }
    
    public var rac_text: MutableProperty<String> {
        return lazyAssociatedProperty(host: self, key: &AssociationKey.text) {
            self.addTarget(self, action: #selector(UITextField.changed), forControlEvents: .EditingChanged)
            
            let property = MutableProperty<String>(self.text ?? "")
            property.producer.startWithNext { newValue in
                self.text = newValue
            }
            return property
        }
    }
    
    dynamic internal func changed() {
        rac_text.value = text ?? ""
    }
}

public extension UITextView {
    public func rac_textSignalProducer() -> SignalProducer<String, NoError> {
        return rac_textSignal().toSignalProducer().map{ $0 as! String }.ignoreError()
    }
    
    public var rac_text: MutableProperty<String> {
        return rac_textSignalProducer().rac_values(text ?? "")
    }
    
    // 中文输入出现问题
//    public var rac_text: MutableProperty<String> {
//        return lazyAssociatedProperty(host: self, key: &AssociationKey.text) {
//            NSNotificationCenter.defaultCenter()
//                .rac_notifications(UITextViewTextDidChangeNotification, object: self)
//                .takeUntil(self.rac_willDeinitProducer)
//                .startWithNext({ [weak self] (notification) -> () in
//                    self?.changed()
//                })
//            
//            let property = MutableProperty<String>(self.text ?? "")
//            property.producer.startWithNext { newValue in
//                self.text = newValue
//            }
//            return property
//        }
//    }
//    
//    dynamic internal func changed() {
//        rac_text.value = text ?? ""
//    }
}

public extension UISearchBar {
    public var rac_text: MutableProperty<String> {
        return lazyAssociatedProperty(host: self, key: &AssociationKey.text) {
            self.rac_signalForSelector(NSSelectorFromString("searchBar:textDidChange:"), fromProtocol: NSProtocolFromString("UISearchBarDelegate"))
                .toSignalProducer()
                .startWithNext{ [weak self] (obj) -> () in
                    self?.changed()
                }
            
            let property = MutableProperty<String>(self.text ?? "")
            property.producer.startWithNext { newValue in
                self.text = newValue
            }
            return property
        }
    }
    
    dynamic internal func changed() {
        rac_text.value = text ?? ""
    }
    
}

public extension UIImageView {
    public var rac_image: MutableProperty<UIImage?> {
        return lazyMutableProperty(
            host: self,
            key: &AssociationKey.image,
            setter: { self.image = $0 },
            getter: { self.image }
        )
    }
}

public extension UIButton {
    public var rac_enabled: MutableProperty<Bool> {
        return lazyMutableProperty(
            host: self,
            key: &AssociationKey.enabled,
            setter: { self.enabled = $0 },
            getter: { self.enabled }
        )
    }
}

public extension SignalProducer {
    public func rac_values(initialValue: Value) -> MutableProperty<Value> {
        let property = MutableProperty<Value>(initialValue)
        
        startWithNext { (value) -> () in
            property.value = value
        }
        
        return property
    }
    
    public func rac_errors(initialValue: Error) -> MutableProperty<Error> {
        let property = MutableProperty<Error>(initialValue)
        
        startWithFailed { (error) -> () in
            property.value = error
        }
        
        return property
    }
}

public extension Signal {
    public func rac_next(initialValue: Value) -> MutableProperty<Value> {
        let property = MutableProperty<Value>(initialValue)
        
        observeNext { (value) -> () in
            property.value = value
        }
        
        return property
    }
    
    public func rac_errors(initialValue: Error) -> MutableProperty<Error> {
        let property = MutableProperty<Error>(initialValue)
        
        observeFailed { (error) -> () in
            property.value = error
        }
        
        return property
    }
}

public extension Action {
    public func rac_errors(initialValue: Error) -> MutableProperty<Error> {
        return errors.rac_next(initialValue)
    }
    
    public func rac_values(initialValue: Output) -> MutableProperty<Output> {
        return values.rac_next(initialValue)
    }
}

// MARK: - CocoaAction

public extension UIControl {
    public func addCocoaAction(target target: CocoaAction, forControlEvents events: UIControlEvents = .TouchUpInside) {
        addTarget(target, action: CocoaAction.selector, forControlEvents: events)
    }
}

// MARK: - Redes

private extension Redes.Request {
    var asyncProducer: SignalProducer <AnyObject, NSError>  {
        return SignalProducer { observer, disposable in
            UIApplication.sharedApplication().networkActivityIndicatorVisible = true
            self.asyncResponseJSON {
                dispatch_async(dispatch_get_main_queue()) {
                    UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                }
                switch $0 {
                case let .Success(_, value):
                    observer.sendNext(value)
                    observer.sendCompleted()
                case let .Failure(_, error):
                    observer.sendFailed(error)
                }
            }
            disposable.addDisposable { [weak self] in
                self?.cancel()
            }
        }
    }
    
    var asyncDownloadProducer: SignalProducer <NSURL, NSError> {
        return SignalProducer { observer, disposable in
            self.response(queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { (req: NSURLRequest?, resp: NSHTTPURLResponse?, data: NSData?, error: NSError?) in
                if let suggestedDestination = resp?.suggestedDestination where nil == error {
                    observer.sendNext(suggestedDestination)
                    observer.sendCompleted()
                } else {
                    observer.sendFailed(error!)
                }
            }
            disposable.addDisposable { [weak self] in
                self?.cancel()
            }
        }
    }
    
    var producer: SignalProducer <AnyObject, NSError>  {
        return SignalProducer { observer, disposable in
            UIApplication.sharedApplication().networkActivityIndicatorVisible = true
            self.responseJSON {
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                switch $0 {
                case let .Success(_, value):
                    observer.sendNext(value)
                    observer.sendCompleted()
                case let .Failure(_, error):
                    observer.sendFailed(error)
                }
            }
            disposable.addDisposable { [weak self] in
                self?.cancel()
            }
        }
    }
}

public extension Redes.BatchRequest {
//    public var asyncProducer: SignalProducer <[AnyObject], NSError> {
//        return SignalProducer { observer, disposable in
//            self.asyncResponseJSON { (results: [Result<Response, AnyObject, NSError>]) in
//                let allSuccessed = results.reduce(true, combine: { (lastSuccessed, result: Result<Response, AnyObject, NSError>) -> Bool in
//                    return lastSuccessed && result.isSuccess
//                })
//                if allSuccessed {
//                    let values = results.map { (result: Result<Response, AnyObject, NSError>) -> AnyObject in
//                        return result.value!
//                    }
//                    observer.sendNext(values)
//                    observer.sendCompleted()
//                } else {
//                    for result in results {
//                        if result.isFailure {
//                            observer.sendFailed(result.error!)
//                            break
//                        }
//                    }
//                }
//            }
//            disposable.addDisposable {  [weak self] in
//                self?.requests.forEach { (req: Request) in
//                    req.cancel()
//                }
//            }
//        }
//    }
    
    public var asyncProducer: SignalProducer<[AnyObject], NSError> {
        let producers = requests.map { (req: Request) -> SignalProducer<AnyObject, NSError> in
            return req.asyncProducer
        }
        return combineLatest(producers)
    }
    
    public var asyncDownloadProducer: SignalProducer<[NSURL], NSError> {
        let producers = requests.map { (req: Request) -> SignalProducer<NSURL, NSError> in
            return req.asyncDownloadProducer
        }
        return combineLatest(producers)
    }
    
    public var producer: SignalProducer<[AnyObject], NSError> {
        let producers = requests.map { (req: Request) -> SignalProducer<AnyObject, NSError> in
            return req.producer
        }
        return combineLatest(producers)
    }
}

public extension Requestable where Self: Responseable {
    public var asyncProducer: SignalProducer <AnyObject, NSError>  {
        return Redes.request(self).asyncProducer
    }
    
    public var producer: SignalProducer <AnyObject, NSError>  {
        return Redes.request(self).producer
    }
}
