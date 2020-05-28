//
//  UDPBroadcastConnection.swift
//  UDPBroadcast
//
//  Created by Thomas Mellenthin on 27.05.20.
//  Copyright © 2020 Gunter Hager. All rights reserved.
//

import Foundation

protocol UDPBroadcastSocketCreating {
    func setupSocket() throws -> Int32
    func sendBroadcast(data: Data) throws
}

/// "Abstract" base class for IPv4/IPv6 upd broadcast sending
open class UDPBroadcastConnection: UDPBroadcastSocketCreating {
    
    // MARK: Properties
    
    /// Type of a closure that handles incoming UDP packets.
    public typealias ReceiveHandler = (_ ipAddress: String, _ port: Int, _ response: Data) -> Void
    /// Closure that handles incoming UDP packets.
    var handler: ReceiveHandler?
    
    /// Type of a closure that handles errors that were encountered during receiving UDP packets.
    public typealias ErrorHandler = (_ error: ConnectionError) -> Void
    /// Closure that handles errors that were encountered during receiving UDP packets.
    var errorHandler: ErrorHandler?
    
    /// A dispatch source for reading data from the UDP socket.
    var responseSource: DispatchSourceRead?
    
    /// The dispatch queue to run responseSource & reconnection on
    var dispatchQueue: DispatchQueue = DispatchQueue.main
    
    /// Internal constructor avoids instanciating of the "abstract" class. Use UDPv4BroadcastConnection() / UDPv6BroadcastConnection() instead.
    init(handler: ReceiveHandler?, errorHandler: ErrorHandler?) throws {
        self.handler = handler
        self.errorHandler = errorHandler
    }
    
    deinit {
        if responseSource != nil {
            responseSource!.cancel()
        }
    }
    
    func setupSocket() throws -> Int32  {
        fatalError("Must be implemended in a subclass.")
    }

    /// Create a UDP socket for broadcasting and set up cancel and event handlers
    ///
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    func createSocket() throws {
        
        let newSocket = try setupSocket()

        // Disable global SIGPIPE handler so that the app doesn't crash
        UDPBroadcastConnection.setNoSigPipe(socket: newSocket)
        
        // Set up a dispatch source
        let newResponseSource = DispatchSource.makeReadSource(fileDescriptor: newSocket, queue: dispatchQueue)
        
        // Set up cancel handler
        newResponseSource.setCancelHandler {
            debugPrint("Closing UDP socket")
            let UDPSocket = Int32(newResponseSource.handle)
            shutdown(UDPSocket, SHUT_RDWR)
            close(UDPSocket)
        }
        
        // Set up event handler (gets called when data arrives at the UDP socket)
        newResponseSource.setEventHandler { [unowned self] in
            guard let source = self.responseSource else { return }
            
            var socketAddress = sockaddr_storage()
            var socketAddressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let response = [UInt8](repeating: 0, count: 4096)
            let UDPSocket = Int32(source.handle)
            
            let bytesRead = withUnsafeMutablePointer(to: &socketAddress) {
                recvfrom(UDPSocket, UnsafeMutableRawPointer(mutating: response), response.count, 0, UnsafeMutableRawPointer($0).bindMemory(to: sockaddr.self, capacity: 1), &socketAddressLength)
            }
            
            do {
                guard bytesRead > 0 else {
                    self.closeConnection()
                    if bytesRead == 0 {
                        debugPrint("recvfrom returned EOF")
                        throw ConnectionError.receivedEndOfFile
                    } else {
                        if let errorString = String(validatingUTF8: strerror(errno)) {
                            debugPrint("recvfrom failed: \(errorString)")
                        }
                        throw ConnectionError.receiveFailed(code: errno)
                    }
                }
                
                guard let endpoint = withUnsafePointer(to: &socketAddress, { self.getEndpointFromSocketAddress(socketAddressPointer: UnsafeRawPointer($0).bindMemory(to: sockaddr.self, capacity: 1)) })
                    else {
                        debugPrint("Failed to get the address and port from the socket address received from recvfrom")
                        self.closeConnection()
                        return
                }
                
                debugPrint("UDP connection received \(bytesRead) bytes from \(endpoint.host):\(endpoint.port)")
                
                let responseBytes = Data(response[0..<bytesRead])
                
                // Handle response
                self.handler?(endpoint.host, endpoint.port, responseBytes)
            } catch {
                if let error = error as? ConnectionError {
                    self.errorHandler?(error)
                } else {
                    self.errorHandler?(ConnectionError.underlying(error: error))
                }
            }
        }
        
        newResponseSource.resume()
        responseSource = newResponseSource
    }
    
    
    /// Close the connection.
    ///
    /// - Parameter reopen: Automatically reopens the connection if true. Defaults to true.
    open func closeConnection(reopen: Bool = true) {
        if let source = responseSource {
            source.cancel()
            responseSource = nil
        }
        if reopen {
            dispatchQueue.async {
                do {
                    try self.createSocket()
                } catch {
                    self.errorHandler?(ConnectionError.reopeningSocketFailed(error: error))
                }
            }
        }
    }
    
    /// Send broadcast message.
    ///
    /// - Parameter message: Message to send via broadcast.
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    open func sendBroadcast(message: String) throws {
        guard let data = message.data(using: .utf8) else { throw ConnectionError.messageEncodingFailed }
        try sendBroadcast(data: data)
    }
    
    open func sendBroadcast(data: Data) throws {
        fatalError("Must be implemended in a subclass.")
    }

    // MARK: - Helpers
    
    /// Convert a sockaddr structure into an IP address string and port.
    ///
    /// - Parameter socketAddressPointer: socketAddressPointer: Pointer to a socket address.
    /// - Returns: Returns a tuple of the host IP address and the port in the socket address given.
    func getEndpointFromSocketAddress(socketAddressPointer: UnsafePointer<sockaddr>) -> (host: String, port: Int)? {
        let socketAddress = UnsafePointer<sockaddr>(socketAddressPointer).pointee
        
        switch Int32(socketAddress.sa_family) {
        case AF_INET:
            var socketAddressInet = UnsafeRawPointer(socketAddressPointer).load(as: sockaddr_in.self)
            let length = Int(INET_ADDRSTRLEN) + 2
            var buffer = [CChar](repeating: 0, count: length)
            let hostCString = inet_ntop(AF_INET, &socketAddressInet.sin_addr, &buffer, socklen_t(length))
            let port = Int(UInt16(socketAddressInet.sin_port).byteSwapped)
            return (String(cString: hostCString!), port)
            
        case AF_INET6:
            var socketAddressInet6 = UnsafeRawPointer(socketAddressPointer).load(as: sockaddr_in6.self)
            let length = Int(INET6_ADDRSTRLEN) + 2
            var buffer = [CChar](repeating: 0, count: length)
            let hostCString = inet_ntop(AF_INET6, &socketAddressInet6.sin6_addr, &buffer, socklen_t(length))
            let port = Int(UInt16(socketAddressInet6.sin6_port).byteSwapped)
            return (String(cString: hostCString!), port)
            
        default:
            return nil
        }
    }
    
    /// Prevents crashes when blocking calls are pending and the app is paused (via Home button).
    ///
    /// - Parameter socket: The socket for which the signal should be disabled.
    static func setNoSigPipe(socket: CInt) {
        var no_sig_pipe: Int32 = 1;
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &no_sig_pipe, socklen_t(MemoryLayout<Int32>.size));
    }
    
    static func htonsPort(port: in_port_t) -> in_port_t {
        let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
        return isLittleEndian ? _OSSwapInt16(port) : port
    }
    
    static func ntohs(value: CUnsignedShort) -> CUnsignedShort {
        return (value << 8) + (value >> 8)
    }
}
