const std = @import("std");

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

    bus: Bus,
    a: u8,
    x: u8,
    y: u8,
    sp: u8,
    pc: u16,

    carry: bool,
    zero: bool,
    interrupt_disable: bool,
    decimal: bool,
    break_: bool,
    overflow: bool,
    negative: bool,

    pub fn init() Cpu {
        return .{
            .bus = Bus{ .mem = undefined },
            .a = 0,
            .x = 0,
            .y = 0,
            .sp = 0,
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

    fn setStatus(self: *Cpu, value: u8) void {
        self.carry = (value & (1 << 0)) != 0;
        self.zero = (value & (1 << 1)) != 0;
        self.interrupt_disable = (value & (1 << 2)) != 0;
        self.decimal = (value & (1 << 3)) != 0;
        self.overflow = (value & (1 << 6)) != 0;
        self.negative = (value & (1 << 7)) != 0;
    }

    inline fn bit(flag: bool, shift: u8) u8 {
        return if (flag) 1 << shift else 0;
    }

    fn getStatus(self: *const Cpu, b: bool) u8 {
        return bit(self.carry, 0)
            | bit(self.zero, 1)
            | bit(self.interrupt_disable, 2)
            | bit(self.decimal, 3)
            | bit(b, 4)
            | 1 << 5
            | bit(self.overflow, 6)
            | bit(self.negative, 7);
    }

    fn updateA(self: *Cpu, value: u8) void {
        self.a = value;
        self.updateNZFlags(value);
    }

    fn updateX(self: *Cpu, value: u8) void {
        self.x = value;
        self.updateNZFlags(value);
    }

    fn updateY(self: *Cpu, value: u8) void {
        self.y = value;
        self.updateNZFlags(value);
    }

    fn updateNZFlags(self: *Cpu, value: u8) void {
        self.negative = @as(i8, @bitCast(value)) < 0;
        self.zero = value == 0;
    }

    fn stackPop(self: *Cpu) u8 {
        self.sp +%= 1;
        const addr = STACK_BASE +% @as(u16, self.sp);
        return self.bus.read(addr);
    }

    fn stackPush(self: *Cpu, value: u8) void {
        const addr = STACK_BASE +% @as(u16, self.sp);
        self.bus.write(addr, value);
        self.sp -%= 1;
    }

    pub fn step(self: *Cpu) void {
        //const old = self.pc;
        const opcode_byte = self.readPC();

        const instruction = Instruction.fromByte(opcode_byte);
        //const out_writer = std.io.getStdOut().writer();
        //out_writer.print("PC: {x} {s} {X} {s}   ", .{old, instruction.name, instruction.opcode, @tagName(instruction.addressing)}) catch unreachable;
        //out_writer.print("FLAGS. C: {} Z: {} N: {} O: {} \n", .{self.carry, self.zero, self.negative, self.overflow}) catch unreachable;

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
    }

    fn nop(_: *Cpu, _: u16) void {}

    fn stp(_: *Cpu, _: u16) void {}

    fn brk(self: *Cpu, _: u16) void {
        self.pc +%= 1;
        const lo: u8 = @intCast(self.pc & 0xFF);
        const hi: u8 = @intCast(self.pc >> 8);
        self.stackPush(hi);
        self.stackPush(lo);
        self.stackPush(self.getStatus(true));
        self.interrupt_disable = true;

        self.pc = self.readAbsolute(0xFFFE);
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

    fn stx(self: *Cpu, addr: u16) void {
        self.bus.write(addr, self.x);
    }

    fn sty(self: *Cpu, addr: u16) void {
        self.bus.write(addr, self.y);
    }

    fn ror(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        const carry: u8 = @intFromBool(self.carry);
        self.carry = n & 0b0000_0001 != 0;
        const result = (n >> 1) | (carry << 7);
        self.bus.write(addr, result);
        self.updateNZFlags(result);
    }

    fn rorImplied(self: *Cpu, _: u16) void {
        const carry: u8 = @intFromBool(self.carry);
        self.carry = self.a & 0b0000_0001 != 0;
        self.updateA((self.a >> 1) | (carry << 7));
    }

    fn lsr(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.carry = n & 0b0000_0001 != 0;
        const result = (n >> 1);
        self.bus.write(addr, result);
        self.updateNZFlags(result);
    }

    fn lsrImplied(self: *Cpu, _: u16) void {
        self.carry = self.a & 0b0000_0001 != 0;
        self.updateA((self.a >> 1));
    }

    fn rol(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        const carry: u8 = @intFromBool(self.carry);
        self.carry = n & 0b1000_0000 != 0;
        const result = (n << 1) | carry;
        self.bus.write(addr, result);
        self.updateNZFlags(result);
    }

    fn rolImplied(self: *Cpu, _: u16) void {
        const carry: u8 = @intFromBool(self.carry);
        self.carry = self.a & 0b1000_0000 != 0;
        self.updateA((self.a << 1) | carry);
    }

    fn asl(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.carry = n & 0b1000_0000 != 0;
        const result = n << 1;
        self.bus.write(addr, result);
        self.updateNZFlags(result);
    }

    fn aslImplied(self: *Cpu, _: u16) void {
        self.carry = self.a & 0b1000_0000 != 0;
        self.updateA(self.a << 1);
    }

    fn ora(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.updateA(self.a | n);
    }

    fn and_(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.updateA(self.a & n);
    }

    fn eor(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.updateA(self.a ^ n);
    }

    fn adc(self: *Cpu, addr: u16) void {
        const operand = self.readByte(addr);
        if (!self.decimal) {
                // Compute the extra addition: add 1 if carry is set, otherwise 0.
            const addend: u8 = if (self.carry) 1 else 0;
                // Perform the addition using a 16-bit integer to capture any overflow.
            const sum: u16 = @as(u16, @intCast(self.a)) + @as(u16, @intCast(operand)) + @as(u16, @intCast(addend));
                // The 8-bit result wraps around (simulate the 6502’s 8-bit arithmetic).
            const result: u8 = @truncate(sum);
                // Carry flag: set if the sum exceeded 0xFF.
            const newCarry: bool = sum > 0xFF;
                // Overflow flag: set if the sign of the result is incorrect.
                // If A and operand have the same sign, but result's sign is different, then overflow occurred.
            const overflow: bool = (((~(self.a ^ operand)) & (self.a ^ result)) & 0x80) != 0;
                // Negative flag: simply bit 7 of the result.
            const negative: bool = (result & 0x80) != 0;
                // Zero flag: set if the result is zero.
            const zero: bool = result == 0;

            self.carry = newCarry;
            self.overflow = overflow;
            self.negative = negative;
            self.zero = zero;
            self.a = result;
        } else {
            var lower = (self.a & 0xF) + (operand & 0xF) + @intFromBool(self.carry);
            var upper = (self.a >> 4) + (operand >> 4);

            var carry_out = false;
            if (lower >= 10) {
                lower = (lower - 10) & 0xF;
                upper += 1;
            }
            if (upper >= 10) {
                upper = (upper - 10) & 0xF;
                carry_out = true;
            }

            const result = (upper << 4) | lower;
            self.carry = carry_out;
            self.updateA(result);
        }
    }

    fn sta(self: *Cpu, addr: u16) void {
        self.bus.write(addr, self.a);
    }

    fn lda(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.updateA(n);
    }

    fn ldx(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.updateX(n);
    }

    fn ldy(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.updateY(n);
    }

    fn cmp(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.updateNZFlags(self.a -% n);
        self.carry = self.a >= n;
    }

    fn cpx(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.updateNZFlags(self.x -% n);
        self.carry = self.x >= n;
    }

    fn cpy(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.updateNZFlags(self.y -% n);
        self.carry = self.y >= n;
    }

    fn dec(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        const result = n -% 1;
        self.bus.write(addr, result);
        self.updateNZFlags(result);
    }

    fn dcp(self: *Cpu, addr: u16) void {
        self.dec(addr);
        self.cmp(addr);
    }

    fn dex(self: *Cpu, _: u16) void {
        self.updateX(self.x -% 1);
    }

    fn dey(self: *Cpu, _: u16) void {
        self.updateY(self.y -% 1);
    }

    fn inc(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        const result = n +% 1;
        self.bus.write(addr, result);
        self.updateNZFlags(result);
    }

    fn inx(self: *Cpu, _: u16) void {
        self.updateX(self.x +% 1);
    }

    fn iny(self: *Cpu, _: u16) void {
        self.updateY(self.y +% 1);
    }

    fn sbc(self: *Cpu, addr: u16) void {
        const operand = self.readByte(addr);
        if (!self.decimal) {

            const borrow: u8 = if (self.carry) 0 else 1;
            const diff: i16 = @as(i16, @intCast(self.a)) - @as(i16, @intCast(operand)) - @as(i16, @intCast(borrow));
            const result: u8 = @truncate(@as(u16, @bitCast(diff)));
            const newCarry: bool = diff >= 0;
            // (This version is derived from interpreting SBC as A + (~operand) + C.)
            const overflow: bool = (((self.a ^ result) & (self.a ^ operand)) & 0x80) != 0;
            const negative: bool = (result & 0x80) != 0;
            const zero: bool = result == 0;

            self.carry = newCarry;
            self.overflow = overflow;
            self.negative = negative;
            self.zero = zero;
            self.a = result;
            return;
        } else {
            var lower = (@as(i16, @intCast(self.a)) & 0xF) - (@as(i16, @intCast(operand)) & 0xF) - @intFromBool(!self.carry);
            var upper = (@as(i16, @intCast(self.a)) >> 4) - (@as(i16, @intCast(operand)) >> 4);

            var carry_out = true;
            if (lower & 0x10 != 0) {
                lower = (lower + 10) & 0xF;
                upper -= 1;
            }
            if (upper & 0x10 != 0) {
                upper = (upper + 10) & 0xF;
                carry_out = false;
            }

            const result = @as(u8, @intCast(upper << 4)) | @as(u8, @intCast(lower));
            self.carry = carry_out;
            self.updateA(result);
        }
    }

    fn bvs(self: *Cpu, addr: u16) void {
        if (self.overflow) {
            self.pc = addr;
        }
    }

    fn bvc(self: *Cpu, addr: u16) void {
        if (!self.overflow) {
            self.pc = addr;
        }
    }

    fn bpl(self: *Cpu, addr: u16) void {
        if (!self.negative) {
            self.pc = addr;
        }
    }

    fn bcc(self: *Cpu, addr: u16) void {
        if (!self.carry) {
            self.pc = addr;
        }
    }

    fn bcs(self: *Cpu, addr: u16) void {
        if (self.carry) {
            self.pc = addr;
        }
    }

    fn beq(self: *Cpu, addr: u16) void {
        if (self.zero) {
            self.pc = addr;
        }
    }

    fn bne(self: *Cpu, addr: u16) void {
        if (!self.zero) {
            self.pc = addr;
            return;
        }
    }

    fn bmi(self: *Cpu, addr: u16) void {
        if (self.negative) {
            self.pc = addr;
        }
    }

    fn tya(self: *Cpu, _: u16) void {
        self.updateA(self.y);
    }

    fn tay(self: *Cpu, _: u16) void {
        self.updateY(self.a);
    }

    fn tax(self: *Cpu, _: u16) void {
        self.updateX(self.a);
    }

    fn txa(self: *Cpu, _: u16) void {
        self.updateA(self.x);
    }

    fn tsx(self: *Cpu, _: u16) void {
        self.updateX(self.sp);
    }

    fn txs(self: *Cpu, _: u16) void {
        self.sp = self.x;
    }

    fn sed(self: *Cpu, _: u16) void {
        self.decimal = true;
    }

    fn sei(self: *Cpu, _: u16) void {
        self.interrupt_disable = true;
    }

    fn cli(self: *Cpu, _: u16) void {
        self.interrupt_disable = false;
    }

    fn clc(self: *Cpu, _: u16) void {
        self.carry = false;
    }

    fn cld(self: *Cpu, _: u16) void {
        self.decimal = false;
    }

    fn sec(self: *Cpu, _: u16) void {
        self.carry = true;
    }

    fn clv(self: *Cpu, _: u16) void {
        self.overflow = false;
    }

    fn rts(self: *Cpu, _: u16) void {
        const lo = self.stackPop();
        const hi = self.stackPop();
        const return_addr = (@as(u16, hi) << 8) | lo;
        self.pc = return_addr +% 1;
    }

    fn jsr(self: *Cpu, addr: u16) void {
        const return_addr = self.pc -% 1;
        const lo: u8 = @intCast(return_addr & 0xFF);
        const hi: u8 = @intCast(return_addr >> 8);
        self.stackPush(hi);
        self.stackPush(lo);
        self.pc = addr;
    }

    fn jmp(self: *Cpu, addr: u16) void {
        self.pc = addr;
    }

    fn rti(self: *Cpu, _: u16) void {
        const status = self.stackPop();
        self.setStatus(status);
        const lo = self.stackPop();
        const hi = self.stackPop();
        self.pc = (@as(u16, hi) << 8) | lo;
    }

    fn php(self: *Cpu, _: u16) void {
        const status = self.getStatus(true);
        self.stackPush(status);
    }

    fn bit_(self: *Cpu, addr: u16) void {
        const n = self.readByte(addr);
        self.zero = (self.a & n) == 0;
        self.overflow = (n & (1 << 6)) != 0;
        self.negative = (n & (1 << 7)) != 0;
    }

    fn plp(self: *Cpu, _: u16) void {
        const status = self.stackPop();
        self.setStatus(status);
    }

    fn pha(self: *Cpu, _: u16) void {
        self.stackPush(self.a);
    }

    fn pla(self: *Cpu, _: u16) void {
        self.updateA(self.stackPop());
    }

    fn isc(self: *Cpu, addr: u16) void {
        self.inc(addr);
        self.sbc(addr);
    }

    fn readByte(self: *Cpu, addr: u16) u8 {
        return self.bus.read(addr);
    }

    fn readAbsolute(self: *Cpu, addr: u16) u16 {
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

pub const Instruction = struct {
    opcode: u8,
    name: []const u8,
    addressing: Cpu.Addressing,
    cycles: u8,
    opcode_fn: *const fn(self: *Cpu, addr: u16) void,

    pub fn fromByte(byte: u8) Instruction {
        return switch (byte) {
        // --- BRK ---
            0x00 => Instruction{ .opcode = 0x00, .name = "BRK", .addressing = .Implied, .cycles = 7, .opcode_fn = Cpu.brk },
            // --- STP ---
            0x02,
            0x12,
            0x22,
            0x32,
            0x42,
            0x52,
            0x62,
            0x72,
            0x92,
            0xB2,
            0xD2,
            0xF2 => Instruction{ .opcode = byte, .name = "STP", .addressing = .Implied, .cycles = 1, .opcode_fn = Cpu.stp },

            // --- ORA ---
            0x01 => Instruction{ .opcode = 0x01, .name = "ORA", .addressing = .IndirectX, .cycles = 6, .opcode_fn = Cpu.ora},
            0x05 => Instruction{ .opcode = 0x05, .name = "ORA", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.ora},
            0x09 => Instruction{ .opcode = 0x09, .name = "ORA", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.ora},
            0x0D => Instruction{ .opcode = 0x0D, .name = "ORA", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.ora},
            0x11 => Instruction{ .opcode = 0x11, .name = "ORA", .addressing = .IndirectY, .cycles = 5, .opcode_fn = Cpu.ora},
            0x15 => Instruction{ .opcode = 0x15, .name = "ORA", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.ora},
            0x19 => Instruction{ .opcode = 0x19, .name = "ORA", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = Cpu.ora}, // +1 if page crossed
            0x1D => Instruction{ .opcode = 0x1D, .name = "ORA", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = Cpu.ora}, // +1 if page crossed
            // --- ASL ---
            0x0A => Instruction{ .opcode = 0x0A, .name = "ASL", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.aslImplied},
            0x06 => Instruction{ .opcode = 0x06, .name = "ASL", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = Cpu.asl},
            0x0E => Instruction{ .opcode = 0x0E, .name = "ASL", .addressing = .Absolute, .cycles = 6, .opcode_fn = Cpu.asl},
            0x16 => Instruction{ .opcode = 0x16, .name = "ASL", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = Cpu.asl},
            0x1E => Instruction{ .opcode = 0x1E, .name = "ASL", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = Cpu.asl},
            // --- PHP ---
            0x08 => Instruction{ .opcode = 0x08, .name = "PHP", .addressing = .Implied, .cycles = 3, .opcode_fn = Cpu.php},
            // --- BPL ---
            0x10 => Instruction{ .opcode = 0x10, .name = "BPL", .addressing = .Relative, .cycles = 2, .opcode_fn = Cpu.bpl},
            // --- BEQ ---
            0xF0 => Instruction{ .opcode = 0xF0, .name = "BEQ", .addressing = .Relative, .cycles = 2, .opcode_fn = Cpu.beq},
            // --- BNE ---
            0xD0 => Instruction{ .opcode = 0xD0, .name = "BNE", .addressing = .Relative, .cycles = 2, .opcode_fn = Cpu.bne},
            // --- BCC ---
            0x90 => Instruction{ .opcode = 0x90, .name = "BCC", .addressing = .Relative, .cycles = 2, .opcode_fn = Cpu.bcc},
            // --- BCS ---
            0xB0 => Instruction{ .opcode = 0xB0, .name = "BCS", .addressing = .Relative, .cycles = 2, .opcode_fn = Cpu.bcs},
            // --- CLC ---
            0x18 => Instruction{ .opcode = 0x18, .name = "CLC", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.clc},
            // --- CLD ---
            0xD8 => Instruction{ .opcode = 0xD8, .name = "CLD", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.cld},
            // --- CLV ---
            0xB8 => Instruction{ .opcode = 0xB8, .name = "CLV", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.clv},
            // --- JSR ---
            0x20 => Instruction{ .opcode = 0x20, .name = "JSR", .addressing = .Absolute, .cycles = 6, .opcode_fn = Cpu.jsr},
            // --- JMP ---
            0x4C => Instruction{ .opcode = 0x4C, .name = "JMP", .addressing = .Absolute, .cycles = 3, .opcode_fn = Cpu.jmp},
            0x6C => Instruction{ .opcode = 0x6C, .name = "JMP", .addressing = .Indirect, .cycles = 5, .opcode_fn = Cpu.jmp},
            // --- AND ---
            0x21 => Instruction{ .opcode = 0x21, .name = "AND", .addressing = .IndirectX, .cycles = 6, .opcode_fn = Cpu.and_ },
            0x25 => Instruction{ .opcode = 0x25, .name = "AND", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.and_ },
            0x29 => Instruction{ .opcode = 0x29, .name = "AND", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.and_ },
            0x2D => Instruction{ .opcode = 0x2D, .name = "AND", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.and_ },
            0x31 => Instruction{ .opcode = 0x31, .name = "AND", .addressing = .IndirectY, .cycles = 6, .opcode_fn = Cpu.and_ },
            0x35 => Instruction{ .opcode = 0x35, .name = "AND", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.and_ },
            0x39 => Instruction{ .opcode = 0x39, .name = "AND", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = Cpu.and_ },
            0x3D => Instruction{ .opcode = 0x3D, .name = "AND", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = Cpu.and_ },
            // --- ROL ---
            0x2A => Instruction{ .opcode = 0x2A, .name = "ROL", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.rolImplied },
            0x26 => Instruction{ .opcode = 0x26, .name = "ROL", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = Cpu.rol },
            0x2E => Instruction{ .opcode = 0x2E, .name = "ROL", .addressing = .Absolute, .cycles = 6, .opcode_fn = Cpu.rol },
            0x36 => Instruction{ .opcode = 0x36, .name = "ROL", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = Cpu.rol },
            0x3E => Instruction{ .opcode = 0x3E, .name = "ROL", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = Cpu.rol },
            // --- BIT ---
            0x24 => Instruction{ .opcode = 0x24, .name = "BIT", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.bit_ },
            0x2C => Instruction{ .opcode = 0x0C, .name = "BIT", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.bit_ },
            // --- PLP ---
            0x28 => Instruction{ .opcode = 0x28, .name = "PLP", .addressing = .Implied, .cycles = 4, .opcode_fn = Cpu.plp},
            // --- PHA ---
            0x48 => Instruction{ .opcode = 0x48, .name = "PHA", .addressing = .Implied, .cycles = 3, .opcode_fn = Cpu.pha},
            // --- PLA ---
            0x68 => Instruction{ .opcode = 0x68, .name = "PLA", .addressing = .Implied, .cycles = 4, .opcode_fn = Cpu.pla},
            // --- BMI ---
            0x30 => Instruction{ .opcode = 0x30, .name = "BMI", .addressing = .Relative, .cycles = 2, .opcode_fn = Cpu.bmi},
            // --- SEC ---
            0x38 => Instruction{ .opcode = 0x38, .name = "SEC", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.sec},
            // --- RTI ---
            0x40 => Instruction{ .opcode = 0x40, .name = "RTI", .addressing = .Implied, .cycles = 6, .opcode_fn = Cpu.rti},
            // --- EOR ---
            0x41 => Instruction{ .opcode = 0x41, .name = "EOR", .addressing = .IndirectX, .cycles = 6, .opcode_fn = Cpu.eor},
            0x45 => Instruction{ .opcode = 0x45, .name = "EOR", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.eor},
            0x49 => Instruction{ .opcode = 0x49, .name = "EOR", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.eor},
            0x4D => Instruction{ .opcode = 0x4D, .name = "EOR", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.eor},
            // --- LSR ---
            0x4A => Instruction{ .opcode = 0x4A, .name = "LSR", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.lsrImplied},
            0x46 => Instruction{ .opcode = 0x46, .name = "LSR", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = Cpu.lsr},
            0x4E => Instruction{ .opcode = 0x4E, .name = "LSR", .addressing = .Absolute, .cycles = 6, .opcode_fn = Cpu.lsr},
            // --- BVC ---
            0x50 => Instruction{ .opcode = 0x50, .name = "BVC", .addressing = .Relative, .cycles = 2, .opcode_fn = Cpu.bvc},
            // --- (Indirect),Y EOR variant ---
            0x51 => Instruction{ .opcode = 0x51, .name = "EOR", .addressing = .IndirectY, .cycles = 5, .opcode_fn = Cpu.eor},
            // --- ZeroPageX variants for EOR/LSR ---
            0x55 => Instruction{ .opcode = 0x55, .name = "EOR", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.eor},
            0x56 => Instruction{ .opcode = 0x56, .name = "LSR", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = Cpu.lsr},
            // --- CLI ---
            0x58 => Instruction{ .opcode = 0x58, .name = "CLI", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.cli},
            // --- AbsoluteY variants for EOR ---
            0x59 => Instruction{ .opcode = 0x59, .name = "EOR", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = Cpu.eor},
            // --- AbsoluteX variants for EOR/LSR ---
            0x5D => Instruction{ .opcode = 0x5D, .name = "EOR", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = Cpu.eor},
            0x5E => Instruction{ .opcode = 0x5E, .name = "LSR", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = Cpu.lsr},
            // --- RTS ---
            0x60 => Instruction{ .opcode = 0x60, .name = "RTS", .addressing = .Implied, .cycles = 6, .opcode_fn = Cpu.rts},
            // --- DCP ---
            0xC3 => Instruction{ .opcode = 0xC3, .name = "DCP", .addressing = .IndirectX, .cycles = 8, .opcode_fn = Cpu.dcp},
            0xC7 => Instruction{ .opcode = 0xC7, .name = "DCP", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = Cpu.dcp},
            0xCF => Instruction{ .opcode = 0xCF, .name = "DCP", .addressing = .Absolute, .cycles = 6, .opcode_fn = Cpu.dcp},
            0xD3 => Instruction{ .opcode = 0xD3, .name = "DCP", .addressing = .IndirectY, .cycles = 8, .opcode_fn = Cpu.dcp},
            0xD7 => Instruction{ .opcode = 0xD7, .name = "DCP", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = Cpu.dcp},
            0xDB => Instruction{ .opcode = 0xDB, .name = "DCP", .addressing = .AbsoluteY, .cycles = 7, .opcode_fn = Cpu.dcp},
            0xDF => Instruction{ .opcode = 0xDF, .name = "DCP", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = Cpu.dcp},
            // --- ADC ---
            0x61 => Instruction{ .opcode = 0x61, .name = "ADC", .addressing = .IndirectX, .cycles = 6, .opcode_fn = Cpu.adc},
            0x65 => Instruction{ .opcode = 0x65, .name = "ADC", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.adc},
            0x69 => Instruction{ .opcode = 0x69, .name = "ADC", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.adc},
            0x6D => Instruction{ .opcode = 0x6D, .name = "ADC", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.adc},
            // --- ROR ---
            0x6A => Instruction{ .opcode = 0x6A, .name = "ROR", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.rorImplied},
            0x6E => Instruction{ .opcode = 0x6E, .name = "ROR", .addressing = .Absolute, .cycles = 6, .opcode_fn = Cpu.ror},
            0x66 => Instruction{ .opcode = 0x66, .name = "ROR", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = Cpu.ror},
            // --- BVS ---
            0x70 => Instruction{ .opcode = 0x70, .name = "BVS", .addressing = .Relative, .cycles = 2, .opcode_fn = Cpu.bvs },
            // --- ADC (Indirect),Y variant ---
            0x71 => Instruction{ .opcode = 0x71, .name = "ADC", .addressing = .IndirectY, .cycles = 5, .opcode_fn = Cpu.adc},
            0x75 => Instruction{ .opcode = 0x75, .name = "ADC", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.adc},
            0x76 => Instruction{ .opcode = 0x76, .name = "ROR", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = Cpu.ror},
            0x78 => Instruction{ .opcode = 0x78, .name = "SEI", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.sei},
            0x79 => Instruction{ .opcode = 0x79, .name = "ADC", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = Cpu.adc},
            0x7D => Instruction{ .opcode = 0x7D, .name = "ADC", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = Cpu.adc},
            0x7E => Instruction{ .opcode = 0x7E, .name = "ROR", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = Cpu.ror},
            // --- STA ---
            0x81 => Instruction{ .opcode = 0x81, .name = "STA", .addressing = .IndirectX, .cycles = 6, .opcode_fn = Cpu.sta},
            0x85 => Instruction{ .opcode = 0x85, .name = "STA", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.sta},
            0x8D => Instruction{ .opcode = 0x8D, .name = "STA", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.sta},
            0x91 => Instruction{ .opcode = 0x91, .name = "STA", .addressing = .IndirectY, .cycles = 6, .opcode_fn = Cpu.sta},
            0x95 => Instruction{ .opcode = 0x95, .name = "STA", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.sta},
            0x99 => Instruction{ .opcode = 0x99, .name = "STA", .addressing = .AbsoluteY, .cycles = 5, .opcode_fn = Cpu.sta},
            0x9D => Instruction{ .opcode = 0x9D, .name = "STA", .addressing = .AbsoluteX, .cycles = 5, .opcode_fn = Cpu.sta},
            // --- STX & STY ---
            0x86 => Instruction{ .opcode = 0x86, .name = "STX", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.stx},
            0x8E => Instruction{ .opcode = 0x8E, .name = "STX", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.stx},
            0x96 => Instruction{ .opcode = 0x96, .name = "STX", .addressing = .ZeroPageY, .cycles = 4, .opcode_fn = Cpu.stx},
            0x84 => Instruction{ .opcode = 0x84, .name = "STY", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.sty},
            0x8C => Instruction{ .opcode = 0x8C, .name = "STY", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.sty},
            0x94 => Instruction{ .opcode = 0x94, .name = "STY", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.sty},
            // --- Transfers ---
            0xAA => Instruction{ .opcode = 0xAA, .name = "TAX", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.tax},
            0xA8 => Instruction{ .opcode = 0xA8, .name = "TAY", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.tay},
            0xBA => Instruction{ .opcode = 0xBA, .name = "TSX", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.tsx},
            0x8A => Instruction{ .opcode = 0x8A, .name = "TXA", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.txa},
            0x9A => Instruction{ .opcode = 0x9A, .name = "TXS", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.txs},
            0x98 => Instruction{ .opcode = 0x98, .name = "TYA", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.tya},
            // --- LDA ---
            0xA1 => Instruction{ .opcode = 0xA1, .name = "LDA", .addressing = .IndirectX, .cycles = 6, .opcode_fn = Cpu.lda},
            0xA5 => Instruction{ .opcode = 0xA5, .name = "LDA", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.lda},
            0xA9 => Instruction{ .opcode = 0xA9, .name = "LDA", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.lda},
            0xAD => Instruction{ .opcode = 0xAD, .name = "LDA", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.lda},
            0xB1 => Instruction{ .opcode = 0xB1, .name = "LDA", .addressing = .IndirectY, .cycles = 5, .opcode_fn = Cpu.lda},
            0xB5 => Instruction{ .opcode = 0xB5, .name = "LDA", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.lda},
            0xB9 => Instruction{ .opcode = 0xB9, .name = "LDA", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = Cpu.lda},
            0xBD => Instruction{ .opcode = 0xBD, .name = "LDA", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = Cpu.lda},
            // --- LDX ---
            0xA2 => Instruction{ .opcode = 0xA2, .name = "LDX", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.ldx},
            0xA6 => Instruction{ .opcode = 0xA6, .name = "LDX", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.ldx},
            0xAE => Instruction{ .opcode = 0xAE, .name = "LDX", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.ldx},
            0xB6 => Instruction{ .opcode = 0xB6, .name = "LDX", .addressing = .ZeroPageY, .cycles = 4, .opcode_fn = Cpu.ldx},
            0xBE => Instruction{ .opcode = 0xBE, .name = "LDX", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = Cpu.ldx},
            // --- LDY ---
            0xA0 => Instruction{ .opcode = 0xA0, .name = "LDY", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.ldy},
            0xA4 => Instruction{ .opcode = 0xA4, .name = "LDY", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.ldy},
            0xAC => Instruction{ .opcode = 0xAC, .name = "LDY", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.ldy},
            0xB4 => Instruction{ .opcode = 0xB4, .name = "LDY", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.ldy},
            0xBC => Instruction{ .opcode = 0xBC, .name = "LDY", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = Cpu.ldy},
            // --- CMP ---
            0xC1 => Instruction{ .opcode = 0xC1, .name = "CMP", .addressing = .IndirectX, .cycles = 6, .opcode_fn = Cpu.cmp},
            0xC5 => Instruction{ .opcode = 0xC5, .name = "CMP", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.cmp},
            0xC9 => Instruction{ .opcode = 0xC9, .name = "CMP", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.cmp},
            0xCD => Instruction{ .opcode = 0xCD, .name = "CMP", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.cmp},
            0xD1 => Instruction{ .opcode = 0xD1, .name = "CMP", .addressing = .IndirectY, .cycles = 5, .opcode_fn = Cpu.cmp},
            0xD5 => Instruction{ .opcode = 0xD5, .name = "CMP", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.cmp},
            0xD9 => Instruction{ .opcode = 0xD9, .name = "CMP", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = Cpu.cmp},
            0xDD => Instruction{ .opcode = 0xDD, .name = "CMP", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = Cpu.cmp},
            // --- CPX ---
            0xE0 => Instruction{ .opcode = 0xE0, .name = "CPX", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.cpx},
            0xE4 => Instruction{ .opcode = 0xE4, .name = "CPX", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.cpx},
            0xEC => Instruction{ .opcode = 0xEC, .name = "CPX", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.cpx},
            // --- CPY ---
            0xC0 => Instruction{ .opcode = 0xC0, .name = "CPY", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.cpy},
            0xC4 => Instruction{ .opcode = 0xC4, .name = "CPY", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.cpy},
            0xCC => Instruction{ .opcode = 0xCC, .name = "CPY", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.cpy},
            // --- DEC ---
            0xC6 => Instruction{ .opcode = 0xC6, .name = "DEC", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = Cpu.dec},
            0xCE => Instruction{ .opcode = 0xCE, .name = "DEC", .addressing = .Absolute, .cycles = 6, .opcode_fn = Cpu.dec},
            0xD6 => Instruction{ .opcode = 0xD6, .name = "DEC", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = Cpu.dec},
            0xDE => Instruction{ .opcode = 0xDE, .name = "DEC", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = Cpu.dec},
            // --- DEX & DEY ---
            0xCA => Instruction{ .opcode = 0xCA, .name = "DEX", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.dex},
            0x88 => Instruction{ .opcode = 0x88, .name = "DEY", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.dey},
            // --- INC ---
            0xE6 => Instruction{ .opcode = 0xE6, .name = "INC", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = Cpu.inc},
            0xEE => Instruction{ .opcode = 0xEE, .name = "INC", .addressing = .Absolute, .cycles = 6, .opcode_fn = Cpu.inc},
            0xF6 => Instruction{ .opcode = 0xF6, .name = "INC", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = Cpu.inc},
            0xFE => Instruction{ .opcode = 0xFE, .name = "INC", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = Cpu.inc},
            // --- INX & INY ---
            0xE8 => Instruction{ .opcode = 0xE8, .name = "INX", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.inx},
            0xC8 => Instruction{ .opcode = 0xC8, .name = "INY", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.iny},
            // --- SBC ---
            0xE1 => Instruction{ .opcode = 0xE1, .name = "SBC", .addressing = .IndirectX, .cycles = 6, .opcode_fn = Cpu.sbc},
            0xE5 => Instruction{ .opcode = 0xE5, .name = "SBC", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = Cpu.sbc},
            0xE9 => Instruction{ .opcode = 0xE9, .name = "SBC", .addressing = .Immediate, .cycles = 2, .opcode_fn = Cpu.sbc},
            0xED => Instruction{ .opcode = 0xED, .name = "SBC", .addressing = .Absolute, .cycles = 4, .opcode_fn = Cpu.sbc},
            0xF1 => Instruction{ .opcode = 0xF1, .name = "SBC", .addressing = .IndirectY, .cycles = 5, .opcode_fn = Cpu.sbc},
            0xF5 => Instruction{ .opcode = 0xF5, .name = "SBC", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = Cpu.sbc},
            0xF9 => Instruction{ .opcode = 0xF9, .name = "SBC", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = Cpu.sbc},
            0xFD => Instruction{ .opcode = 0xFD, .name = "SBC", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = Cpu.sbc},
            // --- SED, SEI ---
            0xF8 => Instruction{ .opcode = 0xF8, .name = "SED", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.sed},
            // --- NOP ---
            0xEA => Instruction{ .opcode = 0xEA, .name = "NOP", .addressing = .Implied, .cycles = 2, .opcode_fn = Cpu.nop },
            0xFF => Instruction{ .opcode = 0xFF, .name = "ISC", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = Cpu.isc },
            else => {
                std.debug.print("Found opcode: {x}\n", .{byte});
                unreachable;
            },
        };
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