const std = @import("std");

// 27 bits use 2GB
const NB_BITS: u8 = 25;
const SIZEX: usize = 4;
const SIZEY: usize = 4;
const SIZEZ: usize = 4;
// 6x7 NB_BITS=29 170s
// 7x6 NB_BITS=30 367s

const Vals = i16;
const Vals_min: Vals = std.math.minInt(i8);
const Vals_max: Vals = std.math.maxInt(i8);
const WIN: Vals = Vals_max - 1;
const Depth = u8;
const Colors = i8;
const Sigs = u64;

const Move = packed struct {
    x: usize,
    y: usize,
    z: usize,
    ox: usize,
    oy: usize,
    oz: usize,
    rem: bool, // if true do not use (ox,oy,oz) and take the ball from the reserve
};
const NB_MAX_MOVES = 32;
const Moves = [NB_MAX_MOVES]Move;

const FOUR: usize = 4;
const WHITE: Colors = 1;
const BLACK = -WHITE;
const EMPTY: Colors = 0;
const HASH_SIZE: usize = 1 << NB_BITS;
const HASH_MASK: Sigs = HASH_SIZE - 1;

var first_hash: Sigs = undefined;
var hashesw: [SIZEX][SIZEY][SIZEZ]Sigs = undefined;
var hashesb: [SIZEX][SIZEY][SIZEZ]Sigs = undefined;

const HashElem = packed struct {
    sig: Sigs,
    v_inf: Vals,
    v_sup: Vals,
    d: Depth,
};

const ZHASH = HashElem{
    .sig = 0,
    .v_inf = 0,
    .v_sup = 0,
    .d = 0,
};

var hashes: []HashElem = undefined;
//var tab1 = [_]Colors{EMPTY} ** SIZEZ;
//var tab2 = [_][SIZEY]Colors{[_]Colors{EMPTY} ** SIZEY} ** SIZEX;
var tab = [_][SIZEY][SIZEZ]Colors{[_][SIZEZ]Colors{[_]Colors{EMPTY} ** SIZEZ} ** SIZEY} ** SIZEX;
var rems = [_]i64{15} ** 2;

fn retrieve(hv: Sigs, v_inf: *Vals, v_sup: *Vals) bool {
    const ind: usize = hv & HASH_MASK;
    if (hashes[ind].sig == hv) {
        v_inf.* = hashes[ind].v_inf;
        v_sup.* = hashes[ind].v_sup;
        return true;
    } else {
        return false;
    }
}

fn store(hv: Sigs, alpha: Vals, beta: Vals, g: Vals, depth: Depth) void {
    const ind = hv & HASH_MASK;
    const d = std.math.maxInt(Depth) - depth;
    if (hashes[ind].d <= d) {
        if (hashes[ind].sig != hv) {
            hashes[ind].d = d;
            hashes[ind].v_inf = Vals_min;
            hashes[ind].v_sup = Vals_max;
            hashes[ind].sig = hv;
        }
        if ((g > alpha) and (g < beta)) {
            hashes[ind].v_inf = g;
            hashes[ind].v_sup = g;
        } else if (g <= alpha) {
            hashes[ind].v_sup = @min(g, hashes[ind].v_sup);
        } else if (g >= beta) {
            hashes[ind].v_inf = @max(g, hashes[ind].v_inf);
        }
    }
}

fn eval() Vals {
    return 0;
}

fn build_all_moves(color: Colors, moves: *Moves) u8 {
    var freex: [30]isize = undefined;
    var freey: [30]isize = undefined;
    var freez: [30]isize = undefined;
    var nb: usize = 0;
    for (0..3) |z| {
        const nz = z + 1;
        for (0..4 - z) |x| {
            for (0..4 - z) |y| {
                if (tab[x][y][z] == color) {
                    var ok = true;
                    outer: for (-1..2) |dx| {
                        for (-1..2) |dy| {
                            if ((dx != 0) or (dy != 0)) {
                                const nx = x + dx;
                                const ny = y + dy;
                                if ((nx >= 0) and (nx < 4 - nz) and (ny >= 0) and (ny < 4 - nz) and (tab[nx][ny][nz] != EMPTY)) {
                                    ok = false;
                                    break :outer;
                                }
                            }
                        }
                    }
                    if (ok) {
                        freex[nb] = x;
                        freey[nb] = y;
                        freez[nb] = z;
                        nb += 1;
                    }
                }
            }
        }
    }
    moves[0].x = 0;
    moves[0].y = 0;
    moves[0].z = 0;
    moves[0].ox = 0;
    moves[0].oy = 0;
    moves[0].oz = 0;
    moves[0].rem = true;

    return 0;
}

fn ab(
    alpha: Vals,
    beta: Vals,
    color: Colors,
    depth: Depth,
    maxdepth: Depth,
    hv: Sigs,
) Vals {
    var a = alpha;
    var b = beta;
    var v_inf: Vals = undefined;
    var v_sup: Vals = undefined;
    if (retrieve(hv, &v_inf, &v_sup)) {
        if (v_inf == v_sup) return v_inf;
        if (v_inf >= b) return v_inf;
        if (v_sup <= a) return v_sup;
        a = @max(a, v_inf);
        b = @min(b, v_sup);
    }
    if (tab[0][0][3] != EMPTY) {
        return WIN * color;
    }
    if ((color == WHITE) and (rems[0] == 0)) {
        return -WIN;
    }
    if ((color == BLACK) and (rems[1] == 0)) {
        return WIN;
    }
    if (depth == maxdepth) {
        return eval();
    }

    var g: Vals = if (color == WHITE) Vals_min else Vals_max;
    var nhv: Sigs = undefined;
    var moves: Moves = undefined;
    var nb: u8 = build_all_moves(color, &moves);
    for (0..nb) |i| {
        const x = moves[i].x;
        const y = moves[i].y;
        const z = moves[i].z;
        tab[x][y][z] = color;
        if (color == WHITE) {
            nhv = hv ^ hashesw[x][y][z];
        } else {
            nhv = hv ^ hashesb[x][y][z];
        }
        const v = ab(a, b, -color, depth + 1, maxdepth, nhv);
        tab[x][y][z] = EMPTY;
        if (color == WHITE) {
            g = @max(v, g);
            a = @max(a, g);
        } else {
            g = @min(v, g);
            a = @min(b, g);
        }
        if (a >= b) break;
    }
    store(hv, alpha, beta, g, depth);
    return g;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const allocator = std.heap.page_allocator;
    const RndGen = std.rand.DefaultPrng;
    hashes = try allocator.alloc(HashElem, HASH_SIZE);
    defer allocator.free(hashes);
    for (hashes) |*a| a.* = ZHASH;
    var rnd = RndGen.init(0);
    for (0..SIZEX) |x| {
        for (0..SIZEY) |y| {
            for (0..SIZEZ) |z| {
                hashesw[x][y][z] = rnd.random().int(Sigs);
                hashesb[x][y][z] = rnd.random().int(Sigs);
            }
        }
    }
    first_hash = rnd.random().int(Sigs);
    var t = std.time.milliTimestamp();
    const ret = ab(Vals_min, Vals_max, WHITE, 0, 1, first_hash);
    t = std.time.milliTimestamp() - t;
    try stdout.print("{d}\n", .{t});
    try stdout.print("{d}\n", .{ret});
}

//const Inner = struct { a: u32, b: bool };
//var toto = [_][20]Inner{[_]Inner{.{ .a = 1, .b = true }} ** 20} ** 10;
