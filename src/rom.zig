const std = @import("std");

pub const Mirroring = enum {
    Vertical,
    Horizontal,
    FourScreen,
};

pub const NES_TAG = "NES\x1A";
pub const PRG_ROM_PAGE_SIZE = 16384;
pub const CHR_ROM_PAGE_SIZE = 8192;

pub const Rom = struct {
    prg_rom: [1024 * 32]u8,
    prg_len: usize,

    chr_rom: [1024 * 8]u8,
    chr_len: usize,

    mapper: u8,
    mirroring: Mirroring,

    pub fn fromFile(path: []const u8, abs: bool) !Rom {
        const file = if (abs) try std.fs.openFileAbsolute(path, .{}) else try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var rom = Rom{
            .prg_rom = undefined,
            .prg_len = 0,
            .chr_rom = undefined,
            .chr_len = 0,
            .mapper = 0,
            .mirroring = .Horizontal,
        };

        // 1 MB max size
        var buffer: [1024 * 1024]u8 = undefined;
        _ = try file.readAll(&buffer);

        if (!std.mem.eql(u8, buffer[0..4], NES_TAG)) return error.InvalidRomFormat;

        rom.mapper = (buffer[7] & 0b1111_0000) | (buffer[6] >> 4);

        const ines_ver: u8 = (buffer[7] >> 2) & 0b11;
        if (ines_ver != 0) return error.UnsupportedInesVersion;

        const four_screen = buffer[6] & 0b1000 != 0;
        const vertical_mirroring = buffer[6] & 0b1 != 0;
        if (four_screen) {
            rom.mirroring = .FourScreen;
        } else if (vertical_mirroring) {
            rom.mirroring = .Vertical;
        }

        const prg_rom_size: usize = @as(usize, buffer[4]) * PRG_ROM_PAGE_SIZE;
        const chr_rom_size: usize = @as(usize, buffer[5]) * CHR_ROM_PAGE_SIZE;

        const skip_trainer = buffer[6] & 0b100 != 0;

        const prg_rom_start: usize = 16 + if (skip_trainer) @as(usize, 512) else (0);
        const chr_rom_start = prg_rom_start + prg_rom_size;

        rom.prg_len = prg_rom_size;
        rom.chr_len = chr_rom_size;

        @memcpy(rom.prg_rom[0..prg_rom_size], buffer[prg_rom_start..(prg_rom_start + prg_rom_size)]);
        @memcpy(rom.chr_rom[0..chr_rom_size], buffer[chr_rom_start..(chr_rom_start + chr_rom_size)]);

        return rom;
    }

    pub fn getInternalAddress(self: *Rom, addr: u16) u16 {
        const nametable_start = 0x2000;
        const mirrored_addr = (addr - nametable_start) % 0x1000;

        return switch (self.mirroring) {
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
};