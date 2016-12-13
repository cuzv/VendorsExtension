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

import Foundation
import ReactiveCocoa
import ReactiveSwift
import enum Result.NoError
import enum Result.Result
import ExtensionKit
import TinyCoordinator
import Redes

// MARK: -

public extension SignalProducerProtocol {
    @discardableResult
    public func startWithSuccess(_ success: @escaping (Self.Value) -> Void) -> Disposable {
        return startWithResult { (result: Result<Self.Value, Self.Error>) in
            if case .success(let value) = result {
                success(value)
            }
        }
    }
}

public extension SignalProtocol {
    @discardableResult
    public func observeSuccess(_ success: @escaping (Self.Value) -> Void) -> Disposable? {
        return observeResult { (result: Result<Self.Value, Self.Error>) in
            if case .success(let value) = result {
                success(value)
            }
        }
    }
}

// MARK: - SignalProducer

public extension SignalProducer {
    public func ignoreError() -> SignalProducer<Value, NoError> {
        return flatMapError({ _ in SignalProducer<Value, NoError>.empty })
    }
    
    public func observeOnUIScheduler() -> SignalProducer<Value, Error> {
        return observe(on: UIScheduler())
    }
    
    public func skipOnce() -> SignalProducer<Value, Error> {
        return skip(first: 1)
    }
    
    public func takeOnce() -> SignalProducer<Value, Error> {
        return take(first: 1)
    }
    
    public func filterEmpty() -> SignalProducer<Value, Error> {
        return filter { (value: Value) -> Bool in
            if let arr = value as? [Any] {
                return !arr.isEmpty
            } else if let dict = value as? [String: Any] {
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

public extension SignalProducer {
    public func rac_values(_ initialValue: Value) -> MutableProperty<Value> {
        let property = MutableProperty<Value>(initialValue)
        
        startWithSuccess { (value) in
            property.value = value
        }
        
        return property
    }
    
    public func rac_errors(_ initialValue: Error) -> MutableProperty<Error> {
        let property = MutableProperty<Error>(initialValue)
        
        startWithFailed { (error) -> () in
            property.value = error
        }
        
        return property
    }
}

// MARK: -

public func merge<Value, Error: Swift.Error>(_ producers: [SignalProducer<Value, Error>]) -> SignalProducer<Value, Error> {
    return SignalProducer<SignalProducer<Value, Error>, Error>(values: producers).flatten(.merge)
}

// MARK: - Signal

public extension Signal {
    public func rac_next(_ initialValue: Value) -> MutableProperty<Value> {
        let property = MutableProperty<Value>(initialValue)
        
        observeSuccess { (value) -> () in
            property.value = value
        }
        
        return property
    }
    
    public func rac_errors(_ initialValue: Error) -> MutableProperty<Error> {
        let property = MutableProperty<Error>(initialValue)
        
        observeFailed { (error) -> () in
            property.value = error
        }
        
        return property
    }
    
    public func observeOnUIScheduler() -> Signal<Value, Error> {
        return observe(on: UIScheduler())
    }
}

// MARK: - Action

public extension Action {
    public func rac_errors(_ initialValue: Error) -> MutableProperty<Error> {
        return errors.rac_next(initialValue)
    }
    
    public func rac_values(_ initialValue: Output) -> MutableProperty<Output> {
        return values.rac_next(initialValue)
    }
}

// MARK: -

public func merge<Value, Error: Swift.Error>(_ signals: [Signal<Value, Error>]) -> Signal<Value, Error> {
    return Signal<Value, Error>.merge(signals)
}

public func mergeErrors(_ errors: [Signal<NSError, NoError>]) -> MutableProperty<NSError> {
    return merge(errors).rac_next(NSError.empty)
}

public func mergeActionsErrors<Input, Output>(_ actions: [ReactiveSwift.Action<Input, Output, NSError>]) -> MutableProperty<NSError> {
    return mergeErrors(actions.map { $0.errors })
}

public func mergeValues<Output>(_ values: [Signal<Output, NoError>], initialValue: Output) -> MutableProperty<Output> {
    return merge(values).rac_next(initialValue)
}

public func mergeActionsValues<Input, Output>(_ actions: [ReactiveSwift.Action<Input, Output, NSError>], initialValue: Output) -> MutableProperty<Output> {
    return mergeValues(actions.map( { $0.values }), initialValue: initialValue)
}

public func mergeExecuting(_ executings: [Property<Bool>]) -> Property<Bool> {
    return Property(initial: false, then: merge(executings.map { $0.producer }))
}

public func mergeActionsExecuting<Input, Output>(_ actions: [ReactiveSwift.Action<Input, Output, NSError>]) -> Property<Bool> {
    return Property(initial: false, then: merge(actions.map { $0.isExecuting.producer }))
}

// MARK: - CocoaAction

public extension UIControl {
    public func addCocoaAction(target: CocoaAction<Any>, forControlEvents events: UIControlEvents = .touchUpInside) {
        addTarget(target, action: CocoaAction<Any>.selector, for: events)
    }
}


// MARK: - Timer

final public class CountdownTimer {
    fileprivate let startTime: Date
    fileprivate let interval: Int
    fileprivate let duration: Int
    fileprivate var next: ((Int) -> ())
    fileprivate var completion: (() -> ())
    
    fileprivate var disposable: Disposable?
    
    public init(
        startTime: Date = Date(),
        interval: Int = 1,
        duration: Int = 60,
        next: @escaping ((Int) -> ()),
        completion: @escaping (() -> ()))
    {
        self.startTime = startTime
        self.interval = interval
        self.duration = duration
        self.next = next
        self.completion = completion
    }
    
    public func start() {
        disposable = timer(interval: .seconds(interval), on: QueueScheduler.main).on(
            disposed: {
                self.completion()
        },
            value: {
                let overTimeInterval: Int = Int($0.timeIntervalSince(self.startTime))
                let leftTimeInterval = self.duration - overTimeInterval
                self.next(leftTimeInterval)
                if leftTimeInterval <= 0 {
                    self.disposable?.dispose()
                }
        }
            ).start()
    }
    
    deinit {
        logging("\(#file):\(#line):\(type(of: self)):\(#function)")
    }
}

// MARK: - MutableProperty
//  https://github.com/ColinEberhardt/ReactiveTwitterSearch/blob/master/ReactiveTwitterSearch/Util/UIKitExtensions.swift

private struct AssociationKey {
    fileprivate static var hidden: String  = "rac_hidden"
    fileprivate static var alpha: String   = "rac_alpha"
    fileprivate static var text: String    = "rac_text"
    fileprivate static var image: String   = "rac_image"
    fileprivate static var enabled: String = "rac_enabled"
    fileprivate static var index: String = "rac_index"

    fileprivate static var delegate: String = "rac_delegate"
    fileprivate static var search: String = "rac_search"

}

/// Lazily creates a gettable associated property via the given factory.
internal func lazyAssociatedProperty<T: AnyObject>(
    host: AnyObject,
    key: UnsafeRawPointer,
    factory: ()->T) -> T
{
    return objc_getAssociatedObject(host, key) as? T ?? {
        let associatedProperty = factory()
        objc_setAssociatedObject(host, key, associatedProperty, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        return associatedProperty
        }()
}

private func lazyMutableProperty<T>(
    host: AnyObject,
    key: UnsafeRawPointer,
    setter: @escaping (T) -> (),
    getter: @escaping () -> T) -> MutableProperty<T>
{
    return lazyAssociatedProperty(host: host, key: key) {
        let property = MutableProperty<T>(getter())
        property.producer.startWithSuccess { newValue in
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
            setter: { self.isHidden = $0 },
            getter: { self.isHidden  }
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
            self.addTarget(self, action: #selector(UISegmentedControl.changed), for: .valueChanged)
            
            let property = MutableProperty<Int>(0)
            property.producer.startWithSuccess{ newValue in
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
        return SignalProducer(signal: reactive.continuousTextValues)
            .filter { $0 != nil }
            .map({ (str: String?) -> String in
                if let str = str {
                    return str
                }
                return ""
            })
            .ignoreError()
    }
    
    public var rac_text: MutableProperty<String> {
        return rac_textSignalProducer().rac_values(text ?? "")
    }
}

public extension UITextView {
    public func rac_textSignalProducer() -> SignalProducer<String, NoError> {
        return SignalProducer(signal: reactive.continuousTextValues)
            .map({ (str: String?) -> String in
                if let str = str {
                    return str
                }
                return ""
            })
            .ignoreError()
    }
    
    public var rac_text: MutableProperty<String> {
        return rac_textSignalProducer().rac_values(text ?? "")
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
            setter: { self.isEnabled = $0 },
            getter: { self.isEnabled }
        )
    }
}

extension UISearchBar {
    var rac_text: MutableProperty<String?> {
        return lazyAssociatedProperty(host: self, key: &AssociationKey.text) {
            self.delegate = self.delegateProxy
            let property = MutableProperty<String?>(self.text)
            property <~ self.delegateProxy.textPipe.signal
            return property
        }
    }
    
    var rac_search: MutableProperty<String?> {
        return lazyAssociatedProperty(host: self, key: &AssociationKey.search) {
            self.delegate = self.delegateProxy
            let property = MutableProperty<String?>(self.text)
            property <~ self.delegateProxy.searchPipe.signal
            return property
        }
    }
    
    private var delegateProxy: UISearchBarDelegateProxy {
        return lazyAssociatedProperty(host: self, key: &AssociationKey.delegate) {
            return UISearchBarDelegateProxy(textPipe: Signal<String?, NoError>.pipe(), searchPipe: Signal<String?, NoError>.pipe())
        }
    }
    
    typealias Pipe = (signal: Signal<String?, NoError>, observer: Observer<String?, NoError>)
    private class UISearchBarDelegateProxy: NSObject, UISearchBarDelegate {
        let textPipe: Pipe
        let searchPipe: Pipe
        init(textPipe: Pipe, searchPipe: Pipe) {
            self.textPipe = textPipe
            self.searchPipe = searchPipe
        }
        
        @objc func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            textPipe.observer.send(value: searchBar.text)
        }
        
        @objc func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchPipe.observer.send(value: searchBar.text)
        }
    }
}


// MARK: - Redes

extension RedesError {
    /// A localized message describing what error occurred.
    public var nserror: NSError {
        switch self {
        case .internalFailed(reason: let reason):
            return reason as NSError
        case .parseFailed(reason: _):
            return NSErrorFrom(message: "解析数据失败")
        case .businessFailed(reason: let reason):
            return NSErrorFrom(message: reason.message)
        }
    }
}


private extension Redes.DataRequest {
    var producer: SignalProducer <Any, NSError>  {
        return SignalProducer { observer, disposable in
            self.responseJSON { (resp: DataResponse<Any>) -> () in
                switch resp.result {
                case let .success(value):
                    observer.send(value: value)
                    observer.sendCompleted()
                case let .failure(error):
                    observer.send(error: error.nserror)
                }
            }
            disposable.add {
                self.cancel()
            }
        }
    }
    
    var asyncProducer: SignalProducer <Any, NSError>  {
        return SignalProducer { observer, disposable in
            self.responseJSON(queue: DispatchQueue.global()) { (resp: DataResponse<Any>) -> () in
                switch resp.result {
                case let .success(value):
                    observer.send(value: value)
                    observer.sendCompleted()
                case let .failure(error):
                    observer.send(error: error.nserror)
                }
            }
            disposable.add {
                self.cancel()
            }
        }
    }
}

private extension Redes.DownloadRequest {
    var asyncProducer: SignalProducer <Any, NSError>  {
        return SignalProducer { observer, disposable in
            self.response(queue: DispatchQueue.global()) { (resp: DefaultDownloadResponse) in
                if let destinationURL = resp.destinationURL, resp.error == nil {
                    observer.send(value: destinationURL)
                    observer.sendCompleted()
                } else {
                    observer.send(error: NSErrorFrom(message: resp.error!.localizedDescription))
                }
            }
            disposable.add {
                self.cancel()
            }
        }
    }
}

public extension Redes.BatchRequest {
    public var producer: SignalProducer<[Any], NSError> {
        let producers = requests.map { (req: Requestable) -> SignalProducer<Any, NSError> in
            return req.producer
        }
        return SignalProducer.combineLatest(producers)
    }
    
    public var asyncProducer: SignalProducer<[Any], NSError> {
        let producers = requests.map { (req: Requestable) -> SignalProducer<Any, NSError> in
            return req.asyncProducer
        }
        return SignalProducer.combineLatest(producers)
    }
    
    public var asyncDownloadProducer: SignalProducer<[URL], NSError> {
        let producers = requests.map { (req: Requestable) -> SignalProducer<URL, NSError> in
            if let req = req as? Downloadable {
                return req.asyncProducer
            }
            return SignalProducer.empty
        }
        return SignalProducer.combineLatest(producers)
    }
}

public extension Redes.Requestable {
    public var asyncProducer: SignalProducer <Any, NSError>  {
        return makeRequest().resume().asyncProducer
    }
    
    public var producer: SignalProducer <Any, NSError>  {
        return makeRequest().resume().asyncProducer
    }
}

public extension Redes.Downloadable {
    public var asyncProducer: SignalProducer <URL, NSError> {
        return makeRequest().resume().asyncProducer.map { $0 as! URL }
    }
}






