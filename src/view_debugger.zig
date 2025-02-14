const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const rl = @import("raylib");
const PPU = @import("ppu.zig");
const Palette = @import("palette.zig");

const PAGE_SIZE = 0xA0;

pub const PageMapping = struct {
    page: []u8,
    page_start: usize,
    page_end: usize,
    offset: usize,
};

pub fn getPage(memory: []u8, address: usize) PageMapping {
    if (address >= memory.len) {
        unreachable;
    }

    // Calculate the starting index of the page that contains `address`.
    const page_start = @divFloor(address, PAGE_SIZE) * PAGE_SIZE;
    // Make sure that we do not exceed the bounds of `memory`.
    const page_end = @min(page_start + PAGE_SIZE, memory.len);
    return PageMapping{
        .page = memory[page_start .. page_end],
        .page_start = page_start,
        .page_end = page_end,
        .offset = address - page_start,
    };
}

pub fn getColor(byte: u8) rl.Color {
    return switch (byte) {
        0 => rl.Color.black,
        1 => rl.Color.white,
        2, 9 => rl.Color.gray,
        3, 10 => rl.Color.red,
        4, 11 => rl.Color.green,
        5, 12 => rl.Color.blue,
        6, 13 => rl.Color.magenta,
        7, 14 => rl.Color.yellow,
        else => rl.Color.sky_blue,
    };
}

pub fn cpuLeftPanel(cpu: *Cpu, screen_height: i32, panel_width: i32) void {
    // === Left Panel: CPU Info ===
    const panelMargin = 10;
    rl.drawRectangle(
        panelMargin, panelMargin,
        panel_width, screen_height - 2 * panelMargin,
        rl.Color{ .r = 50, .g = 50, .b = 50, .a = 255 }
    );

    // Title text for the CPU panel.
    rl.drawText("CPU Debugger", panelMargin + 20, panelMargin + 20, 20, rl.Color.white);

    var yPos: i32 = panelMargin + 60;
    rl.drawText("Registers:", panelMargin + 20, yPos, 18, rl.Color.light_gray);
    yPos += 30;

    // --- CPU Registers (using rl.textFormat) ---
    rl.drawText(rl.textFormat("A: = 0x%02x", .{cpu.a}), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("X: = 0x%02x", .{cpu.x}), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("Y: = 0x%02x", .{cpu.y}), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("SP: = 0x%02x", .{cpu.sp}), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("PC: = 0x%04x", .{cpu.pc}), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 30;

    rl.drawText("Flags:", panelMargin + 20, yPos, 18, rl.Color.light_gray);
    yPos += 30;
    rl.drawText(rl.textFormat("Carry: = %s", .{ if (cpu.carry) "1" else "0" }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("Zero: = %s", .{ if (cpu.zero) "1" else "0" }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("Interrupt: = %s", .{ if (cpu.interrupt_disable) "1" else "0" }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("Decimal: = %s", .{ if (cpu.decimal) "1" else "0" }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("Break: = %s", .{ if (cpu.break_) "1" else "0" }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("Overflow: = %s", .{ if (cpu.overflow) "1" else "0" }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("Negative: = %s", .{ if (cpu.negative) "1" else "0" }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 30;
    rl.drawText("Vectors:", panelMargin + 20, yPos, 18, rl.Color.light_gray);
    yPos += 20;
    rl.drawText(rl.textFormat("Stack: 0x%04X", .{ cpu.stack_base + 0xFD }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("Base:  0x%02X", .{ cpu.vector_base }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("NMI:    0x%02X", .{ @as(u8, 0xFA) }), panelMargin + 20, yPos, 16, rl.Color.white);
    yPos += 20;
    rl.drawText(rl.textFormat("IRQ:    0x%02X", .{ @as(u8, 0xFE) }), panelMargin + 20, yPos, 16, rl.Color.white);

    cpuStackView(cpu, screen_height, panel_width);
}

pub fn cpuStackView(cpu: *Cpu, screen_height: i32, panel_width: i32) void {
    const stackPanelHeight: i32 = 255;
    const panelMargin = 10;
    const stackPanelY: i32 = screen_height - stackPanelHeight - panelMargin;
    rl.drawRectangle(
        panelMargin, stackPanelY,
        panel_width, stackPanelHeight,
        rl.Color{ .r = 60, .g = 60, .b = 60, .a = 255 }
    );
    rl.drawText("Stack Visualisation", panelMargin + 20, stackPanelY + 20, 20, rl.Color.white);

    const viewCount: u8 = 10;
    const half: u8 = viewCount / 2;
    var viewStart: u16 = 0;
    if (0xFF - cpu.sp > half) {
        viewStart = cpu.sp + half;
    } else {
        viewStart = 0xFF;
    }

    const lineHeight: i32 = 20;
    var stackTextY: i32 = stackPanelY + 50;

    for (0..viewCount) |idx| {
        const addr: u16 = @intCast(0x0100 + viewStart - idx);
        const text = rl.textFormat("0x%02x: 0x%02x", .{ addr - 0x0100, cpu.bus.peek(addr) });

        if ((addr - 0x0100) == cpu.sp) {
            rl.drawRectangle(
                panelMargin + 10,
                stackTextY,
                panel_width - 20,
                lineHeight,
                rl.Color{ .r = 80, .g = 120, .b = 80, .a = 255 }
            );
        }
        rl.drawText(text, panelMargin + 25, stackTextY, 16, rl.Color.white);
        stackTextY += lineHeight;
    }
}

pub fn cpuMemoryView(cpu: *Cpu, left_panel_width: i32, screen_width: i32, height: i32, margin: i32) void {
    const memPanelX = left_panel_width + 2 * margin;
    const memPanelWidth = screen_width - memPanelX - margin;
    rl.drawRectangle(
        memPanelX, margin,
        memPanelWidth, height,
        rl.Color{ .r = 40, .g = 40, .b = 40, .a = 255 }
    );

    var posY: i32 = margin + 20;
    rl.drawText("Memory Dump", memPanelX + 20, posY, 20, rl.Color.white);
    posY += 30;

    var memX: i32 = memPanelX + 20;
    rl.drawText(rl.textFormat("Clocks per frame: %d", .{ cpu.clocks_per_s/60 }), memPanelX + 20, posY, 16, rl.Color.white);
    posY += 20;

    const page = getPage(cpu.bus.getSlice()[0..], cpu.pc);
    rl.drawText(rl.textFormat("Page: %02X - %02X", .{ page.page_start, page.page_end }), memPanelX + 300, posY - 20, 16, rl.Color.white);

    rl.drawText(rl.textFormat("CI: %02X - %s", .{ cpu.current_instruction.opcode, cpu.current_instruction.name.ptr }), memPanelX + 500, posY - 20, 16, rl.Color.white);

    var idx: u8 = 0;
    for (page.page, 0..) |elem, el_idx| {
        if (el_idx == page.offset) {
            rl.drawText(rl.textFormat("0x%02x", .{ elem }), memX + 20, posY, 16, rl.Color.green);
        } else {
            rl.drawText(rl.textFormat("0x%02x", .{ elem }), memX + 20, posY, 16, rl.Color.white);
        }
        memX += 40;
        if (idx == 15) {
            idx = 0;
            posY += 20;
            memX = memPanelX + 20;
            continue;
        }
        idx += 1;
    }
}

pub fn chrRomView(ppu: *PPU, screen_height: i32, textures_bank_0: [256]rl.Texture2D, textures_bank_1: [256]rl.Texture2D, frames_bank_0: [][8*8]rl.Color, frames_bank_1: [][8*8]rl.Color) void {

    const size = 15;
    const stackPanelHeight: i32 = 300;
    const panelMargin = 320;
    const stackPanelY: i32 = screen_height - stackPanelHeight - 10;
    rl.drawRectangle(
        panelMargin, stackPanelY,
        650, stackPanelHeight,
        rl.Color{ .r = 60, .g = 60, .b = 60, .a = 255 }
    );
    rl.drawText("CHR Rom", panelMargin + 10, stackPanelY + 20, 20, rl.Color.white);


    tileBankToFrames(ppu, 0, frames_bank_0);
    tileBankToFrames(ppu, 1, frames_bank_1);
    const start_x: usize = panelMargin + 10;
    var start_y: usize = @intCast(stackPanelY + 40);

    for (frames_bank_0, frames_bank_1, 0..) |*frame0, *frame1, idx| {
        if (idx % 20 == 0) {
            start_y += size+2;
        }
        rl.updateTexture(textures_bank_0[idx], frame0);
        rl.drawTexturePro(textures_bank_0[idx], .{ .x = 0, .y = 0, .width = @floatFromInt(textures_bank_0[idx].width), .height =  @floatFromInt(textures_bank_0[idx].height)}, .{.x = @floatFromInt(start_x + ((idx % 20)*size) + 330), .y = @floatFromInt(start_y), .height = size, .width = size}, rl.Vector2{.x = 0, .y = 0}, 0, rl.Color.white);

        rl.updateTexture(textures_bank_1[idx], frame1);
        rl.drawTexturePro(textures_bank_1[idx], .{ .x = 0, .y = 0, .width = @floatFromInt(textures_bank_1[idx].width), .height =  @floatFromInt(textures_bank_1[idx].height)}, .{.x = @floatFromInt(start_x + ((idx % 20)*size)), .y = @floatFromInt(start_y), .height = size, .width = size}, rl.Vector2{.x = 0, .y = 0}, 0, rl.Color.white);
    }
}

pub fn tileBankToFrames(ppu: *PPU, bank: usize, frame: [][8*8]rl.Color) void {
    var tile_y: usize = 0;
    var tile_x: usize = 0;
    const bank_n = (bank * 0x1000);

    for (0..255) |tile_idx| {
        if (tile_idx != 0 and tile_idx % 20 == 0) {
            tile_y += 10;
            tile_x = 0;
        }

        const tile = ppu.rom.chr_rom[(bank_n + tile_idx * 16)..(bank_n + tile_idx * 16 + 15)+1];
        for (0..8) |y| {
            var upper = tile[y];
            var lower = tile[y + 8];

            for (0..8) |x_r| {
                const x: usize = 7 - x_r;
                const value = (1 & upper) << 1 | (1 & lower);
                upper = upper >> 1;
                lower = lower >> 1;
                const rgb = switch (value) {
                    0 => ppu.palette.getColor(0x01),
                    1 => ppu.palette.getColor(0x23),
                    2 => ppu.palette.getColor(0x27),
                    3 => ppu.palette.getColor(0x30),
                    else => unreachable,
                };
                frame[tile_idx][(y * 8) + x] = rgb;
            }
        }

        tile_x += 10;
    }
}

pub fn paletteViewer(ppu: *PPU) [4*8]rl.Color {
    var frame: [4*8]rl.Color = undefined;
    @memset(&frame, rl.Color.white);
    for (0..8) |palette_idx| {
        for (0..4) |palette_color_idx| {
            const color_index = ppu.read(
                0x3F00 + @as(u16, @truncate(palette_idx)) * 4 + @as(u16, @truncate(palette_color_idx))
            );

            const pixel = ppu.palette.getColor(color_index % 64);
            const offset = (palette_idx * 4 + palette_color_idx);
            frame[offset] = pixel;
        }
    }

    return frame;
}

pub fn spriteViewer(ppu: *PPU, frame: []rl.Color) void {
    std.debug.assert(frame.len == 64*64);

    const sprite_bank: u16 = ppu.control_register.flags.S;

    for (0..ppu.oam.len/4) |i| {
        const sprite_idx = i * 4;

        const tile: u16 = ppu.oam[sprite_idx + 1];
        const palette_id: u2 = @truncate(ppu.oam[sprite_idx + 2]);
        const flip_h = ppu.oam[sprite_idx + 2] >> 6 & 1 == 1;
        const flip_v = ppu.oam[sprite_idx + 2] >> 7 & 1 == 1;

        const base_offset = (sprite_bank * 0x1000) + (tile * 16);

        for (0..8) |y| {
            var lower = ppu.read(base_offset + @as(u16, @truncate(y)));
            var upper = ppu.read(base_offset + @as(u16, @truncate(y + 8)));

            for (0..8) |x| {
                const palette_color: u2 = @truncate((upper & 1) << 1 | (lower & 1));
                upper = upper >> 1;
                lower = lower >> 1;
                var color: u8 = undefined;
                if (palette_color == 0) {
                    color = ppu.read(0x3F00);
                } else {
                    color = ppu.read(0x3F10 + @as(u16, palette_id) * 4 + palette_color);
                }

                const pixel = ppu.palette.getColor(color);
                const x_offset = if (flip_h) x else 7 - x;
                const y_offset = if (!flip_v) y else 7 - y;
                const offset = (((i / 8) * 8 + y_offset) * 64 + ((i % 8) * 8 + x_offset));
                frame[offset] = pixel;
            }
        }
    }
}

fn getBgPalette(ppu: *PPU, tile_column: usize, tile_row: usize) [4]u8 {

    const attribute_table_idx = (tile_row / 4) * 8 + (tile_column / 4);
    const attribute_byte = ppu.read(
        @truncate(0x23C0 + 0x400 * @as(u16, ppu.control_register.flags.N) + attribute_table_idx)
    );

    const palette_idx = switch (@as(u2, @truncate((((tile_row % 4) & 2) + ((tile_column % 4) / 2))))) {
        0 => attribute_byte & 0b11,
        1 => (attribute_byte >> 2) & 0b11,
        2 => (attribute_byte >> 4) & 0b11,
        3 => (attribute_byte >> 6) & 0b11,
    };

    const palette_offset: u16 = 0x3F01;
    const palette_start: u16 = palette_offset + palette_idx * 4;
    return .{
        ppu.read(palette_start - 1),
        ppu.read(palette_start),
        ppu.read(palette_start + 1),
        ppu.read(palette_start + 2),
    };
}

pub fn nametableViewer(ppu: *PPU, frame: []rl.Color) void {
    std.debug.assert(frame.len == 32*8*4*30*8);
    const tile_bank: u16 = ppu.control_register.flags.B;

    for (0..4) |nametable| {
        for (0..32) |tile_x| {
            for (0..30) |tile_y| {
                const tile: u16 = ppu.read(@truncate(0x2000 + (0x400 * nametable) + tile_y * 32 * tile_x));
                const base_offset = (tile_bank * 0x1000) + (tile * 16);

                const bg_palette = getBgPalette(ppu, tile_x, tile_y);

                for (0..8) |y| {
                    var lower = ppu.read(base_offset + @as(u16, @truncate(y)));
                    var upper = ppu.read(base_offset + @as(u16, @truncate(y + 8)));

                    for (0..8) |x| {
                        const palette_color: u2 = @truncate((upper & 1) << 1 | (lower & 1));
                        upper = upper >> 1;
                        lower = lower >> 1;
                        const color = bg_palette[palette_color];
                        const pixel = ppu.palette.getColor(color);
                        const x_offset = 7 - x;
                        const y_offset = y;
                        const texture_tile_y = tile_y + 30 * nametable;
                        const offset = ((texture_tile_y * 8 + y_offset) * 32 * 8) + (tile_x * 8 + x_offset);
                        frame[offset] = pixel;
                    }
                }
            }
        }
    }
}