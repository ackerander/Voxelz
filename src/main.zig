const GLapp = @import("GLapp.zig");

pub fn main() !void {
    try GLapp.init(9);
    GLapp.mainLoop();
    GLapp.deinit();
}
