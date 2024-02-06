const GLapp = @import("GLapp.zig");

pub fn main() !void {
    try GLapp.init();
    GLapp.mainLoop();
    GLapp.deinit();
}
