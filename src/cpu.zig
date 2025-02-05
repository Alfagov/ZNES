const std = @import("std");
const Instruction = @import("instruction.zig");

pub const Bus = struct {

    mem: [0x20000]u8 = undefined,

    pub fn read(self: *Bus, addr: u16) u8 {
        return self.mem[addr];
    }
    pub fn write(self: *Bus, addr: u16, data: u8) void {
        self.mem[addr] = data;
    }
};

const STACK_BASE: u16 = 0x0100;
const VECTOR_BASE: u8 = 0xFF;

pub const Cpu = struct {
    pub const Flag = enum(u8) {
        Carry,
        Zero,
        InterruptDisable,
        DecimalMode,
        Break,
        Reserved,
        Overflow,
        Negative,
    };

    pub const Addressing = enum {
        Immediate,
        ZeroPage,
        ZeroPageX,
        ZeroPageY,
        Absolute,
        AbsoluteX,
        AbsoluteY,
        IndirectX,
        IndirectY,
        Relative,
        Implied,
        Indirect,
    };

    // Memory
    bus: Bus,

    // Registers
    a: u8,
    x: u8,
    y: u8,
    sp: u8,
    pc: u16,

    // Flags
    carry: bool,
    zero: bool,
    interrupt_disable: bool,
    decimal: bool,
    break_: bool,
    overflow: bool,
    negative: bool,

    // Vectors
    stack_base: u16 = STACK_BASE,
    vector_base: u8 = VECTOR_BASE,

    // Info
    clocks_per_s: usize = 13000,//1_789_773,
    remaining_clocks: usize = 0,
    current_instruction: Instruction = Instruction.fromByte(0),

    pub fn init() Cpu {
        var bus = Bus{ .mem = undefined };
        @memset(&bus.mem, 0);
        return .{
            .bus = bus,
            .a = 0,
            .x = 0,
            .y = 0,
            .sp = 0xFD,
            .pc = 0,
            .carry = false,
            .zero = false,
            .interrupt_disable = false,
            .decimal = false,
            .break_ = false,
            .overflow = false,
            .negative = false,
        };
    }

    pub fn reset(self: *Cpu) void {
        self.interrupt_disable = true;

        self.sp = self.sp -% 3;
        self.pc = self.readAbsolute(0xFFFC);
    }

    inline fn bit(flag: bool, shift: u8) u8 {
        return if (flag) 1 << shift else 0;
    }

    pub fn setStatus(self: *Cpu, value: u8) void {
        self.carry = (value & (1 << 0)) != 0;
        self.zero = (value & (1 << 1)) != 0;
        self.interrupt_disable = (value & (1 << 2)) != 0;
        self.decimal = (value & (1 << 3)) != 0;
        self.overflow = (value & (1 << 6)) != 0;
        self.negative = (value & (1 << 7)) != 0;
    }

    pub fn getStatus(self: *const Cpu, b: bool) u8 {
        return bit(self.carry, 0)
            | bit(self.zero, 1)
            | bit(self.interrupt_disable, 2)
            | bit(self.decimal, 3)
            | bit(b, 4)
            | 1 << 5
            | bit(self.overflow, 6)
            | bit(self.negative, 7);
    }

    pub fn updateA(self: *Cpu, value: u8) void {
        self.a = value;
        self.updateNZFlags(value);
    }

    pub fn updateX(self: *Cpu, value: u8) void {
        self.x = value;
        self.updateNZFlags(value);
    }

    pub fn updateY(self: *Cpu, value: u8) void {
        self.y = value;
        self.updateNZFlags(value);
    }

    pub fn updateNZFlags(self: *Cpu, value: u8) void {
        self.negative = @as(i8, @bitCast(value)) < 0;
        self.zero = value == 0;
    }

    pub fn stackPop(self: *Cpu) u8 {
        self.sp +%= 1;
        const addr = STACK_BASE +% @as(u16, self.sp);
        return self.bus.read(addr);
    }

    pub fn stackPush(self: *Cpu, value: u8) void {
        const addr = STACK_BASE +% @as(u16, self.sp);
        self.bus.write(addr, value);
        self.sp -%= 1;
    }

    pub fn clock(self: *Cpu) void {
        if (self.remaining_clocks == 0) {
            self.step();
        } else {
            self.remaining_clocks -= 1;
        }
    }

    pub fn step(self: *Cpu) void {
        const opcode_byte = self.readPC();
        const instruction = Instruction.fromByte(opcode_byte);

        self.current_instruction = instruction;

        const addr: u16 = switch (instruction.addressing) {
            .Implied => 0,
            .Immediate => self.takeImmediate(),
            .ZeroPage => self.takeZeroPage(),
            .ZeroPageX => self.takeZeroPageX(),
            .ZeroPageY => self.takeZeroPageY(),
            .Absolute => self.takeAbsolute(),
            .AbsoluteX => self.takeAbsoluteX(),
            .AbsoluteY => self.takeAbsoluteY(),
            .IndirectX => self.takeIndexedIndirect(),
            .IndirectY => self.takeIndirectIndexed(),
            .Relative => self.takeRelative(),
            .Indirect => self.takeIndirect(),
        };

        instruction.opcode_fn(self, addr);
        self.remaining_clocks = instruction.cycles - 1;
    }

    fn nmi(self: *Cpu) void {
        const NMI_VECTOR: u16 = 0xFFFA;
        const lo: u8 = @intCast(self.pc & 0xFF);
        const hi: u8 = @intCast(self.pc >> 8);
        self.stackPush(hi);
        self.stackPush(lo);
        self.stackPush(self.getStatus(false));
        self.interrupt_disable = true;

        self.pc = self.readAbsolute(NMI_VECTOR);
    }

    fn irq(self: *Cpu) void {
        if (!self.interrupt_disable) {
            const NMI_VECTOR: u16 = 0xFFFE;
            const lo: u8 = @intCast(self.pc & 0xFF);
            const hi: u8 = @intCast(self.pc >> 8);
            self.stackPush(hi);
            self.stackPush(lo);
            self.stackPush(self.getStatus(false));
            self.interrupt_disable = true;

            self.pc = self.readAbsolute(NMI_VECTOR);
        }
    }

    pub fn readByte(self: *Cpu, addr: u16) u8 {
        return self.bus.read(addr);
    }

    pub fn readAbsolute(self: *Cpu, addr: u16) u16 {
        const lo = self.readByte(addr);
        const hi = self.readByte(addr + 1);
        return (@as(u16, hi) << 8) | lo;
    }

    pub fn readPC(self: *Cpu) u8 {
        const byte = self.readByte(self.pc);
        self.pc +%= 1;
        return byte;
    }

    pub fn peekPC(self: *Cpu) u8 {
        const byte = self.readByte(self.pc);
        return byte;
    }

    fn takeImmediate(self: *Cpu) u16 {
        const addr = self.pc;
        _ = self.readPC();
        return addr;
    }

    fn takeRelative(self: *Cpu) u16 {
        const offset = @as(i8, @bitCast(self.readPC()));
        const result: i16 = @as(i16, @intCast(self.pc)) +% offset;
        return @intCast(result);
    }

    fn takeZeroPage(self: *Cpu) u8 {
        return self.readPC();
    }

    fn takeIndirect(self: *Cpu) u16 {
        const addr = self.takeAbsolute();
        return self.readAbsolute(addr);
    }

    fn takeAbsolute(self: *Cpu) u16 {
        const lo = self.readPC();
        const hi = self.readPC();
        return (@as(u16, hi) << 8) | lo;
    }

    fn takeAbsoluteX(self: *Cpu) u16 {
        return self.takeAbsolute() +% self.x;
    }

    fn takeAbsoluteY(self: *Cpu) u16 {
        return self.takeAbsolute() +% self.y;
    }

    fn takeZeroPageX(self: *Cpu) u8 {
        return self.takeZeroPage() +% self.x;
    }

    fn takeZeroPageY(self: *Cpu) u8 {
        return self.takeZeroPage() +% self.y;
    }

    fn takeIndexedIndirect(self: *Cpu) u16 {
        const addr = self.takeZeroPageX();
        return self.readAbsolute(addr);
    }

    fn takeIndirectIndexed(self: *Cpu) u16 {
        const addr = self.takeZeroPage();
        return self.readAbsolute(addr) +% self.y;
    }

    pub fn loadFromFile(self: *Cpu, path: []const u8, start: u16) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var buffer: [65536]u8 = undefined;
        const size = try file.readAll(&buffer);
        std.debug.print("Size of loaded file is: {}\n", .{size});

        @memcpy(self.bus.mem[start..start+size], buffer[0..size]);
    }
};

test "functional test" {
    const BIN_START_ADDR: u16 = 0x000A;
    const PROGRAM_START: u16 = 0x0400;
    const SUCCESS_TRAP: u16 = 0x3469;

    var cpu = Cpu.init();
    try cpu.loadFromFile("tests/6502_functional_test.bin", BIN_START_ADDR);
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

test "decimal test" {
    const BIN_START_ADDR: u16 = 0x0200;
    const PROGRAM_START: u16 = 0x0200;
    const ERROR_ADDR: u16 = 0x000B;
    const DONE_ADDR: u16 = 0x024B;

    var cpu = Cpu.init();
    try cpu.loadFromFile("tests/6502_decimal_test.bin", BIN_START_ADDR);
    cpu.pc = PROGRAM_START;

    while (cpu.pc != DONE_ADDR) {
        cpu.step();
    }

    std.debug.print("LAST PC: {X}\n", .{cpu.pc});
    const opcode_byte = cpu.peekPC();
    const instruction = Instruction.fromByte(opcode_byte);
    std.debug.print("LAST INSTRUCTION: {s}\n", .{instruction.name});
    std.debug.print("FLAGS: z: {} n: {} o: {}\n", .{cpu.zero, cpu.negative, cpu.overflow});
    std.debug.print("Registers: a: {X} x: {X} y: {X} sp: {X}\n", .{cpu.a, cpu.x, cpu.y, cpu.sp});

    std.debug.assert(cpu.bus.read(ERROR_ADDR) == 0);
}

test "interrupt test" {
    const BIN_START_ADDR: u16 = 0x000A;
    const PROGRAM_START: u16 = 0x0400;
    const SUCCESS_TRAP: u16 = 0x06F5;
    const FEEDBACK_ADDR: u16 = 0xBFFC;
    const IRQ_BIT: u8 = 1 << 0;
    const NMI_BIT: u8 = 1 << 1;

    var cpu = Cpu.init();
    try cpu.loadFromFile("tests/6502_interrupt_test.bin", BIN_START_ADDR);
    cpu.pc = PROGRAM_START;
    cpu.bus.write(FEEDBACK_ADDR, 0);

    while (true) {
        const prev_feedback = cpu.bus.read(FEEDBACK_ADDR);
        const prev_pc = cpu.pc;
        cpu.step();
        const feedback = cpu.bus.read(FEEDBACK_ADDR);
        if ((feedback & (~prev_feedback)) & NMI_BIT != 0) {
            cpu.nmi();
        } else if (feedback & IRQ_BIT != 0) {
            cpu.irq();
        }

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