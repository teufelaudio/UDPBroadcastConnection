//
//  UDPBroadcastConnection.swift
//  UDPBroadcast
//
//  Created by Thomas Mellenthin on 27.05.20.
//  Copyright © 2020 Gunter Hager. All rights reserved.
//

import Foundation

/// An object representing the UDP broadcast connection. Uses a dispatch source to handle the incoming traffic on the UDP socket.
open class UDPBroadcastConnection {
    
    public enum AddressFamily {
        case ipv4
        case ipv6
    }
    
    /// Broadcast address 255.255.255.255
    static let INADDR_BROADCAST = in_addr(s_addr: 0xffffffff)

    /// Long form of "ff02::1" Multicast to all link-local nodes (must be bound to an interface)
    static let INADDR6_BROADCAST = "ff02:0000:0000:0000:0000:0000:0000:0001"

    // MARK: Properties
    
    /// IPv4 or IPv6
    private let addressFamily: AddressFamily

    /// The IPv4 address of the UDP socket.
    var v4address: sockaddr_in
    
    /// The IPv6 address of the UDP socket.
    var v6address: sockaddr_in6
    
    /// Name of the network interface, usually "en0" (needed for IPv6 only)
    let interface: String

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
    
    /// Initializes the UDP connection with the correct port address.
    
    /// - Note: This doesn't open a socket! The socket is opened transparently as needed when sending broadcast messages. If you want to open a socket
    ///   immediately, use the `bindIt` parameter. This will also try to reopen the socket if it gets closed.
    ///
    /// - Parameters:
    ///   - addressFamily: .ipv4 or .ipv6
    ///   - interface: Name of the network interface, usually "en0" (needed for IPv6 only)
    ///   - port: Number of the UDP port to use.
    ///   - handler: Handler that gets called when data is received.
    ///   - errorHandler: Handler that gets called when an error occurs.
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    public init(addressFamily: AddressFamily, interface: String = "en0", port: UInt16, handler: ReceiveHandler?, errorHandler: ErrorHandler?) throws {
        self.addressFamily = addressFamily
        self.interface = interface
        self.handler = handler
        self.errorHandler = errorHandler
        
        switch addressFamily {
        case .ipv4:
            self.v4address = UDPBroadcastConnection.setupv4Address(port: port)
            // initialise v6 as well with a dummy address to avoid v6address being an optional
            self.v6address = sockaddr_in6(sin6_len: UInt8(MemoryLayout<sockaddr_in6>.size),
                                          sin6_family: sa_family_t(AF_INET6),
                                          sin6_port: 0,
                                          sin6_flowinfo: 0,
                                          sin6_addr: in6_addr(),
                                          sin6_scope_id: 0)
        case .ipv6:
            self.v6address = try UDPBroadcastConnection.setupv6Address(port: port)
            // initialise v4 as well with a dummy address to avoid v4address being an optional
            self.v4address = sockaddr_in(sin_len:    __uint8_t(MemoryLayout<sockaddr_in>.size),
                                         sin_family: sa_family_t(AF_INET),
                                         sin_port:   0,
                                         sin_addr:   in_addr(),
                                         sin_zero:   ( 0, 0, 0, 0, 0, 0, 0, 0 ))
        }
    }
    
    deinit {
        if responseSource != nil {
            responseSource!.cancel()
        }
    }
    
    private static func setupv4Address(port: in_port_t) -> sockaddr_in {
        return sockaddr_in(
            sin_len:    __uint8_t(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port:   UDPBroadcastConnection.htonsPort(port: port),
            sin_addr:   UDPBroadcastConnection.INADDR_BROADCAST,
            sin_zero:   ( 0, 0, 0, 0, 0, 0, 0, 0 )
        )
    }
    
    private static func setupv6Address(port: in_port_t) throws -> sockaddr_in6 {
        var addr = in6_addr()
        let ret = withUnsafeMutablePointer(to: &addr) {
            inet_pton(AF_INET6, UDPBroadcastConnection.INADDR6_BROADCAST, UnsafeMutablePointer($0))
        }
        
        if ret == 0 {
            throw ConnectionError.createv6AddressFailed(message: "Invalid address")
        } else if ret == -1 {
            var msg: String = ""
            if let errorString = String(validatingUTF8: strerror(errno)) {
                msg = errorString
            }
            throw ConnectionError.createv6AddressFailed(message: "Failed: \(msg) (\(errno))")
        }
        // addr contains the result.
        
        return sockaddr_in6(
            sin6_len: UInt8(MemoryLayout<sockaddr_in6>.size),
            sin6_family: sa_family_t(AF_INET6),
            sin6_port: UDPBroadcastConnection.htonsPort(port: port),
            sin6_flowinfo: 0,
            sin6_addr: addr,
            sin6_scope_id: 0
        )
    }
    
    /// Create a UDP socket for broadcasting
    ///
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    private func setupSocket(addressFamily: AddressFamily, interface: String) throws -> Int32 {
        
        let newSocket: Int32
        let ret: Int32
        
        switch addressFamily {
        case .ipv4:
            newSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard newSocket > 0 else { throw ConnectionError.createSocketFailed }
            var broadcastEnable = Int32(1);
            ret = setsockopt(newSocket, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<UInt32>.size));
        case .ipv6:
            newSocket = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
            guard newSocket > 0 else { throw ConnectionError.createSocketFailed }
            let index = if_nametoindex(interface.cString(using: .ascii))
            var scope: UInt32 = UInt32(index)
            ret = setsockopt(newSocket, IPPROTO_IPV6, IPV6_MULTICAST_IF, &scope, socklen_t(MemoryLayout<UInt32>.size));
        }
        
        // Enable broadcast on socket
        if ret == -1 {
            debugPrint("Couldn't enable broadcast on socket")
            close(newSocket)
            throw ConnectionError.enableBroadcastFailed
        }
        
        return newSocket
    }

    /// Create a UDP socket for broadcasting and set up cancel and event handlers
    ///
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    private func createSocket() throws {
        
        let newSocket = try setupSocket(addressFamily: addressFamily, interface: interface)

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
        switch addressFamily {
        case .ipv4:
            try sendBroadcastv4(data: data)
        case .ipv6:
            try sendBroadcastv6(data: data)
        }
    }
    
    /// Send broadcast data.
    ///
    /// - Parameter data: Data to send via broadcast.
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    private func sendBroadcastv4(data: Data) throws {
        if responseSource == nil {
            try createSocket()
        }
        
        guard let source = responseSource else { return }
        let UDPSocket = Int32(source.handle)
        let socketLength = socklen_t(v4address.sin_len)
        try data.withUnsafeBytes { (broadcastMessage) in
            let broadcastMessageLength = data.count
            let sent = withUnsafeMutablePointer(to: &v4address) { pointer -> Int in
                let memory = UnsafeRawPointer(pointer).bindMemory(to: sockaddr.self, capacity: 1)
                return sendto(UDPSocket, broadcastMessage.baseAddress, broadcastMessageLength, 0, memory, socketLength)
            }
            
            guard sent > 0 else {
                if let errorString = String(validatingUTF8: strerror(errno)) {
                    debugPrint("UDP connection failed to send data: \(errorString)")
                }
                closeConnection()
                throw ConnectionError.sendingMessageFailed(code: errno)
            }
            
            if sent == broadcastMessageLength {
                // Success
                debugPrint("UDP connection sent \(broadcastMessageLength) bytes")
            }
        }
    }
    
    /// Send broadcast data.
    ///
    /// - Parameter data: Data to send via broadcast.
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    private func sendBroadcastv6(data: Data) throws {
        if responseSource == nil {
            try createSocket()
        }
        
        guard let source = responseSource else { return }
        let UDPSocket = Int32(source.handle)
        let socketLength = socklen_t(v6address.sin6_len)
        try data.withUnsafeBytes { (broadcastMessage) in
            let broadcastMessageLength = data.count
            let sent = withUnsafeMutablePointer(to: &v6address) { pointer -> Int in
                let memory = UnsafeRawPointer(pointer).bindMemory(to: sockaddr.self, capacity: 1)
                return sendto(UDPSocket, broadcastMessage.baseAddress, broadcastMessageLength, 0, memory, socketLength)
            }
            
            guard sent > 0 else {
                if let errorString = String(validatingUTF8: strerror(errno)) {
                    debugPrint("UDP connection failed to send data: \(errorString)")
                }
                closeConnection()
                throw ConnectionError.sendingMessageFailed(code: errno)
            }
            
            if sent == broadcastMessageLength {
                // Success
                debugPrint("UDP connection sent \(broadcastMessageLength) bytes")
            }
        }
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
