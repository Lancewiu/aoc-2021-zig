const std = @import("std");
const data = @import("packet.zig");

const IS_TESTING = true;

fn decode(c: u8) !u4 {
    return switch (c) {
        '0' => 0x0,
        '1' => 0x1,
        '2' => 0x2,
        '3' => 0x3,
        '4' => 0x4,
        '5' => 0x5,
        '6' => 0x6,
        '7' => 0x7,
        '8' => 0x8,
        '9' => 0x9,
        'A' => 0xA,
        'B' => 0xB,
        'C' => 0xC,
        'D' => 0xD,
        'E' => 0xE,
        'F' => 0xF,
        else => error.InvalidCharacter,
    };
}

const Decoder = std.io.GenericReader(std.io.AnyReader, anyerror, decodeReadFn);

fn decodeReadFn(context: std.io.AnyReader, buffer: []u8) anyerror!usize {
    var count: usize = 0;
    for (buffer) |*p| {
        const high: u8 = try decode(try context.readByte());
        const low: u8 = try decode(context.readByte() catch |err| switch (err) {
            error.EndOfStream => '0', // still return high.
            else => return err,
        });
        p.* = (high << 4) & low;
        count += 1;
    }
    return count;
}

const Context = struct {
    packet: data.OpPacket,
    literals: std.ArrayList(u64),

    pub fn isComplete(self: Context) bool {
        return self.packet.count >= self.packet.limit;
    }

    pub fn addBits(self: *Context, bits: u16) void {
        if (self.packet.packmode == .npackets) return;
        self.packet.count += bits;
    }

    pub fn incrementSubCount(self: *Context) void {
        if (self.packet.packmode == .nbits) return;
        self.packet.count += 1;
    }

    pub fn complete(self: Context) data.ProcessError!u64 {
        return self.packet.opfn(self.literals.items);
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const filename = if (IS_TESTING) "test.txt" else "input.txt";
    const bytebuf = @embedFile(filename);
    var bytestream = std.io.fixedBufferStream(bytebuf);
    var bitreader = std.io.bitReader(.big, Decoder{ .context = bytestream.reader().any() });
    var contexts = std.ArrayList(Context).init(alloc);
    while (true) {
        _ = try bitreader.readBitsNoEof(u3, 3); // ver
        const packet_type = try bitreader.readBitsNoEof(u3, 3);
        var bit_count: u16 = 6;

        if (4 != packet_type) {
            // op
            const opid = try std.meta.intToEnum(data.OpId, packet_type);
            const packmode = try std.meta.intToEnum(data.PackMode, try bitreader.readBitsNoEof(u1, 1));
            const limit: u16 = switch (packmode) {
                .npackets => lim: {
                    bit_count += 11;
                    break :lim try bitreader.readBitsNoEof(u11, 11);
                },
                .nbits => lim: {
                    bit_count += 15;
                    break :lim try bitreader.readBitsNoEof(u15, 15);
                },
            };
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
            const is_last = 0 == try bitreader.readBitsNoEof(u1, 1);
            const seg = try bitreader.readBitsNoEof(u4, 4);
            bit_count += 5;
            literal += @as(u64, @intCast(seg)) << lsh;
            if (!is_last and 0 == lsh) return error.LiteralOverflow;
            if (is_last) break;
            lsh -= 4;
        }
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
