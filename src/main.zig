const GLapp = @import("GLapp.zig").GLapp;

pub fn main() !void {
    var app = try GLapp.init();
    app.mainLoop();
    app.deinit();
}
