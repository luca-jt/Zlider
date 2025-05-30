pub const Vec2 = packed struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Vec3 = packed struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

pub const Vec4 = packed struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,
};

/// column major matrix
pub const Mat4 = packed struct {
    c1: Vec4 = .{},
    c2: Vec4 = .{},
    c3: Vec4 = .{},
    c4: Vec4 = .{},
};
