//
//  UDPv4BroadcastConnection.swift
//  UDPBroadcast
//
//  Created by Gunter Hager on 10.02.16.
//  Copyright © 2016 Gunter Hager. All rights reserved.
//

import Foundation
import Darwin

/// An object representing the UDP broadcast connection. Uses a dispatch source to handle the incoming traffic on the UDP socket.
public class UDPv4BroadcastConnection: UDPBroadcastConnection {
    
    // MARK: Properties

    let INADDR_ANY = in_addr(s_addr: 0)
    /// Broadcast address 255.255.255.255
    let INADDR_BROADCAST = in_addr(s_addr: 0xffffffff)

    /// The IPv4 address of the UDP socket.
    var address: sockaddr_in

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
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    public init(port: UInt16, bindIt: Bool = false, handler: ReceiveHandler?, errorHandler: ErrorHandler?) throws {
        self.address = sockaddr_in(
            sin_len:    __uint8_t(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port:   UDPBroadcastConnection.htonsPort(port: port),
            sin_addr:   INADDR_BROADCAST,
            sin_zero:   ( 0, 0, 0, 0, 0, 0, 0, 0 )
        )
        try super.init(bindIt: bindIt, handler: handler, errorHandler: errorHandler)
    }
    
    deinit {
        if responseSource != nil {
            responseSource!.cancel()
        }
    }
    
    // MARK: Interface
    
    /// Create a UDP socket for broadcasting and set up cancel and event handlers
    ///
    /// - Throws: Throws a `ConnectionError` if an error occurs.
    override func setupSocket() throws -> Int32 {
        // Create new socket
        let newSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard newSocket > 0 else { throw ConnectionError.createSocketFailed }
        
        // Enable broadcast on socket
        var broadcastEnable = Int32(1);
        let ret = setsockopt(newSocket, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<UInt32>.size));
        if ret == -1 {
            debugPrint("Couldn't enable broadcast on socket")
            close(newSocket)
            throw ConnectionError.enableBroadcastFailed
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
        let socketLength = socklen_t(address.sin_len)
        try data.withUnsafeBytes { (broadcastMessage) in
            let broadcastMessageLength = data.count
            let sent = withUnsafeMutablePointer(to: &address) { pointer -> Int in
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
