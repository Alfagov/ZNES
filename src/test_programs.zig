const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const view_debugger = @import("view_debugger.zig");
const rl = @import("raylib");


pub const snake_program = [_]u8{0x20, 0x06, 0x06, 0x20, 0x38, 0x06, 0x20, 0x0d, 0x06, 0x20, 0x2a, 0x06, 0x60, 0xa9, 0x02, 0x85,
    0x02, 0xa9, 0x04, 0x85, 0x03, 0xa9, 0x11, 0x85, 0x10, 0xa9, 0x10, 0x85, 0x12, 0xa9, 0x0f, 0x85,
    0x14, 0xa9, 0x04, 0x85, 0x11, 0x85, 0x13, 0x85, 0x15, 0x60, 0xa5, 0xfe, 0x85, 0x00, 0xa5, 0xfe,
    0x29, 0x03, 0x18, 0x69, 0x02, 0x85, 0x01, 0x60, 0x20, 0x4d, 0x06, 0x20, 0x8d, 0x06, 0x20, 0xc3,
    0x06, 0x20, 0x19, 0x07, 0x20, 0x20, 0x07, 0x20, 0x2d, 0x07, 0x4c, 0x38, 0x06, 0xa5, 0xff, 0xc9,
    0x77, 0xf0, 0x0d, 0xc9, 0x64, 0xf0, 0x14, 0xc9, 0x73, 0xf0, 0x1b, 0xc9, 0x61, 0xf0, 0x22, 0x60,
    0xa9, 0x04, 0x24, 0x02, 0xd0, 0x26, 0xa9, 0x01, 0x85, 0x02, 0x60, 0xa9, 0x08, 0x24, 0x02, 0xd0,
    0x1b, 0xa9, 0x02, 0x85, 0x02, 0x60, 0xa9, 0x01, 0x24, 0x02, 0xd0, 0x10, 0xa9, 0x04, 0x85, 0x02,
    0x60, 0xa9, 0x02, 0x24, 0x02, 0xd0, 0x05, 0xa9, 0x08, 0x85, 0x02, 0x60, 0x60, 0x20, 0x94, 0x06,
    0x20, 0xa8, 0x06, 0x60, 0xa5, 0x00, 0xc5, 0x10, 0xd0, 0x0d, 0xa5, 0x01, 0xc5, 0x11, 0xd0, 0x07,
    0xe6, 0x03, 0xe6, 0x03, 0x20, 0x2a, 0x06, 0x60, 0xa2, 0x02, 0xb5, 0x10, 0xc5, 0x10, 0xd0, 0x06,
    0xb5, 0x11, 0xc5, 0x11, 0xf0, 0x09, 0xe8, 0xe8, 0xe4, 0x03, 0xf0, 0x06, 0x4c, 0xaa, 0x06, 0x4c,
    0x35, 0x07, 0x60, 0xa6, 0x03, 0xca, 0x8a, 0xb5, 0x10, 0x95, 0x12, 0xca, 0x10, 0xf9, 0xa5, 0x02,
    0x4a, 0xb0, 0x09, 0x4a, 0xb0, 0x19, 0x4a, 0xb0, 0x1f, 0x4a, 0xb0, 0x2f, 0xa5, 0x10, 0x38, 0xe9,
    0x20, 0x85, 0x10, 0x90, 0x01, 0x60, 0xc6, 0x11, 0xa9, 0x01, 0xc5, 0x11, 0xf0, 0x28, 0x60, 0xe6,
    0x10, 0xa9, 0x1f, 0x24, 0x10, 0xf0, 0x1f, 0x60, 0xa5, 0x10, 0x18, 0x69, 0x20, 0x85, 0x10, 0xb0,
    0x01, 0x60, 0xe6, 0x11, 0xa9, 0x06, 0xc5, 0x11, 0xf0, 0x0c, 0x60, 0xc6, 0x10, 0xa5, 0x10, 0x29,
    0x1f, 0xc9, 0x1f, 0xf0, 0x01, 0x60, 0x4c, 0x35, 0x07, 0xa0, 0x00, 0xa5, 0xfe, 0x91, 0x00, 0x60,
    0xa6, 0x03, 0xa9, 0x00, 0x81, 0x10, 0xa2, 0x00, 0xa9, 0x01, 0x81, 0x10, 0x60, 0xa2, 0x00, 0xea,
    0xea, 0xca, 0xd0, 0xfb, 0x60};

pub fn loadSnakeProgram(cpu: *Cpu) void {
    @memcpy(cpu.bus.getSlice()[0x0600..0x0600+snake_program.len], snake_program[0..]);
    cpu.pc = 0x0600;

    cpu.bus.write(0xFFFC, 0x00);
    cpu.bus.write(0xFFFD, 0x06);
}

fn loadTestFunctionalProgram(cpu: *Cpu) void {
    const PROGRAM_START: u16 = 0x0400;
    const BIN_START_ADDR: u16 = 0x000A;
    //const SUCCESS_TRAP: u16 = 0x3469;

    try cpu.loadFromFile("tests/6502_functional_test.bin", BIN_START_ADDR);
    cpu.pc = PROGRAM_START;

    cpu.bus.mem[0xFFFC] = 0x00;
    cpu.bus.mem[0xFFFD] = 0x04;
}

pub fn snakeProgram() void {
    var cpu = Cpu.init();

    loadSnakeProgram(&cpu);

    const screenWidth = 1024;
    const screenHeight = 768;

    rl.initWindow(screenWidth, screenHeight, "raylib [text] example - text formatting");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60);

    var pause = true;

    const text_image = rl.Image.genColor(32, 32, rl.Color.white);
    const texture = try rl.loadTextureFromImage(text_image);

    var frame: [32*32]rl.Color = undefined;

    while (!rl.windowShouldClose()) {

        cpu.bus.mem[0xFE] = std.crypto.random.int(u8);

        if (rl.isKeyDown(rl.KeyboardKey.p)) {
            pause = true;
        }

        if (rl.isKeyDown(rl.KeyboardKey.left_shift) and rl.isKeyDown(rl.KeyboardKey.r)) {
            cpu.reset();
            for (0..frame.len) |fidx| {
                frame[fidx] = rl.Color.black;
            }

            @memset(cpu.bus.mem[0x0200..0x600], 0);

            rl.updateTexture(texture, &frame);
        } else if (rl.isKeyDown(rl.KeyboardKey.r)) {
            pause = false;
        }

        if (rl.isKeyReleased(rl.KeyboardKey.w)) {
            cpu.bus.mem[0xFF] = 0x77;
        }

        if (rl.isKeyReleased(rl.KeyboardKey.s)) {
            cpu.bus.mem[0xFF] = 0x73;
        }

        if (rl.isKeyReleased(rl.KeyboardKey.a)) {
            cpu.bus.mem[0xFF] = 0x61;
        }

        if (rl.isKeyReleased(rl.KeyboardKey.d)) {
            cpu.bus.mem[0xFF] = 0x64;
        }

        if (rl.isKeyReleased(rl.KeyboardKey.n)) {
            if (pause) {
                cpu.step();
                cpu.remaining_clocks = 0;

                var frame_idx: usize = 0;

                for (0x0200..0x600) |i| {
                    const ci = cpu.bus.mem[i];
                    const color = view_debugger.getColor(ci);
                    frame[frame_idx] = color;

                    frame_idx += 1;
                }

                rl.updateTexture(texture, &frame);
            }
        }

        if (!pause) {
            for (0..cpu.clocks_per_s/60) |_| {
                cpu.clock();
            }

            var frame_idx: usize = 0;

            for (0x0200..0x600) |i| {
                const ci = cpu.bus.mem[i];
                const color = view_debugger.getColor(ci);
                frame[frame_idx] = color;

                frame_idx += 1;
            }

            rl.updateTexture(texture, &frame);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);

        view_debugger.cpuLeftPanel(&cpu, screenHeight, 300);

        view_debugger.cpuMemoryView(&cpu, 300, screenWidth, 300, 10);

        rl.drawTexturePro(texture, .{ .x = 0, .y = 0, .width = @floatFromInt(texture.width), .height =  @floatFromInt(texture.height)}, .{.x = 320, .y = 320, .height = 420, .width = 512}, rl.Vector2{.x = 0, .y = 0}, 0, rl.Color.white);

        rl.drawFPS(700, 600);
    }
}

pub fn functionalTestProgram() void {
    var cpu = Cpu.init();

    const SUCCESS_TRAP: u16 = 0x3469;

    loadTestFunctionalProgram(&cpu);

    const screenWidth = 1024;
    const screenHeight = 768;

    rl.initWindow(screenWidth, screenHeight, "raylib [text] example - text formatting");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60);

    var pause = true;

    while (!rl.windowShouldClose()) {

        cpu.bus.mem[0xFE] = std.crypto.random.int(u8);

        if (rl.isKeyDown(rl.KeyboardKey.p)) {
            pause = true;
        }

        if (rl.isKeyDown(rl.KeyboardKey.left_shift) and rl.isKeyDown(rl.KeyboardKey.r)) {
            cpu.reset();
        } else if (rl.isKeyDown(rl.KeyboardKey.r)) {
            pause = false;
        }

        if (rl.isKeyReleased(rl.KeyboardKey.n)) {
            if (pause) {
                cpu.step();
                cpu.remaining_clocks = 0;

                if (cpu.pc == SUCCESS_TRAP) {
                    std.debug.print("SUCCESS\n", .{});
                    pause = true;
                }
            }
        }

        if (!pause) {
            for (0..cpu.clocks_per_s/60) |_| {
                cpu.clock();
                if (cpu.pc == SUCCESS_TRAP) {
                    std.debug.print("SUCCESS\n", .{});
                    pause = true;
                    break;
                }
            }
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);

        view_debugger.cpuLeftPanel(&cpu, screenHeight, 300);

        view_debugger.cpuMemoryView(&cpu, 300, screenWidth, 300, 10);

        rl.drawFPS(700, 600);
    }
}