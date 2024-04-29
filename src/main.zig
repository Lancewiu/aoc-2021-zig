const std = @import("std");
const assert = std.debug.assert;
const data = @import("packet.zig");

const IS_TESTING = true;

fn decode(c: u8) ![4]u1 {
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
        else => error.InvalidEncodeChar,
    };
}

const Context = struct {
    packet: data.OpPacket,
    literals: std.ArrayList(u64),

    fn isComplete(self: Context) bool {
        return self.packet.count >= self.packet.limit;
    }

    fn addBits(self: *Context, bits: u16) void {
        if (self.packet.packmode == .npackets) return;
        self.packet.count += bits;
    }

    fn incrementSubCount(self: *Context) void {
        if (self.packet.packmode == .nbits) return;
        self.packet.count += 1;
    }

    fn complete(self: Context) data.ProcessError!u64 {
        return self.packet.opfn(self.literals.items);
    }
};

const Bits = struct {
    i: usize,
    buf: []u1,

    fn init(slice: []u1) Bits {
        return .{ .i = 0, .buf = slice };
    }

    fn readInt(self: *Bits, count: u4) !u16 {
        if (self.i > self.buf.len) return error.EndOfBitsBuffer;
        if (0 == count) return 0;
        var val: u16 = 0;
        for (self.buf[self.i..][0..count], 0..) |bit, i| {
            if (1 == bit) val |= @as(u16, 1) << (count - 1 - std.math.lossyCast(u4, i));
        }
        return val;
    }

    fn skip(self: *Bits, count: u4) void {
        self.i +|= count;
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const filename = if (IS_TESTING) "test.txt" else "input.txt";
    const bytebuf = @embedFile(filename);
    var bitbuf: [4 * bytebuf.len]u1 = undefined;
    for (bytebuf[0..], 0..) |byte, i| {
        if (byte == '\r' or byte == '\n') break;
        const bitoffset = 4 * i;
        const word = try decode(byte);
        for (0..4) |ibit| bitbuf[bitoffset..][ibit] = word[ibit];
    }
    var contexts = std.ArrayList(Context).init(alloc);
    var bits = Bits.init(bitbuf[0..]);

    while (bits.i < bits.buf.len) {
        const istart = bits.i;
        bits.skip(3);
        const packet_type = try bits.readInt(3);

        if (4 != packet_type) {
            // op
            const opid = try std.meta.intToEnum(data.OpId, packet_type);
            const packmode = try std.meta.intToEnum(
                data.PackMode,
                try bits.readInt(1),
            );
            const limit: u16 = switch (packmode) {
                .npackets => try bits.readInt(11),
                .nbits => try bits.readInt(15),
            };
            const bit_count: u16 = @truncate(bits.i - istart);
            for (contexts.items) |*ctx| {
                ctx.addBits(bit_count);
                if (ctx.isComplete()) return error.PacketTruncated;
            }
            try contexts.append(.{
                .packet = .{
                    .count = 0,
                    .limit = limit,
                    .packmode = packmode,
                    .opfn = opid.opFn(),
                },
                .literals = std.ArrayList(u64).init(alloc),
            });
            continue;
        }

        // literal
        var literal: u64 = 0;
        var lsh: u6 = 60;
        while (true) {
            const is_last = 0 == try bits.readInt(1);
            const seg = try bits.readInt(4);
            literal += @as(u64, @intCast(seg)) << lsh;
            if (!is_last and 0 == lsh) return error.LiteralOverflow;
            if (is_last) break;
            lsh -= 4;
        }
        const bit_count: u16 = @truncate(bits.i - istart);
        for (contexts.items) |*ctx| ctx.addBits(bit_count);
        var last_ctx = &contexts.items[contexts.items.len - 1];
        last_ctx.incrementSubCount();
        try last_ctx.literals.append(literal);
        while (last_ctx.isComplete()) {
            literal = try last_ctx.complete();
            _ = contexts.pop();
            if (0 == contexts.items.len) {
                std.debug.print("= {d}\n", .{literal});
                return;
            }
            last_ctx = &contexts.items[contexts.items.len - 1];
        }
    }
}
