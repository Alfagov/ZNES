const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Instruction = @import("cpu.zig").Instruction;


pub fn main() !void {
    const BIN_START_ADDR: u16 = 0x000A;
    const PROGRAM_START: u16 = 0x0400;
    const SUCCESS_TRAP: u16 = 0x3469;

    var cpu = Cpu.init();
    try cpu.loadFromFile("src/6502_functional_test.bin", BIN_START_ADDR);
    cpu.pc = PROGRAM_START;

    while (true) {
        const prev_pc = cpu.pc;
        cpu.step();
        if (cpu.pc == prev_pc) {
            break;
        }
    }

    std.debug.print("LAST PC: {X}\n", .{cpu.pc});
    const opcode_byte = cpu.peekPC();
    const instruction = Instruction.fromByte(opcode_byte);
    std.debug.print("LAST INSTRUCTION: {s}\n", .{instruction.name});
    std.debug.print("FLAGS: z: {} n: {} o: {}\n", .{cpu.zero, cpu.negative, cpu.overflow});
    std.debug.print("Registers: a: {X} x: {X} y: {X} sp: {X}\n", .{cpu.a, cpu.x, cpu.y, cpu.sp});

    std.debug.assert(cpu.pc == SUCCESS_TRAP);
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
