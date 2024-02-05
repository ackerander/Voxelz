const std = @import("std");
const malloc = std.heap.c_allocator;

pub const Game = struct {
    pub const Face = struct {
        positions: [3]i32,
        spans: @Vector(2, u8),
        dir: u8,
        texture: u8,
    };
    faces: std.MultiArrayList(Face),
    pub fn newGame() !@This() {
        var game: @This() = .{
            .faces = std.MultiArrayList(Face){},
        };
        try game.faces.ensureTotalCapacity(malloc, 6);
        game.faces.appendAssumeCapacity(.{
            .positions = [3]i32{ 0, 0, 0 },
            .spans = @Vector(2, u8){ 1, 1 },
            .dir = 0,
            .texture = 0,
        });
        game.faces.appendAssumeCapacity(.{
            .positions = [3]i32{ 1, 0, 0 },
            .spans = @Vector(2, u8){ 1, 1 },
            .dir = 1,
            .texture = 0,
        });
        game.faces.appendAssumeCapacity(.{
            .positions = [3]i32{ 1, 0, -1 },
            .spans = @Vector(2, u8){ 1, 1 },
            .dir = 2,
            .texture = 0,
        });
        game.faces.appendAssumeCapacity(.{
            .positions = [3]i32{ 0, 0, -1 },
            .spans = @Vector(2, u8){ 1, 1 },
            .dir = 3,
            .texture = 0,
        });
        game.faces.appendAssumeCapacity(.{
            .positions = [3]i32{ 0, 1, 0 },
            .spans = @Vector(2, u8){ 1, 1 },
            .dir = 4,
            .texture = 0,
        });
        game.faces.appendAssumeCapacity(.{
            .positions = [3]i32{ 0, 0, -1 },
            .spans = @Vector(2, u8){ 1, 1 },
            .dir = 5,
            .texture = 0,
        });
        return game;
    }
    pub fn quitGame(self: *@This()) void {
        self.faces.deinit(malloc);
    }
};
