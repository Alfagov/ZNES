// Based on: https://github.com/jakehffn/zig-nes
const std = @import("std");
const rl = @import("raylib");
const Bus = @import("bus.zig").BusInterface;
const Rom = @import("rom.zig").Rom;
const Palette = @import("palette.zig");

const Self = @This();

v: u15 = 0,
t: packed union {
    value: u15,
    bytes: packed struct {
        lo: u8,
        hi: u8,
    },
    scroll: packed struct {
        coarse_x: u5,
        coarse_y: u5,
        nametable: u2,
        fine_y: u3
    },
} = .{ .value = 0 },
x: u3 = 0,
w: bool = true,

scanline: u16 = 0,
dot: u16 = 0,
pre_render_dot_skip: bool = false,
total_cycles: u32 = 0,

oam: [256]u8,
secondary_oam: [8]u8,
secondary_oam_size: u8 = 0,

tile_low_shift: u16 = 0,
tile_low_shift_latch: u16 = 0,
tile_high_shift: u16 = 0,
tile_high_shift_latch: u16 = 0,
palette_offset: u16 = 0,
previus_palette_offset: u16 = 0,
palette_offset_latch: u16 = 0,
tile_address: u16 = 0,
tile_address_latch: u16 = 0,

nmi_interupt: bool = false,

palette_ram_indices: [0x20]u8,

screen: Screen,
bus: Bus,
vram: [2048]u8,
rom: Rom,
palette: Palette = Palette.init(),

control_register: struct {
    const ControlRegister = @This();

    flags: ControlFlags = .{},

    pub fn write(self: *ControlRegister, value: u8) void {
        var ppu = @as(*Self, @alignCast(@fieldParentPtr("control_register", self)));
        const prev_v = ppu.control_register.flags.V;
        ppu.control_register.flags = @bitCast(value);
        ppu.t.bytes.hi = (ppu.t.bytes.hi & ~@as(u7, 0b1100)) | @as(u7, @truncate((value & 0b11) << 2));
        
        if (ppu.status_register.flags.V == 1 and prev_v == 0 and ppu.control_register.flags.V == 1) {
            ppu.nmi_interupt = true;
        }
    }
} = .{},

mask_register: struct {
    const MaskRegister = @This();

    flags: MaskFlags = .{},

    pub fn write(self: *MaskRegister, value: u8) void {
        var ppu = @as(*Self, @alignCast(@fieldParentPtr("mask_register", self)));
        ppu.mask_register.flags = @bitCast(value);
    }
} = .{},

status_register: struct {
    const StatusRegister = @This();

    flags: StatusFlags = .{},

    pub fn read(self: *StatusRegister) u8 {
        var ppu = @as(*Self, @alignCast(@fieldParentPtr("status_register", self)));
        ppu.w = true;
        const return_flags = self.flags;
        self.flags.V = 0;
        return @bitCast(return_flags);
    }
} = .{},

oam_address_register: struct {
    const OamAddressRegister = @This();

    address: u8 = 0,

    pub fn write(self: *OamAddressRegister, value: u8) void {
        self.address = value;
    }
} = .{},

oam_data_register: struct {
    const OamDataRegister = @This();

    pub fn read(self: *OamDataRegister) u8 {
        const ppu = @as(*Self, @alignCast(@fieldParentPtr("oam_data_register", self)));
        return ppu.oam[ppu.oam_address_register.address];
    }

    pub fn write(self: *OamDataRegister, value: u8) void {
        var ppu = @as(*Self, @alignCast(@fieldParentPtr("oam_data_register", self)));
        ppu.oam[ppu.oam_address_register.address] = value;
        ppu.oam_address_register.address +%= 1;
    }
} = .{},

scroll_register: struct {
    const ScrollRegister = @This();

    pub fn write(self: *ScrollRegister, value: u8) void {
        var ppu = @as(*Self, @alignCast(@fieldParentPtr("scroll_register", self)));
        if (ppu.w) {
            ppu.t.bytes.lo = (ppu.t.bytes.lo & ~@as(u8, 0b11111)) | (value >> 3);
            ppu.x = @truncate(value);
        } else {
            ppu.t.bytes.hi = @truncate((ppu.t.bytes.hi &  ~@as(u7, 0b1110011)) | ((0b111 & value) << 4) | (value >> 6));
            ppu.t.bytes.lo = (ppu.t.bytes.lo & ~@as(u8, 0b11100000)) | ((value & 0b111000) << 2);
        }

        ppu.w = !ppu.w;
    }
} = .{},

address_register: struct {
    const AddressRegister = @This();

    pub fn write(self: *AddressRegister, value: u8) void {
        var ppu = @as(*Self, @alignCast(@fieldParentPtr("address_register", self)));
        if (ppu.w) {
            ppu.t.bytes.hi = @truncate(value & 0b111111);
        } else {
            ppu.t.bytes.lo = value;
            ppu.v = ppu.t.value;
        }

        ppu.w = !ppu.w;
    }

    pub fn incrementAddress(self: *Self) void {
        self.v +%= if (self.control_register.flags.I == 0) 1 else 32;
        self.v &= 0x3FFF;
    }
} = .{},

data_register: struct {
    const DataRegister = @This();

    read_buffer: u8 = 0,

    pub fn read(self: *DataRegister) u8 {
        var ppu = @as(*Self, @alignCast(@fieldParentPtr("data_register", self)));

        var data = ppu.read(ppu.v);

        if (ppu.v < 0x3F00) {
            const last_read_byte = ppu.data_register.read_buffer;
            ppu.data_register.read_buffer = data;
            data = last_read_byte;
        } else {
            ppu.data_register.read_buffer = ppu.read(ppu.v - 0x1000);
        }

        @TypeOf(ppu.address_register).incrementAddress(ppu);
        return data;
    }

    pub fn write(self: *DataRegister, value: u8) void {
        var ppu = @as(*Self, @alignCast(@fieldParentPtr("data_register", self)));
        ppu.write(ppu.v, value);
        @TypeOf(ppu.address_register).incrementAddress(ppu);
    }
} = .{},

oam_dma_register: struct {
    const OamDmaRegister = @This();

    pub fn write(self: *OamDmaRegister, value: u8) void {
        var ppu = @as(*Self, @alignCast(@fieldParentPtr("oam_dma_register", self)));
        const page = @as(u16, value) << 8;
        for (0..ppu.oam.len) |_| {
            const cpu_page_offset: u16 = ppu.oam_address_register.address;
            ppu.oam_data_register.write(ppu.bus.read(page + cpu_page_offset));
        }
    }
} = .{},

pub fn init(bus: Bus, rom: Rom) Self {
    var ppu: Self = .{
        .oam = undefined,
        .secondary_oam = undefined,
        .bus = bus,
        .vram = undefined,
        .screen = Screen.init(),
        .palette_ram_indices = undefined,
        .rom = rom,
    };

    @memset(ppu.vram[0..], 0);
    @memset(ppu.oam[0..], 0);
    @memset(ppu.secondary_oam[0..], 0);
    @memset(ppu.palette_ram_indices[0..], 0);

    return ppu;
}

pub fn reset(self: *Self) void {
    self.v = 0;
    self.t.value = 0;
    self.x = 0;
    self.w = true;
    self.scanline = 0;
    self.dot = 0;
    self.pre_render_dot_skip = false;
    self.total_cycles = 0;
    self.secondary_oam_size = 0;
    self.tile_low_shift = 0;
    self.tile_low_shift_latch = 0;
    self.tile_high_shift = 0;
    self.tile_high_shift_latch = 0;
    self.palette_offset = 0;
    self.previus_palette_offset = 0;
    self.palette_offset_latch = 0;
    self.tile_address = 0;
    self.tile_address_latch = 0;
    self.nmi_interupt = false;
    self.control_register.flags = .{};
    self.mask_register.flags = .{};
    self.status_register.flags = .{};
    self.oam_address_register.address = 0;
    self.data_register.read_buffer = 0;
    self.vram = undefined;
    @memset(self.vram[0..], 0);
    @memset(self.oam[0..], 0);
    @memset(self.secondary_oam[0..], 0);
    @memset(self.palette_ram_indices[0..], 0);
}

pub fn pollNmi(self: *Self) bool {
    const result = self.nmi_interupt;
    self.nmi_interupt = false;
    return result;
}

pub fn read(self: *Self, addr: u16) u8 {
    const wrapped_addr = addr % 0x4000;
    return switch (wrapped_addr) {
        0...0x3EFF => switch (wrapped_addr) {
            0...0x1FFF => return self.rom.chr_rom[wrapped_addr],
            0x2000...0x3FFF => {
                const internal_addres = self.rom.getInternalAddress(wrapped_addr);
                return self.vram[internal_addres];
            },
            else => unreachable,
        },
        0x3F00...0x3FFF => {
            return self.palette_ram_indices[getPaletteAddress(wrapped_addr)];
        },
        else => {
            std.debug.print("Unmapped ppu bus read: {X}\n", .{addr});
            return 0;
        },
    };
}

pub fn write(self: *Self, addr: u16, data: u8) void {
    switch (addr % 0x4000) {
        0...0x3EFF =>  switch (addr) {
            0...0x1FFF => std.debug.print("Cannot write to CHR_ROM\n", .{}),
            0x2000...0x3FFF => {
                const internal_addres = self.rom.getInternalAddress(addr);
                self.vram[internal_addres] = data;
            },
            else => unreachable,
        },
        0x3F00...0x3FFF => {
            self.palette_ram_indices[getPaletteAddress(addr)] = data;
        },
        else => {
            std.debug.print("Unmapped ppu bus read: {X}\n", .{addr});
        },
    }
}

inline fn getPaletteAddress(addr: u16) u16 {
    const index = addr % 0x20;
    return switch (index) {
        0x10, 0x14, 0x18, 0x1C => index - 0x10,
        else => index,
    };
}


const ControlFlags = packed struct {
    N: u2 = 0,
    I: u1 = 0,
    S: u1 = 0,
    B: u1 = 0,
    H: u1 = 0,
    P: u1 = 0,
    V: u1 = 0,
};

const MaskFlags = packed struct {
    Gr: u1 = 0, // `0`: normal; `1`: greyscale
    m: u1 = 0,  // `1`: Show background in leftmost 8 pixels of screen; `0`: Hide
    M: u1 = 0,  // `1`: Show sprites in leftmost 8 pixels of screen; `0`: Hide
    b: u1 = 0,  // `1`: Show background; `0`: Hide
    s: u1 = 0,  // `1`: Show spites; `0`: Hide
    R: u1 = 0,  // Emphasize red
    G: u1 = 0,  // Emphasize green
    B: u1 = 0   // Emphasize blue
};

const StatusFlags = packed struct {
    _: u5 = 0,
    O: u1 = 0, // Indicate sprite overflow
    S: u1 = 0, // Set when a nonzero pixel of sprite 0 overlaps a nonzero background pixel
    V: u1 = 0, // V-blank has started
};

const Screen = struct {
    const width: usize = 256;
    const height: usize = 240;

    data: [width * height]rl.Color = undefined,

    pub fn init() Screen {
        var screen: Screen = .{};
        @memset(screen.data[0..screen.data.len], rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        return screen;
    }

    pub fn setPixel(self: *Screen, x: usize, y: usize, color: rl.Color) void {
        if (x < width and y < height) {
            const offset = y * width + x;
            self.data[offset] = color;
        }
    }
};

inline fn dotIncrement(self: *Self) void {
    self.total_cycles +%= 1;

    self.dot += 1;
    if (self.dot == 341) {
        self.dot = 0;
        self.scanline += 1;
    }

    if (self.scanline == 262) {
        self.scanline = 0;
    }
}

pub fn step(self: *Self) void {
    if (self.scanline == 261) {
        self.prerenderStep();
    } else if (self.scanline < 240) {
        self.renderStep();
    } else {
        if (self.scanline == 241 and self.dot == 1) {
            self.status_register.flags.V = 1;
            if (self.control_register.flags.V == 1) {
                self.nmi_interupt = true;
            }
        }
    }
    self.dotIncrement();
}

inline fn prerenderStep(self: *Self) void {
    if (self.dot == 1) {
        self.status_register.flags.O = 0;
        self.status_register.flags.S = 0;
        self.status_register.flags.V = 0;
    }
    if (self.isRendering()) {

        if (self.dot == 257) {
            self.v = (self.v & ~@as(u15, 0x41F)) | (self.t.value & 0x41F);
        }

        if (self.dot >= 280 and self.dot <= 304) {
            self.v = (self.v & ~@as(u15, 0x7BE0)) | (self.t.value & 0x7BE0);
        }
    }

    if (self.dot == 338) {
        if (self.pre_render_dot_skip and self.isRendering()) {
            self.dot += 1;
        }
        self.pre_render_dot_skip = !self.pre_render_dot_skip;
    }
}

fn renderStep(self: *Self) void {
    if (self.dot > 0 and self.dot <= 256) {
        self.updateTileRegisters();
        if (self.isRendering()) {
            if (self.dot % 8 == 0) {
                self.incrementScrollH();
            }
            if (self.dot == 256) {
                self.incrementScrollV();
            }
        }
        self.renderPixel();
        self.incrementShiftRegisters();
    } else if (self.dot >= 257 and self.dot <= 320) {
        if (self.dot == 260 and self.mask_register.flags.b == 1 and self.mask_register.flags.s == 1) {
            // TODO: MAPPER IRQ
        }
        if (self.isRendering()) {
            if ((self.dot -% 261) % 8 == 0) {
                self.updateTileRegisters();
            }

            if (self.dot == 257) {
                self.v = (self.v & ~@as(u15, 0x41F)) | (self.t.value & 0x41F);
            }
        }
    } else if (self.dot >= 321 and self.dot <= 336) {
        if (self.dot == 321) {
            self.updateTileRegisters();
        } else if ((self.dot == 328 or self.dot == 336) and self.isRendering()) {
            self.updateTileRegisters();
            self.tile_low_shift <<= 8;
            self.tile_high_shift <<= 8;
            self.incrementScrollH();
        } else {
            self.updateTileRegisters();
        }
    } else if (self.dot == 340) {
        self.secondary_oam_size = 0;

        const use_tall = self.control_register.flags.H == 1;
        const sprite_height: u16 = if (use_tall) 16 else 8;

        for (0..64) |i| {
            const sprite_y = self.oam[i*4] +| 1;
            const distance = (self.scanline + 1) -% sprite_y;

            if (distance < sprite_height) {
                if (self.secondary_oam_size == 8) {
                    self.status_register.flags.O = 1;
                    break;
                }
                self.secondary_oam[self.secondary_oam_size] = @truncate(i);
                self.secondary_oam_size += 1;
            }
        }
    }
}

inline fn incrementScrollH(self: *Self) void {
    if ((self.v & 0x001F) == 31) {
        self.v &= ~@as(u15, 0x001F);
        self.v ^= 0x0400;
    } else {
        self.v += 1;
    }
}

inline fn incrementScrollV(self: *Self) void {
    if ((self.v & 0x7000) != 0x7000) {
        self.v += 0x1000;
    } else {
        self.v &= ~@as(u15, 0x7000);
        var y = (self.v & 0x03E0) >> 5;
        if (y == 29) {
            y = 0;
            self.v ^= 0x0800;
        } else if (y == 31) {
            y = 0;
        } else {
            y += 1;
        }
        self.v = (self.v & ~@as(u15, 0x03E0)) | (y << 5);
    }
}

inline fn isRendering(self: *Self) bool {
    return self.mask_register.flags.b == 1 or self.mask_register.flags.s == 1;
}

fn updateTileRegisters(self: *Self) void {
    if (self.isRendering()) {
        switch (self.dot % 8) {
            1 => {
                self.tile_low_shift |= self.tile_low_shift_latch;
                self.tile_high_shift |= self.tile_high_shift_latch;

                self.previus_palette_offset = self.palette_offset;
                self.palette_offset = self.palette_offset_latch;
                self.tile_address = self.tile_address_latch;

                const tile: u16 = self.read(0x2000 | (self.v & 0x0FFF));
                self.tile_address_latch = (@as(u16, self.control_register.flags.B) * 0x1000) | (((self.v >> 12) & 0x7) + (tile * 16));
            },
            3 => {
                const attr_byte = self.read(0x23C0 | (self.v & 0x0C00) | ((self.v >> 4) & 0x38) | ((self.v >> 2) & 0x07));
                const palette_idx = (attr_byte >> @truncate(((self.v >> 4) & 4) | (self.v & 2))) & 0b11;
                self.palette_offset_latch = palette_idx << 2;
            },
            5 => {
                self.tile_low_shift_latch = self.read(self.tile_address_latch);
            },
            7 => {
                self.tile_high_shift_latch = self.read(self.tile_address_latch + 8);
            },
            else => {},
        }
    }
}

inline fn incrementShiftRegisters(self: *Self) void {
    self.tile_low_shift <<= 1;
    self.tile_high_shift <<= 1;
}

fn renderPixel(self: *Self) void {
    var pixel_color_address: u16 = 0;
    var bg_is_global = false;

    if (self.mask_register.flags.b == 1 and !(self.mask_register.flags.m == 0 and self.dot <= 8)) {
        const x_offset: u3 = self.x;
        const palette_color: u16 = (((self.tile_low_shift << x_offset) & 0x8000) >> 15)  |
                                   (((self.tile_high_shift << x_offset) & 0x8000) >> 14);

        var palette_offset: u16 = 0;
        if (palette_color == 0) {
            bg_is_global = true;
        } else {
            palette_offset = if (((self.dot - 1) % 8) + x_offset < 8) self.previus_palette_offset else self.palette_offset;
        }

        pixel_color_address = (palette_offset | palette_color);
    }

    if (self.mask_register.flags.s == 1 and !(self.mask_register.flags.M == 0 and self.dot <= 8)) {
        const use_tall_sprites = self.control_register.flags.H == 1;
        const sprite_h: u16 = if (use_tall_sprites) 16 else 8;

        for (0..self.secondary_oam_size) |i| {
            const oam_sprite_offset = self.secondary_oam[i] * 4;
            const sprite_x = self.oam[oam_sprite_offset + 3] +| 1;

            const distance = self.dot -% @as(u16, sprite_x);
            if (distance >= 8) {
                continue;
            }

            const sprite_y = self.oam[oam_sprite_offset] +% 1;
            const tile: u16 = self.oam[oam_sprite_offset + 1];
            const palette_idx: u2 = @truncate(self.oam[oam_sprite_offset + 2]);
            const priority = self.oam[oam_sprite_offset + 2] >> 5 & 1 == 0;
            const flip_h = self.oam[oam_sprite_offset + 2] >> 6 & 1 == 1;
            const flip_v = self.oam[oam_sprite_offset + 2] >> 7 & 1 == 1;

            var tile_y = self.scanline -| sprite_y;
            if (flip_v) {
                tile_y = sprite_h - 1 - tile_y;
            }

            var tile_x: u3 = @truncate(self.dot -| sprite_x);
            if (flip_h) {
                tile_x = 7 - tile_x;
            }

            var tile_pattern_offset: u16 = undefined;

            if (use_tall_sprites) {
                const y_offset = @as(u16, (tile_y & 7) | ((tile_y & 8) << 1));
                tile_pattern_offset = (tile >> 1) * 32 + y_offset;
                tile_pattern_offset |= (tile & 1) << 12;
            } else {
                tile_pattern_offset = (@as(u16, self.control_register.flags.S) * 0x1000) + (tile * 16) + @as(u16, tile_y);
            }

            const lower = self.read(tile_pattern_offset) >> (7 ^ tile_x);
            const upper = self.read(tile_pattern_offset + 8) >> (7 ^ tile_x);
            const palette_color: u2 = @truncate((upper & 1) << 1 | (lower & 1));

            if (palette_color == 0) {
                continue;
            }

            if (oam_sprite_offset == 0 and !bg_is_global and self.status_register.flags.S == 0) {
                self.status_register.flags.S = 1;
            }

            if (priority or bg_is_global) {
                pixel_color_address = (0x10 + @as(u16, palette_idx) * 4) + @as(u16, palette_color);
            }
        }
    }
    const pixel_color = self.palette.getColor(self.read(0x3F00 + pixel_color_address) % 64);
    self.screen.setPixel(self.dot - 1, self.scanline, pixel_color);
}