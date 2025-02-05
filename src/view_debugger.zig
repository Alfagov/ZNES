const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const rl = @import("raylib");

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
        const text = rl.textFormat("0x%02x: 0x%02x", .{ addr - 0x0100, cpu.bus.mem[addr] });

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

    const page = getPage(cpu.bus.mem[0..], cpu.pc);
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