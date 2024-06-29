const std = @import("std");

const IS_TESTING = true;

const vec_t = struct {
    x: i32,
    y: i32,
};

fn parseToken(comptime T: type, buf: []const u8, comptime end: u8) !struct { T, usize } {
    var i_end: usize = 1;
    while (buf.len > i_end and buf[i_end] != end) i_end += 1;
    return .{ try std.fmt.parseInt(T, buf[0..i_end], 10), i_end };
}

fn getSteps(dest: i32, v_i: i32) ?struct { i32, i32 } {
    if (0 == dest) return 0;
    // x = 0.5at^2 + bt
    // x := dest
    // b := init_velocity
    // a := -1
    // via quadratic formula, c := -dest
    //
    // x = -0.5t^2 + v_ix*t
    // 
    // t = v_ix +- sqrt(v_ix^2 - 2x)
    // t = v_iy +- sqrt(v_iy^2 - 2y)
    //

    if (v_i < 4 * dest) return null; // complex

    const b = @as(f64, v_i);
    const root = @sqrt(@as(f64, (v_i * v_i) - (4 * dest)));
    const nearstep = (b - root) / 2.0;
    const farstep = (b + root) / 2.0;
    const near_fpart, const near_ipart = std.math.modf(nearstep);
    if (0.0 != near_fpart) return null;
    return .{ near_ipart, @intFromFloat(farstep) };
}

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const alloc = arena.allocator();
    const filename = if (IS_TESTING) "../test.txt" else "../input.txt";
    const input = @embedFile(filename);

    const xmin, var offset = try parseToken(i32, input[15..], '.');
    offset += 2;
    const xmax, offset = try parseToken(i32, input[offset..], ',');
    offset += 4;
    const ymin, offset = try parseToken(i32, input[offset..], '.');
    offset += 2;

    const endchar = if (IS_TESTING) '\r' else '\n';
    const ymax, _ = try parseToken(i32, input[offset..], endchar);
}
