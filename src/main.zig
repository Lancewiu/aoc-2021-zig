const std = @import("std");

const IS_TESTING = true;

fn decode(c: u8) [4]u1 {
    return switch (c) {
        '0' => .{ 0, 0, 0, 0 },
        '1' => .{ 0, 0, 0, 1 },
        '2' => .{ 0, 0, 1, 0 },
        '3' => .{ 0, 0, 1, 1 },
        '4' => .{ 0, 1, 0, 0 },
        '5' => .{ 0, 1, 0, 1 },
        '6' => .{ 0, 1, 1, 0 },
        '7' => .{ 0, 1, 1, 1 },
        '8' => .{ 1, 0, 0, 0 },
        '9' => .{ 1, 0, 0, 1 },
        'A' => .{ 1, 0, 1, 0 },
        'B' => .{ 1, 0, 1, 1 },
        'C' => .{ 1, 1, 0, 0 },
        'D' => .{ 1, 1, 0, 1 },
        'E' => .{ 1, 1, 1, 0 },
        'F' => .{ 1, 1, 1, 1 },
        else => unreachable,
    };
}

const BITBUF_LEN = 4096;

const BitStream = struct {
    start: usize,
    end: usize, // buffer one-past-end index
    dead: usize, // dead zone a la biparite buffer
    bitbuf: [BITBUF_LEN]u1,
    reader: std.io.AnyReader,

    pub fn init(reader: std.io.AnyReader) BitStream {
        return .{
            .start = 0,
            .end = 0,
            .dead = BITBUF_LEN,
            .bitbuf = undefined,
            .reader = reader,
        };
    }

    fn expand(self: *BitStream) !void {
        const code = decode(try self.reader.readByte());
        const dest = if (self.end + 4 > self.bitbuf.len) todest: {
            self.dead = self.end;
            self.end = 0;
            break :todest self.bitbuf[0..4];
        } else todest: {
            self.end += 4;
            break :todest self.bitbuf[self.end..][0..4];
        };
        @memcpy(dest, &code);
    }

    pub fn next(self: *BitStream) !u1 {
        if (self.start == self.end) try self.expand();
        defer {
            self.start += 1;
            if (self.start == self.dead) {
                self.start = 0;
                self.dead = self.bitbuf.len;
            }
        }
        return self.bitbuf[self.start];
    }

    pub fn nextInt(self: *BitStream, comptime nbits: u4) !u16 {
        var raw: [nbits]u1 = undefined;
        @memset(&raw, 0);
        for (0..nbits) |i| raw[i] = try self.next();
        var out: u16 = 0; // required due to lshift rule
        var i_shift: u4 = 0;
        while (i_shift < nbits) : (i_shift += 1) {
            out |= @as(@intCast(raw[nbits - 1 - i_shift]), u8) << i_shift;
        }
        return out;
    }
};

const OpMode = enum {
    bit_count,
    num_packets,
};

const Context = struct {
    count: u16,
    limit: u16,
    op: OpMode,
};

fn countIds(alloc: std.mem.Allocator) !u64 {
    const filename = if (IS_TESTING) "test.txt" else "input.txt";
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    var bitreader = BitStream.init(file.reader());
    var contexts = try std.ArrayList(Context).initCapacity(alloc, 1);
    defer contexts.deinit();
    contexts.appendAssumeCapacity(.{ .count = 0, .limit = 1, .op = .num_packets });
    var version_sum = 0;
    while (true) {
        version_sum += bitreader.nextInt(3) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        var current_context = &contexts.items[contexts.len - 1];
        const typeid = try bitreader.nextInt(3);
        var bit_count: u16 = 6;

        if (typeid == 4) {
            // literal
            while (true) {
                const group = try bitreader.nextInt(5);
                bit_count += 5;
                if (0 == group & 0b10000) break;
            }
            // now we escape while we can
            while (0 < contexts.items.len) {
                switch (current_context.op) {
                    .num_packets => current_context.count += 1,
                    .bit_count => current_context.count += bit_count,
                }
                if (current_context.count < current_context.limit) break;
                _ = contexts.pop();
            } else break;
            continue;
        }

        // op
        const subp_len = try bitreader.nextInt(1);
        const new_context: Context = if (0 == subp_len)
            .{ .count = 0, .limit = try bitreader.nextInt(15), .op = .bit_count }
        else
            .{ .count = 0, .limit = try bitreader.nextInt(11), .op = .num_packets };
        try contexts.append(new_context);
    }
    return version_sum;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    std.debug.print("id sum: {d}", .{try countIds(alloc)});
}
