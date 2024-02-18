const std = @import("std");

const IS_TESTING = true;
const MAP_SIZE = if (IS_TESTING) 10 else 100;

const Point = struct {
    x: i16,
    y: i16,

    pub fn hash(self: Point) u64 {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, self);
        return hasher.final();
    }
};

const SquareMap = struct {
    const Self = @This();
    buf: [MAP_SIZE * MAP_SIZE]u4,

    pub fn init() Self {
        return .{ .buf = undefined };
    }

    pub fn valueAt(self: Self, point: Point) ?u16 {
        const x_true = std.math.cast(usize, point.x) orelse return null;
        const y_true = std.math.cast(usize, point.y) orelse return null;
        if (x_true >= 5 * MAP_SIZE or y_true >= 5 * MAP_SIZE) return null;
        const x = x_true % MAP_SIZE;
        const y = y_true % MAP_SIZE;
        const modifier: u16 = @truncate((x_true + y_true) / MAP_SIZE);
        return @as(u16, self.buf[x + MAP_SIZE * y]) + modifier;
    }
};

fn insertNext(
    distance: std.AutoHashMap(Point, u16),
    next: *std.ArrayList(Point),
    point: Point,
) !void {
    if (point.x < 0 or point.y < 0) return error.PointOffMap;
    if (point.x >= 5 * MAP_SIZE or point.y >= 5 * MAP_SIZE) return error.PointOffMap;
    const pt_val = distance.get(point) orelse return error.MissingPointDistance;
    var i_l: usize = 0;
    var i_r: usize = next.items.len;
    while (i_l != i_r) {
        const i_mid = i_l + (i_r - i_l) / 2;
        const mid_pt = next.items[i_mid];
        const mid_val = distance.get(mid_pt) orelse unreachable;
        if (pt_val < mid_val) {
            i_l = i_mid + 1;
        } else if (pt_val > mid_val) {
            i_r = i_mid;
        } else {
            i_l = i_mid;
            break;
        }
    }
    try next.insert(i_l, point);
}

fn insertVisited(visited: *std.ArrayList(Point), point: Point) !void {
    const pt_val = point.hash();
    var i_l: usize = 0;
    var i_r: usize = visited.items.len;
    while (i_l != i_r) {
        const i_mid = i_l + (i_r - i_l) / 2;
        const mid_pt = visited.items[i_mid];
        const mid_val = mid_pt.hash();
        if (pt_val < mid_val) {
            i_r = i_mid;
        } else if (pt_val > mid_val) {
            i_l = i_mid + 1;
        } else {
            i_l = i_mid;
            break;
        }
    }
    try visited.insert(i_l, point);
}

fn isVisited(visited: []const Point, point: Point) bool {
    const pt_val = point.hash();
    var i_l: usize = 0;
    var i_r: usize = visited.len;
    while (i_l != i_r) {
        const i_mid = i_l + (i_r - i_l) / 2;
        const mid = visited[i_mid];
        if (mid.x == point.x and mid.y == point.y) return true;
        const mid_val = mid.hash();
        if (pt_val < mid_val) {
            i_r = i_mid;
        } else {
            i_l = i_mid + 1;
        }
    }
    return false;
}

pub fn main() !void {
    var map = SquareMap.init();

    { // parse file
        const filename = if (IS_TESTING) "test.txt" else "input.txt";
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        const file_reader = file.reader();
        var line_buf: [MAP_SIZE + 1]u8 = undefined;
        var line_stream = std.io.fixedBufferStream(line_buf[0..]);
        const line_writer = line_stream.writer();
        var map_y: usize = 0;
        while (true) : ({
            line_stream.reset();
            map_y += 1;
        }) {
            file_reader.streamUntilDelimiter(line_writer, '\n', line_buf.len) catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                }
            };
            const line = line_stream.getWritten();
            if (line.len < MAP_SIZE) return error.InvalidLineLength;
            for (0..MAP_SIZE) |x| {
                map.buf[x + MAP_SIZE * map_y] = @truncate(try std.fmt.charToDigit(line[x], 10));
            }
        }
    }
    // set up adjacencies
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var distance = std.AutoHashMap(Point, u16).init(allocator);
    var visited = std.ArrayList(Point).init(allocator);
    const start = Point{ .x = 0, .y = 0 };
    try visited.append(start);
    try distance.put(start, 0);
    {
        const east = Point{ .x = 1, .y = 0 };
        try distance.put(east, map.valueAt(east) orelse unreachable);
        const south = Point{ .x = 0, .y = 1 };
        try distance.put(south, map.valueAt(south) orelse unreachable);
    }

    var next = std.ArrayList(Point).init(allocator);
    try next.append(.{ .x = 1, .y = 0 });
    try insertNext(distance, &next, .{ .x = 0, .y = 1 });

    const end = Point{ .x = (5 * MAP_SIZE) - 1, .y = (5 * MAP_SIZE) - 1 };
    while (next.popOrNull()) |curr| {
        if (isVisited(visited.items, curr)) continue;
        try insertVisited(&visited, curr);
        if (curr.x == end.x and curr.y == end.y) break;
        const curr_dist = distance.get(curr) orelse return error.InvalidPoint;
        const adj = [_]Point{
            .{ .x = curr.x, .y = curr.y - 1 },
            .{ .x = curr.x, .y = curr.y + 1 },
            .{ .x = curr.x - 1, .y = curr.y },
            .{ .x = curr.x + 1, .y = curr.y },
        };
        for (adj[0..]) |pt| {
            if (pt.x < 0 or pt.x >= 5 * MAP_SIZE) continue;
            if (pt.y < 0 or pt.y >= 5 * MAP_SIZE) continue;
            if (isVisited(visited.items, pt)) continue;
            const dist = curr_dist + (map.valueAt(pt) orelse return error.InvalidPoint);
            const entry = try distance.getOrPut(pt);
            if (entry.found_existing) {
                entry.value_ptr.* = @min(dist, entry.value_ptr.*);
            } else {
                entry.value_ptr.* = dist;
            }
            try insertNext(distance, &next, pt);
        }
    }
    const min_risk = distance.get(end) orelse return error.InvalidPoint;
    std.debug.print("min risk length: {d}\n", .{min_risk});
}
