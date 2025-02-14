const Cpu = @import("cpu.zig").Cpu;
const std = @import("std");

opcode: u8,
name: []const u8,
addressing: Cpu.Addressing,
cycles: u8,
opcode_fn: *const fn (self: *Cpu, addr: u16) void,

const Instruction = @This();

pub fn fromByte(byte: u8) Instruction {
    return switch (byte) {
        // --- BRK ---
        0x00 => Instruction{ .opcode = 0x00, .name = "BRK", .addressing = .Implied, .cycles = 7, .opcode_fn = brk },
        // --- STP ---
        0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2 => Instruction{ .opcode = byte, .name = "STP", .addressing = .Implied, .cycles = 1, .opcode_fn = stp },

        // --- ORA ---
        0x01 => Instruction{ .opcode = 0x01, .name = "ORA", .addressing = .IndirectX, .cycles = 6, .opcode_fn = ora },
        0x05 => Instruction{ .opcode = 0x05, .name = "ORA", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = ora },
        0x09 => Instruction{ .opcode = 0x09, .name = "ORA", .addressing = .Immediate, .cycles = 2, .opcode_fn = ora },
        0x0D => Instruction{ .opcode = 0x0D, .name = "ORA", .addressing = .Absolute, .cycles = 4, .opcode_fn = ora },
        0x11 => Instruction{ .opcode = 0x11, .name = "ORA", .addressing = .IndirectY, .cycles = 5, .opcode_fn = ora },
        0x15 => Instruction{ .opcode = 0x15, .name = "ORA", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = ora },
        0x19 => Instruction{ .opcode = 0x19, .name = "ORA", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = ora }, // +1 if page crossed
        0x1D => Instruction{ .opcode = 0x1D, .name = "ORA", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = ora }, // +1 if page crossed
        // --- ASL ---
        0x0A => Instruction{ .opcode = 0x0A, .name = "ASL", .addressing = .Implied, .cycles = 2, .opcode_fn = aslImplied },
        0x06 => Instruction{ .opcode = 0x06, .name = "ASL", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = asl },
        0x0E => Instruction{ .opcode = 0x0E, .name = "ASL", .addressing = .Absolute, .cycles = 6, .opcode_fn = asl },
        0x16 => Instruction{ .opcode = 0x16, .name = "ASL", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = asl },
        0x1E => Instruction{ .opcode = 0x1E, .name = "ASL", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = asl },
        // --- PHP ---
        0x08 => Instruction{ .opcode = 0x08, .name = "PHP", .addressing = .Implied, .cycles = 3, .opcode_fn = php },
        // --- BPL ---
        0x10 => Instruction{ .opcode = 0x10, .name = "BPL", .addressing = .Relative, .cycles = 2, .opcode_fn = bpl },
        // --- BEQ ---
        0xF0 => Instruction{ .opcode = 0xF0, .name = "BEQ", .addressing = .Relative, .cycles = 2, .opcode_fn = beq },
        // --- BNE ---
        0xD0 => Instruction{ .opcode = 0xD0, .name = "BNE", .addressing = .Relative, .cycles = 2, .opcode_fn = bne },
        // --- BCC ---
        0x90 => Instruction{ .opcode = 0x90, .name = "BCC", .addressing = .Relative, .cycles = 2, .opcode_fn = bcc },
        // --- BCS ---
        0xB0 => Instruction{ .opcode = 0xB0, .name = "BCS", .addressing = .Relative, .cycles = 2, .opcode_fn = bcs },
        // --- CLC ---
        0x18 => Instruction{ .opcode = 0x18, .name = "CLC", .addressing = .Implied, .cycles = 2, .opcode_fn = clc },
        // --- CLD ---
        0xD8 => Instruction{ .opcode = 0xD8, .name = "CLD", .addressing = .Implied, .cycles = 2, .opcode_fn = cld },
        // --- CLV ---
        0xB8 => Instruction{ .opcode = 0xB8, .name = "CLV", .addressing = .Implied, .cycles = 2, .opcode_fn = clv },
        // --- JSR ---
        0x20 => Instruction{ .opcode = 0x20, .name = "JSR", .addressing = .Absolute, .cycles = 6, .opcode_fn = jsr },
        // --- JMP ---
        0x4C => Instruction{ .opcode = 0x4C, .name = "JMP", .addressing = .Absolute, .cycles = 3, .opcode_fn = jmp },
        0x6C => Instruction{ .opcode = 0x6C, .name = "JMP", .addressing = .Indirect, .cycles = 5, .opcode_fn = jmp },
        // --- AND ---
        0x21 => Instruction{ .opcode = 0x21, .name = "AND", .addressing = .IndirectX, .cycles = 6, .opcode_fn = and_ },
        0x25 => Instruction{ .opcode = 0x25, .name = "AND", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = and_ },
        0x29 => Instruction{ .opcode = 0x29, .name = "AND", .addressing = .Immediate, .cycles = 2, .opcode_fn = and_ },
        0x2D => Instruction{ .opcode = 0x2D, .name = "AND", .addressing = .Absolute, .cycles = 4, .opcode_fn = and_ },
        0x31 => Instruction{ .opcode = 0x31, .name = "AND", .addressing = .IndirectY, .cycles = 6, .opcode_fn = and_ },
        0x35 => Instruction{ .opcode = 0x35, .name = "AND", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = and_ },
        0x39 => Instruction{ .opcode = 0x39, .name = "AND", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = and_ },
        0x3D => Instruction{ .opcode = 0x3D, .name = "AND", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = and_ },
        // --- ROL ---
        0x2A => Instruction{ .opcode = 0x2A, .name = "ROL", .addressing = .Implied, .cycles = 2, .opcode_fn = rolImplied },
        0x26 => Instruction{ .opcode = 0x26, .name = "ROL", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = rol },
        0x2E => Instruction{ .opcode = 0x2E, .name = "ROL", .addressing = .Absolute, .cycles = 6, .opcode_fn = rol },
        0x36 => Instruction{ .opcode = 0x36, .name = "ROL", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = rol },
        0x3E => Instruction{ .opcode = 0x3E, .name = "ROL", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = rol },
        // --- BIT ---
        0x24 => Instruction{ .opcode = 0x24, .name = "BIT", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = bit_ },
        0x2C => Instruction{ .opcode = 0x0C, .name = "BIT", .addressing = .Absolute, .cycles = 4, .opcode_fn = bit_ },
        // --- PLP ---
        0x28 => Instruction{ .opcode = 0x28, .name = "PLP", .addressing = .Implied, .cycles = 4, .opcode_fn = plp },
        // --- PHA ---
        0x48 => Instruction{ .opcode = 0x48, .name = "PHA", .addressing = .Implied, .cycles = 3, .opcode_fn = pha },
        // --- PLA ---
        0x68 => Instruction{ .opcode = 0x68, .name = "PLA", .addressing = .Implied, .cycles = 4, .opcode_fn = pla },
        // --- BMI ---
        0x30 => Instruction{ .opcode = 0x30, .name = "BMI", .addressing = .Relative, .cycles = 2, .opcode_fn = bmi },
        // --- SEC ---
        0x38 => Instruction{ .opcode = 0x38, .name = "SEC", .addressing = .Implied, .cycles = 2, .opcode_fn = sec },
        // --- RTI ---
        0x40 => Instruction{ .opcode = 0x40, .name = "RTI", .addressing = .Implied, .cycles = 6, .opcode_fn = rti },
        // --- EOR ---
        0x41 => Instruction{ .opcode = 0x41, .name = "EOR", .addressing = .IndirectX, .cycles = 6, .opcode_fn = eor },
        0x45 => Instruction{ .opcode = 0x45, .name = "EOR", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = eor },
        0x49 => Instruction{ .opcode = 0x49, .name = "EOR", .addressing = .Immediate, .cycles = 2, .opcode_fn = eor },
        0x4D => Instruction{ .opcode = 0x4D, .name = "EOR", .addressing = .Absolute, .cycles = 4, .opcode_fn = eor },
        // --- LSR ---
        0x4A => Instruction{ .opcode = 0x4A, .name = "LSR", .addressing = .Implied, .cycles = 2, .opcode_fn = lsrImplied },
        0x46 => Instruction{ .opcode = 0x46, .name = "LSR", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = lsr },
        0x4E => Instruction{ .opcode = 0x4E, .name = "LSR", .addressing = .Absolute, .cycles = 6, .opcode_fn = lsr },
        // --- BVC ---
        0x50 => Instruction{ .opcode = 0x50, .name = "BVC", .addressing = .Relative, .cycles = 2, .opcode_fn = bvc },
        // --- (Indirect),Y EOR variant ---
        0x51 => Instruction{ .opcode = 0x51, .name = "EOR", .addressing = .IndirectY, .cycles = 5, .opcode_fn = eor },
        // --- ZeroPageX variants for EOR/LSR ---
        0x55 => Instruction{ .opcode = 0x55, .name = "EOR", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = eor },
        0x56 => Instruction{ .opcode = 0x56, .name = "LSR", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = lsr },
        // --- CLI ---
        0x58 => Instruction{ .opcode = 0x58, .name = "CLI", .addressing = .Implied, .cycles = 2, .opcode_fn = cli },
        // --- AbsoluteY variants for EOR ---
        0x59 => Instruction{ .opcode = 0x59, .name = "EOR", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = eor },
        // --- AbsoluteX variants for EOR/LSR ---
        0x5D => Instruction{ .opcode = 0x5D, .name = "EOR", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = eor },
        0x5E => Instruction{ .opcode = 0x5E, .name = "LSR", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = lsr },
        // --- RTS ---
        0x60 => Instruction{ .opcode = 0x60, .name = "RTS", .addressing = .Implied, .cycles = 6, .opcode_fn = rts },
        // --- DCP ---
        0xC3 => Instruction{ .opcode = 0xC3, .name = "DCP", .addressing = .IndirectX, .cycles = 8, .opcode_fn = dcp },
        0xC7 => Instruction{ .opcode = 0xC7, .name = "DCP", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = dcp },
        0xCF => Instruction{ .opcode = 0xCF, .name = "DCP", .addressing = .Absolute, .cycles = 6, .opcode_fn = dcp },
        0xD3 => Instruction{ .opcode = 0xD3, .name = "DCP", .addressing = .IndirectY, .cycles = 8, .opcode_fn = dcp },
        0xD7 => Instruction{ .opcode = 0xD7, .name = "DCP", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = dcp },
        0xDB => Instruction{ .opcode = 0xDB, .name = "DCP", .addressing = .AbsoluteY, .cycles = 7, .opcode_fn = dcp },
        0xDF => Instruction{ .opcode = 0xDF, .name = "DCP", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = dcp },
        // --- ADC ---
        0x61 => Instruction{ .opcode = 0x61, .name = "ADC", .addressing = .IndirectX, .cycles = 6, .opcode_fn = adc },
        0x65 => Instruction{ .opcode = 0x65, .name = "ADC", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = adc },
        0x69 => Instruction{ .opcode = 0x69, .name = "ADC", .addressing = .Immediate, .cycles = 2, .opcode_fn = adc },
        0x6D => Instruction{ .opcode = 0x6D, .name = "ADC", .addressing = .Absolute, .cycles = 4, .opcode_fn = adc },
        // --- ROR ---
        0x6A => Instruction{ .opcode = 0x6A, .name = "ROR", .addressing = .Implied, .cycles = 2, .opcode_fn = rorImplied },
        0x6E => Instruction{ .opcode = 0x6E, .name = "ROR", .addressing = .Absolute, .cycles = 6, .opcode_fn = ror },
        0x66 => Instruction{ .opcode = 0x66, .name = "ROR", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = ror },
        // --- BVS ---
        0x70 => Instruction{ .opcode = 0x70, .name = "BVS", .addressing = .Relative, .cycles = 2, .opcode_fn = bvs },
        // --- ADC (Indirect),Y variant ---
        0x71 => Instruction{ .opcode = 0x71, .name = "ADC", .addressing = .IndirectY, .cycles = 5, .opcode_fn = adc },
        0x75 => Instruction{ .opcode = 0x75, .name = "ADC", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = adc },
        0x76 => Instruction{ .opcode = 0x76, .name = "ROR", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = ror },
        0x78 => Instruction{ .opcode = 0x78, .name = "SEI", .addressing = .Implied, .cycles = 2, .opcode_fn = sei },
        0x79 => Instruction{ .opcode = 0x79, .name = "ADC", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = adc },
        0x7D => Instruction{ .opcode = 0x7D, .name = "ADC", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = adc },
        0x7E => Instruction{ .opcode = 0x7E, .name = "ROR", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = ror },
        // --- STA ---
        0x81 => Instruction{ .opcode = 0x81, .name = "STA", .addressing = .IndirectX, .cycles = 6, .opcode_fn = sta },
        0x85 => Instruction{ .opcode = 0x85, .name = "STA", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = sta },
        0x8D => Instruction{ .opcode = 0x8D, .name = "STA", .addressing = .Absolute, .cycles = 4, .opcode_fn = sta },
        0x91 => Instruction{ .opcode = 0x91, .name = "STA", .addressing = .IndirectY, .cycles = 6, .opcode_fn = sta },
        0x95 => Instruction{ .opcode = 0x95, .name = "STA", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = sta },
        0x99 => Instruction{ .opcode = 0x99, .name = "STA", .addressing = .AbsoluteY, .cycles = 5, .opcode_fn = sta },
        0x9D => Instruction{ .opcode = 0x9D, .name = "STA", .addressing = .AbsoluteX, .cycles = 5, .opcode_fn = sta },
        // --- STX & STY ---
        0x86 => Instruction{ .opcode = 0x86, .name = "STX", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = stx },
        0x8E => Instruction{ .opcode = 0x8E, .name = "STX", .addressing = .Absolute, .cycles = 4, .opcode_fn = stx },
        0x96 => Instruction{ .opcode = 0x96, .name = "STX", .addressing = .ZeroPageY, .cycles = 4, .opcode_fn = stx },
        0x84 => Instruction{ .opcode = 0x84, .name = "STY", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = sty },
        0x8C => Instruction{ .opcode = 0x8C, .name = "STY", .addressing = .Absolute, .cycles = 4, .opcode_fn = sty },
        0x94 => Instruction{ .opcode = 0x94, .name = "STY", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = sty },
        // --- Transfers ---
        0xAA => Instruction{ .opcode = 0xAA, .name = "TAX", .addressing = .Implied, .cycles = 2, .opcode_fn = tax },
        0xA8 => Instruction{ .opcode = 0xA8, .name = "TAY", .addressing = .Implied, .cycles = 2, .opcode_fn = tay },
        0xBA => Instruction{ .opcode = 0xBA, .name = "TSX", .addressing = .Implied, .cycles = 2, .opcode_fn = tsx },
        0x8A => Instruction{ .opcode = 0x8A, .name = "TXA", .addressing = .Implied, .cycles = 2, .opcode_fn = txa },
        0x9A => Instruction{ .opcode = 0x9A, .name = "TXS", .addressing = .Implied, .cycles = 2, .opcode_fn = txs },
        0x98 => Instruction{ .opcode = 0x98, .name = "TYA", .addressing = .Implied, .cycles = 2, .opcode_fn = tya },
        // --- LDA ---
        0xA1 => Instruction{ .opcode = 0xA1, .name = "LDA", .addressing = .IndirectX, .cycles = 6, .opcode_fn = lda },
        0xA5 => Instruction{ .opcode = 0xA5, .name = "LDA", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = lda },
        0xA9 => Instruction{ .opcode = 0xA9, .name = "LDA", .addressing = .Immediate, .cycles = 2, .opcode_fn = lda },
        0xAD => Instruction{ .opcode = 0xAD, .name = "LDA", .addressing = .Absolute, .cycles = 4, .opcode_fn = lda },
        0xB1 => Instruction{ .opcode = 0xB1, .name = "LDA", .addressing = .IndirectY, .cycles = 5, .opcode_fn = lda },
        0xB5 => Instruction{ .opcode = 0xB5, .name = "LDA", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = lda },
        0xB9 => Instruction{ .opcode = 0xB9, .name = "LDA", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = lda },
        0xBD => Instruction{ .opcode = 0xBD, .name = "LDA", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = lda },
        // --- LDX ---
        0xA2 => Instruction{ .opcode = 0xA2, .name = "LDX", .addressing = .Immediate, .cycles = 2, .opcode_fn = ldx },
        0xA6 => Instruction{ .opcode = 0xA6, .name = "LDX", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = ldx },
        0xAE => Instruction{ .opcode = 0xAE, .name = "LDX", .addressing = .Absolute, .cycles = 4, .opcode_fn = ldx },
        0xB6 => Instruction{ .opcode = 0xB6, .name = "LDX", .addressing = .ZeroPageY, .cycles = 4, .opcode_fn = ldx },
        0xBE => Instruction{ .opcode = 0xBE, .name = "LDX", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = ldx },
        // --- LDY ---
        0xA0 => Instruction{ .opcode = 0xA0, .name = "LDY", .addressing = .Immediate, .cycles = 2, .opcode_fn = ldy },
        0xA4 => Instruction{ .opcode = 0xA4, .name = "LDY", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = ldy },
        0xAC => Instruction{ .opcode = 0xAC, .name = "LDY", .addressing = .Absolute, .cycles = 4, .opcode_fn = ldy },
        0xB4 => Instruction{ .opcode = 0xB4, .name = "LDY", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = ldy },
        0xBC => Instruction{ .opcode = 0xBC, .name = "LDY", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = ldy },
        // --- CMP ---
        0xC1 => Instruction{ .opcode = 0xC1, .name = "CMP", .addressing = .IndirectX, .cycles = 6, .opcode_fn = cmp },
        0xC5 => Instruction{ .opcode = 0xC5, .name = "CMP", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = cmp },
        0xC9 => Instruction{ .opcode = 0xC9, .name = "CMP", .addressing = .Immediate, .cycles = 2, .opcode_fn = cmp },
        0xCD => Instruction{ .opcode = 0xCD, .name = "CMP", .addressing = .Absolute, .cycles = 4, .opcode_fn = cmp },
        0xD1 => Instruction{ .opcode = 0xD1, .name = "CMP", .addressing = .IndirectY, .cycles = 5, .opcode_fn = cmp },
        0xD5 => Instruction{ .opcode = 0xD5, .name = "CMP", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = cmp },
        0xD9 => Instruction{ .opcode = 0xD9, .name = "CMP", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = cmp },
        0xDD => Instruction{ .opcode = 0xDD, .name = "CMP", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = cmp },
        // --- CPX ---
        0xE0 => Instruction{ .opcode = 0xE0, .name = "CPX", .addressing = .Immediate, .cycles = 2, .opcode_fn = cpx },
        0xE4 => Instruction{ .opcode = 0xE4, .name = "CPX", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = cpx },
        0xEC => Instruction{ .opcode = 0xEC, .name = "CPX", .addressing = .Absolute, .cycles = 4, .opcode_fn = cpx },
        // --- CPY ---
        0xC0 => Instruction{ .opcode = 0xC0, .name = "CPY", .addressing = .Immediate, .cycles = 2, .opcode_fn = cpy },
        0xC4 => Instruction{ .opcode = 0xC4, .name = "CPY", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = cpy },
        0xCC => Instruction{ .opcode = 0xCC, .name = "CPY", .addressing = .Absolute, .cycles = 4, .opcode_fn = cpy },
        // --- DEC ---
        0xC6 => Instruction{ .opcode = 0xC6, .name = "DEC", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = dec },
        0xCE => Instruction{ .opcode = 0xCE, .name = "DEC", .addressing = .Absolute, .cycles = 6, .opcode_fn = dec },
        0xD6 => Instruction{ .opcode = 0xD6, .name = "DEC", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = dec },
        0xDE => Instruction{ .opcode = 0xDE, .name = "DEC", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = dec },
        // --- DEX & DEY ---
        0xCA => Instruction{ .opcode = 0xCA, .name = "DEX", .addressing = .Implied, .cycles = 2, .opcode_fn = dex },
        0x88 => Instruction{ .opcode = 0x88, .name = "DEY", .addressing = .Implied, .cycles = 2, .opcode_fn = dey },
        // --- INC ---
        0xE6 => Instruction{ .opcode = 0xE6, .name = "INC", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = inc },
        0xEE => Instruction{ .opcode = 0xEE, .name = "INC", .addressing = .Absolute, .cycles = 6, .opcode_fn = inc },
        0xF6 => Instruction{ .opcode = 0xF6, .name = "INC", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = inc },
        0xFE => Instruction{ .opcode = 0xFE, .name = "INC", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = inc },
        // --- INX & INY ---
        0xE8 => Instruction{ .opcode = 0xE8, .name = "INX", .addressing = .Implied, .cycles = 2, .opcode_fn = inx },
        0xC8 => Instruction{ .opcode = 0xC8, .name = "INY", .addressing = .Implied, .cycles = 2, .opcode_fn = iny },
        // --- SBC ---
        0xE1 => Instruction{ .opcode = 0xE1, .name = "SBC", .addressing = .IndirectX, .cycles = 6, .opcode_fn = sbc },
        0xE5 => Instruction{ .opcode = 0xE5, .name = "SBC", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = sbc },
        0xE9 => Instruction{ .opcode = 0xE9, .name = "SBC", .addressing = .Immediate, .cycles = 2, .opcode_fn = sbc },
        0xED => Instruction{ .opcode = 0xED, .name = "SBC", .addressing = .Absolute, .cycles = 4, .opcode_fn = sbc },
        0xF1 => Instruction{ .opcode = 0xF1, .name = "SBC", .addressing = .IndirectY, .cycles = 5, .opcode_fn = sbc },
        0xF5 => Instruction{ .opcode = 0xF5, .name = "SBC", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = sbc },
        0xF9 => Instruction{ .opcode = 0xF9, .name = "SBC", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = sbc },
        0xFD => Instruction{ .opcode = 0xFD, .name = "SBC", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = sbc },
        // --- SED, SEI ---
        0xF8 => Instruction{ .opcode = 0xF8, .name = "SED", .addressing = .Implied, .cycles = 2, .opcode_fn = sed },
        // --- NOP ---
        0xEA => Instruction{ .opcode = 0xEA, .name = "NOP", .addressing = .Implied, .cycles = 2, .opcode_fn = nop },
        0x80 => Instruction{ .opcode = 0x80, .name = "NOP", .addressing = .Immediate, .cycles = 2, .opcode_fn = nop },
        0x04 => Instruction{ .opcode = 0x04, .name = "NOP", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = nop },
        0x0C => Instruction{ .opcode = 0x0C, .name = "NOP", .addressing = .Absolute, .cycles = 4, .opcode_fn = nop },
        0x14 => Instruction{ .opcode = 0x14, .name = "NOP", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = nop },
        0x1A => Instruction{ .opcode = 0x1A, .name = "NOP", .addressing = .Implied, .cycles = 2, .opcode_fn = nop },
        0x1C => Instruction{ .opcode = 0x1C, .name = "NOP", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = nop },
        0x34 => Instruction{ .opcode = 0x34, .name = "NOP", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = nop },
        0x3A => Instruction{ .opcode = 0x3A, .name = "NOP", .addressing = .Implied, .cycles = 2, .opcode_fn = nop },
        0x3C => Instruction{ .opcode = 0x3C, .name = "NOP", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = nop },
        0x44 => Instruction{ .opcode = 0x44, .name = "NOP", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = nop },
        0x54 => Instruction{ .opcode = 0x54, .name = "NOP", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = nop },
        0x5A => Instruction{ .opcode = 0x5A, .name = "NOP", .addressing = .Implied, .cycles = 2, .opcode_fn = nop },
        0x5C => Instruction{ .opcode = 0x5C, .name = "NOP", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = nop },
        0x64 => Instruction{ .opcode = 0x64, .name = "NOP", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = nop },
        0x74 => Instruction{ .opcode = 0x74, .name = "NOP", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = nop },
        0x7A => Instruction{ .opcode = 0x7A, .name = "NOP", .addressing = .Implied, .cycles = 2, .opcode_fn = nop },
        0x7C => Instruction{ .opcode = 0x7C, .name = "NOP", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = nop },
        0x82 => Instruction{ .opcode = 0x82, .name = "NOP", .addressing = .Immediate, .cycles = 2, .opcode_fn = nop },
        0x89 => Instruction{ .opcode = 0x89, .name = "NOP", .addressing = .Immediate, .cycles = 2, .opcode_fn = nop },
        0xC2 => Instruction{ .opcode = 0xC2, .name = "NOP", .addressing = .Immediate, .cycles = 2, .opcode_fn = nop },
        0xD4 => Instruction{ .opcode = 0xD4, .name = "NOP", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = nop },
        0xDA => Instruction{ .opcode = 0xDA, .name = "NOP", .addressing = .Implied, .cycles = 2, .opcode_fn = nop },
        0xDC => Instruction{ .opcode = 0xDC, .name = "NOP", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = nop },
        0xE2 => Instruction{ .opcode = 0xE2, .name = "NOP", .addressing = .Immediate, .cycles = 2, .opcode_fn = nop },
        0xF4 => Instruction{ .opcode = 0xF4, .name = "NOP", .addressing = .ZeroPageX, .cycles = 4, .opcode_fn = nop },
        0xFA => Instruction{ .opcode = 0xFA, .name = "NOP", .addressing = .Implied, .cycles = 2, .opcode_fn = nop },
        0xFC => Instruction{ .opcode = 0xFC, .name = "NOP", .addressing = .AbsoluteX, .cycles = 4, .opcode_fn = nop },
        0xFF => Instruction{ .opcode = 0xFF, .name = "ISC", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = isc },

        // Unofficial
        0x03 => Instruction{ .opcode = 0x03, .name = "SLO", .addressing = .IndirectX, .cycles = 8, .opcode_fn = slo },
        0x07 => Instruction{ .opcode = 0x07, .name = "SLO", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = slo },
        0x0B => Instruction{ .opcode = 0x0B, .name = "ANC", .addressing = .Immediate, .cycles = 2, .opcode_fn = anc },
        0x0F => Instruction{ .opcode = 0x0F, .name = "SLO", .addressing = .Absolute, .cycles = 6, .opcode_fn = slo },

        0x13 => Instruction{ .opcode = 0x13, .name = "SLO", .addressing = .IndirectY, .cycles = 8, .opcode_fn = slo },
        0x17 => Instruction{ .opcode = 0x17, .name = "SLO", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = slo },
        0x1B => Instruction{ .opcode = 0x1B, .name = "SLO", .addressing = .AbsoluteY, .cycles = 7, .opcode_fn = slo },
        0x1F => Instruction{ .opcode = 0x1F, .name = "SLO", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = slo },

        0x23 => Instruction{ .opcode = 0x23, .name = "RLA", .addressing = .IndirectX, .cycles = 8, .opcode_fn = rla },
        0x27 => Instruction{ .opcode = 0x27, .name = "RLA", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = rla },
        0x2B => Instruction{ .opcode = 0x2B, .name = "ANC", .addressing = .Immediate, .cycles = 2, .opcode_fn = anc },
        0x2F => Instruction{ .opcode = 0x2F, .name = "RLA", .addressing = .Absolute, .cycles = 6, .opcode_fn = rla },

        0x33 => Instruction{ .opcode = 0x33, .name = "RLA", .addressing = .IndirectY, .cycles = 8, .opcode_fn = rla },
        0x37 => Instruction{ .opcode = 0x37, .name = "RLA", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = rla },
        0x3B => Instruction{ .opcode = 0x3B, .name = "RLA", .addressing = .AbsoluteY, .cycles = 7, .opcode_fn = rla },
        0x3F => Instruction{ .opcode = 0x3F, .name = "RLA", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = rla },

        0x43 => Instruction{ .opcode = 0x43, .name = "SRE", .addressing = .IndirectX, .cycles = 8, .opcode_fn = sre },
        0x47 => Instruction{ .opcode = 0x47, .name = "SRE", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = sre },
        0x4B => Instruction{ .opcode = 0x4B, .name = "ALR", .addressing = .Immediate, .cycles = 2, .opcode_fn = alr },
        0x4F => Instruction{ .opcode = 0x4F, .name = "SRE", .addressing = .Absolute, .cycles = 6, .opcode_fn = sre },

        0x53 => Instruction{ .opcode = 0x53, .name = "SRE", .addressing = .IndirectY, .cycles = 8, .opcode_fn = sre },
        0x57 => Instruction{ .opcode = 0x57, .name = "SRE", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = sre },
        0x5B => Instruction{ .opcode = 0x5B, .name = "SRE", .addressing = .AbsoluteY, .cycles = 7, .opcode_fn = sre },
        0x5F => Instruction{ .opcode = 0x5F, .name = "SRE", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = sre },

        0x63 => Instruction{ .opcode = 0x63, .name = "RRA", .addressing = .IndirectX, .cycles = 8, .opcode_fn = rra },
        0x67 => Instruction{ .opcode = 0x67, .name = "RRA", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = rra },
        0x6B => Instruction{ .opcode = 0x6B, .name = "ARR", .addressing = .Immediate, .cycles = 2, .opcode_fn = arr },
        0x6F => Instruction{ .opcode = 0x6F, .name = "RRA", .addressing = .Absolute, .cycles = 6, .opcode_fn = rra },

        0x73 => Instruction{ .opcode = 0x73, .name = "RRA", .addressing = .IndirectY, .cycles = 8, .opcode_fn = rra },
        0x77 => Instruction{ .opcode = 0x77, .name = "RRA", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = rra },
        0x7B => Instruction{ .opcode = 0x7B, .name = "RRA", .addressing = .AbsoluteY, .cycles = 7, .opcode_fn = rra },
        0x7F => Instruction{ .opcode = 0x7F, .name = "RRA", .addressing = .AbsoluteX, .cycles = 7, .opcode_fn = rra },

        0x83 => Instruction{ .opcode = 0x83, .name = "SAX", .addressing = .IndirectX, .cycles = 6, .opcode_fn = sax },
        0x87 => Instruction{ .opcode = 0x87, .name = "SAX", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = sax },
        0x8B => Instruction{ .opcode = 0x8B, .name = "XAA", .addressing = .Immediate, .cycles = 2, .opcode_fn = xaa },
        0x8F => Instruction{ .opcode = 0x8F, .name = "SAX", .addressing = .Absolute, .cycles = 4, .opcode_fn = sax },

        0x93 => Instruction{ .opcode = 0x93, .name = "AHX", .addressing = .IndirectY, .cycles = 6, .opcode_fn = ahx },
        0x97 => Instruction{ .opcode = 0x97, .name = "SAX", .addressing = .ZeroPageY, .cycles = 4, .opcode_fn = sax },
        0x9B => Instruction{ .opcode = 0x9B, .name = "TAS", .addressing = .AbsoluteY, .cycles = 5, .opcode_fn = tas },
        0x9F => Instruction{ .opcode = 0x9F, .name = "AHX", .addressing = .AbsoluteY, .cycles = 5, .opcode_fn = ahx },

        0xA3 => Instruction{ .opcode = 0xA3, .name = "LAX", .addressing = .IndirectX, .cycles = 6, .opcode_fn = lax },
        0xA7 => Instruction{ .opcode = 0xA7, .name = "LAX", .addressing = .ZeroPage, .cycles = 3, .opcode_fn = lax },
        0xAB => Instruction{ .opcode = 0xAB, .name = "LAX", .addressing = .Immediate, .cycles = 2, .opcode_fn = lax },
        0xAF => Instruction{ .opcode = 0xAF, .name = "LAX", .addressing = .Absolute, .cycles = 4, .opcode_fn = lax },

        0xB3 => Instruction{ .opcode = 0xB3, .name = "LAX", .addressing = .IndirectY, .cycles = 5, .opcode_fn = lax },
        0xB7 => Instruction{ .opcode = 0xB7, .name = "LAX", .addressing = .ZeroPageY, .cycles = 4, .opcode_fn = lax },
        0xBB => Instruction{ .opcode = 0xBB, .name = "LAS", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = las },
        0xBF => Instruction{ .opcode = 0xBF, .name = "LAX", .addressing = .AbsoluteY, .cycles = 4, .opcode_fn = lax },

        0xE3 => Instruction{ .opcode = 0xE3, .name = "ISC", .addressing = .IndirectX, .cycles = 8, .opcode_fn = isc },
        0xE7 => Instruction{ .opcode = 0xE7, .name = "ISC", .addressing = .ZeroPage, .cycles = 5, .opcode_fn = isc },
        0xEB => Instruction{ .opcode = 0xEB, .name = "SBC", .addressing = .Immediate, .cycles = 2, .opcode_fn = sbc },
        0xEF => Instruction{ .opcode = 0xEF, .name = "ISC", .addressing = .Absolute, .cycles = 6, .opcode_fn = isc },

        0xF3 => Instruction{ .opcode = 0xF3, .name = "ISC", .addressing = .IndirectY, .cycles = 8, .opcode_fn = isc },
        0xF7 => Instruction{ .opcode = 0xF7, .name = "ISC", .addressing = .ZeroPageX, .cycles = 6, .opcode_fn = isc },
        0xFB => Instruction{ .opcode = 0xFB, .name = "ISC", .addressing = .AbsoluteY, .cycles = 7, .opcode_fn = isc },

        else => {
            std.debug.print("Found opcode: {x}\n", .{byte});
            unreachable;
        },
    };
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

    self.pc = self.read16(0xFFFE);
}

fn stx(self: *Cpu, addr: u16) void {
    self.writeByte(addr, self.x);
}

fn sty(self: *Cpu, addr: u16) void {
    self.writeByte(addr, self.y);
}

fn ror(self: *Cpu, addr: u16) void {
    const n = self.readByte(addr);
    const carry: u8 = @intFromBool(self.carry);
    self.carry = n & 0b0000_0001 != 0;
    const result = (n >> 1) | (carry << 7);
    self.writeByte(addr, result);
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
    self.writeByte(addr, result);
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
    self.writeByte(addr, result);
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
    self.writeByte(addr, result);
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

    const op = self.a;
    self.a = op +% operand +% @intFromBool(self.carry);

    self.overflow = @as(u1, @truncate(((self.a ^ op) & (self.a ^ operand)) >> 7)) == 1;
    self.carry = self.a < (@as(u16, operand) +% @intFromBool(self.carry));
    self.zero = self.a == 0;
    self.negative = self.a & 0x80 != 0;

    // {
    //     std.debug.print("DECIMAL ADC\n", .{});
    //
    //     var lower = (self.a & 0xF) + (operand & 0xF) + @intFromBool(self.carry);
    //     var upper = (self.a >> 4) + (operand >> 4);
    //
    //     var carry_out = false;
    //     if (lower >= 10) {
    //         lower = (lower - 10) & 0xF;
    //         upper += 1;
    //     }
    //     if (upper >= 10) {
    //         upper = (upper - 10) & 0xF;
    //         carry_out = true;
    //     }
    //
    //     const result = (upper << 4) | lower;
    //     self.carry = carry_out;
    //     self.updateA(result);
    //
    //     std.debug.print("Operand: {} Result: {}\n", .{operand, self.a});
    //
    // }
}

fn sta(self: *Cpu, addr: u16) void {
    self.writeByte(addr, self.a);
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
    self.writeByte(addr, result);
    self.updateNZFlags(result);
}

fn dcp(self: *Cpu, addr: u16) void {
    dec(self, addr);
    cmp(self, addr);
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
    self.writeByte(addr, result);
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

    // {
    //     var lower = (@as(i16, @intCast(self.a)) & 0xF) - (@as(i16, @intCast(operand)) & 0xF) - @intFromBool(!self.carry);
    //     var upper = (@as(i16, @intCast(self.a)) >> 4) - (@as(i16, @intCast(operand)) >> 4);
    //
    //     var carry_out = true;
    //     if (lower & 0x10 != 0) {
    //         lower = (lower + 10) & 0xF;
    //         upper -= 1;
    //     }
    //     if (upper & 0x10 != 0) {
    //         upper = (upper + 10) & 0xF;
    //         carry_out = false;
    //     }
    //
    //     const result = @as(u8, @intCast(upper << 4)) | @as(u8, @intCast(lower));
    //     self.carry = carry_out;
    //     self.updateA(result);
    // }
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
    inc(self,addr);
    sbc(self, addr);
}

fn slo(self: *Cpu, addr: u16) void {
    asl(self, addr);
    ora(self, addr);
}

fn rla(self: *Cpu, addr: u16) void {
    rol(self, addr);
    and_(self, addr);
}

fn sre(self: *Cpu, addr: u16) void {
    lsr(self, addr);
    eor(self, addr);
}

fn rra(self: *Cpu, addr: u16) void {
    ror(self, addr);
    adc(self, addr);
}

fn arr(self: *Cpu, addr: u16) void {
    and_(self, addr);
    ror(self, addr);
}

fn alr(self: *Cpu, addr: u16) void {
    and_(self, addr);
    lsr(self, addr);
}

fn sax(self: *Cpu, addr: u16) void {
    self.writeByte(addr, self.a & self.x);
}

fn las(self: *Cpu, addr: u16) void {
    const n = self.readByte(addr);
    const data = n & self.sp;
    self.updateA(data);
    self.updateX(data);
    self.sp = data;
}

fn tas(self: *Cpu, addr: u16) void {
    var data: u8 = self.a & self.x;
    self.sp = data;
    data = (@as(u8, @intCast(addr >> 8)) + 1) & self.sp;
    self.writeByte(addr, data);
}

fn ahx(self: *Cpu, addr: u16) void {
    const data: u8 = self.a & self.x & (@as(u8, @intCast(addr >> 8)));
    self.writeByte(addr, data);
}

fn xaa(self: *Cpu, addr: u16) void {
    self.updateA(self.x);
    and_(self, addr);
}

fn lax(self: *Cpu, addr: u16) void {
    const n = self.readByte(addr);
    self.updateA(n);
    self.x = self.a;
}

fn axs(self: *Cpu, addr: u16) void {
    const n = self.readByte(addr);
    const x_and_a = self.x & self.a;
    const result = x_and_a -% n;

    if (n <= x_and_a) {
        self.carry = true;
    }

    self.updateNZFlags(result);

    self.x = result;
}

fn anc(self: *Cpu, addr: u16) void {
    and_(self, addr);
    if (self.negative) {
        self.carry = true;
    } else {
        self.carry = false;
    }
}