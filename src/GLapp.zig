const std = @import("std");
const malloc = std.heap.c_allocator;
const math = @import("math.zig");
const game = @import("game.zig");
const gl = @cImport({
    @cInclude("glad/gl.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("loadPng.h");
});

const SCREEN = .{ .w = 1400, .h = 1050 };

const GLerror = error{
    GLFWinitErr,
    WindowErr,
    GLADinitErr,
    ShaderErr,
    TexLoadErr,
};

const GLinfo = struct {
    window: *gl.GLFWwindow,
    vert_arr_id: gl.GLuint,
    prog_id: gl.GLuint,
    matrix_id: gl.GLint,
    texture: gl.GLuint,
    vert_buff: gl.GLuint,
    offset_buff: gl.GLuint,
    span_buff: gl.GLuint,
    face_buff: gl.GLuint,
    tex_buff: gl.GLuint,
    draw_dist: u8,
};
const Camera = struct {
    position: math.Vec3,
    theta: f32,
    rho: f32,
    cursor: [2]f64 = [2]f64{ 0.5 * SCREEN.w, 0.5 * SCREEN.h },
};

var gl_info: GLinfo = undefined;
var camera: Camera = undefined;
var game_data: game.Game = undefined;

pub fn init(draw_dist: u8) !void {
    game_data = try game.Game.newGame();
    // GLFW setup
    if (gl.glfwInit() == 0) {
        std.debug.print("GLFW couldn't initalize\n", .{});
        return GLerror.GLFWinitErr;
    }
    errdefer gl.glfwTerminate();

    gl.glfwWindowHint(gl.GLFW_RESIZABLE, gl.GLFW_FALSE);
    gl.glfwWindowHint(gl.GLFW_SAMPLES, 4); // 4x antialiasing
    gl.glfwWindowHint(gl.GLFW_CONTEXT_VERSION_MAJOR, 3);
    gl.glfwWindowHint(gl.GLFW_CONTEXT_VERSION_MINOR, 3);
    // We don't want the old OpenGL
    gl.glfwWindowHint(gl.GLFW_OPENGL_PROFILE, gl.GLFW_OPENGL_CORE_PROFILE);
    // To make MacOS happy (not needed)
    gl.glfwWindowHint(gl.GLFW_OPENGL_FORWARD_COMPAT, gl.GL_TRUE);
    gl_info.window = gl.glfwCreateWindow(SCREEN.w, SCREEN.h, "GLFW Zig", null, null) orelse {
        std.debug.print("GLFW couldn't open window\n", .{});
        return GLerror.WindowErr;
    };
    errdefer gl.glfwDestroyWindow(gl_info.window);
    gl.glfwMakeContextCurrent(gl_info.window);

    gl.glfwSetInputMode(gl_info.window, gl.GLFW_CURSOR, gl.GLFW_CURSOR_DISABLED);
    gl.glfwSetCursorPos(gl_info.window, SCREEN.w / 2, SCREEN.h / 2);
    _ = gl.glfwSetKeyCallback(gl_info.window, handleKey);
    _ = gl.glfwSetCursorPosCallback(gl_info.window, handleMouse);

    // GLAD setup
    if (gl.gladLoadGL(@ptrCast(&gl.glfwGetProcAddress)) == 0) {
        std.debug.print("GLAD couldn't initalize\n", .{});
        return GLerror.GLADinitErr;
    }

    // OpenGL setup
    gl.glClearColor(0.3, 0.8, 1, 0);
    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glDepthFunc(gl.GL_LESS);
    gl.glEnable(gl.GL_CULL_FACE);

    gl.glGenVertexArrays(1, &gl_info.vert_arr_id);
    errdefer gl.glDeleteVertexArrays(1, &gl_info.vert_arr_id);
    gl.glBindVertexArray(gl_info.vert_arr_id);

    gl_info.prog_id = try loadShaders();
    errdefer gl.glDeleteProgram(gl_info.prog_id);
    gl_info.matrix_id = gl.glGetUniformLocation(gl_info.prog_id, "MVP");

    // TODO: OpenGL error handling
    // Load texture atlas
    gl_info.texture = try loadTex();
    if (gl_info.texture == 0) return GLerror.TexLoadErr;
    // errdefer gl.glDeleteTextures(1, &gl_info.texture);
    const tex_id = gl.glGetUniformLocation(gl_info.prog_id, "myTextureSampler");

    // Allocate buffers
    const vert_data = [4]gl.GLubyte{ 0, 1, 2, 3 };
    gl.glGenBuffers(1, @constCast(&gl_info.vert_buff));
    // errdefer gl.glDeleteBuffers(1, &gl_info.vert_buff);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.vert_buff);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, vert_data.len, &vert_data, gl.GL_STATIC_DRAW);

    gl_info.draw_dist = draw_dist;
    const max_faces = game.MAXMESH * math.cube(u32, gl_info.draw_dist - 2);
    // TODO: Sparse buffers, allowing for less memory usage
    // (registry.khronos.org/OpenGL/extensions/ARB/ARB_sparse_buffer.txt)
    gl.glGenBuffers(1, @constCast(&gl_info.offset_buff));
    // errdefer gl.glDeleteBuffers(1, &gl_info.offset_buff);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.offset_buff);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, 3 * max_faces * @sizeOf(gl.GLint), null, gl.GL_STATIC_DRAW);
    gl.glVertexAttribDivisor(1, 1);

    gl.glGenBuffers(1, @constCast(&gl_info.span_buff));
    // errdefer gl.glDeleteBuffers(1, &gl_info.span_buff);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.span_buff);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, 2 * max_faces * @sizeOf(gl.GLint), null, gl.GL_DYNAMIC_DRAW);
    gl.glVertexAttribDivisor(2, 1);

    gl.glGenBuffers(1, @constCast(&gl_info.face_buff));
    // errdefer gl.glDeleteBuffers(1, &gl_info.face_buff);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.face_buff);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, max_faces, null, gl.GL_DYNAMIC_DRAW);
    gl.glVertexAttribDivisor(3, 1);

    gl.glGenBuffers(1, @constCast(&gl_info.tex_buff));
    // errdefer gl.glDeleteBuffers(1, &gl_info.tex_buff);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.tex_buff);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, max_faces, null, gl.GL_DYNAMIC_DRAW);
    gl.glVertexAttribDivisor(4, 1);

    // Texture
    gl.glActiveTexture(gl.GL_TEXTURE0);
    gl.glBindTexture(gl.GL_TEXTURE_2D, gl_info.texture);
    gl.glUniform1i(tex_id, 0);

    gl.glUseProgram(gl_info.prog_id);
    gl.glEnableVertexAttribArray(0);
    // errdefer gl.glDisableVertexAttribArray(0);
    gl.glEnableVertexAttribArray(1);
    // errdefer gl.glDisableVertexAttribArray(1);
    gl.glEnableVertexAttribArray(2);
    // errdefer gl.glDisableVertexAttribArray(2);
    gl.glEnableVertexAttribArray(3);
    // errdefer gl.glDisableVertexAttribArray(3);
    gl.glEnableVertexAttribArray(4);
    // errdefer gl.glDisableVertexAttribArray(4);

    // Init camera
    camera = Camera{ .position = @splat(-5), .theta = 0.9, .rho = 0.6 };
}

pub fn deinit() void {
    game_data.quitGame();
    gl.glDisableVertexAttribArray(4);
    gl.glDisableVertexAttribArray(3);
    gl.glDisableVertexAttribArray(2);
    gl.glDisableVertexAttribArray(1);
    gl.glDisableVertexAttribArray(0);
    gl.glDeleteBuffers(1, &gl_info.tex_buff);
    gl.glDeleteBuffers(1, &gl_info.face_buff);
    gl.glDeleteBuffers(1, &gl_info.span_buff);
    gl.glDeleteBuffers(1, &gl_info.offset_buff);
    gl.glDeleteBuffers(1, &gl_info.vert_buff);
    gl.glDeleteTextures(1, &gl_info.texture);
    gl.glDeleteProgram(gl_info.prog_id);
    gl.glDeleteVertexArrays(1, &gl_info.vert_arr_id);
    gl.glfwDestroyWindow(gl_info.window);
    gl.glfwTerminate();
}

pub fn mainLoop() void {
    const perspec_mat: math.Mat4 = math.perspec(0.25 * std.math.pi, 4.0 / 3.0, 0.1, 100);

    writeMeshes();
    const size = game_data.faces.len;

    var last_t = gl.glfwGetTime();

    while (gl.glfwWindowShouldClose(gl_info.window) == 0) {
        const new_t = gl.glfwGetTime();
        const view_mat = updateView(@floatCast(new_t - last_t));
        const mvp = math.mul(perspec_mat, view_mat);

        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
        gl.glUniformMatrix4fv(gl_info.matrix_id, 1, gl.GL_TRUE, @ptrCast(&mvp));

        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.vert_buff);
        gl.glVertexAttribIPointer(0, 1, gl.GL_UNSIGNED_BYTE, 0, null);

        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.offset_buff);
        gl.glVertexAttribIPointer(1, 3, gl.GL_INT, 0, null);

        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.span_buff);
        gl.glVertexAttribIPointer(2, 2, gl.GL_UNSIGNED_BYTE, 0, null);

        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.face_buff);
        gl.glVertexAttribIPointer(3, 1, gl.GL_UNSIGNED_BYTE, 0, null);

        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.tex_buff);
        gl.glVertexAttribIPointer(4, 1, gl.GL_UNSIGNED_BYTE, 0, null);

        gl.glDrawArraysInstanced(gl.GL_TRIANGLE_STRIP, 0, 4, @intCast(size));
        gl.glfwSwapBuffers(gl_info.window);

        gl.glfwPollEvents();
        last_t = new_t;
    }
}

// Internal functions
fn writeMeshes() void {
    const faces = game_data.faces;
    const size: isize = @intCast(faces.len);
    const ptrs = faces.slice();
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.offset_buff);
    gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, 3 * size * @sizeOf(i32), @ptrCast(ptrs.items(.positions)));
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.span_buff);
    gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, 2 * size, @ptrCast(ptrs.items(.spans)));
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.face_buff);
    gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, size, @ptrCast(ptrs.items(.dir)));
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, gl_info.tex_buff);
    gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, size, @ptrCast(ptrs.items(.texture)));
}

fn loadShaders() !gl.GLuint {
    const vert_code = @embedFile("shaders/vert");
    const frag_code = @embedFile("shaders/frag");
    var iv_result: gl.GLint = undefined;

    // Compile vert shader
    const vert_shader_id = gl.glCreateShader(gl.GL_VERTEX_SHADER);
    defer gl.glDeleteShader(vert_shader_id);
    gl.glShaderSource(vert_shader_id, 1, @ptrCast(&vert_code), 0);
    gl.glCompileShader(vert_shader_id);
    gl.glGetShaderiv(vert_shader_id, gl.GL_COMPILE_STATUS, &iv_result);
    if (iv_result == gl.GL_FALSE) {
        gl.glGetShaderiv(vert_shader_id, gl.GL_INFO_LOG_LENGTH, &iv_result);
        if (iv_result > 0) {
            const err_log = try malloc.alloc(u8, @intCast(iv_result + 1));
            defer malloc.free(err_log);
            gl.glGetShaderInfoLog(vert_shader_id, iv_result, 0, @ptrCast(err_log));
            std.debug.print("Error in vert: {s}\n", .{err_log});
            return GLerror.ShaderErr;
        }
    }

    // Compile frag shader
    const frag_shader_id = gl.glCreateShader(gl.GL_FRAGMENT_SHADER);
    defer gl.glDeleteShader(frag_shader_id);
    gl.glShaderSource(frag_shader_id, 1, @ptrCast(&frag_code), 0);
    gl.glCompileShader(frag_shader_id);
    gl.glGetShaderiv(frag_shader_id, gl.GL_COMPILE_STATUS, &iv_result);
    if (iv_result == gl.GL_FALSE) {
        gl.glGetShaderiv(frag_shader_id, gl.GL_INFO_LOG_LENGTH, &iv_result);
        if (iv_result > 0) {
            const err_log = try malloc.alloc(u8, @intCast(iv_result + 1));
            defer malloc.free(err_log);
            gl.glGetShaderInfoLog(frag_shader_id, iv_result, 0, @ptrCast(err_log));
            std.debug.print("Error in frag: {s}\n", .{err_log});
            return GLerror.ShaderErr;
        }
    }

    // Link program
    const program = gl.glCreateProgram();
    gl.glAttachShader(program, vert_shader_id);
    defer gl.glDetachShader(program, vert_shader_id);
    gl.glAttachShader(program, frag_shader_id);
    defer gl.glDetachShader(program, frag_shader_id);
    gl.glLinkProgram(program);

    // Check program
    gl.glGetProgramiv(program, gl.GL_LINK_STATUS, &iv_result);
    if (iv_result == gl.GL_FALSE) {
        gl.glGetProgramiv(program, gl.GL_INFO_LOG_LENGTH, &iv_result);
        if (iv_result > 0) {
            const err_log = try malloc.alloc(u8, @intCast(iv_result + 1));
            defer malloc.free(err_log);
            gl.glGetProgramInfoLog(program, iv_result, 0, @ptrCast(err_log));
            std.debug.print("Error in program: {s}\n", .{err_log});
            return GLerror.ShaderErr;
        }
    }
    return program;
}

fn loadTex() !gl.GLuint {
    var width: u32 = undefined;
    var height: u32 = undefined;
    const data = gl.loadPng(@ptrCast(&width), @ptrCast(&height)) orelse return GLerror.TexLoadErr;
    var tex: gl.GLuint = undefined;
    gl.glGenTextures(1, &tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGB, @intCast(width), @intCast(height), 0, gl.GL_RGB, gl.GL_UNSIGNED_BYTE, data);
    std.c.free(data);

    //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
    return tex;
}

fn handleMouse(win: ?*gl.GLFWwindow, xpos: f64, ypos: f64) callconv(.C) void {
    _ = win;
    const MOUSESPD = 5e-4;

    camera.theta += @floatCast(MOUSESPD * (camera.cursor[0] - xpos));
    camera.rho += @floatCast(MOUSESPD * (camera.cursor[1] - ypos));
    camera.cursor = [2]f64{ xpos, ypos };
}
const KeyStates = std.bit_set.IntegerBitSet(6);
var key_states = KeyStates.initEmpty();
fn handleKey(win: ?*gl.GLFWwindow, key: i32, scancode: i32, action: i32, mods: i32) callconv(.C) void {
    _ = mods;
    _ = scancode;
    _ = win;
    if (action == gl.GLFW_PRESS or action == gl.GLFW_RELEASE) {
        const idx: u8 = switch (key) {
            gl.GLFW_KEY_A => 0,
            gl.GLFW_KEY_D => 1,
            gl.GLFW_KEY_S => 2,
            gl.GLFW_KEY_W => 3,
            gl.GLFW_KEY_LEFT_CONTROL => 4,
            gl.GLFW_KEY_LEFT_SHIFT => 5,
            else => return,
        };
        key_states.setValue(idx, action == gl.GLFW_PRESS);
    }
}
// TODO: better timer
fn updateView(delta_t: f32) math.Mat4 {
    const dir = math.Vec3{ @cos(camera.rho) * @sin(camera.theta), @sin(camera.rho), @cos(camera.rho) * @cos(camera.theta) };
    const right = math.Vec3{ @sin(camera.theta - 0.5 * std.math.pi), 0, @cos(camera.theta - 0.5 * std.math.pi) };
    const up = math.cross(right, dir);
    const displacement = @as(math.Vec3, @splat(getAxis(0))) * right + @as(math.Vec3, @splat(getAxis(1))) * dir + @as(math.Vec3, @splat(getAxis(2))) * up;
    camera.position += @as(math.Vec3, @splat(4 * delta_t)) * displacement;

    return math.lookAt(camera.position, camera.position + dir, up);
}
fn getAxis(axis: u3) f32 {
    return switch ((key_states.mask >> (2 * axis)) & 0b11) {
        0 => 0,
        1 => -1,
        2 => 1,
        3 => 0,
        else => unreachable,
    };
}
