const std = @import("std");

const NROM = @import("roms/NROM.zig");
const SXROM = @import("roms/SXROM.zig");
const TXROM = @import("roms/TXROM.zig");

pub const Mirroring = enum {
    Vertical,
    Horizontal,
    FourScreen,
};

pub const NES_TAG = "NES\x1A";
pub const PRG_ROM_PAGE_SIZE = 16384;
pub const CHR_ROM_PAGE_SIZE = 8192;

const Self = @This();

pub const INesHeader = struct {
    format: u2,
    prg_ram_size: u8,
    mapper: u8,
    mirror: Mirroring,
    battery: bool,
    trainer: bool,
    num_prg_rom_banks: u8,
    num_chr_rom_banks: u8,
};

pub const HeaderDecode = packed struct {
    nes_string: u32,
    n_prg_rom_banks: u8,
    n_chr_rom_banks: u8,
    control_byte_1: packed struct {
        mirroring: u1,
        battery: u1,
        trainer: u1,
        four_screen: u1,
        mapper_type_low: u4,
    },
    control_byte_2: packed struct {
        _: u2,
        i_nes_format: u2,
        mapper_type_high: u4,
    },
    prg_ram_size: u8,
    _: u8,
    reserved: u48,
};

header: INesHeader = undefined,

prg_rom: [0x4000 * 128]u8 = undefined,
prg_len: usize = 0,

chr_rom: [0x2000 * 64]u8 = undefined,
chr_len: usize = 0,

ppu_ram: [0x1000]u8 = undefined,

rom_impl: RomImpl = undefined,

pub const Mappers = enum {
    NROM,
    SXROM,
    TXROM,
};

pub const RomImpl = union(Mappers) {
    NROM: NROM,
    SXROM: SXROM,
    TXROM: TXROM,

    pub fn read(self: *RomImpl, addr: u16) u8 {
        return switch (self.*) {
            .NROM => self.NROM.read(addr),
            .SXROM => self.SXROM.read(addr),
            .TXROM => self.TXROM.read(addr),
        };
    }

    pub fn write(self: *RomImpl, addr: u16, data: u8) void {
        switch (self.*) {
            .NROM => self.NROM.write(addr, data),
            .SXROM => self.SXROM.write(addr, data),
            .TXROM => self.TXROM.write(addr, data),
        }
    }

    pub fn ppuRead(self: *RomImpl, addr: u16) u8 {
        return switch (self.*) {
            .NROM => self.NROM.ppuRead(addr),
            .SXROM => self.SXROM.ppuRead(addr),
            .TXROM => self.TXROM.ppuRead(addr),
        };
    }

    pub fn ppuWrite(self: *RomImpl, addr: u16, data: u8) void {
        switch (self.*) {
            .NROM => self.NROM.ppuWrite(addr, data),
            .SXROM => self.SXROM.ppuWrite(addr, data),
            .TXROM => self.TXROM.ppuWrite(addr, data),
        }
    }

    pub fn fromRom(rom: *Self) RomImpl {
        return switch (rom.header.mapper) {
            0 => .{ .NROM = NROM.init(rom) },
            1 => .{ .SXROM = SXROM.init(rom) },
            else => @panic("Unsupported mapper"),
        };
    }
};

pub fn loadRom(self: *Self, path: []const u8, abs: bool) !void {
    try self.readFromFile(path, abs);
    self.rom_impl = RomImpl.fromRom(self);
}

pub fn readFromFile(self: *Self, path: []const u8, abs: bool) !void {
    const file = if (abs) try std.fs.openFileAbsolute(path, .{}) else try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var header_data = try in_stream.readStruct(HeaderDecode);

    std.debug.assert(std.mem.eql(u8, @as(*const [4]u8, @ptrCast(&header_data.nes_string)), NES_TAG));

    self.header = .{
        .format = header_data.control_byte_2.i_nes_format,
        .prg_ram_size = header_data.prg_ram_size,
        .mapper = @as(u8, header_data.control_byte_2.mapper_type_high) << 4 |
            @as(u8, header_data.control_byte_1.mapper_type_low),
        .mirror = switch ((@as(u2, header_data.control_byte_1.four_screen) << 1) + header_data.control_byte_1.mirroring) {
            0 => .Horizontal,
            1 => .Vertical,
            else => .FourScreen,
        },
        .battery = header_data.control_byte_1.battery == 1,
        .trainer = header_data.control_byte_1.trainer == 1,
        .num_prg_rom_banks = header_data.n_prg_rom_banks,
        .num_chr_rom_banks = header_data.n_chr_rom_banks,
    };

    const prg_bank_size = 0x4000;
    const prg_bytes = prg_bank_size * @as(u32, self.header.num_prg_rom_banks);

    const chr_bank_size = 0x2000;
    const chr_bytes = chr_bank_size * @as(u32, self.header.num_chr_rom_banks);

    const trainer_size = 512;
    if (self.header.trainer) {
        try in_stream.skipBytes(trainer_size, .{});
    }

    _ = try in_stream.readAll(self.prg_rom[0..prg_bytes]);
    _ = try in_stream.readAll(self.chr_rom[0..chr_bytes]);

    std.debug.print("{}\n", .{self.header});
}
