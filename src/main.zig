const std = @import("std");

const IS_TESTING = false;

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
        else => error.InvalidCharacter,
    };
}

const BitStream = struct {
    const BITLEN = 8;
    const BYTELEN = 1024;

    start: usize,
    end: usize, // buffer one-past-end index
    dead: usize, // dead zone a la biparite buffer
    bitbuf: [BITLEN]u1,
    byte_start: usize,
    byte_end: usize,
    bytebuf: [BYTELEN]u8,
    reader: std.io.AnyReader,

    pub fn init(reader: std.io.AnyReader) BitStream {
        return .{
            .start = 0,
            .end = 0,
            .dead = BITLEN,
            .bitbuf = undefined,
            .byte_start = 0,
            .byte_end = 0,
            .bytebuf = undefined,
            .reader = reader,
        };
    }

    fn expand(self: *BitStream) !void {
        if (self.byte_start == self.byte_end) {
            self.byte_end = try self.reader.read(self.bytebuf[0..]);
            self.byte_start = 0;
            if (0 == self.byte_end) return error.EndOfStream;
        }
        const code: [4]u1 = try decode(self.bytebuf[self.byte_start]);
        self.byte_start += 1;
        if (self.end + 4 > self.bitbuf.len) {
            self.dead = self.end;
            self.end = 0;
        }
        @memcpy(self.bitbuf[self.end..][0..4], &code);
        self.end += 4;
    }

    pub fn next(self: *BitStream) !u1 {
        if (self.start == self.end) try self.expand();
        if (self.start == self.dead) {
            self.start = 0;
            self.dead = BITLEN;
        }
        defer self.start += 1;
        return self.bitbuf[self.start];
    }

    pub fn skip(self: *BitStream, nbits: u4) !void {
        for (0..nbits) |_| _ = try self.next();
    }

    pub fn nextInt(self: *BitStream, nbits: u4) !u16 {
        var raw: [16]u1 = undefined;
        @memset(&raw, 0);
        for (0..nbits) |i| raw[i] = try self.next();
        var out: u16 = 0; // required due to lshift rule
        var i_shift: u4 = 0;
        while (i_shift < nbits) : (i_shift += 1) {
            out |= @as(u16, @intCast(raw[nbits - 1 - i_shift])) << i_shift;
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

fn updateBitCounts(contexts: *std.ArrayList(Context), bit_count: u4) !?u4 {
    var i: usize = 0;
    var remainder_bits: u4 = 0;
    while (i < contexts.items.len) : (i += 1) {
        const ctx = &contexts.items[i];
        if (.bit_count != ctx.op) continue;
        if (ctx.count >= ctx.limit) return error.PacketAlreadyCompleted;
        ctx.count += bit_count;
        if (ctx.count >= ctx.limit) {
            remainder_bits = bit_count - @as(u4, @truncate(ctx.count - ctx.limit));
            std.debug.print("  (exiting context {d})\n", .{i});
            contexts.shrinkRetainingCapacity(i);
            break;
        }
    } else return null;
    incrementCompletedPackets(contexts);
    return remainder_bits;
}

fn incrementCompletedPackets(contexts: *std.ArrayList(Context)) void {
    while (0 < contexts.items.len) {
        const ctx_i = contexts.items.len - 1;
        const ctx = &contexts.items[ctx_i];
        if (.num_packets != ctx.op) break;
        ctx.count += 1;
        if (ctx.count < ctx.limit) break;
        std.debug.print("  (exiting context {d})\n", .{ctx_i});
        _ = contexts.pop();
    }
}

fn countIds(alloc: std.mem.Allocator) !u64 {
    const filename = if (IS_TESTING) "test.txt" else "input.txt";
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    var bitreader = BitStream.init(file.reader().any());
    var contexts = try std.ArrayList(Context).initCapacity(alloc, 1);
    defer contexts.deinit();
    contexts.appendAssumeCapacity(.{ .count = 0, .limit = 1, .op = .num_packets });
    var version_sum: u64 = 0;
    packetstart: while (0 < contexts.items.len) {
        std.debug.print("----\n", .{});
        if (try updateBitCounts(&contexts, 3)) |rem| {
            if (3 == rem) {
                // we have just enough to parse the version before restarting.
                version_sum += bitreader.nextInt(3) catch |err| switch (err) {
                    error.EndOfStream, error.InvalidCharacter => break,
                    else => return err,
                };
            } else try bitreader.skip(rem);
            continue;
        }
        version_sum += bitreader.nextInt(3) catch |err| switch (err) {
            error.EndOfStream, error.InvalidCharacter => break,
            else => return err,
        };

        if (try updateBitCounts(&contexts, 3)) |rem| {
            try bitreader.skip(rem);
            continue;
        }
        const typeid: u16 = try bitreader.nextInt(3);

        if (typeid == 4) {
            // literal
            std.debug.print("  literal type {d}\n", .{typeid});

            while (true) {
                if (try updateBitCounts(&contexts, 5)) |rem| {
                    try bitreader.skip(rem);
                    continue :packetstart;
                }
                const group = try bitreader.nextInt(5);
                if (0 == group & 0b10000) break;
            }
            incrementCompletedPackets(&contexts);
            continue;
        }
        // op
        std.debug.print("  operator type {d} ", .{typeid});
        if (try updateBitCounts(&contexts, 1)) |rem| {
            try bitreader.skip(rem);
            continue;
        }
        const subp_len: u16 = try bitreader.nextInt(1);
        const op: OpMode = if (0 == subp_len) .bit_count else .num_packets;
        const lim_size: u4 = if (OpMode.bit_count == op) 15 else 11;
        if (try updateBitCounts(&contexts, lim_size)) |rem| {
            try bitreader.skip(rem);
            continue;
        }
        const limit = try bitreader.nextInt(lim_size);

        const new_context = .{ .count = 0, .limit = limit, .op = op };
        std.debug.print("of {d} {s} (context {d})\n", .{
            limit,
            if (OpMode.bit_count == op) "bits" else "packets",
            contexts.items.len,
        });
        try contexts.append(new_context);
    }
    return version_sum;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    std.debug.print("id sum: {d}\n", .{try countIds(alloc)});
}
