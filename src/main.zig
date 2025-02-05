const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const test_programs = @import("test_programs.zig");
const view_debugger = @import("view_debugger.zig");
const rl = @import("raylib");

pub fn main() !void {

    var cpu = Cpu.init();

    test_programs.loadSnakeProgram(&cpu);

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


