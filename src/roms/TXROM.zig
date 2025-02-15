const std = @import("std");
const Rom = @import("../rom.zig");

const Self = @This();

const prg_bank_size = 0x2000;
const chr_bank_size = 0x400;

num_prg_banks: u32 = 0,
num_chr_banks: u32 = 0,

bank_update_register: u3 = 0,
prg_bank_mode: u1 = 0,
chr_bank_mode: u1 = 0,
mirroring: u1 = 0,
irq_counter_reload: u8 = 0,
irq_counter: u8 = 0,
irq_enabled: bool = false,

bank_registers: [8]u32 = .{0} ** 8,

prg_ram: [0x8000]u8 = undefined,
chr_ram: [0x2000]u8 = undefined,

rom: *Rom,

pub fn init(rom: *Rom) Self {
    var self: Self = .{
        .rom = rom,
    };

    self.num_prg_banks = rom.header.num_prg_rom_banks * 2;
    self.num_chr_banks = rom.header.num_chr_rom_banks * 8;

    @memset(self.prg_ram[0..], 0);
    @memset(self.chr_ram[0..], 0);
}

pub fn read(self: *Self, addr: u16) u8 {
    return switch (addr) {
        0x4000...0x5FFF => 0,
        0x6000...0x7FFF => self.prg_ram[addr-0x6000],
        0x8000...0xFFFF => self.rom.prg_rom[self.getPrgAddress(addr)],
        else => unreachable,
    };
}

pub fn write(self: *Self, addr: u16, data: u8) void {
    switch (addr) {
        0x4000...0x5FFF => {},
        0x6000...0x7FFF => {
            self.prg_ram[addr-0x6000] = data;
        },
        0x8000...0x9FFF => {
            if (addr & 1 == 0) {
                const value: packed union {
                    value: u8,
                    bits: packed struct {
                        bank_update_register: u3,
                        _: u3,
                        prg_bank_mode: u1,
                        chr_bank_mode: u1
                    }
                } = .{.value = data};

                self.bank_update_register = value.bits.bank_update_register;
                self.prg_bank_mode = value.bits.prg_bank_mode;
                self.chr_bank_mode = value.bits.chr_bank_mode;
            } else {
                self.bank_registers[self.bank_update_register] = data;
            }
        },
        0xA000...0xBFFF => {
            if (addr & 1 == 0) {
                self.mirroring = @truncate(data & 1);
            } else {}
        },
        0xC000...0xBFFF => {
            if (addr & 1 == 0) {
                self.irq_counter_reload = data;
            } else {
                self.irq_counter = 0;
            }
        },
        0xE000...0xFFFF => {
            if (addr & 1 == 0) {
                self.irq_enabled = true;
            } else {
                self.irq_enabled = false;
            }
        },
        else => unreachable,
    }
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    return switch (addr) {
        0...0x1FFF => self.rom.chr_rom[self.getChrAddress(addr)],
        0x2000...0x3FFF => self.rom.ppu_ram[getInternalAddress(self.mirroring, addr)],
        else => unreachable,
    };
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    switch (addr) {
        0...0x1FFF => self.rom.chr_rom[self.getChrAddress(addr)] = data,
        0x2000...0x3FFF => self.rom.ppu_ram[getInternalAddress(self.mirroring, addr)] = data,
        else => unreachable,
    }
}

fn getInternalAddress(mirror: u1, address: u16) u16 {
    const nametable_start = 0x2000;
    const mirrored_addr = (address - nametable_start) % 0x1000;

    return switch (mirror) {
        1 => switch (mirrored_addr) {
            0...0x3FF => mirrored_addr,
            0x400...0xBFF => mirrored_addr - 0x400,
            0xC00...0xFFF => mirrored_addr - 0x800,
            else => unreachable,
        },
        0 => mirrored_addr % 0x800,
        else => unreachable,
    };
}

fn getPrgAddress(self: *Self, addr: u16) u32 {
    if (self.prg_bank_mode == 0) {
        switch (addr) {
            0x8000...0x9FFF => {
                return self.bank_registers[6] * prg_bank_size + @as(u32, addr) - 0x8000;
            },
            0xA000...0xBFFF => {
                return self.bank_registers[7] * prg_bank_size + @as(u32, addr) - 0xA000;
            },
            0xC000...0xDFFF => {
                return (self.num_prg_banks - 2) * prg_bank_size + @as(u32, addr) - 0xC000;
            },
            0xE000...0xFFFF => {
                return (self.num_prg_banks - 1) * prg_bank_size + @as(u32, addr) - 0xE000;
            },
            else => { unreachable; }
        }
    } else {
        switch(addr) {
            0x8000...0x9FFF => {
                return (self.num_prg_banks - 2) * prg_bank_size + @as(u32, addr) - 0x8000;
            },
            0xA000...0xBFFF => {
                return self.bank_registers[7] * prg_bank_size + @as(u32, addr) - 0xA000;
            },
            0xC000...0xDFFF => {
                return self.bank_registers[6] * prg_bank_size + @as(u32, addr) - 0xC000;
            },
            0xE000...0xFFFF => {
                return (self.num_prg_banks - 1) * prg_bank_size + @as(u32, addr) - 0xE000;
            },
            else => { unreachable; }
        }
    }
}


fn getChrAddress(self: *Self, addr: u16) u32 {
    if (self.chr_bank_mode == 0) {
        switch(addr) {
            0...0x7FF => {
                return (self.bank_registers[0] & 0xFE) * chr_bank_size + @as(u32, addr);
            },
            0x800...0xFFF => {
                return (self.bank_registers[1] & 0xFE) * chr_bank_size + @as(u32, addr) - 0x800;
            },
            0x1000...0x13FF => {
                return self.bank_registers[2] * chr_bank_size + @as(u32, addr) - 0x1000;
            },
            0x1400...0x17FF => {
                return self.bank_registers[3] * chr_bank_size + @as(u32, addr) - 0x1400;
            },
            0x1800...0x1BFF => {
                return self.bank_registers[4] * chr_bank_size + @as(u32, addr) - 0x1800;
            },
            0x1C00...0x1FFF => {
                return self.bank_registers[5] * chr_bank_size + @as(u32, addr) - 0x1C00;
            },
            else => { unreachable; }
        }
    } else {
        switch(addr) {
            0...0x3FF => {
                return self.bank_registers[2] * chr_bank_size + @as(u32, addr);
            },
            0x400...0x7FF => {
                return self.bank_registers[3] * chr_bank_size + @as(u32, addr) - 0x400;
            },
            0x800...0xBFF => {
                return self.bank_registers[4] * chr_bank_size + @as(u32, addr) - 0x800;
            },
            0xC00...0xFFF => {
                return self.bank_registers[5] * chr_bank_size + @as(u32, addr) - 0xC00;
            },
            0x1000...0x17FF => {
                return (self.bank_registers[0] & 0xFE) * chr_bank_size + @as(u32, addr) - 0x1000;
            },
            0x1800...0x1FFF => {
                return (self.bank_registers[1] & 0xFE) * chr_bank_size + @as(u32, addr) - 0x1800;
            },
            else => { unreachable; }
        }
    }
}

pub fn mapperIrq(self: *Self) void {
    if (self.irq_counter == 0) {
        self.irq_counter = self.irq_counter_reload;
    } else {
        self.irq_counter -= 1;
    }

    if (self.irq_counter == 0 and self.irq_enabled) {
        // TODO TRIGGER IRQ
    }
}