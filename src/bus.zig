const std = @import("std");
const Rom = @import("rom.zig");
const RomInterface = Rom.RomInterface;
const PPU = @import("ppu.zig");
const Cpu = @import("cpu.zig").Cpu;
const Controller = @import("controllers.zig");

//  _______________ $10000  _______________
// | PRG-ROM       |       |               |
// | Upper Bank    |       |               |
// |_ _ _ _ _ _ _ _| $C000 | PRG-ROM       |
// | PRG-ROM       |       |               |
// | Lower Bank    |       |               |
// |_______________| $8000 |_______________|
// | SRAM          |       | SRAM          |
// |_______________| $6000 |_______________|
// | Expansion ROM |       | Expansion ROM |
// |_______________| $4020 |_______________|
// | I/O Registers |       |               |
// |_ _ _ _ _ _ _ _| $4000 |               |
// | Mirrors       |       | I/O Registers |
// | $2000-$2007   |       |               |
// |_ _ _ _ _ _ _ _| $2008 |               |
// | I/O Registers |       |               |
// |_______________| $2000 |_______________|
// | Mirrors       |       |               |
// | $0000-$07FF   |       |               |
// |_ _ _ _ _ _ _ _| $0800 |               |
// | RAM           |       | RAM           |
// |_ _ _ _ _ _ _ _| $0200 |               |
// | Stack         |       |               |
// |_ _ _ _ _ _ _ _| $0100 |               |
// | Zero Page     |       |               |
// |_______________| $0000 |_______________|

const RAM: u16 = 0x0000;
const RAM_MIRRORS_END: u16 = 0x1FFF;
const PPU_REGISTERS: u16 = 0x2000;
const PPU_REGISTERS_MIRRORS_END: u16 = 0x3FFF;

pub const BusInterface = struct {
    ctx: *anyopaque,
    readFn: *const fn(ctx: *anyopaque, addr: u16) u8,
    writeFn: *const fn(ctx: *anyopaque, addr: u16, data: u8) void,
    peekFn: *const fn(ctx: *anyopaque, addr: u16) u8,
    getSliceFn: *const fn(ctx: *anyopaque) []u8,
    pollNmiFn: *const fn(ctx: *anyopaque) void,

    pub fn read(self: *BusInterface, addr: u16) u8 {
        return self.readFn(self.ctx, addr);
    }

    pub fn write(self: *BusInterface, addr: u16, data: u8) void {
        self.writeFn(self.ctx, addr, data);
    }

    pub fn peek(self: *BusInterface, addr: u16) u8 {
        return self.peekFn(self.ctx, addr);
    }

    pub fn getSlice(self: *BusInterface) []u8 {
        return self.getSliceFn(self.ctx);
    }

    pub fn pollNmi(self: *BusInterface) void {
        self.pollNmiFn(self.ctx);
    }
};

pub const NesBus = struct {
    ram: [2048]u8 = undefined,
    rom: Rom = .{},
    ppu: ?PPU,
    cpu: ?*Cpu = null,
    controller: Controller = .{},

    pub fn init() NesBus {
        return .{
            .ram = undefined,
            .ppu = null,
        };
    }

    pub fn pollNmiStatus(self: *anyopaque) void {
        const bus: *NesBus = @ptrCast(@alignCast(self));

        if (bus.ppu.?.pollNmi()) {
            bus.cpu.?.nmi();
            bus.cpu.?.remaining_clocks = 0;
            for (0..6) |_| {
                bus.ppu.?.step();
            }
        }
    }

    pub fn reset(self: *NesBus) void {
        if (self.ppu != null) {
            if (self.cpu != null) {
                self.cpu.?.reset();
            }
            self.ppu.?.reset();
        }
    }

    pub fn loadRom(self: *NesBus, path: []const u8) !void {
        try self.rom.loadRom(path, false);
        self.ppu = PPU.init(self.interface(), &self.rom);
    }

    pub fn loadRomAbs(self: *NesBus, path: []const u8) !void {
        try self.rom.loadRom(path, true);
        self.ppu = PPU.init(self.interface(), &self.rom);
    }

    pub fn setupCpu(self: *NesBus, cpu: *Cpu) void {
        self.cpu = cpu;
    }

    pub fn clock(self: *NesBus) void {
        pollNmiStatus(self);
        if (self.cpu.?.remaining_clocks == 0) {
            self.step();
            self.ppu.?.step();
            self.ppu.?.step();
            self.ppu.?.step();

        } else {
            self.cpu.?.remaining_clocks -= 1;
            self.ppu.?.step();
            self.ppu.?.step();
            self.ppu.?.step();
        }
    }

    pub fn step(self: *NesBus) void {
        self.cpu.?.step();
    }

    fn readPrgRom(self: *NesBus, addr: u16) u8 {
        if (self.rom) |rom| {
            switch (addr) {
                0x4000...0x7FFF => return 0,
                0x8000...0xBFFF => {
                    const rom_addr = addr - 0x8000;
                    return rom.prg_rom[rom_addr];
                },
                0xC000...0xFFFF => {
                    const rom_addr = addr - 0x8000 - rom.mirror;
                    return rom.prg_rom[rom_addr];

                },
                else => unreachable,
            }
        } else {
            @panic("No ROM loaded");
        }
    }

    pub fn memRead(self: *anyopaque, addr: u16) u8 {
        const bus: *NesBus = @ptrCast(@alignCast(self));

        switch (addr) {
            RAM...RAM_MIRRORS_END => {
                const mirrored_address = addr & 0b00000111_11111111;
                return bus.ram[mirrored_address];
            },
            0x2000...0x3FFF => switch (addr % 8) {
                2 => return bus.ppu.?.status_register.read(),
                4 => return bus.ppu.?.oam_data_register.read(),
                7 => return bus.ppu.?.data_register.read(),
                else => return 0,
            },
            0x4016 => return bus.controller.readControllerOne(),
            0x4020...0xFFFF => {
                return bus.rom.rom_impl.read(addr);
            },
            else => return 0,
        }
    }

    pub fn memWrite(self: *anyopaque, addr: u16, data: u8) void {
        const bus: *NesBus = @ptrCast(@alignCast(self));

        switch (addr) {
            RAM...RAM_MIRRORS_END => {
                const mirrored_address = addr & 0b11111111111;
                bus.ram[mirrored_address] = data;
            },
            0x2000...0x3FFF => {
                switch (addr % 8) {
                    0 => bus.ppu.?.control_register.write(data),
                    1 => bus.ppu.?.mask_register.write(data),
                    3 => bus.ppu.?.oam_address_register.write(data),
                    4 => bus.ppu.?.oam_data_register.write(data),
                    5 => bus.ppu.?.scroll_register.write(data),
                    6 => bus.ppu.?.address_register.write(data),
                    7 => bus.ppu.?.data_register.write(data),
                    else => {
                        std.debug.print("Unmapped main bus write: {X}\n", .{addr});
                    }
                }
            },
            0x4014 => bus.ppu.?.oam_dma_register.write(data),
            0x4016 => bus.controller.strobeSet(data),
            0x4020...0xFFFF => {
                bus.rom.rom_impl.write(addr, data);
            },
            else => {},
        }
    }

    pub fn peek(self: *anyopaque, addr: u16) u8 {
        const bus: *NesBus = @ptrCast(@alignCast(self));
        return bus.ram[addr];
    }

    pub fn getSlice(self: *anyopaque) []u8 {
        const bus: *NesBus = @ptrCast(@alignCast(self));
        return bus.ram[0..];
    }

    pub fn interface(self: *NesBus) BusInterface {
        return .{
            .ctx = self,
            .readFn = memRead,
            .writeFn = memWrite,
            .peekFn = peek,
            .getSliceFn = getSlice,
            .pollNmiFn = pollNmiStatus,
        };
    }
};

pub const Bus6502 = struct {

    mem: [0x20000]u8 = undefined,

    pub fn read(self: *anyopaque, addr: u16) u8 {
        const bus: *Bus6502 = @ptrCast(@alignCast(self));
        return bus.mem[addr];
    }

    pub fn peek(self: *anyopaque, addr: u16) u8 {
        const bus: *Bus6502 = @ptrCast(@alignCast(self));
        return bus.mem[addr];
    }

    pub fn write(self: *anyopaque, addr: u16, data: u8) void {
        const bus: *Bus6502 = @ptrCast(@alignCast(self));
        bus.mem[addr] = data;
    }

    pub fn getSlice(self: *anyopaque) []u8 {
        const bus: *Bus6502 = @ptrCast(@alignCast(self));
        return bus.mem[0..];
    }

    pub fn pollNmi(_: *anyopaque) void {}

    pub fn interface(self: *Bus6502) BusInterface {
        return .{
            .ctx = self,
            .readFn = read,
            .writeFn = write,
            .peekFn = peek,
            .getSliceFn = getSlice,
            .pollNmiFn = pollNmi,
        };
    }
};