const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const busses = @import("bus.zig");
const Rom = @import("rom.zig").Rom;
const test_programs = @import("test_programs.zig");
const view_debugger = @import("view_debugger.zig");
const rl = @import("raylib");
const FE = @import("frontend.zig");

var log_writer: ?std.io.AnyWriter = null;

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    _ = message_level;
    if (log_writer) |l_writer| {
        //l_writer.print("{s}: ", .{@tagName(scope)}) catch unreachable;
        l_writer.print(format, args) catch unreachable;
    }
}

pub const std_options = std.Options{
    .log_level = std.log.Level.debug,
    .logFn = logFn,
};

pub fn main() !void {

    const file = try std.fs.cwd().createFile("run_log.log", .{});
    defer file.close();

    log_writer = file.writer().any();

    var bus = busses.NesBus.init();
    bus.loadRom("tests/roms/Donkey Kong.nes") catch {
        std.debug.print("WARNING: error loading default rom\n", .{});
    };
    var cpu = Cpu.init(bus.interface());
    bus.setupCpu(&cpu);
    bus.reset();

    var fe = try FE.init(&bus, 1024, 768);
    try fe.run();
}

