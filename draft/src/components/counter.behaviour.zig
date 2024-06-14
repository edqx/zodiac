const Reactive = @import("../src/main.zig").Reactive;

const Counter = @This();

count: Reactive(usize) = .{ .value = 0 },

pub fn increment(self: *Counter) void {
    self.count.emitUpdate(self.count.value + 1);
}
