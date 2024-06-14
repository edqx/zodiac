const std = @import("std");

pub fn PeekableReader(comptime Reader: type) type {
    return struct {
        const PeekableReaderT = @This();
        const ReaderErrors = @typeInfo(@typeInfo(@TypeOf(@field(Reader, "readByte"))).Fn.return_type.?).ErrorUnion.error_set;
        const Error = ReaderErrors || error{ CannotMoveBack, BufferOverflow };

        childReader: Reader,
        offset: usize = 0,
        buffer: [4096]u8 = undefined,

        bufferFirst: usize = 0,
        bufferLast: usize = 0,

        pub fn reader(self: *PeekableReaderT) std.io.Reader(*PeekableReaderT, Error, read) {
            return std.io.Reader(*PeekableReaderT, Error, read){ .context = self };
        }

        pub fn read(self: *PeekableReaderT, dest: []u8) Error!usize {
            if (self.bufferFirst + dest.len <= self.bufferLast) {
                @memcpy(dest, self.buffer[self.bufferFirst .. self.bufferFirst + dest.len]);
                self.bufferFirst += dest.len;
                self.offset += dest.len;
                return dest.len;
            }
            self.bufferLast = self.bufferFirst;

            const num = try self.childReader.read(dest);
            @memcpy(self.buffer[self.bufferLast .. self.bufferLast + num], dest[0..num]);
            self.offset += num;

            self.bufferFirst += num;
            self.bufferLast += num;
            if (self.bufferLast >= self.buffer.len) {
                if (self.bufferLast - self.bufferFirst >= self.buffer.len) return Error.BufferOverflow;
                std.mem.copyForwards(u8, self.buffer[0..], self.buffer[self.bufferFirst..]);
                self.bufferLast -= self.bufferFirst;
                self.bufferFirst = 0;
            }
            return num;
        }

        pub fn peekByte(self: *PeekableReaderT) Error!u8 {
            const byte = try self.reader().readByte();
            try self.moveBackByte();
            return byte;
        }

        pub fn moveBackByte(self: *PeekableReaderT) Error!void {
            if (self.bufferFirst <= 0) return Error.CannotMoveBack;
            self.bufferFirst -= 1;
            self.offset -= 1;
        }
    };
}

pub fn peekableReader(childReader: anytype) PeekableReader(@TypeOf(childReader)) {
    return PeekableReader(@TypeOf(childReader)){ .childReader = childReader };
}

fn isWhitespace(char: u8) bool {
    return switch (char) {
        '\n', '\t', '\r', ' ' => true,
        else => false,
    };
}

pub const Lexer = struct {
    pub const Token = struct {
        pub const Kind = enum(u8) {
            // xml-specific
            open_tag,
            close_tag,
            end_children,
            ident,
            string,
            equals,
            text,
            instruction,
            exclamation,
            // zodiac-specific
            action,
        };

        pub const Src = struct {
            start: usize,
            end: usize,
        };

        kind: Kind,
        src: Src,
        contents: []const u8,
    };

    pub const State = enum(u1) {
        tag,
        out_of_tag,
    };

    pub fn Iter(comptime Reader: type) type {
        return struct {
            const LexerT = @This();

            pub const tagTokens = .{};

            allocator: std.mem.Allocator,
            peekableReader: PeekableReader(Reader),

            stringBuilder: std.ArrayList(u8),
            arenaAllocator: std.heap.ArenaAllocator,

            pub fn init(allocator: std.mem.Allocator, reader: Reader) !LexerT {
                return LexerT{
                    .allocator = allocator,
                    .peekableReader = peekableReader(reader),
                    .stringBuilder = try std.ArrayList(u8).initCapacity(allocator, 4096),
                    .arenaAllocator = std.heap.ArenaAllocator.init(allocator),
                };
            }

            pub fn deinit(self: LexerT) void {
                self.stringBuilder.deinit();
                self.arenaAllocator.deinit();
            }

            pub fn next(self: *LexerT, state: State) !?Token {
                const offset = self.peekableReader.offset;
                var nextChar = try self.peekableReader.reader().readByte();
                return switch (state) {
                    .tag => blk: {
                        while (isWhitespace(nextChar)) {
                            nextChar = try self.peekableReader.reader().readByte();
                        }
                        break :blk switch (nextChar) {
                            '>' => Token{
                                .kind = .close_tag,
                                .src = .{ .start = offset, .end = self.peekableReader.offset },
                                .contents = &.{},
                            },
                            '=' => Token{
                                .kind = .equals,
                                .src = .{ .start = offset, .end = self.peekableReader.offset },
                                .contents = &.{},
                            },
                            '"' => self.readString(),
                            '/' => Token{
                                .kind = .end_children,
                                .src = .{ .start = offset, .end = self.peekableReader.offset },
                                .contents = &.{},
                            },
                            '@' => Token{
                                .kind = .action,
                                .src = .{ .start = offset, .end = self.peekableReader.offset },
                                .contents = &.{},
                            },
                            else => self.readIdent(),
                        };
                    },
                    .out_of_tag => switch (nextChar) {
                        '<' => Token{
                            .kind = .open_tag,
                            .src = .{ .start = offset, .end = self.peekableReader.offset },
                            .contents = &.{},
                        },
                        else => self.readText(),
                    },
                };
            }

            pub fn copiedString(self: *LexerT) ![]const u8 {
                const newMemory = try self.arenaAllocator.allocator().alloc(u8, self.stringBuilder.items.len);
                @memcpy(newMemory, self.stringBuilder.items);
                return newMemory;
            }

            pub fn readString(self: *LexerT) !?Token {
                const start = self.peekableReader.offset;
                self.stringBuilder.clearRetainingCapacity();
                var nextByte = try self.peekableReader.reader().readByte();
                while (nextByte != '\"') {
                    try self.stringBuilder.append(nextByte);
                    nextByte = try self.peekableReader.reader().readByte();
                }
                return Token{
                    .kind = .string,
                    .src = .{ .start = start, .end = self.peekableReader.offset },
                    .contents = try self.copiedString(),
                };
            }

            pub fn readIdent(self: *LexerT) !?Token {
                const start = self.peekableReader.offset;
                self.stringBuilder.clearRetainingCapacity();
                var nextByte = try self.peekableReader.reader().readByte();
                while (true) {
                    if (isWhitespace(nextByte)) break;
                    switch (nextByte) {
                        '=', '"', '<', '>', '@' => {
                            try self.peekableReader.moveBackByte();
                            break;
                        },
                        else => {
                            try self.stringBuilder.append(nextByte);
                        },
                    }
                    nextByte = try self.peekableReader.reader().readByte();
                }
                return Token{
                    .kind = .ident,
                    .src = .{ .start = start, .end = self.peekableReader.offset },
                    .contents = try self.copiedString(),
                };
            }

            pub fn readText(self: *LexerT) !?Token {
                const start = self.peekableReader.offset;
                self.stringBuilder.clearRetainingCapacity();
                var nextByte = try self.peekableReader.reader().readByte();
                while (true) {
                    switch (nextByte) {
                        '<' => {
                            try self.peekableReader.moveBackByte();
                            break;
                        },
                        else => {
                            try self.stringBuilder.append(nextByte);
                        },
                    }
                    nextByte = try self.peekableReader.reader().readByte();
                }
                return Token{
                    .kind = .text,
                    .src = .{ .start = start, .end = self.peekableReader.offset },
                    .contents = try self.copiedString(),
                };
            }
        };
    }

    pub fn iter(allocator: std.mem.Allocator, reader: anytype) !Iter(@TypeOf(reader)) {
        return try Iter(@TypeOf(reader)).init(allocator, reader);
    }
};

test Lexer {
    const src = "<button @onclick=\"increment\">{count}</button>";
    var stream = std.io.fixedBufferStream(src);
    var iter = try Lexer.iter(std.testing.allocator, stream.reader());
    defer iter.deinit();

    try std.testing.expectEqual((try iter.next(.out_of_tag)).?.kind, .open_tag);
    try std.testing.expectEqual((try iter.next(.tag)).?.kind, .ident);
    try std.testing.expectEqual((try iter.next(.tag)).?.kind, .action);
    try std.testing.expectEqual((try iter.next(.tag)).?.kind, .ident);
    try std.testing.expectEqual((try iter.next(.tag)).?.kind, .equals);
    try std.testing.expectEqual((try iter.next(.tag)).?.kind, .string);
    try std.testing.expectEqual((try iter.next(.tag)).?.kind, .close_tag);
    try std.testing.expectEqual((try iter.next(.out_of_tag)).?.kind, .text);
    try std.testing.expectEqual((try iter.next(.out_of_tag)).?.kind, .open_tag);
    try std.testing.expectEqual((try iter.next(.tag)).?.kind, .end_children);
    try std.testing.expectEqual((try iter.next(.tag)).?.kind, .ident);
    try std.testing.expectEqual((try iter.next(.tag)).?.kind, .close_tag);
}
