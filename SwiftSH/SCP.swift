//
// The MIT License (MIT)
//
// Copyright (c) 2017 Tommaso Madonia
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

//@available(*, unavailable)
public class SCPSession: SSHChannel {
    
    // MARK: - Internal variables
    
    internal var socketSource: DispatchSourceRead?
    internal var timeoutSource: DispatchSourceTimer?
    
    // MARK: - Initialization
    
    public override init(sshLibrary: SSHLibrary.Type = Libssh2.self, host: String, port: UInt16 = 22, environment: [Environment] = [], terminal: Terminal? = nil) throws {
        try super.init(sshLibrary: sshLibrary, host: host, port: port, environment: environment, terminal: terminal)
    }
    
    deinit {
        self.cancelSources()
    }
    
    
    public override func close() {
        self.cancelSources()
        
        self.queue.async {
            super.close()
        }
    }
    
    private func cancelSources() {
        if let timeoutSource = self.timeoutSource, !timeoutSource.isCancelled {
            timeoutSource.cancel()
        }
        
        if let socketSource = self.socketSource, !socketSource.isCancelled {
            socketSource.cancel()
        }
    }
    // MARK: - Download
    private var response: Data?
    private var error: Data?
    
    public func download(_ from: String, completion: ((Data?, Error?) -> Void)?) {
        self.queue.async(completion: { (error: Error?) in
            if let error = error {
                self.close()
                
                if let completion = completion {
                    completion(nil, error)
                }
            }
        }, block: {
            self.response = nil
            self.error = nil
            
            // open SCP Channel
            let fileSize = try self.openScp(remotePath: from)
            self.log.debug("Filesize: \(fileSize)")
            
            // Read the received data
            self.socketSource = DispatchSource.makeReadSource(fileDescriptor: CFSocketGetNative(self.socket), queue: self.queue.queue)
            guard let socketSource = self.socketSource else {
                throw SSHError.allocation
            }
            
            socketSource.setEventHandler { [weak self] in
                guard let self = self, let timeoutSource = self.timeoutSource else {
                    return
                }
                
                // Suspend the timer to prevent calling completion two times
                timeoutSource.suspend()
                defer {
                    timeoutSource.resume()
                }
                
                // Set non-blocking mode
                self.session.blocking = false
                
                // read the data
                // Read the result
                var socketClosed = true
                do {
                    let data = try self.channel.read()
                    if self.response == nil {
                        self.response = Data()
                    }
                    self.response!.append(data)
                    
                    socketClosed = false
                } catch let error {
                    self.log.error("[STD] \(error)")
                }
                
                // Read the error
                do {
                    let data = try self.channel.readError()
                    if data.count > 0 {
                        if self.error == nil {
                            self.error = Data()
                        }
                        
                        self.error!.append(data)
                    }
                    
                    socketClosed = false
                } catch let error {
                    self.log.error("[ERR] \(error)")
                }
                
                // Check if we can return the response
                if self.channel.receivedEOF || self.channel.exitStatus() != nil || socketClosed {
                    defer {
                        self.cancelSources()
                    }
                    
                    if let completion = completion {
                        let result = self.response
                        var error: Error?
                        if let message = self.error {
                            error = SSHError.Command.execError(String(data: message, encoding: .utf8), message)
                        }
                        
                        self.queue.callbackQueue.async {
                            completion(result, error)
                        }
                    }
                }
            }
            socketSource.setCancelHandler { [weak self] in
                self?.close()
            }
            
            // Create the timeout handler
            self.timeoutSource = DispatchSource.makeTimerSource(queue: self.queue.queue)
            guard let timeoutSource = self.timeoutSource else {
                throw SSHError.allocation
            }
            
            timeoutSource.setEventHandler { [weak self] in
                guard let self = self else {
                    return
                }
                
                self.cancelSources()
                
                if let completion = completion {
                    let result = self.response
                    
                    self.queue.callbackQueue.async {
                        completion(result, SSHError.timeout)
                    }
                }
            }
            timeoutSource.schedule(deadline: .now() + self.timeout, repeating: self.timeout, leeway: .seconds(10))
            
            // Set blocking mode
            self.session.blocking = true
            
            // Set non-blocking mode
            self.session.blocking = false
            
            // Start listening for new data
            timeoutSource.resume()
            socketSource.resume()
        })
        
    }
    
    
    public func upload(_ to: String, data:Data, completion: ((Error?) -> Void)?) {
        self.queue.async(completion: { (error: Error?) in
            if let error = error {
                self.close()
                
                if let completion = completion {
                    completion(error)
                }
            }
        }, block: {
            self.response = nil
            self.error = nil
            
            // open SCP Channel
            do {
                try self.openScpSend(remotePath: to, size:data.count)
            } catch let error {
                self.log.error("Error OpenScpSend \(error)")
            }
            
            // Read the received data
            //            self.socketSource = DispatchSource.makeReadSource(fileDescriptor: CFSocketGetNative(self.socket), queue: self.queue.queue)
            //            guard let socketSource = self.socketSource else {
            //                throw SSHError.allocation
            //            }
            
            //            socketSource.setEventHandler { [weak self] in
            //                guard let self = self, let timeoutSource = self.timeoutSource else {
            //                    return
            //                }
            
            // Suspend the timer to prevent calling completion two times
            //                timeoutSource.suspend()
            //                defer {
            //                    timeoutSource.resume()
            //                }
            
            // Set non-blocking mode
            self.session.blocking = true
            
            // write the data
            var socketClosed = true
            
            let (error, sendBytes) = self.channel.write(data)
            print("send bytes: \(sendBytes)")
            if let error = error {
                print("\(error)")
            }
            socketClosed = false
            
            
            
            // Check if we can return the response
            if self.channel.receivedEOF || self.channel.exitStatus() != nil || socketClosed {
                defer {
                    self.cancelSources()
                }
                
                if let completion = completion {
                    //                        let result = self.response
                    var error: Error?
                    if let message = self.error {
                        error = SSHError.Command.execError(String(data: message, encoding: .utf8), message)
                    }
                    
                    self.queue.callbackQueue.async {
                        completion(error)
                    }
                }
            }
            //            }
            //            socketSource.setCancelHandler { [weak self] in
            //                self?.close()
            //            }
            
            // Create the timeout handler
            self.timeoutSource = DispatchSource.makeTimerSource(queue: self.queue.queue)
            guard let timeoutSource = self.timeoutSource else {
                throw SSHError.allocation
            }
            
            timeoutSource.setEventHandler { [weak self] in
                guard let self = self else {
                    return
                }
                
                self.cancelSources()
                
                if let completion = completion {
                    //                    let result = self.response
                    self.queue.callbackQueue.async {
                        completion(SSHError.timeout)
                    }
                }
            }
            timeoutSource.schedule(deadline: .now() + self.timeout, repeating: self.timeout, leeway: .seconds(10))
            
            // Set blocking mode
            self.session.blocking = true
            
            // Set non-blocking mode
            self.session.blocking = false
            
            // Start listening for new data
            timeoutSource.resume()
            //            socketSource.resume()
        })
        
    }
    
    
    
    #if RELEASE_VERSION
    public func download(_ from: String, to path: String) -> Self {
        self.download(from, to: path, completion: nil)
        
        return self
    }
    
    public func download(_ from: String, to path: String, completion: SSHCompletionBlock?) {
        if let stream = OutputStream(toFileAtPath: path, append: false) {
            self.download(from, to: stream, completion: completion)
        } else if let completion = completion {
            self.queue.callbackQueue.async {
                completion(SSHError.SCP.invalidPath)
            }
        }
    }
    
    
    public func download(_ from: String, to stream: OutputStream) -> Self {
        self.download(from, to: stream, completion: nil)
        
        return self
    }
    
    public func download(_ from: String, to stream: OutputStream, completion: SSHCompletionBlock?) {
        self.queue.async(completion: completion) {
            
            stream.open()
            // open the channel in scp mode
            let count = try self.openScp(remotePath: from)
            print("-->  Filesize: \(count)")
            do {
                print("Receive the data here...")
                try self.read()
                print("Got data..")
                stream.close()
            } catch {
                print("Exception")
                stream.close()
            }
        }
    }
    
    
    public func download(_ from: String, completion: @escaping ((Data?, Error?) -> Void)) {
        let stream = OutputStream.toMemory()
        self.download(from, to: stream) { error in
            if let data = stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data {
                completion(data, error)
            } else {
                completion(nil, error ?? SSHError.unknown)
            }
        }
    }
    
    // MARK: - Upload
    
    
    #endif
    
}
