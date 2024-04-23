const std = @import("std");

pub const ProcessError = error{
    InvalidNumArgs,
    Overflow,
    Underflow,
};

fn sum(literals: []u64) ProcessError!u64 {
    var v: u64 = 0;
    for (literals) |l| {
        const res = @addWithOverflow(v, l);
        if (0 < res[1]) return ProcessError.Overflow;
        v = res[0];
    }
    return v;
}

fn prod(literals: []u64) ProcessError!u64 {
    var v: u64 = 0;
    for (literals) |l| {
        const res = @mulWithOverflow(v, l);
        if (0 < res[1]) return ProcessError.Overflow;
        v = res[0];
    }
    return v;
}

fn min(literals: []u64) ProcessError!u64 {
    var v: u64 = std.math.maxInt(u64);
    for (literals) |l| v = @min(v, l);
    return v;
}

fn max(literals: []u64) ProcessError!u64 {
    var v: u64 = 0;
    for (literals) |l| v = @max(v, l);
    return v;
}

fn gt(literals: []u64) ProcessError!u64 {
    if (2 > literals.len) return ProcessError.InvalidNumArgs;
    return if (literals[0] > literals[1]) 1 else 0;
}

fn lt(literals: []u64) ProcessError!u64 {
    if (2 > literals.len) return ProcessError.InvalidNumArgs;
    return if (literals[0] < literals[1]) 1 else 0;
}

fn eq(literals: []u64) ProcessError!u64 {
    if (2 > literals.len) return ProcessError.InvalidNumArgs;
    return if (literals[0] == literals[1]) 1 else 0;
}

pub const OpId = enum(u3) {
    sum = 0,
    prod,
    min,
    max,
    gt = 5, // 4 indicates literal which parses differently
    lt,
    eq,

    pub fn opFn(self: OpId) *const fn ([]u64) ProcessError!u64 {
        return switch (self) {
            .sum => sum,
            .prod => prod,
            .min => min,
            .max => max,
            .gt => gt,
            .lt => lt,
            .eq => eq,
        };
    }
};

pub const PackMode = enum(u1) {
    nbits = 0,
    npackets,
};

pub const OpPacket = struct {
    count: u16,
    limit: u16,
    packmode: PackMode,
    opfn: *const fn (literals: []u64) ProcessError!u64,
};
