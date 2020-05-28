# UDPBroadcastConnection

<a href="https://developer.apple.com/swift"><img src="https://img.shields.io/badge/Language-Swift 5-orange.svg" alt="Language: Swift 5.0" /></a>
<a href="https://github.com/Carthage/Carthage"><img src="https://img.shields.io/badge/Carthage-compatible-brightgreen.svg" alt="Carthage compatible" /></a>

Framework to send UDP broadcast messages and listen to responses using a [Dispatch](https://developer.apple.com/reference/dispatch) dispatch source.

## Requirements

iOS 9.3+, Swift 5.0

## Usage

An example app is included demonstrating UDPBroadcastConnection's functionality. The example probably won't work for you out of the box since you need someone to listen and respond on the correct UDP port on your network.

### Getting Started

Create an `UDPv4BroadcastConnection` on port `35602` with a closure that handles the response:

```swift
broadcastConnection = try UDPv4BroadcastConnection(
  port: 35602,
  handler: { (response: (ipAddress: String, port: Int, response: [UInt8])) -> Void in
    print("Received from \(response.ipAddress):\(response.port):\n\n\(response.response)")
	},
  errorHandler: { (error) in 
    print(error)
  })
```

Note: Make sure to keep a strong reference to `broadcastConnection` (e.g. by storing it in a property) to be able to receive responses.

Send a message via broadcast:

```swift
try broadcastConnection.sendBroadcast("This is a test!")
```

### IPv6 support

There is also support for link-local multicasts to `fe02::1` via `UDPv6BroadcastConnection`. This needs to be scoped to a network interface. Usually `en0` is the
right choice, however you should figure out programmatically the default network interface (i.e. via the `NWPathMonitor` class in the Network framework).

This example sets up two connections, one for IPv4 and one for IPv6:

```swift
broadcastv4Connection = try UDPBroadcastConnection(
  addressFamily: .ipv4,
  port: 35602,
  handler: { (response: (ipAddress: String, port: Int, response: [UInt8])) -> Void in
    print("Received from \(response.ipAddress):\(response.port):\n\n\(response.response)")
    },
  errorHandler: { (error) in 
    print(error)
  })

broadcastv6Connection = try UDPBroadcastConnection(
  addressFamily: .ipv6,
  interface: "en0",
  port: 35602,
  handler: { (response: (ipAddress: String, port: Int, response: [UInt8])) -> Void in
    print("Received from \(response.ipAddress):\(response.port):\n\n\(response.response)")
    },
  errorHandler: { (error) in 
    print(error)
  })
  
```

Send a messages via broadcast:

```swift
try broadcastv4Connection.sendBroadcast("This is an IPv4 test!")
try broadcastv6Connection.sendBroadcast("This is an IPv6 test!")
```


### Try it out

You can test the broadcast and the handler for receiving messages by running the included `receive_and_reply.py`  script (tested with Python 2.7.10) on your Mac. If you send a broadcast with the example app, you should see the message that was sent in the terminal and see the script's answer in the example app.

## Installation

### Carthage

Add the following line to your [Cartfile](https://github.com/Carthage/Carthage/blob/master/Documentation/Artifacts.md#cartfile).

```
github "gunterhager/UDPBroadcastConnection"
```

Then run `carthage update`.

### Manually

Just drag and drop the `.swift` files in the `UDPBroadcastConnection` folder into your project.

## License

`UDPBroadcastConnection` is available under the MIT license. See the [LICENSE](https://github.com/gunterhager/UDPBroadcastConnection/blob/master/LICENSE) file for details.


Made with ❤ at [all about apps](https://www.allaboutapps.at).

[<img src="https://github.com/gunterhager/UDPBroadcastConnection/blob/master/Resources/aaa_logo.png" height="60" alt="all about apps" />](https://www.allaboutapps.at)
