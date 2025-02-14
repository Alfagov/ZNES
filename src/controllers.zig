const std = @import("std");

pub const ButtonsStatus = packed struct(u8) {
    B: u1 = 0,
    A: u1 = 0,
    Select: u1 = 0,
    Start: u1 = 0,
    Up: u1 = 0,
    Down: u1 = 0,
    Left: u1 = 0,
    Right: u1 = 0,
};

const Self = @This();

status_one: ButtonsStatus = .{},
status_two: ButtonsStatus = .{},
current_input_one: u16 = 1,
current_input_two: u16 = 1,
strobe: bool = false,

pub fn readControllerOne(self: *Self) u8 {
    return self.readController(self.status_one, &self.current_input_one);
}

pub fn readControllerTwo(self: *Self) u8 {
    return self.readController(self.status_two, &self.current_input_two);
}

fn readController(self: *Self, status: ButtonsStatus, current_input: *u16) u8 {
    if (current_input.* > (1 << 7)) {
        return 1;
    }

    const is_pressed = @intFromBool((@as(u8, @bitCast(status)) & current_input.*) > 0);
    if (!self.strobe) {
        current_input.* <<= 1;
    }
    return is_pressed;
}

pub fn strobeSet(self: *Self, value: u8) void {
    self.strobe = @bitCast(@as(u1, @truncate(value & 1)));
    if (self.strobe) {
        self.current_input_one = 1;
        self.current_input_two = 1;
    }
}