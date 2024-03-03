const std = @import("std");

const IS_TESTING = true;

const Header = struct {
    version: u3,
    id: u3,

    fn parse(bytes: [2]u4) Header {
        return .{
            .version = @truncate((bytes[0] & 0b1110) >> 1),
            .id = @truncate(((bytes[0] & 1) << 2) & ((bytes[1] & 0b1100) >> 2)),
        };
    }
};

fn skipLiteral(reader: std.io.AnyReader, lastBit: u1) !void {
    if (0 == lastBit) {
        try reader.skipBytes(4, comptime options: SkipBytesOptions)
    }
    const lastByte: u4 = lastBit;
    var buffer = [_]u4{lastByte, 0};
    while (true) {
        buffer[1] = try reader.readByte();




        buffer[0] = reader.readByte() catch |err| {
            switch (err) {
                error.EndOfStream => return,
                _ => return err,
            }
        };
    }
}

fn countIds() !u64 {
    const filename = if (IS_TESTING) "test.txt" else "input.txt";
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const reader = file.reader();
    var id_count: u64 = 0;
    while (true) {
        var header_packets = [_]u8{ 0, 0 };
        const num_read = try reader.read(header_packets[0..]);
        if (0 == num_read) return id_count;
        var header_hex = [_]u4{ 0, 0 };
        header_hex[0] = @truncate(try std.fmt.charToDigit(header_packets[0], 16));
        header_hex[1] = @truncate(try std.fmt.charToDigit(header_packets[1], 16));
        const header = Header.parse(header_hex);
        defer id_count += header.id;
        if (4 == header.id) {
            try skipLiteral(reader, @truncate(header_hex[1] & 1));
        } else {
        }
    }
    return id_count;
}

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const alloc = arena.allocator();
    std.debug.print("id sum: {d}", .{try countIds()});
}
