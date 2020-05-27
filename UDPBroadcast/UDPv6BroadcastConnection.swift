//
//  UDPv6BroadcastConnection.swift
//  UDPBroadcast
//
//  Created by Gunter Hager on 10.02.16.
//  Copyright © 2016 Gunter Hager. All rights reserved.
//

import Foundation
import Darwin


/// An object representing the UDP broadcast connection. Uses a dispatch source to handle the incoming traffic on the UDP socket.
public class UDPv6BroadcastConnection: UDPBroadcastConnection {
    
    // MARK: Properties
    
    /// Long form of "ff02::1" Multicast to all link-local nodes (must be bound to an interface)
    static let LINK_LOCAL_NODES = "ff02:0000:0000:0000:0000:0000:0000:0001"

    /// The IPv6 address of the UDP socket.
    var v6address: sockaddr_in6
    
    // MARK: Initializers
    
    /// Initializes the UDP connection with the correct port address.
    
    /// - Note: This doesn't open a socket! The socket is opened transparently as needed when sending broadcast messages. If you want to open a socket
    ///   immediately, use the `bindIt` parameter. This will also try to reopen the socket if it gets closed.
    ///
    /// - Parameters:
    ///   - port: Number of the UDP port to use.
    ///   - bindIt: Opens a port immediately if true, on demand if false. Default is false.
    ///   - handler: Handler that gets called when data is received.
    ///   - errorHandler: Handler that gets called when an error occurs.
    ///
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    public init(port: UInt16, bindIt: Bool = false, handler: ReceiveHandler?, errorHandler: ErrorHandler?) throws {

        var addr = in6_addr()
        let ret = withUnsafeMutablePointer(to: &addr) {
            inet_pton(AF_INET6, UDPv6BroadcastConnection.LINK_LOCAL_NODES, UnsafeMutablePointer($0))
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
        
        self.v6address = sockaddr_in6(
            sin6_len: UInt8(MemoryLayout<sockaddr_in6>.size),
            sin6_family: sa_family_t(AF_INET6),
            sin6_port: UDPv6BroadcastConnection.htonsPort(port: port),
            sin6_flowinfo: 0,
            sin6_addr: addr,
            sin6_scope_id: 0
        )

        try super.init(bindIt: bindIt, handler: handler, errorHandler: errorHandler)
    }
    
    override func setupSocket() throws -> Int32 {
        
        let newSocket = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
        guard newSocket > 0 else { throw ConnectionError.createSocketFailed }
        
        // Enable broadcast on socket
        let index = if_nametoindex("en0".cString(using: .ascii))
        var scope: UInt32 = UInt32(index)
        let ret = setsockopt(newSocket, IPPROTO_IPV6, IPV6_MULTICAST_IF, &scope, socklen_t(MemoryLayout<UInt32>.size));
        if ret == -1 {
            debugPrint("Couldn't enable broadcast on socket")
            close(newSocket)
            throw ConnectionError.enableBroadcastFailed
        }

        // Bind socket if needed
        if shouldBeBound {
            // FIXME: not yet implemented
            debugPrint("FIXME: implement IPv6 binding!")
            throw ConnectionError.createSocketFailed
        }
        
        return newSocket
    }

    /// Send broadcast data.
    ///
    /// - Parameter data: Data to send via broadcast.
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    open override func sendBroadcast(data: Data) throws {
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
}
