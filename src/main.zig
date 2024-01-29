const std = @import("std");
const glfw = @cImport({
    @cInclude("GLFW/glfw3.h");
});

const GLFWerror = error{
    Init,
    Window,
};

pub fn main() !void {
    if (glfw.glfwInit() == 0) {
        std.debug.print("GLFW couldn't initalize\n", .{});
        return GLFWerror.Init;
    }
    defer glfw.glfwTerminate();

    glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, glfw.GLFW_FALSE);
    glfw.glfwWindowHint(glfw.GLFW_SAMPLES, 4); // 4x antialiasing
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3); // We want OpenGL 3.3
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_FORWARD_COMPAT, glfw.GL_TRUE); // To make MacOS happy (not needed)
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE); // We don't want the old OpenGL
    const window = glfw.glfwCreateWindow(640, 480, "GLFW Zig", null, null) orelse {
        std.debug.print("GLFW couldn't open window\n", .{});
        return GLFWerror.Window;
    };
    defer glfw.glfwDestroyWindow(window);
    glfw.glfwMakeContextCurrent(window);

    while (glfw.glfwWindowShouldClose(window) == 0) {
        glfw.glfwPollEvents();
    }
}
