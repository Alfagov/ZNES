const std = @import("std");
const rl = @import("raylib");

const Self = @This();

palette: [64]rl.Color = undefined,

const fallback_palette_path = "fallback_palette.pal";
const fallback_palette: *[64][4]u8 = @constCast(@ptrCast(@embedFile(fallback_palette_path)));

pub fn init() Self {
    var palette: [64]rl.Color = undefined;
    for (fallback_palette, 0..) |color, i| {
        palette[i] = rl.Color{ .r = color[0], .g = color[1], .b = color[2], .a = color[3] };
    }

    return .{
        .palette = palette,
    };
}

pub fn loadPalette(self: *Self, path: []const u8) void {
    const palette_file = try std.fs.cwd().openFile(path, .{});
    defer palette_file.close();

    var buffer: [64*4]u8 = undefined;
    _ = try palette_file.read(&buffer);

    for (&self.palette, 0..) |*color, i| {
        color.r = buffer[i*4];
        color.g = buffer[i*4+1];
        color.b = buffer[i*4+2];
        color.a = buffer[i*4+3];
    }
}

pub fn getColor(self: *Self, index: usize) rl.Color {
    return self.palette[index];
}