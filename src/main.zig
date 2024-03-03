const std = @import("std");

const IS_TESTING = false;
const SEC_SIZE = if (IS_TESTING) 10 else 100;
const MAP_SIZE = 5 * SEC_SIZE;
const SEC_TOTAL_SIZE = SEC_SIZE * SEC_SIZE;
const MAP_TOTAL_SIZE = MAP_SIZE * MAP_SIZE;

fn getRisk(index: usize, section: []u4) u64 {
    const x = index % MAP_SIZE;
    const y = index / MAP_SIZE;
    const sec_y = y % SEC_SIZE;
    const sec_x = x % SEC_SIZE;
    const sec_dist: u64 = (y / SEC_SIZE) + (x / SEC_SIZE);
    const risk_values = [_]u64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const sec_risk: u64 = section[sec_y * SEC_SIZE + sec_x];
    const risk_i = (sec_dist + (sec_risk - 1)) % risk_values.len;
    const risk = risk_values[risk_i];
    return risk;
}

fn pushPriority(index: usize, risk: []u64, pq: *std.ArrayList(usize)) !void {
    // search for dupes first
    for (pq.items, 0..) |q_index, i| {
        if (q_index == index) {
            _ = pq.orderedRemove(i);
            break;
        }
    }

    const insert_risk = risk[index];
    for (pq.items, 0..) |q_index, i| {
        if (risk[q_index] < insert_risk) {
            try pq.insert(i, index);
            return;
        }
    }
    try pq.append(index);
}

fn find(alloc: std.mem.Allocator, section: []u4) !u64 {
    var risk = try alloc.alloc(u64, MAP_TOTAL_SIZE);
    defer alloc.free(risk);
    @memset(risk, std.math.maxInt(u64));
    risk[0] = 0;

    var visited = try alloc.alloc(bool, MAP_TOTAL_SIZE);
    defer alloc.free(visited);
    @memset(visited, false);

    var pq = std.ArrayList(usize).init(alloc);
    defer pq.deinit();
    try pq.append(0);
    while (true) {
        const cursor = pq.popOrNull() orelse break;
        if (cursor == MAP_TOTAL_SIZE - 1) break;
        defer visited[cursor] = true;
        const cursor_x = cursor % MAP_SIZE;
        const cursor_y = cursor / MAP_SIZE;
        const cursor_risk = risk[cursor];
        if (cursor_x < MAP_SIZE - 1) {
            const east = cursor + 1;
            if (!visited[east]) {
                const new_risk = cursor_risk + getRisk(east, section);
                if (new_risk < risk[east]) {
                    risk[east] = new_risk;
                    try pushPriority(east, risk, &pq);
                }
            }
        }
        if (cursor_x > 0) {
            const west = cursor - 1;
            if (!visited[west]) {
                const new_risk = cursor_risk + getRisk(west, section);
                if (new_risk < risk[west]) {
                    risk[west] = new_risk;
                    try pushPriority(west, risk, &pq);
                }
            }
        }
        if (cursor_y > 0) {
            const north = cursor - MAP_SIZE;
            if (!visited[north]) {
                const new_risk = cursor_risk + getRisk(north, section);
                if (new_risk < risk[north]) {
                    risk[north] = new_risk;
                    try pushPriority(north, risk, &pq);
                }
            }
        }
        if (cursor_y < MAP_SIZE - 1) {
            const south = cursor + MAP_SIZE;
            if (!visited[south]) {
                const new_risk = cursor_risk + getRisk(south, section);
                if (new_risk < risk[south]) {
                    risk[south] = new_risk;
                    try pushPriority(south, risk, &pq);
                }
            }
        }
    }
    return risk[risk.len - 1];
}

fn parseSection(alloc: std.mem.Allocator) ![]u4 {
    var section = try alloc.alloc(u4, SEC_TOTAL_SIZE);
    errdefer alloc.free(section);
    const filename = if (IS_TESTING) "test.txt" else "input.txt";
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const file_reader = file.reader();
    var line_buf: [SEC_SIZE + 1]u8 = undefined;
    var line_stream = std.io.fixedBufferStream(line_buf[0..]);
    const line_writer = line_stream.writer();
    var y: usize = 0;
    while (true) : ({
        line_stream.reset();
        y += 1;
    }) {
        file_reader.streamUntilDelimiter(line_writer, '\n', line_buf.len) catch |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        };
        const line = line_stream.getWritten();
        for (0..SEC_SIZE) |x| {
            section[(y * SEC_SIZE) + x] = @intCast(try std.fmt.charToDigit(line[x], 10));
        }
    }
    return section;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    std.debug.print("lowest risk: {d}", .{try find(alloc, try parseSection(alloc))});
}
