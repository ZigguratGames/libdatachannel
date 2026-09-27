const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("libdatachannel", .{});
    const juice_dep = b.dependency("libjuice", .{});
    const usrsctp_dep = b.dependency("usrsctp", .{});
    const plog_dep = b.dependency("plog", .{});
    const mbedtls_dep = b.dependency("mbedtls", .{
        .target = target,
        .optimize = .ReleaseFast,
        .@"dtls-srtp" = true,
    });
    const mbedtls = mbedtls_dep.artifact("mbedtls");

    const windows = target.result.os.tag == .windows;
    // BSD-family sockaddrs (incl. usrsctp's sockaddr_conn) carry a length
    // byte; upstream CMake probes these with check_struct_has_member.
    const bsd_sockaddr = target.result.os.tag.isBSD();

    // libjuice (ICE), mirroring upstream CMake: static, USE_NETTLE=0.
    const juice = b.addLibrary(.{
        .name = "juice",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    juice.root_module.addCMacro("JUICE_STATIC", "");
    juice.root_module.addCMacro("JUICE_EXPORTS", "");
    juice.root_module.addCMacro("USE_NETTLE", "0");
    juice.root_module.addCMacro("RELEASE", "1");
    juice.root_module.addIncludePath(juice_dep.path("include"));
    // juice's private headers include "juice.h" directly.
    juice.root_module.addIncludePath(juice_dep.path("include/juice"));
    if (windows) {
        juice.root_module.addCMacro("WIN32_LEAN_AND_MEAN", "");
        juice.root_module.linkSystemLibrary("ws2_32", .{});
        juice.root_module.linkSystemLibrary("iphlpapi", .{});
    }
    juice.root_module.addCSourceFiles(.{
        .root = juice_dep.path("src"),
        .files = juice_sources,
        .flags = &.{},
    });
    b.installArtifact(juice);

    // usrsctp (SCTP), mirroring upstream: __Userspace__, no INET/INET6.
    // min/max macros come from user_environment.h under real MinGW headers;
    // Zig's bundled stdlib.h disables them (#if 0), so they are injected here.
    const usrsctp = b.addLibrary(.{
        .name = "usrsctp",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    usrsctp.root_module.addCMacro("__Userspace__", "");
    usrsctp.root_module.addCMacro("SCTP_DEBUG", "");
    usrsctp.root_module.addCMacro("SCTP_PROCESS_LEVEL_LOCKS", "");
    usrsctp.root_module.addCMacro("SCTP_SIMPLE_ALLOCATOR", "");
    usrsctp.root_module.addCMacro("SCTP_STDINT_INCLUDE", "<stdint.h>");
    usrsctp.root_module.addCMacro("HAVE_STDATOMIC_H", "");
    usrsctp.root_module.addCMacro("min(a,b)", "(((a) > (b)) ? (b) : (a))");
    usrsctp.root_module.addCMacro("max(a,b)", "(((a) > (b)) ? (a) : (b))");
    usrsctp.root_module.addIncludePath(usrsctp_dep.path("usrsctplib"));
    if (bsd_sockaddr) {
        usrsctp.root_module.addCMacro("HAVE_SA_LEN", "");
        usrsctp.root_module.addCMacro("HAVE_SIN_LEN", "");
        usrsctp.root_module.addCMacro("HAVE_SIN6_LEN", "");
        usrsctp.root_module.addCMacro("HAVE_SCONN_LEN", "");
    }
    if (target.result.os.tag.isDarwin()) usrsctp.root_module.addCMacro("__APPLE_USE_RFC_2292", "");
    if (target.result.os.tag == .linux) usrsctp.root_module.addCMacro("_GNU_SOURCE", "");
    if (windows) {
        usrsctp.root_module.addCMacro("WIN32_LEAN_AND_MEAN", "");
        usrsctp.root_module.linkSystemLibrary("ws2_32", .{});
        usrsctp.root_module.linkSystemLibrary("iphlpapi", .{});
    }
    usrsctp.root_module.addCSourceFiles(.{
        .root = usrsctp_dep.path("usrsctplib"),
        .files = usrsctp_sources,
        .flags = &.{},
    });
    b.installArtifact(usrsctp);

    // libdatachannel (C++17) matching upstream's
    // -DUSE_MBEDTLS=ON -DUSE_NICE=OFF -DNO_MEDIA=ON -DNO_WEBSOCKET=ON build.
    const lib = b.addLibrary(.{
        .name = "datachannel",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    const mod = lib.root_module;
    mod.addCMacro("RTC_STATIC", "");
    mod.addCMacro("RTC_EXPORTS", "");
    mod.addCMacro("RTC_ENABLE_MEDIA", "0");
    mod.addCMacro("RTC_ENABLE_WEBSOCKET", "0");
    mod.addCMacro("RTC_SYSTEM_JUICE", "0");
    mod.addCMacro("USE_MBEDTLS", "1");
    mod.addCMacro("USE_NICE", "0");
    mod.addCMacro("JUICE_STATIC", "");
    mod.addCMacro("SCTP_STDINT_INCLUDE", "<stdint.h>");
    mod.addCMacro("SCTP_DEBUG", "");
    if (bsd_sockaddr) mod.addCMacro("HAVE_SCONN_LEN", "");
    // Must match the mbedtls dep's -Ddtls-srtp so ssl.h exposes the
    // mbedtls_ssl_srtp_profile declarations used by dtlstransport.cpp.
    mod.addCMacro("MBEDTLS_SSL_DTLS_SRTP", "");
    mod.addIncludePath(upstream.path("include"));
    // impl headers include "common.hpp" etc. directly.
    mod.addIncludePath(upstream.path("include/rtc"));
    mod.addIncludePath(upstream.path("src"));
    mod.addIncludePath(plog_dep.path("include"));
    mod.addIncludePath(usrsctp_dep.path("usrsctplib"));
    mod.addIncludePath(juice_dep.path("include"));
    if (windows) {
        mod.addCMacro("WIN32_LEAN_AND_MEAN", "");
        mod.addCMacro("_CRT_SECURE_NO_WARNINGS", "");
        mod.linkSystemLibrary("ws2_32", .{});
    }
    mod.linkLibrary(juice);
    mod.linkLibrary(usrsctp);
    mod.linkLibrary(mbedtls);
    mod.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = libdatachannel_sources,
        .flags = &.{"-std=c++17"},
    });

    lib.installHeadersDirectory(upstream.path("include/rtc"), "rtc", .{});
    b.installArtifact(lib);
}

const libdatachannel_sources: []const []const u8 = &.{
    "candidate.cpp",
    "channel.cpp",
    "configuration.cpp",
    "datachannel.cpp",
    "dependencydescriptor.cpp",
    "description.cpp",
    "iceudpmuxlistener.cpp",
    "mediahandler.cpp",
    "global.cpp",
    "message.cpp",
    "peerconnection.cpp",
    "rtcpreceivingsession.cpp",
    "track.cpp",
    "websocket.cpp",
    "websocketserver.cpp",
    "rtppacketizationconfig.cpp",
    "rtcpsrreporter.cpp",
    "rtppacketizer.cpp",
    "rtpdepacketizer.cpp",
    "h264rtppacketizer.cpp",
    "h264rtpdepacketizer.cpp",
    "nalunit.cpp",
    "h265rtppacketizer.cpp",
    "h265rtpdepacketizer.cpp",
    "h265nalunit.cpp",
    "av1rtppacketizer.cpp",
    "rtcpnackresponder.cpp",
    "rtp.cpp",
    "capi.cpp",
    "plihandler.cpp",
    "pacinghandler.cpp",
    "rembhandler.cpp",
    "impl/certificate.cpp",
    "impl/channel.cpp",
    "impl/datachannel.cpp",
    "impl/dtlssrtptransport.cpp",
    "impl/dtlstransport.cpp",
    "impl/icetransport.cpp",
    "impl/iceudpmuxlistener.cpp",
    "impl/init.cpp",
    "impl/peerconnection.cpp",
    "impl/logcounter.cpp",
    "impl/sctptransport.cpp",
    "impl/threadpool.cpp",
    "impl/tls.cpp",
    "impl/track.cpp",
    "impl/utils.cpp",
    "impl/processor.cpp",
    "impl/sha.cpp",
    "impl/pollinterrupter.cpp",
    "impl/pollservice.cpp",
    "impl/http.cpp",
    "impl/httpproxytransport.cpp",
    "impl/tcpserver.cpp",
    "impl/tcptransport.cpp",
    "impl/tlstransport.cpp",
    "impl/transport.cpp",
    "impl/verifiedtlstransport.cpp",
    "impl/websocket.cpp",
    "impl/websocketserver.cpp",
    "impl/wstransport.cpp",
    "impl/wshandshake.cpp",
};

const juice_sources: []const []const u8 = &.{
    "addr.c",
    "agent.c",
    "base64.c",
    "const_time.c",
    "conn.c",
    "conn_mux.c",
    "conn_poll.c",
    "conn_thread.c",
    "crc32.c",
    "hash.c",
    "hmac.c",
    "ice.c",
    "juice.c",
    "log.c",
    "random.c",
    "server.c",
    "stun.c",
    "timestamp.c",
    "tcp.c",
    "turn.c",
    "udp.c",
};

const usrsctp_sources: []const []const u8 = &.{
    "netinet/sctp_asconf.c",
    "netinet/sctp_auth.c",
    "netinet/sctp_bsd_addr.c",
    "netinet/sctp_callout.c",
    "netinet/sctp_cc_functions.c",
    "netinet/sctp_crc32.c",
    "netinet/sctp_indata.c",
    "netinet/sctp_input.c",
    "netinet/sctp_output.c",
    "netinet/sctp_pcb.c",
    "netinet/sctp_peeloff.c",
    "netinet/sctp_sha1.c",
    "netinet/sctp_ss_functions.c",
    "netinet/sctp_sysctl.c",
    "netinet/sctp_timer.c",
    "netinet/sctp_userspace.c",
    "netinet/sctp_usrreq.c",
    "netinet/sctputil.c",
    "netinet6/sctp6_usrreq.c",
    "user_environment.c",
    "user_mbuf.c",
    "user_recv_thread.c",
    "user_socket.c",
};
