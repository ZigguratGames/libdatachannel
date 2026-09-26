# libdatachannel

This is [libdatachannel](https://github.com/paullouisageneau/libdatachannel) (v0.24.5), packaged for [Zig](https://ziglang.org/) 0.17.

Builds a single static `datachannel` archive containing libdatachannel plus its bundled dependencies libjuice (ICE) and usrsctp (SCTP), compiled from source with Zig's bundled clang and libc++. TLS is provided by [ZigguratGames/mbedtls](https://github.com/ZigguratGames/mbedtls).

Configuration matches upstream's `-DUSE_MBEDTLS=ON -DUSE_NICE=OFF -DNO_MEDIA=ON -DNO_WEBSOCKET=ON -DNO_EXAMPLES=ON` build (data channels only, mbedTLS backend).

```zig
const ldc = b.dependency("libdatachannel", .{ .target = target, .optimize = optimize });
mod.linkLibrary(ldc.artifact("datachannel"));
```
