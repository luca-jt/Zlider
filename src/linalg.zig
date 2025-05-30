const std = @import("std");

// This is heavily inspired by https://github.com/ziglibs/zlm. I made slight modifications and added compatibility fixes for Zig version 0.14.1 (e.g. matrices are column major).

pub usingnamespace LinAlgTypes(f32);

pub fn LinAlgTypes(comptime T: type) type {
    return struct {
        fn SwizzleType(comptime i: usize) type {
            return switch (i) {
                1 => T,
                2 => Vec2,
                3 => Vec3,
                4 => Vec4,
                else => @compileError("Swizzle is only available for up to 4 elements."),
            };
        }

        fn VectorFunctions(comptime Self: type) type {
            return struct {
                pub fn fromElement(value: T) Self {
                    var result: Self = undefined;
                    inline for (@typeInfo(Self).@"struct".fields) |field| {
                        @field(result, field.name) = value;
                    }
                    return result;
                }

                pub fn add(a: Self, b: Self) Self {
                    var result: Self = undefined;
                    inline for (@typeInfo(Self).@"struct".fields) |field| {
                        @field(result, field.name) = @field(a, field.name) + @field(b, field.name);
                    }
                    return result;
                }

                pub fn sub(a: Self, b: Self) Self {
                    var result: Self = undefined;
                    inline for (@typeInfo(Self).@"struct".fields) |field| {
                        @field(result, field.name) = @field(a, field.name) - @field(b, field.name);
                    }
                    return result;
                }

                pub fn mul(a: Self, b: Self) Self {
                    var result: Self = undefined;
                    inline for (@typeInfo(Self).@"struct".fields) |field| {
                        @field(result, field.name) = @field(a, field.name) * @field(b, field.name);
                    }
                    return result;
                }

                pub fn div(a: Self, b: Self) Self {
                    var result: Self = undefined;
                    inline for (@typeInfo(Self).@"struct".fields) |field| {
                        @field(result, field.name) = @field(a, field.name) / @field(b, field.name);
                    }
                    return result;
                }

                pub fn scale(self: Self, scalar: T) Self {
                    var result: Self = undefined;
                    inline for (@typeInfo(Self).@"struct".fields) |field| {
                        @field(result, field.name) = @field(self, field.name) * scalar;
                    }
                    return result;
                }

                pub fn dot(a: Self, b: Self) T {
                    var result: T = 0;
                    inline for (@typeInfo(Self).@"struct".fields) |field| {
                        result += @field(a, field.name) * @field(b, field.name);
                    }
                    return result;
                }

                pub fn length(a: Self) T {
                    return @sqrt(a.length2());
                }

                pub fn length2(a: Self) T {
                    return Self.dot(a, a);
                }

                pub fn distance(a: Self, b: Self) T {
                    return @sqrt(distance2(a, b));
                }

                pub fn distance2(a: Self, b: Self) T {
                    return a.sub(b).length2();
                }

                pub fn normalize(self: Self) Self {
                    const len = self.length();
                    return if (len != 0.0) self.scale(1.0 / len) else Self.zero;
                }

                pub fn abs(self: Self) Self {
                    var result: Self = undefined;
                    inline for (@typeInfo(Self).@"struct".fields) |field| {
                        @field(result, field.name) = @abs(@field(self, field.name));
                    }
                    return result;
                }

                pub fn swizzle(self: Self, comptime components: []const u8) SwizzleType(components.len) {
                    var result: SwizzleType(components.len) = undefined;
                    if (components.len > 1) {
                        inline for (0..components.len) |i| {
                            const slice = components[i..i+1];

                            const value = if (comptime std.mem.eql(u8, slice, "0"))
                                0
                            else if (comptime std.mem.eql(u8, slice, "1"))
                                1
                            else
                                @field(self, slice);

                            @field(result, switch (i) {
                                0 => "x",
                                1 => "y",
                                2 => "z",
                                3 => "w",
                                else => @compileError("unreachable"),
                            }) = value;
                        }
                    } else if (components.len == 1) {
                        result = @field(self, components);
                    } else {
                        @compileError("'components' must at least contain a single field!");
                    }
                    return result;
                }

                pub fn componentClamp(a: Self, min: Self, max: Self) Self {
                    var result: Self = undefined;
                    inline for (@typeInfo(Self).@"struct".fields) |field| {
                        @field(result, field.name) = std.math.clamp(@field(a, field.name), @field(min, field.name), @field(max, field.name));
                    }
                    return result;
                }
            };
        }

        pub const Vec2 = extern struct {
            x: T,
            y: T,

            const Self = @This();

            pub const zero = Self.new(0, 0);
            pub const unitX = Self.new(1, 0);
            pub const unitY = Self.new(0, 1);

            pub usingnamespace VectorFunctions(Self);

            pub fn new(x: T, y: T) Self {
                return Self{
                    .x = x,
                    .y = y,
                };
            }

            fn getField(v: Self, comptime index: comptime_int) T {
                switch (index) {
                    0 => return v.x,
                    1 => return v.y,
                    else => @compileError("field index out of bounds"),
                }
            }

            pub fn transform(v: Self, mat: Mat2) Self {
                var result = zero;
                inline for (0..2) |i| {
                    result.x += v.getField(i) * mat.fields[0][i];
                    result.y += v.getField(i) * mat.fields[1][i];
                }
                return result;
            }
        };

        pub const Vec3 = extern struct {
            x: T,
            y: T,
            z: T,

            const Self = @This();

            pub const zero = Self.new(0, 0, 0);
            pub const unitX = Self.new(1, 0, 0);
            pub const unitY = Self.new(0, 1, 0);
            pub const unitZ = Self.new(0, 0, 1);

            pub usingnamespace VectorFunctions(Self);

            pub fn new(x: T, y: T, z: T) Self {
                return Self{
                    .x = x,
                    .y = y,
                    .z = z,
                };
            }

            pub fn cross(a: Self, b: Self) Self {
                return Self{
                    .x = a.y * b.z - a.z * b.y,
                    .y = a.z * b.x - a.x * b.z,
                    .z = a.x * b.y - a.y * b.x,
                };
            }

            pub fn toVec4(v: Self) Vec4 {
                return Vec4.new(v.x, v.y, v.z, 1.0);
            }

            pub fn fromVec4(v: Vec4) Self {
                return Self.new(v.x, v.y, v.z);
            }

            pub fn transform(v: Self, mat: Mat3) Self {
                var result = zero;
                inline for (0..3) |i| {
                    result.x += v.getField(i) * mat.fields[0][i];
                    result.y += v.getField(i) * mat.fields[1][i];
                    result.z += v.getField(i) * mat.fields[2][i];
                }
                return result;
            }

            pub fn transform4(vec: Self, mat: Mat4) Self {
                return fromVec4(vec.toVec4().transform(mat));
            }

            fn getField(v: Self, comptime index: comptime_int) T {
                switch (index) {
                    0 => return v.x,
                    1 => return v.y,
                    2 => return v.z,
                    else => @compileError("field index out of bounds"),
                }
            }
        };

        pub const Vec4 = extern struct {
            x: T,
            y: T,
            z: T,
            w: T,

            const Self = @This();

            pub const zero = Self.new(0, 0, 0, 0);
            pub const unitX = Self.new(1, 0, 0, 0);
            pub const unitY = Self.new(0, 1, 0, 0);
            pub const unitZ = Self.new(0, 0, 1, 0);
            pub const unitW = Self.new(0, 0, 0, 1);

            pub usingnamespace VectorFunctions(Self);

            pub fn new(x: T, y: T, z: T, w: T) Self {
                return Self{
                    .x = x,
                    .y = y,
                    .z = z,
                    .w = w,
                };
            }

            pub fn transform(vec: Self, mat: Mat4) Self {
                var result = zero;
                inline for (0..4) |i| {
                    result.x += vec.getField(i) * mat.fields[i][0];
                    result.y += vec.getField(i) * mat.fields[i][1];
                    result.z += vec.getField(i) * mat.fields[i][2];
                    result.w += vec.getField(i) * mat.fields[i][3];
                }
                return result;
            }

            fn getField(vec: Self, comptime index: comptime_int) T {
                switch (index) {
                    0 => return vec.x,
                    1 => return vec.y,
                    2 => return vec.z,
                    3 => return vec.w,
                    else => @compileError("field index out of bounds"),
                }
            }
        };

        pub const Mat2 = extern struct {
            fields: [2][2]T, // [row][col]

            const Self = @This();

            pub const zero = Mat2{
                .fields = [2][2]T{
                    [2]T{ 0, 0 },
                    [2]T{ 0, 0 },
                },
            };

            pub const identity = Mat2{
                .fields = [2][2]T{
                    [2]T{ 1, 0 },
                    [2]T{ 0, 1 },
                },
            };

            pub fn mul(a: Self, b: Self) Self {
                var result: Self = undefined;
                inline for (0..2) |row| {
                    inline for (0..2) |col| {
                        var sum: T = 0.0;
                        inline for (0..2) |i| {
                            sum += a.fields[row][i] * b.fields[i][col];
                        }
                        result.fields[row][col] = sum;
                    }
                }
                return result;
            }

            pub fn transpose(a: Self) Self {
                var result: Self = undefined;
                inline for (0..2) |row| {
                    inline for (0..2) |col| {
                        result.fields[row][col] = a.fields[col][row];
                    }
                }
                return result;
            }
        };

        pub const Mat3 = extern struct {
            fields: [3][3]T, // [row][col]

            const Self = @This();

            pub const zero = Mat3{
                .fields = [3][3]T{
                    [3]T{ 0, 0, 0 },
                    [3]T{ 0, 0, 0 },
                    [3]T{ 0, 0, 0 },
                },
            };

            pub const identity = Mat3{
                .fields = [3][3]T{
                    [3]T{ 1, 0, 0 },
                    [3]T{ 0, 1, 0 },
                    [3]T{ 0, 0, 1 },
                },
            };

            pub fn mul(a: Self, b: Self) Self {
                var result: Self = undefined;
                inline for (0..3) |row| {
                    inline for (0..3) |col| {
                        var sum: T = 0.0;
                        inline for (0..3) |i| {
                            sum += a.fields[row][i] * b.fields[i][col];
                        }
                        result.fields[row][col] = sum;
                    }
                }
                return result;
            }

            pub fn transpose(a: Self) Self {
                var result: Self = undefined;
                inline for (0..3) |row| {
                    inline for (0..3) |col| {
                        result.fields[row][col] = a.fields[col][row];
                    }
                }
                return result;
            }
        };

        pub const Mat4 = extern struct {
            fields: [4][4]T, // [row][col]

            const Self = @This();

            pub const zero = Self{
                .fields = [4][4]T{
                    [4]T{ 0, 0, 0, 0 },
                    [4]T{ 0, 0, 0, 0 },
                    [4]T{ 0, 0, 0, 0 },
                    [4]T{ 0, 0, 0, 0 },
                },
            };

            pub const identity = Self{
                .fields = [4][4]T{
                    [4]T{ 1, 0, 0, 0 },
                    [4]T{ 0, 1, 0, 0 },
                    [4]T{ 0, 0, 1, 0 },
                    [4]T{ 0, 0, 0, 1 },
                },
            };

            pub fn mul(a: Self, b: Self) Self {
                var result: Self = undefined;
                inline for (0..4) |row| {
                    inline for (0..4) |col| {
                        var sum: T = 0.0;
                        inline for (0..4) |i| {
                            sum += a.fields[row][i] * b.fields[i][col];
                        }
                        result.fields[row][col] = sum;
                    }
                }
                return result;
            }

            pub fn transpose(a: Self) Self {
                var result: Self = undefined;
                inline for (0..4) |row| {
                    inline for (0..4) |col| {
                        result.fields[row][col] = a.fields[col][row];
                    }
                }
                return result;
            }

            pub fn scaleFromFactor(factor: T) Self {
                return scale(factor, factor, factor);
            }


            //
            // taken from the GLM implementation:
            //

            pub fn lookAt(eye: Vec3, look_at: Vec3, up: Vec3) Self {
                const f = Vec3.sub(look_at, eye).normalize();
                const s = Vec3.cross(f, up).normalize();
                const u = Vec3.cross(s, f);

                var result = Self.identity;
                result.fields[0][0] = s.x;
                result.fields[1][0] = s.y;
                result.fields[2][0] = s.z;
                result.fields[0][1] = u.x;
                result.fields[1][1] = u.y;
                result.fields[2][1] = u.z;
                result.fields[0][2] = - f.x;
                result.fields[1][2] = - f.y;
                result.fields[2][2] = - f.z;
                result.fields[3][0] = - Vec3.dot(s, eye);
                result.fields[3][1] = - Vec3.dot(u, eye);
                result.fields[3][2] = Vec3.dot(f, eye);
                return result;
            }

            pub fn perspective(fov: T, aspect: T, near: T, far: T) Self {
                std.debug.assert(@abs(aspect - 0.001) > 0);
                const tanHalfFovy = @tan(fov / 2);
                var result = Self.zero;
                result.fields[0][0] = 1.0 / (aspect * tanHalfFovy);
                result.fields[1][1] = 1.0 / (tanHalfFovy);
                result.fields[2][2] = - (far + near) / (far - near);
                result.fields[2][3] = - 1;
                result.fields[3][2] = - (2 * far * near) / (far - near);
                return result;
            }

            pub fn rotateAngleAxis(axis: Vec3, angle: T) Self {
                const cos = @cos(angle);
                const sin = @sin(angle);

                const normalized = axis.normalize();
                const x = normalized.x;
                const y = normalized.y;
                const z = normalized.z;

                return Self{
                    .fields = [4][4]T{
                        [4]T{ cos + x * x * (1 - cos),       x * y * (1 - cos) + z * sin,    x * z * (1 - cos) - y * sin, 0 },
                        [4]T{ y * x * (1 - cos) - z * sin,   cos + y * y * (1 - cos),        y * z * (1 - cos) + x * sin, 0 },
                        [4]T{ z * x * (1 - cos) + y * sin,   z * y * (1 - cos) - x * sin,    cos + z * z * (1 - cos),     0 },
                        [4]T{ 0,                             0,                              0,                           1 },
                    },
                };
            }

            pub fn scale(x: T, y: T, z: T) Self {
                return Self{
                    .fields = [4][4]T{
                        [4]T{ x, 0, 0, 0 },
                        [4]T{ 0, y, 0, 0 },
                        [4]T{ 0, 0, z, 0 },
                        [4]T{ 0, 0, 0, 1 },
                    },
                };
            }

            pub fn translation(v: Vec3) Self {
                return Self{
                    .fields = [4][4]T{
                        [4]T{ 1, 0, 0, 0 },
                        [4]T{ 0, 1, 0, 0 },
                        [4]T{ 0, 0, 1, 0 },
                        [4]T{ v.x, v.y, v.z, 1 },
                    },
                };
            }

            pub fn ortho(left: T, right: T, bottom: T, top: T, near: T, far: T) Self {
                var result = Self.identity;
                result.fields[0][0] = 2 / (right - left);
                result.fields[1][1] = 2 / (top - bottom);
                result.fields[2][2] = - 2 / (far - near);
                result.fields[3][0] = - (right + left) / (right - left);
                result.fields[3][1] = - (top + bottom) / (top - bottom);
                result.fields[3][2] = - (far + near) / (far - near);
                return result;
            }
        };

        pub const vec2 = Vec2.new;
        pub const vec3 = Vec3.new;
        pub const vec4 = Vec4.new;
    };
}
