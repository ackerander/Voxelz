const std = @import("std");
pub fn sqr(comptime T: type, x: anytype) T {
    if (@typeInfo(T).Int.bits < 2 * @typeInfo(@TypeOf(x)).Int.bits)
        @compileError("Type must be 2x as wide to fit square.");
    return @as(T, x) * x;
}
pub fn cube(comptime T: type, x: anytype) T {
    if (@typeInfo(T).Int.bits < 3 * @typeInfo(@TypeOf(x)).Int.bits)
        @compileError("Type must be 3x as wide to fit cube.");
    return @as(T, x) * x * x;
}

pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);
pub const Mat4 = [4]Vec4;
pub fn zero(comptime T: type) T {
    if (T == Vec4 or T == Vec3) {
        return @splat(0);
    } else if (T == Mat4) {
        return Mat4{ @splat(0), @splat(0), @splat(0), @splat(0) };
    } else {
        @compileError("Only Vec3, Vec4 or Mat4");
    }
}

pub inline fn swizzle(comptime T: type, v: T, select: [@typeInfo(T).Vector.len]comptime_int) T {
    return @shuffle(@typeInfo(T).Vector.child, v, undefined, select);
}
pub fn magnitude(v: anytype) f32 {
    return @sqrt(dot(v, v));
}
pub fn normalize(v: anytype) @TypeOf(v) {
    return v * @as(@TypeOf(v), @splat(1 / magnitude(v)));
}
pub fn dot(a: anytype, b: anytype) @typeInfo(@TypeOf(a)).Vector.child {
    return @reduce(.Add, a * b);
}
pub fn cross(a: Vec3, b: Vec3) Vec3 {
    var out = -swizzle(Vec3, a, [3]comptime_int{ 2, 0, 1 }) * swizzle(Vec3, b, [3]comptime_int{ 1, 2, 0 });
    const part1 = swizzle(Vec3, a, [3]comptime_int{ 1, 2, 0 });
    const part2 = swizzle(Vec3, b, [3]comptime_int{ 2, 0, 1 });
    out = @mulAdd(Vec3, part1, part2, out);
    return out;
}

pub fn mul(a: anytype, b: anytype) @TypeOf(b) {
    const Type_a = @TypeOf(a);
    const Type_b = @TypeOf(b);
    return switch (Type_b) {
        Mat4 => switch (Type_a) {
            Mat4 => mul_mm(a, b),
            f32 => mul_sm(a, b),
            else => @compileError("Unsupported operands"),
        },
        Vec4, Vec3 => switch (Type_a) {
            Mat4 => mul_mv(a, b),
            f32 => @as(Type_b, @splat(a)) * b,
            else => @compileError("Unsupported operands"),
        },
        else => @compileError("Unsupported operands"),
    };
}
fn mul_mm(a: Mat4, b: Mat4) Mat4 {
    var out: Mat4 = undefined;
    inline for (0..4) |i| {
        const x = swizzle(Vec4, a[i], [4]comptime_int{ 0, 0, 0, 0 });
        const y = swizzle(Vec4, a[i], [4]comptime_int{ 1, 1, 1, 1 });
        const z = swizzle(Vec4, a[i], [4]comptime_int{ 2, 2, 2, 2 });
        const w = swizzle(Vec4, a[i], [4]comptime_int{ 3, 3, 3, 3 });
        out[i] = @mulAdd(Vec4, x, b[0], z * b[2]) + @mulAdd(Vec4, y, b[1], w * b[3]);
    }
    return out;
}
fn mul_mv(m: Mat4, v: Vec4) Vec4 {
    return .{ dot(m[0], v), dot(m[1], v), dot(m[2], v), dot(m[3], v) };
}
fn mul_sm(s: f32, m: Mat4) Mat4 {
    const sv: Vec4 = @splat(s);
    return .{ sv * m[0], sv * m[1], sv * m[2], sv * m[3] };
}

pub fn perspec(angle: f32, r: f32, near: f32, far: f32) Mat4 {
    var out = zero(Mat4);
    const a = @tan(angle / 2);
    out[0][0] = 1 / (r * a);
    out[1][1] = 1 / a;
    out[2][2] = (near + far) / (near - far);
    out[2][3] = 2 * near * far / (near - far);
    out[3][2] = -1;
    return out;
}

fn extend(from: Vec3, last: f32) Vec4 {
    return @shuffle(f32, from, @Vector(1, f32){last}, @Vector(4, i32){ 0, 1, 2, -1 });
}
pub fn lookAt(eye: Vec3, center: Vec3, up: Vec3) Mat4 {
    const f = normalize(eye - center);
    const s = normalize(cross(up, f));
    const u = cross(f, s);
    return Mat4{ extend(s, -dot(s, eye)), extend(u, -dot(u, eye)), extend(f, -dot(f, eye)), Vec4{ 0, 0, 0, 1 } };
}

test "matrix mul" {
    const a = Mat4{ Vec4{ 0, -6, -3, -12 }, Vec4{ 2, 13, -6, -19 }, Vec4{ 1, 15, 8, -10 }, Vec4{ 6, 10, -17, 8 } };
    const b = Mat4{ Vec4{ 15, -1, 13, -19 }, Vec4{ 4, -11, 4, -18 }, Vec4{ -1, 3, 15, -2 }, Vec4{ 6, 17, 15, 18 } };
    const actual = Mat4{ Vec4{ -93, -147, -249, -102 }, Vec4{ -26, -486, -297, -602 }, Vec4{ 7, -312, 43, -485 }, Vec4{ 195, -31, -17, -116 } };
    try std.testing.expect(std.meta.eql(mul(a, b), actual));
}
test "perspective matrix" {}
