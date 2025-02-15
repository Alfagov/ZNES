const std = @import("std");
const Rom = @import("../rom.zig");

const Self = @This();

inline fn getRomImpl(rom: *Rom) *Self {
    return @as(*Self, @ptrCast(@alignCast(rom.rom_impl)));
}

mirror: u16 = 0,
rom: *Rom,

pub fn init(rom: *Rom) Self {
    return .{
        .rom = rom,
        .mirror = if (rom.header.num_prg_rom_banks == 1) 0x4000 else 0,
    };
}

pub fn read(self: *Self, addr: u16) u8 {
    const start = 0x8000;
    switch (addr) {
        0x4000...0x7FFF => return 0,
        0x8000...0xBFFF => {
            const rom_addr = addr - start;
            return self.rom.prg_rom[rom_addr];
        },
        0xC000...0xFFFF => {
            const rom_addr = addr - start - self.mirror;
            return self.rom.prg_rom[rom_addr];
        },
        else => @panic("Reading invalid ROM address"),
    }
}

pub fn write(_: *Self, _: u16, _: u8) void {
    std.debug.print("Cannot write to NROM PRG_ROM\n", .{});
}

fn getInternalAddress(mirror: Rom.Mirroring, addr: u16) u16 {
    const nametable_start = 0x2000;
    const mirrored_addr = (addr - nametable_start) % 0x1000;

    return switch (mirror) {
        .Horizontal => switch (mirrored_addr) {
            0...0x3FF => mirrored_addr,
            0x400...0xBFF => mirrored_addr - 0x400,
            0xC00...0xFFF => mirrored_addr - 0x800,
            else => @panic("Invalid address"),
        },
        .Vertical => mirrored_addr % 0x800,
        .FourScreen => mirrored_addr,
    };
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    switch (addr) {
        0...0x1FFF => return self.rom.chr_rom[addr],
        0x2000...0x3FFF => {
            const internal_addr = getInternalAddress(self.rom.header.mirror, addr);
            return self.rom.ppu_ram[internal_addr];
        },
        else => @panic("PPU: Reading invalid ROM address"),
    }
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    switch (addr) {
        0...0x1FFF => std.debug.print("Cannot write to CHR rom\n", .{}),
        0x2000...0x3FFF => {
            const internal_addr = getInternalAddress(self.rom.header.mirror, addr);
            self.rom.ppu_ram[internal_addr] = data;
        },
        else => @panic("PPU: Writing invalid ROM address"),
    }
}