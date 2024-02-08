const std = @import("std");
const malloc = std.heap.c_allocator;

pub const CHUNK = 32;
pub const CHUNK_SZ = CHUNK * CHUNK * CHUNK;
pub const MAXMESH = 3 * CHUNK_SZ / 4;

pub const Game = struct {
    pub const Face = struct {
        positions: [3]i32,
        spans: [2]u8,
        dir: u8,
        texture: u8,
    };
    faces: std.MultiArrayList(Face),
    chunk: [CHUNK][CHUNK][CHUNK]u8,

    pub fn newGame() !@This() {
        var game: @This() = .{
            .faces = std.MultiArrayList(Face){},
            .chunk = undefined,
        };
        @memset(@as(*[CHUNK_SZ]u8, @ptrCast(&game.chunk)), 0);
        game.chunk[1][1][1] = 1;
        game.chunk[1][1][2] = 1;
        game.chunk[1][1][3] = 1;

        game.chunk[1][2][1] = 1;
        game.chunk[1][3][1] = 1;

        game.chunk[2][1][1] = 1;
        game.chunk[3][1][1] = 1;

        game.meshifyChunk();
        return game;
    }
    pub fn quitGame(self: *@This()) void {
        self.faces.deinit(malloc);
    }

    const FaceFlags = std.bit_set.IntegerBitSet(6);
    fn isVisible(self: *@This(), face: comptime_int, x: u8, y: u8, z: u8) bool {
        return switch (face) {
            0 => z != CHUNK - 1 and self.chunk[x][y][z + 1] == 0,
            1 => x != CHUNK - 1 and self.chunk[x + 1][y][z] == 0,
            2 => z != 0 and self.chunk[x][y][z - 1] == 0,
            3 => x != 0 and self.chunk[x - 1][y][z] == 0,
            4 => y != CHUNK - 1 and self.chunk[x][y + 1][z] == 0,
            5 => y != 0 and self.chunk[x][y - 1][z] == 0,
            else => 0,
        };
    }
    inline fn tile(self: *@This(), x: u8, y: u8, z: u8, faces: [CHUNK][CHUNK][CHUNK]FaceFlags, face: comptime_int, t: u8) bool {
        return !faces[x][y][z].isSet(face) and self.isVisible(face, x, y, z) and self.chunk[x][y][z] == t;
    }
    fn stripX(self: *@This(), x: u8, y: u8, z: u8, len: u8, faces: [CHUNK][CHUNK][CHUNK]FaceFlags, face: comptime_int, t: u8) bool {
        var i: u8 = 0;
        while (i < len and self.tile(x + i, y, z, faces, face, t)) : (i += 1) {}
        return i == len;
    }
    fn stripY(self: *@This(), x: u8, y: u8, z: u8, len: u8, faces: [CHUNK][CHUNK][CHUNK]FaceFlags, face: comptime_int, t: u8) bool {
        var i: u8 = 0;
        while (i < len and self.tile(x, y + i, z, faces, face, t)) : (i += 1) {}
        return i == len;
    }
    pub fn meshifyChunk(self: *@This()) void {
        var meshed_faces: [CHUNK][CHUNK][CHUNK]FaceFlags = undefined;
        @memset(@as(*[CHUNK_SZ]u8, @ptrCast(&meshed_faces)), 0);
        for (self.chunk, 0..CHUNK) |slice, usx| {
            const x: u8 = @truncate(usx);
            for (slice, 0..CHUNK) |strip, usy| {
                const y: u8 = @truncate(usy);
                for (strip, 0..CHUNK) |box, usz| {
                    const z: u8 = @truncate(usz);
                    if (box == 0) continue;
                    inline for (0..6) |i| {
                        const face: u8 = @truncate(i);
                        if (!meshed_faces[x][y][z].isSet(face) and self.isVisible(face, x, y, z)) {
                            var n: u8 = 0;
                            var m: u8 = 1;
                            self.faces.append(malloc, .{
                                .positions = switch (face) {
                                    inline 0, 2 => |comp_face| blk: {
                                        while (x + n < CHUNK and self.tile(x + n, y, z, meshed_faces, comp_face, box)) : (n += 1)
                                            meshed_faces[x + n][y][z].set(comp_face);
                                        while (y + m < CHUNK and self.stripX(x, y + m, z, n, meshed_faces, comp_face, box)) : (m += 1) {
                                            for (0..n) |j|
                                                meshed_faces[x + j][y + m][z].set(comp_face);
                                        }
                                        break :blk [3]i32{ x + if (comp_face == 2) n else 0, y, @as(i32, z) - @intFromBool(comp_face == 2) };
                                    },
                                    inline 1, 3 => |comp_face| blk: {
                                        while (y + n < CHUNK and self.tile(x, y + n, z, meshed_faces, comp_face, box)) : (n += 1)
                                            meshed_faces[x][y + n][z].set(comp_face);
                                        while (z + m < CHUNK and self.stripY(x, y, z + m, n, meshed_faces, comp_face, box)) : (m += 1) {
                                            for (0..n) |j|
                                                meshed_faces[x][y + j][z + m].set(comp_face);
                                        }
                                        break :blk [3]i32{ x + @intFromBool(comp_face == 1), y, @as(i32, z) - 1 + if (comp_face == 1) m else 0 };
                                    },
                                    inline 4, 5 => |comp_face| blk: {
                                        while (x + n < CHUNK and self.tile(x + n, y, z, meshed_faces, comp_face, box)) : (n += 1)
                                            meshed_faces[x + n][y][z].set(comp_face);
                                        while (z + m < CHUNK and self.stripX(x, y, z + m, n, meshed_faces, comp_face, box)) : (m += 1) {
                                            for (0..n) |j|
                                                meshed_faces[x + j][y][z + m].set(comp_face);
                                        }
                                        break :blk [3]i32{ x, y + @intFromBool(comp_face == 4), @as(i32, z) - 1 + if (comp_face == 4) m else 0 };
                                    },
                                    else => unreachable,
                                },
                                .spans = if (face == 1 or face == 3) [2]u8{ m, n } else [2]u8{ n, m },
                                .dir = face,
                                .texture = box - 1,
                            }) catch @panic("Allocation failed; shit!");
                        }
                    }
                }
            }
        }
    }
};
