# Substrate SCALE Codec for Zig

A Zig implementation of the SCALE (Simple Concatenated Aggregate Little-Endian) encoding and decoding library for Substrate blockchain projects.

## Overview

SCALE is a lightweight, efficient encoding and decoding codec used extensively in the Polkadot/Substrate ecosystem. This library provides a Zig implementation based on the [Parity SCALE codec](https://github.com/paritytech/parity-scale-codec).

## Installation

```sh
zig fetch --save git+https://github.com/RomarQ/substrate-scale-zig/#HEAD
```

## Usage

### Basic Example

```zig
const std = @import("std");
const scale = @import("scale");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Encoding
    const value: u32 = 42;
    const encoded = try scale.encoder.encodeAlloc(allocator, value);
    defer allocator.free(encoded);
    
    // Decoding
    const result = try scale.decoder.decodeAlloc(u32, encoded, allocator);
    std.debug.print("Decoded value: {}\n", .{result.value});
}
```

## Testing

Run the tests with:

```bash
zig build test --summary all
```