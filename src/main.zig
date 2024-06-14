const std = @import("std");

pub fn Reactive(comptime T: type) type {
    return struct {
        const ReactiveT = @This();

        value: T,

        pub fn emitUpdate(self: *ReactiveT, val: usize) void {
            self.value = val;
        }
    };
}

pub extern fn mount(
    mountpointSnippetId: usize,
    subMountpointId: usize,
    templateId: usize,
    numSlots: usize,
    slots: [*]const [*:0]const u8,
) void;

pub export fn init() void {
    const slots1: []const [*:0]const u8 = &.{"hello"};
    const slots2: []const [*:0]const u8 = &.{};
    mount(0, 0, 1, slots1.len, slots1.ptr);
    mount(1, 0, 2, slots2.len, slots2.ptr);
}
