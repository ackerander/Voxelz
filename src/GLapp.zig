const std = @import("std");
const malloc = std.heap.c_allocator;
const math = @import("math.zig");
const Game = @import("game.zig").Game;
const gl = @cImport({
    @cInclude("glad/gl.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("loadPng.h");
});

const SCREEN = .{ .w = 1400, .h = 1050 };
const CHUNK = 32;
const CHUNK_SZ = CHUNK * CHUNK * CHUNK;
const MAXMESH = 3 * CHUNK_SZ / 4;

const GLerror = error{
    GLFWinitErr,
    WindowErr,
    GLADinitErr,
    ShaderErr,
    TexLoadErr,
};

pub const GLapp = struct {
    window: *gl.GLFWwindow,
    vert_arr_id: gl.GLuint,
    prog_id: gl.GLuint,
    matrix_id: gl.GLint,
    tex: gl.GLuint,
    vert_buff: gl.GLuint,
    offset_buff: gl.GLuint,
    span_buff: gl.GLuint,
    face_buff: gl.GLuint,
    tex_buff: gl.GLuint,
    view_mat: math.Mat4,
    draw_dist: u8,

    game: Game,

    pub fn init() !@This() {
        var app: @This() = undefined;

        app.game = try Game.newGame();
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
        app.window = gl.glfwCreateWindow(SCREEN.w, SCREEN.h, "GLFW Zig", null, null) orelse {
            std.debug.print("GLFW couldn't open window\n", .{});
            return GLerror.WindowErr;
        };
        errdefer gl.glfwDestroyWindow(app.window);
        gl.glfwMakeContextCurrent(app.window);

        gl.glfwSetInputMode(app.window, gl.GLFW_CURSOR, gl.GLFW_CURSOR_DISABLED);
        gl.glfwSetCursorPos(app.window, SCREEN.w / 2, SCREEN.h / 2);
        // TODO: handle inputs
        // gl.glfwSetKeyCallback(app.window, handleKey);
        // gl.glfwSetCursorPosCallback(app.window, handleMouse);

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

        gl.glGenVertexArrays(1, &app.vert_arr_id);
        errdefer gl.glDeleteVertexArrays(1, &app.vert_arr_id);
        gl.glBindVertexArray(app.vert_arr_id);

        app.prog_id = try loadShaders();
        errdefer gl.glDeleteProgram(app.prog_id);
        app.matrix_id = gl.glGetUniformLocation(app.prog_id, "MVP");

        // Load texture atlas
        app.tex = try loadTex();
        if (app.tex == 0) return GLerror.TexLoadErr;
        errdefer gl.glDeleteTextures(1, &app.tex);
        const tex_id = gl.glGetUniformLocation(app.prog_id, "myTextureSampler");

        // Allocate buffers
        const vert_data = [4]gl.GLubyte{ 0, 1, 2, 3 };
        gl.glGenBuffers(1, @constCast(&app.vert_buff));
        errdefer gl.glDeleteBuffers(1, &app.vert_buff);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, app.vert_buff);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, vert_data.len, &vert_data, gl.GL_STATIC_DRAW);

        app.draw_dist = 9;
        const max_faces = MAXMESH * math.cube(u32, app.draw_dist - 2);
        // TODO: Sparse buffers, allowing for less memory usage
        // (registry.khronos.org/OpenGL/extensions/ARB/ARB_sparse_buffer.txt)
        gl.glGenBuffers(1, @constCast(&app.offset_buff));
        errdefer gl.glDeleteBuffers(1, &app.offset_buff);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, app.offset_buff);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, 3 * max_faces * @sizeOf(gl.GLint), null, gl.GL_STATIC_DRAW);
        gl.glVertexAttribDivisor(1, 1);

        gl.glGenBuffers(1, @constCast(&app.span_buff));
        errdefer gl.glDeleteBuffers(1, &app.span_buff);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, app.span_buff);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, 2 * max_faces * @sizeOf(gl.GLint), null, gl.GL_DYNAMIC_DRAW);
        gl.glVertexAttribDivisor(2, 1);

        gl.glGenBuffers(1, @constCast(&app.face_buff));
        errdefer gl.glDeleteBuffers(1, &app.face_buff);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, app.face_buff);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, max_faces, null, gl.GL_DYNAMIC_DRAW);
        gl.glVertexAttribDivisor(3, 1);

        gl.glGenBuffers(1, @constCast(&app.tex_buff));
        errdefer gl.glDeleteBuffers(1, &app.tex_buff);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, app.tex_buff);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, max_faces, null, gl.GL_DYNAMIC_DRAW);
        gl.glVertexAttribDivisor(4, 1);

        // Texture
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, app.tex);
        gl.glUniform1i(tex_id, 0);

        gl.glUseProgram(app.prog_id);
        gl.glEnableVertexAttribArray(0);
        errdefer gl.glDisableVertexAttribArray(0);
        gl.glEnableVertexAttribArray(1);
        errdefer gl.glDisableVertexAttribArray(1);
        gl.glEnableVertexAttribArray(2);
        errdefer gl.glDisableVertexAttribArray(2);
        gl.glEnableVertexAttribArray(3);
        errdefer gl.glDisableVertexAttribArray(3);
        gl.glEnableVertexAttribArray(4);
        errdefer gl.glDisableVertexAttribArray(4);

        return app;
    }

    pub fn deinit(self: *@This()) void {
        self.game.quitGame();
        gl.glDisableVertexAttribArray(4);
        gl.glDisableVertexAttribArray(3);
        gl.glDisableVertexAttribArray(2);
        gl.glDisableVertexAttribArray(1);
        gl.glDisableVertexAttribArray(0);
        gl.glDeleteBuffers(1, &self.tex_buff);
        gl.glDeleteBuffers(1, &self.face_buff);
        gl.glDeleteBuffers(1, &self.span_buff);
        gl.glDeleteBuffers(1, &self.offset_buff);
        gl.glDeleteBuffers(1, &self.vert_buff);
        gl.glDeleteTextures(1, &self.tex);
        gl.glDeleteProgram(self.prog_id);
        gl.glDeleteVertexArrays(1, &self.vert_arr_id);
        gl.glfwDestroyWindow(self.window);
        gl.glfwTerminate();
    }

    pub fn mainLoop(self: *@This()) void {
        const perspec_mat: math.Mat4 = math.perspec(0.25 * std.math.pi, 4.0 / 3.0, 0.1, 100);

        self.writeMeshes();

        const h_angle = 0.9;
        const v_angle = 0.6;
        const dir = math.Vec3{ @cos(v_angle) * @sin(h_angle), @sin(v_angle), @cos(v_angle) * @cos(h_angle) };
        const up = math.cross(math.Vec3{ @sin(h_angle - 0.5 * std.math.pi), 0, @cos(h_angle - 0.5 * std.math.pi) }, dir);
        const position: math.Vec3 = @splat(-5);
        self.view_mat = math.lookAt(position, position + dir, up);
        const mvp = math.mul(perspec_mat, self.view_mat);

        while (gl.glfwWindowShouldClose(self.window) == 0) {
            gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

            // self.updateView();

            gl.glUniformMatrix4fv(self.matrix_id, 1, gl.GL_TRUE, @ptrCast(&mvp));

            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vert_buff);
            gl.glVertexAttribIPointer(0, 1, gl.GL_UNSIGNED_BYTE, 0, null);

            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.offset_buff);
            gl.glVertexAttribIPointer(1, 3, gl.GL_INT, 0, null);

            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.span_buff);
            gl.glVertexAttribIPointer(2, 2, gl.GL_UNSIGNED_BYTE, 0, null);

            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.face_buff);
            gl.glVertexAttribIPointer(3, 1, gl.GL_UNSIGNED_BYTE, 0, null);

            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.tex_buff);
            gl.glVertexAttribIPointer(4, 1, gl.GL_UNSIGNED_BYTE, 0, null);

            const size: i32 = @intCast(self.game.faces.len);
            gl.glDrawArraysInstanced(gl.GL_TRIANGLE_STRIP, 0, 4, size);
            gl.glfwSwapBuffers(self.window);

            gl.glfwPollEvents();
        }
    }

    fn writeMeshes(self: *@This()) void {
        const faces = self.game.faces;
        const size: isize = @intCast(faces.len);
        const ptrs = faces.slice();
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.offset_buff);
        gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, 3 * size * @sizeOf(i32), @ptrCast(ptrs.items(.positions)));
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.span_buff);
        gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, 2 * size, @ptrCast(ptrs.items(.spans)));
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.face_buff);
        gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, size, @ptrCast(ptrs.items(.dir)));
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.tex_buff);
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
        const prog_id = gl.glCreateProgram();
        gl.glAttachShader(prog_id, vert_shader_id);
        defer gl.glDetachShader(prog_id, vert_shader_id);
        gl.glAttachShader(prog_id, frag_shader_id);
        defer gl.glDetachShader(prog_id, frag_shader_id);
        gl.glLinkProgram(prog_id);

        // Check program
        gl.glGetProgramiv(prog_id, gl.GL_LINK_STATUS, &iv_result);
        if (iv_result == gl.GL_FALSE) {
            gl.glGetProgramiv(prog_id, gl.GL_INFO_LOG_LENGTH, &iv_result);
            if (iv_result > 0) {
                const err_log = try malloc.alloc(u8, @intCast(iv_result + 1));
                defer malloc.free(err_log);
                gl.glGetProgramInfoLog(prog_id, iv_result, 0, @ptrCast(err_log));
                std.debug.print("Error in program: {s}\n", .{err_log});
                return GLerror.ShaderErr;
            }
        }
        return prog_id;
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
};
