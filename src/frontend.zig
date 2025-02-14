const std = @import("std");
const rl = @import("raylib");

const NesBus = @import("bus.zig").NesBus;
const view_debugger = @import("view_debugger.zig");

const Self = @This();

bus: *NesBus,
paused: bool = true,
debug: bool = false,

screen_height: i32,
screen_width: i32,

palette_texture: rl.Texture,
sprite_texture: rl.Texture,
sprite_frame: [64*64]rl.Color = undefined,
nametable_texture: rl.Texture,
nametable_frame: [32*8*4*30*8]rl.Color = undefined,
screen_texture: rl.Texture = undefined,

chr_textutes: [2][256]rl.Texture = undefined,
chr_frames: [2][256][8*8]rl.Color = undefined,

pub fn init(bus: *NesBus, screen_width: i32, screen_height: i32) !Self {

    rl.initWindow(screen_width, screen_height, "ZNES");
    rl.setTargetFPS(60);

    const palette_image = rl.Image.genColor(4, 8, rl.Color.black);
    const sprite_image = rl.Image.genColor(64, 64, rl.Color.black);
    const nametable_image = rl.Image.genColor(32*8, 4*30*8, rl.Color.black);
    const render_image = rl.Image.genColor(256, 240, rl.Color.black);

    var fe: Self = .{
        .screen_height = screen_height,
        .screen_width = screen_width,
        .bus = bus,

        .palette_texture = try rl.loadTextureFromImage(palette_image),
        .sprite_texture = try rl.loadTextureFromImage(sprite_image),
        .nametable_texture = try rl.loadTextureFromImage(nametable_image),
        .screen_texture = try rl.loadTextureFromImage(render_image),
    };

    for (0..2) |bank| {
        for (0..256) |idx| {
            const text_image = rl.Image.genColor(8, 8, rl.Color.white);
            const texture = try rl.loadTextureFromImage(text_image);
            fe.chr_textutes[bank][idx] = texture;
        }
    }

    return fe;
}


pub fn run(self: *Self) !void {

    defer rl.closeWindow();

    while (!rl.windowShouldClose()) {
        // Load ROM by dropping it into the window
        if (rl.isFileDropped()) {
            const path_list = rl.loadDroppedFiles();
            for (0..path_list.count) |idx| {
                const path = path_list.paths[idx];
                std.debug.print("Loading rom from: {s}\n", .{std.mem.span(path)});
                try self.bus.loadRomAbs(std.mem.span(path));
                self.bus.reset();
            }

            rl.unloadDroppedFiles(path_list);
        }

        self.controls();

        if (!self.paused) {
            for (0..self.bus.cpu.?.clocks_per_s/60) |_| {
                self.bus.clock();
            }
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);

        if (self.debug) {
            if (self.bus.ppu != null) {
                view_debugger.cpuLeftPanel(self.bus.cpu.?, self.screen_height, 300);

                view_debugger.chrRomView(&self.bus.ppu.?, self.screen_height, self.chr_textutes[0], self.chr_textutes[1], &self.chr_frames[0], &self.chr_frames[1]);

                var fr = view_debugger.paletteViewer(&self.bus.ppu.?);
                rl.updateTexture(self.palette_texture, &fr);

                // Sprite
                view_debugger.spriteViewer(&self.bus.ppu.?, &self.sprite_frame);
                rl.updateTexture(self.sprite_texture, &self.sprite_frame);

                // Nametable
                view_debugger.nametableViewer(&self.bus.ppu.?, &self.nametable_frame);
                rl.updateTexture(self.nametable_texture, &self.nametable_frame);

                rl.drawTexturePro(self.palette_texture, .{ .x = 0, .y = 0, .width = @floatFromInt(self.palette_texture.width), .height =  @floatFromInt(self.palette_texture.height)}, .{.x = 750, .y = 350, .height = 100, .width = 100}, rl.Vector2{.x = 0, .y = 0}, 0, rl.Color.white);
                rl.drawTexturePro(self.sprite_texture, .{ .x = 0, .y = 0, .width = @floatFromInt(self.sprite_texture.width), .height =  @floatFromInt(self.sprite_texture.height)}, .{.x = 750, .y = 210, .height = 128, .width = 128}, rl.Vector2{.x = 0, .y = 0}, 0, rl.Color.white);
                rl.drawTexturePro(self.nametable_texture, .{ .x = 0, .y = 0, .width = @floatFromInt(self.nametable_texture.width), .height =  @floatFromInt(self.nametable_texture.height)}, .{.x = 870, .y = 350, .height = 100, .width = 100}, rl.Vector2{.x = 0, .y = 0}, 0, rl.Color.white);
            }
        }

        // Screen
        if (self.bus.ppu != null) {
            rl.updateTexture(self.screen_texture, &self.bus.ppu.?.screen.data);

            if (self.debug) {
                rl.drawTexturePro(self.screen_texture, .{ .x = 0, .y = 0, .width = @floatFromInt(self.screen_texture.width), .height =  @floatFromInt(self.screen_texture.height)}, .{.x = 330, .y = 10, .height = 375, .width = 400}, rl.Vector2{.x = 0, .y = 0}, 0, rl.Color.white);
            } else {
                rl.drawTexturePro(self.screen_texture, .{ .x = 0, .y = 0, .width = @floatFromInt(self.screen_texture.width), .height =  @floatFromInt(self.screen_texture.height)}, .{.x = 0, .y = 0, .height = 768, .width = 819}, rl.Vector2{.x = 0, .y = 0}, 0, rl.Color.white);
            }
        } else {
            rl.drawText("Drop a ROM file to start", 10, @divFloor(self.screen_height, 2) - 30, 60, rl.Color.black);
        }

        commandPalette(self.debug);
        joypadView(self.bus);

        rl.drawFPS(700, 600);

    }

}

fn controls(self: *Self) void {

    // Reset or start
    if (rl.isKeyDown(rl.KeyboardKey.left_shift) and rl.isKeyDown(rl.KeyboardKey.r)) {
        self.bus.reset();
    } else if (rl.isKeyDown(rl.KeyboardKey.r)) {
        self.paused = false;
    }

    // Debug View
    if (rl.isKeyReleased(rl.KeyboardKey.d)) {
        self.debug = !self.debug;
    }

    pollController(self.bus);
}

fn joypadView(bus: *NesBus) void {
    const base_x: i32 = 940;
    var base_y: i32 = 240;

    rl.drawCircle(base_x, base_y, 10, if (bus.controller.status_one.A == 1) rl.Color.green else rl.Color.gray);
    rl.drawCircle(base_x + 30, base_y, 10, if (bus.controller.status_one.B == 1) rl.Color.green else rl.Color.gray);
    rl.drawText("A", base_x - 3, base_y - 3, 10, rl.Color.black);
    rl.drawText("B", base_x + 30 - 3, base_y - 3, 10, rl.Color.black);

    base_y += 25;
    rl.drawCircle(base_x, base_y, 10, if (bus.controller.status_one.Start == 1) rl.Color.green else rl.Color.gray);
    rl.drawCircle(base_x + 30, base_y, 10, if (bus.controller.status_one.Select == 1) rl.Color.green else rl.Color.gray);
    rl.drawText("S", base_x - 3, base_y - 3, 10, rl.Color.black);
    rl.drawText("SL", base_x + 30 - 3, base_y - 3, 10, rl.Color.black);

    // Draw Directional Pad
    // ------------------------
    const dpad_x: i32 = 945; // starting x position for D-Pad
    const dpad_y: i32 = 275; // starting y position for D-Pad

    // UP button
    rl.drawCircle(dpad_x + 10, dpad_y + 20, 10, if (bus.controller.status_one.Up == 1) rl.Color.green else rl.Color.gray);
    rl.drawText("U", dpad_x + 10 - 3, dpad_y + 20 - 3, 10, rl.Color.black);

    // LEFT button
    rl.drawCircle(dpad_x - 10, dpad_y + 40, 10, if (bus.controller.status_one.Left == 1) rl.Color.green else rl.Color.gray);
    rl.drawText("L", dpad_x - 10 - 3, dpad_y + 40 - 3, 10, rl.Color.black);

    // DOWN button
    rl.drawCircle(dpad_x + 10, dpad_y + 60, 10, if (bus.controller.status_one.Down == 1) rl.Color.green else rl.Color.gray);
    rl.drawText("D", dpad_x + 10 - 3, dpad_y + 60 - 3, 10, rl.Color.black);

    // RIGHT button
    rl.drawCircle(dpad_x + 30, dpad_y + 40, 10, if (bus.controller.status_one.Right == 1) rl.Color.green else rl.Color.gray);
    rl.drawText("R", dpad_x + 30 - 3, dpad_y + 40 - 3, 10, rl.Color.black);
}

fn commandPalette(debug: bool) void {
    const base_x: usize = 820 + 100;
    var base_y: i32 = 10;

    rl.drawText("Commands", base_x, base_y, 15, rl.Color.black);
    base_y += 20;
    rl.drawText("T: Start", base_x, base_y, 15, rl.Color.black);
    base_y += 20;
    rl.drawText("Y: Select", base_x, base_y, 15, rl.Color.black);
    base_y += 40;

    rl.drawText("Emulation", base_x, base_y, 15, rl.Color.black);
    base_y += 20;
    rl.drawText("P: Pause", base_x, base_y, 15, rl.Color.black);
    base_y += 20;
    rl.drawText("R: Run", base_x, base_y, 15, rl.Color.black);
    base_y += 20;
    rl.drawText("N: Step", base_x, base_y, 15, rl.Color.black);
    base_y += 20;
    rl.drawText("Shift+R: Reset", base_x, base_y, 15, rl.Color.black);
    base_y += 40;
    rl.drawText("D: Debug View", base_x, base_y, 15, if (debug) rl.Color.green else rl.Color.black);
}

fn pollController(bus: *NesBus) void {
    if (rl.isKeyPressed(rl.KeyboardKey.down)) {
        bus.controller.status_one.Down = 1;
    }

    if (rl.isKeyReleased(rl.KeyboardKey.down)) {
        bus.controller.status_one.Down = 0;
    }

    if (rl.isKeyPressed(rl.KeyboardKey.up)) {
        bus.controller.status_one.Up = 1;
    }

    if (rl.isKeyReleased(rl.KeyboardKey.up)) {
        bus.controller.status_one.Up = 0;
    }

    if (rl.isKeyPressed(rl.KeyboardKey.left)) {
        bus.controller.status_one.Left = 1;
    }

    if (rl.isKeyReleased(rl.KeyboardKey.left)) {
        bus.controller.status_one.Left = 0;
    }

    if (rl.isKeyPressed(rl.KeyboardKey.right)) {
        bus.controller.status_one.Right = 1;
    }

    if (rl.isKeyReleased(rl.KeyboardKey.right)) {
        bus.controller.status_one.Right = 0;
    }

    if (rl.isKeyPressed(rl.KeyboardKey.a)) {
        bus.controller.status_one.A = 1;
    }

    if (rl.isKeyReleased(rl.KeyboardKey.a)) {
        bus.controller.status_one.A = 0;
    }

    if (rl.isKeyPressed(rl.KeyboardKey.b)) {
        bus.controller.status_one.B = 1;
    }

    if (rl.isKeyReleased(rl.KeyboardKey.b)) {
        bus.controller.status_one.B = 0;
    }

    if (rl.isKeyPressed(rl.KeyboardKey.t)) {
        bus.controller.status_one.Start = 1;
    }

    if (rl.isKeyReleased(rl.KeyboardKey.t)) {
        bus.controller.status_one.Start = 0;
    }

    if (rl.isKeyPressed(rl.KeyboardKey.y)) {
        bus.controller.status_one.Select = 1;
    }

    if (rl.isKeyReleased(rl.KeyboardKey.y)) {
        bus.controller.status_one.Select = 0;
    }
}