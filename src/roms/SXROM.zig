const std = @import("std");
const Rom = @import("../rom.zig");

const Self = @This();

const prg_bank_size = 0x4000;
const chr_bank_size = 0x1000;

has_chr_ram: bool = false,
num_chr_banks: u16 = 0,

shift_register: u5 = 0,
shift_counter: u8 = 0,
control_register: packed union {
    value: u5,
    bits: packed struct {
        mirroring: u2,
        prg_rom_bank_mode: u2,
        chr_rom_two_bank_mode: bool,
    },
} = .{ .value = 0 },

prg_register: u5 = 0,
chr_register_0: u5 = 0,
chr_register_1: u5 = 0,

prg_bank_offset_0: u32 = 0,
prg_bank_offset_1: u32 = 0,
chr_bank_offset_0: u32 = 0,
chr_bank_offset_1: u32 = 0,

prg_ram: [0x8000]u8 = undefined,
chr_ram: [0x2000]u8 = undefined,

rom: *Rom,

pub fn init(rom: *Rom) Self {
    var self: Self = .{
        .rom = rom,
    };

    self.control_register.value |= 0xC;
    self.has_chr_ram = rom.header.num_chr_rom_banks == 0;
    self.num_chr_banks = if (!self.has_chr_ram) rom.header.num_chr_rom_banks * 2 else 2;
    @memset(self.prg_ram[0..], 0);
    @memset(self.chr_ram[0..], 0);

    self.control_register.bits.prg_rom_bank_mode = 3;
    self.updateChrBankOffsets();
    self.updatePrgBankOffsets();

    return self;
}

pub fn read(self: *Self, addr: u16) u8 {
    switch (addr) {
        0x4000...0x5FFF => return 0,
        0x6000...0x7FFF => {
            return self.prg_ram[addr - 0x6000];
        },
        0x8000...0xBFFF => return self.rom.prg_rom[(addr - 0x8000) + self.prg_bank_offset_0],
        0xC000...0xFFFF => return self.rom.prg_rom[(addr - 0xC000) + self.prg_bank_offset_1],
        else => unreachable,
    }
}

pub fn write(self: *Self, addr: u16, value: u8) void {
    switch (addr) {
        0x4000...0x5FFF => {},
        0x6000...0x7FFF => {
            self.prg_ram[addr - 0x6000] = value;
        },
        0x8000...0xFFFF => self.writeToSerial(addr, value),
        else => unreachable,
    }
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    return switch (addr) {
        0...0x0FFF => {
            if (self.has_chr_ram) {
                return self.chr_ram[addr + self.chr_bank_offset_0];
            } else {
                return self.rom.chr_rom[addr + self.chr_bank_offset_0];
            }
        },
        0x1000...0x1FFF => {
            if (self.has_chr_ram) {
                return self.chr_ram[(addr - 0x1000) + self.chr_bank_offset_1];
            } else {
                return self.rom.chr_rom[(addr - 0x1000) + self.chr_bank_offset_1];
            }
        },
        0x2000...0x3FFF => self.rom.ppu_ram[getInternalAddress(self.control_register.bits.mirroring, addr)],
        else => unreachable,
    };
}

pub fn ppuWrite(self: *Self, addr: u16, value: u8) void {
    switch (addr) {
        0...0x0FFF => {
            if (self.has_chr_ram) {
                self.chr_ram[addr + self.chr_bank_offset_0] = value;
            } else {
                self.rom.chr_rom[addr + self.chr_bank_offset_0] = value;
            }
        },
        0x1000...0x1FFF => {
            if (self.has_chr_ram) {
                self.chr_ram[(addr - 0x1000) + self.chr_bank_offset_1] = value;
            } else {
                self.rom.chr_rom[(addr - 0x1000) + self.chr_bank_offset_1] = value;
            }
        },
        0x2000...0x3FFF => {
            self.rom.ppu_ram[getInternalAddress(self.control_register.bits.mirroring, addr)] = value;
        },
        else => unreachable,
    }
}

fn updateChrBankOffsets(self: *Self) void {
    if (self.control_register.bits.chr_rom_two_bank_mode) {
        self.chr_bank_offset_0 = @as(u32, self.chr_register_0) * chr_bank_size;
    } else {
        self.chr_bank_offset_0 = @as(u32, self.chr_register_0 & 0x1E) * chr_bank_size;
    }

    if (self.control_register.bits.chr_rom_two_bank_mode) {
        self.chr_bank_offset_1 = @as(u32, self.chr_register_1) * chr_bank_size;
    } else {
        self.chr_bank_offset_1 = @as(u32, self.chr_register_1 | 1) * chr_bank_size;
    }
}

fn updatePrgBankOffsets(self: *Self) void {
    self.prg_bank_offset_0 = switch (self.control_register.bits.prg_rom_bank_mode) {
        0, 1 => @as(u32, self.prg_register & 0x1E) * prg_bank_size,
        2 => 0,
        3 => @as(u32, self.prg_register) * prg_bank_size,
    };

    self.prg_bank_offset_1 = switch (self.control_register.bits.prg_rom_bank_mode) {
        0, 1 => @as(u32, self.prg_register | 1) * prg_bank_size,
        2 => @as(u32, self.prg_register) * prg_bank_size,
        3 => @as(u32,  self.rom.header.num_prg_rom_banks -| 1) * prg_bank_size,
    };
}

fn writeToSerial(self: *Self, addr: u16, value: u8) void {
    if (value & 0x80 == 0x80) {
        self.shift_register = 0;
        self.shift_counter = 5;
        self.control_register.value |= 0xC;
        self.updateChrBankOffsets();
        self.updatePrgBankOffsets();
        return;
    }

    self.shift_register >>= 1;
    self.shift_register |= @truncate((value & 1) << 4);
    self.shift_counter -= 1;

    if (self.shift_counter == 0) {
        switch (addr) {
            0x8000...0x9FFF => {
                self.control_register.value = self.shift_register;
                self.updateChrBankOffsets();
                self.updatePrgBankOffsets();
            },
            0xA000...0xBFFF => {
                self.chr_register_0 = self.shift_register & @as(u5, @truncate(self.num_chr_banks -| 1));
                self.updateChrBankOffsets();
            },
            0xC000...0xDFFF => {
                self.chr_register_1 = self.shift_register & @as(u5, @truncate(self.num_chr_banks -| 1));
                self.updateChrBankOffsets();
            },
            0xE000...0xFFFF => {
                self.prg_register = self.shift_register & @as(u5, @truncate(self.rom.header.num_prg_rom_banks -| 1));
                self.updatePrgBankOffsets();
            },
            else => unreachable,
        }
        self.shift_register = 0;
        self.shift_counter = 5;
    }
}

fn getInternalAddress(mirroring: u4, addr: u16) u16 {
    const nametable_start = 0x2000;
    const mirrored_addr = (addr - nametable_start) % 0x1000;

    return switch (mirroring) {
        0 => mirrored_addr % 0x400,
        1 => (mirrored_addr % 0x400) + 0x400,
        2 => mirrored_addr % 0x800,
        3 => switch (mirrored_addr) {
            0...0x3FF => mirrored_addr,
            0x400...0xBFF => mirrored_addr - 0x400,
            0xC00...0xFFF => mirrored_addr - 0x800,
            else => 0,
        },
        else => 0,
    };
}