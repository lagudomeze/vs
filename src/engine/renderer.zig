//! Software 3D renderer for a low-resolution pixel-art framebuffer.
//!
//! Pipeline: world-space triangles -> near clip -> perspective project ->
//! z-buffered raster -> per-pixel palette quantisation with Bayer dithering ->
//! depth/id silhouette outline. Flat shading + a curated palette is what makes
//! real 3D meshes read as pixel art.
const std = @import("std");
const math = @import("../core/math.zig");
const color = @import("../core/color.zig");
const palette = @import("../core/palette.zig");
const font = @import("../core/font.zig");
const model_mod = @import("model.zig");
const arena_mesh = @import("arena_mesh.zig");
pub const icons = @import("icons.zig");

pub const max_lights = 18;

pub const Light = struct {
    pos: math.Vec3,
    color: math.Vec3,
    intensity: f32,
    radius: f32,
};

pub const Stats = struct {
    tris: u32 = 0,
    drawn: u32 = 0,
    draw_calls: u32 = 0,
};

pub const DrawMode = enum { solid, additive, shadow };

pub const RenderOpts = struct {
    tint: u32 = 0xffffff,
    boost: f32 = 1.0,
    additive: bool = false,
    id: u16 = 0,
    alpha: f32 = 1.0,
};

const ScreenVert = struct {
    x: f32,
    y: f32,
    iz: f32,
};

pub const Renderer = struct {
    gpa: std.mem.Allocator,
    width: u32,
    height: u32,
    color_buf: []u32,
    depth: []f32,
    ids: []u16,
    background: []u32,

    view: math.Mat4 = math.Mat4.identity,
    proj: math.Mat4 = math.Mat4.identity,
    inv_aspect: f32 = 1,
    focal: f32 = 1.5,
    near: f32 = 0.08,
    cam_pos: math.Vec3 = math.Vec3.zero,
    time: f32 = 0,

    lights: [max_lights]Light = undefined,
    light_count: usize = 0,

    sun_dir: math.Vec3 = .{ .x = -0.38, .y = 0.84, .z = 0.38 },
    sun_color: math.Vec3 = .{ .x = 0.62, .y = 0.70, .z = 0.92 },
    fill_dir: math.Vec3 = .{ .x = 0.30, .y = 0.18, .z = 0.94 },
    fill_color: math.Vec3 = .{ .x = 0.17, .y = 0.13, .z = 0.13 },
    key_dir: math.Vec3 = .{ .x = 0.42, .y = 0.52, .z = 0.75 },
    key_color: math.Vec3 = .{ .x = 0.62, .y = 0.32, .z = 0.16 },
    ambient: math.Vec3 = .{ .x = 0.30, .y = 0.32, .z = 0.42 },
    fog_color: math.Vec3 = .{ .x = 0.018, .y = 0.022, .z = 0.040 },

    palette_state: palette.Palette = .{},
    stats: Stats = .{},

    pub fn init(gpa: std.mem.Allocator, width: u32, height: u32) !Renderer {
        const count = @as(usize, width) * @as(usize, height);
        const color_buf = try gpa.alloc(u32, count);
        errdefer gpa.free(color_buf);
        const depth = try gpa.alloc(f32, count);
        errdefer gpa.free(depth);
        const ids = try gpa.alloc(u16, count);
        errdefer gpa.free(ids);
        const background = try gpa.alloc(u32, count);

        var self = Renderer{
            .gpa = gpa,
            .width = width,
            .height = height,
            .color_buf = color_buf,
            .depth = depth,
            .ids = ids,
            .background = background,
        };
        self.buildBackground();
        return self;
    }

    pub fn deinit(self: *Renderer) void {
        self.gpa.free(self.color_buf);
        self.gpa.free(self.depth);
        self.gpa.free(self.ids);
        self.gpa.free(self.background);
    }

    fn buildBackground(self: *Renderer) void {
        const top = color.pack(15, 17, 29);
        const bottom = color.pack(5, 6, 11);
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            const t = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(self.height - 1));
            const base = color.lerp(top, bottom, t);
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                var c = base;
                const h = color.hashU32(x *% 0x9e3779b1 +% y *% 0x85ebca6b +% 0x27d4eb2f);
                if (h % 733 == 0) {
                    c = color.lerp(base, color.pack(78, 86, 120), 0.45);
                }
                self.background[y * self.width + x] = c;
            }
        }
    }

    pub fn begin(self: *Renderer, camera: math.OrbitCamera, time: f32) void {
        @memcpy(self.color_buf, self.background);
        @memset(self.depth, 0.0);
        @memset(self.ids, 0);
        self.stats = .{};
        self.light_count = 0;
        self.time = time;
        self.view = camera.view();
        self.proj = camera.projection(@as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height)));
        self.inv_aspect = @as(f32, @floatFromInt(self.height)) / @as(f32, @floatFromInt(self.width));
        self.focal = 1.0 / @tan(camera.fov * 0.5);
        self.near = camera.near;
        self.cam_pos = camera.eye();
    }

    pub fn addLight(self: *Renderer, light: Light) void {
        if (self.light_count >= max_lights) return;
        self.lights[self.light_count] = light;
        self.light_count += 1;
    }

    // ---------------------------------------------------------------- shading
    fn shade(
        self: *Renderer,
        base: [3]u8,
        tint: u32,
        emissive: bool,
        n: math.Vec3,
        world: math.Vec3,
        boost: f32,
    ) u32 {
        const tr = color.srgbToLinear(color.red(tint));
        const tg = color.srgbToLinear(color.green(tint));
        const tb = color.srgbToLinear(color.blue(tint));
        const br = color.srgbToLinear(base[0]) * tr;
        const bg = color.srgbToLinear(base[1]) * tg;
        const bb = color.srgbToLinear(base[2]) * tb;

        var lit = math.Vec3{
            .x = self.ambient.x,
            .y = self.ambient.y,
            .z = self.ambient.z,
        };
        const sun = @max(n.dot(self.sun_dir), 0.0);
        lit.x += self.sun_color.x * sun;
        lit.y += self.sun_color.y * sun;
        lit.z += self.sun_color.z * sun;
        const fill = @max(n.dot(self.fill_dir), 0.0);
        lit.x += self.fill_color.x * fill;
        lit.y += self.fill_color.y * fill;
        lit.z += self.fill_color.z * fill;
        const key = @max(n.dot(self.key_dir), 0.0);
        lit.x += self.key_color.x * key;
        lit.y += self.key_color.y * key;
        lit.z += self.key_color.z * key;
        const view_dir = self.cam_pos.sub(world).normalize();
        const rim = std.math.pow(f32, 1.0 - @max(n.dot(view_dir), 0.0), 3.0) * 0.38;
        lit.x += 0.18 * rim;
        lit.y += 0.30 * rim;
        lit.z += 0.55 * rim;

        var li: usize = 0;
        while (li < self.light_count) : (li += 1) {
            const l = self.lights[li];
            const delta = l.pos.sub(world);
            const d2 = delta.lengthSquared();
            const r2 = l.radius * l.radius;
            if (d2 >= r2) continue;
            const d = @sqrt(d2);
            const atten_raw = 1.0 - d / l.radius;
            const atten = atten_raw * atten_raw;
            const ndl = @max(n.dot(delta.scale(1.0 / @max(d, 1e-4))), 0.0);
            const k = atten * ndl * l.intensity;
            lit.x += l.color.x * k;
            lit.y += l.color.y * k;
            lit.z += l.color.z * k;
        }

        var out = math.Vec3{
            .x = br * lit.x,
            .y = bg * lit.y,
            .z = bb * lit.z,
        };
        if (emissive) {
            const e = 1.9 * boost;
            out.x += br * e;
            out.y += bg * e;
            out.z += bb * e;
        }

        // Film-ish exposure curve keeps highlights from clipping flat.
        out.x = 1.0 - @exp(-out.x * 1.75);
        out.y = 1.0 - @exp(-out.y * 1.75);
        out.z = 1.0 - @exp(-out.z * 1.75);

        const dist = world.distance(self.cam_pos);
        const fog_t = math.smoothstep(20.0, 52.0, dist) * 0.42;
        out = out.lerp(self.fog_color, fog_t);

        return color.pack(
            color.linearToSrgb(out.x),
            color.linearToSrgb(out.y),
            color.linearToSrgb(out.z),
        );
    }

    // -------------------------------------------------------------- geometry
    pub fn drawMesh(self: *Renderer, mesh: *const arena_mesh.Mesh, entity: math.Mat4, opts: RenderOpts) void {
        self.stats.draw_calls += 1;
        for (mesh.tris) |tri| {
            const p0 = entity.mulPoint(mesh.verts[tri.a]);
            const p1 = entity.mulPoint(mesh.verts[tri.b]);
            const p2 = entity.mulPoint(mesh.verts[tri.c]);
            self.stats.tris += 1;
            if (opts.additive) {
                const tinted = tintColor(tri.color, opts.tint, opts.boost);
                self.emitTriangle(p0, p1, p2, tinted, .additive, 0, opts.alpha);
            } else {
                const base = color.unpack(tri.color);
                const n = p1.sub(p0).cross(p2.sub(p0)).normalize();
                const centroid = p0.add(p1).add(p2).scale(1.0 / 3.0);
                const c = self.shade(.{ base.r, base.g, base.b }, opts.tint, tri.emissive, n, centroid, opts.boost);
                self.emitTriangle(p0, p1, p2, c, .solid, opts.id, 1.0);
            }
        }
    }

    pub fn drawModel(
        self: *Renderer,
        model: *const model_mod.Model,
        pose: ?[]const math.Mat4,
        entity: math.Mat4,
        opts: RenderOpts,
    ) void {
        self.stats.draw_calls += 1;
        for (model.parts) |part| {
            const joint_mat = if (pose) |p|
                (if (part.joint < p.len) p[part.joint] else math.Mat4.identity)
            else
                (if (part.joint < model.rest_world.len) model.rest_world[part.joint] else math.Mat4.identity);
            const mat = entity.mul(joint_mat);
            var ti: usize = 0;
            while (ti < part.colors.len) : (ti += 1) {
                const tri_color = part.colors[ti];
                const ia = part.indices[ti * 3 + 0];
                const ib = part.indices[ti * 3 + 1];
                const ic = part.indices[ti * 3 + 2];
                const p0 = mat.mulPoint(part.verts[ia]);
                const p1 = mat.mulPoint(part.verts[ib]);
                const p2 = mat.mulPoint(part.verts[ic]);
                self.stats.tris += 1;
                if (opts.additive) {
                    const base = color.pack(tri_color.r, tri_color.g, tri_color.b);
                    const tinted = tintColor(base, opts.tint, opts.boost);
                    self.emitTriangle(p0, p1, p2, tinted, .additive, 0, opts.alpha);
                } else {
                    const n = p1.sub(p0).cross(p2.sub(p0)).normalize();
                    const centroid = p0.add(p1).add(p2).scale(1.0 / 3.0);
                    const c = self.shade(
                        .{ tri_color.r, tri_color.g, tri_color.b },
                        opts.tint,
                        tri_color.emissive != 0,
                        n,
                        centroid,
                        opts.boost,
                    );
                    self.emitTriangle(p0, p1, p2, c, .solid, opts.id, 1.0);
                }
            }
        }
    }

    fn tintColor(base: u32, tint: u32, boost: f32) u32 {
        const c = color.unpack(base);
        const t = color.unpack(tint);
        const r: u32 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(c.r)) * @as(f32, @floatFromInt(t.r)) / 255.0 * boost));
        const g: u32 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(c.g)) * @as(f32, @floatFromInt(t.g)) / 255.0 * boost));
        const b: u32 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(c.b)) * @as(f32, @floatFromInt(t.b)) / 255.0 * boost));
        return color.pack(@intCast(r), @intCast(g), @intCast(b));
    }

    pub fn drawShadow(self: *Renderer, center: math.Vec3, radius: f32) void {
        const segs = 12;
        const y = 0.014;
        var i: usize = 0;
        while (i < segs) : (i += 1) {
            const a0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs)) * 2.0 * std.math.pi;
            const a1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segs)) * 2.0 * std.math.pi;
            const p0 = math.Vec3.init(center.x + @sin(a0) * radius, y, center.z + @cos(a0) * radius);
            const p1 = math.Vec3.init(center.x + @sin(a1) * radius, y, center.z + @cos(a1) * radius);
            self.emitTriangle(center, p0, p1, 0, .shadow, 0, 0.52);
        }
    }

    // ---------------------------------------------------------------- raster
    fn emitTriangle(
        self: *Renderer,
        w0: math.Vec3,
        w1: math.Vec3,
        w2: math.Vec3,
        c: u32,
        mode: DrawMode,
        id: u16,
        alpha: f32,
    ) void {
        const v0 = self.view.mulPoint(w0);
        const v1 = self.view.mulPoint(w1);
        const v2 = self.view.mulPoint(w2);
        const near = -self.near;

        const pts = [3]math.Vec3{ v0, v1, v2 };
        var poly: [4]math.Vec3 = undefined;
        var n: usize = 0;
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const a = pts[i];
            const b = pts[(i + 1) % 3];
            const a_in = a.z <= near;
            const b_in = b.z <= near;
            if (a_in) {
                if (n < poly.len) {
                    poly[n] = a;
                    n += 1;
                }
            }
            if (a_in != b_in) {
                const t = (near - a.z) / (b.z - a.z);
                if (n < poly.len) {
                    poly[n] = a.lerp(b, t);
                    n += 1;
                }
            }
        }
        if (n < 3) return;

        var sv: [4]ScreenVert = undefined;
        var k: usize = 0;
        while (k < n) : (k += 1) {
            sv[k] = self.projectView(poly[k]);
        }
        k = 1;
        while (k + 1 < n) : (k += 1) {
            self.rasterTri(sv[0], sv[k], sv[k + 1], c, mode, id, alpha);
        }
    }

    fn projectView(self: *Renderer, p: math.Vec3) ScreenVert {
        const w = -p.z;
        const inv = 1.0 / w;
        const f = self.focal;
        const wf = @as(f32, @floatFromInt(self.width));
        const hf = @as(f32, @floatFromInt(self.height));
        return .{
            .x = ((p.x * f * self.inv_aspect) * inv * 0.5 + 0.5) * wf,
            .y = (0.5 - (p.y * f) * inv * 0.5) * hf,
            .iz = inv,
        };
    }

    inline fn edge(ax: f32, ay: f32, bx: f32, by: f32, px: f32, py: f32) f32 {
        return (bx - ax) * (py - ay) - (by - ay) * (px - ax);
    }

    fn rasterTri(
        self: *Renderer,
        a: ScreenVert,
        b: ScreenVert,
        c: ScreenVert,
        tri_color: u32,
        mode: DrawMode,
        id: u16,
        alpha: f32,
    ) void {
        const area = edge(a.x, a.y, b.x, b.y, c.x, c.y);
        if (@abs(area) < 0.0001) return;
        if (mode == .solid and area > 0.0) return; // backface cull (screen Y is flipped)

        var min_x = @floor(@min(a.x, @min(b.x, c.x)));
        var max_x = @ceil(@max(a.x, @max(b.x, c.x)));
        var min_y = @floor(@min(a.y, @min(b.y, c.y)));
        var max_y = @ceil(@max(a.y, @max(b.y, c.y)));
        const wf: f32 = @floatFromInt(self.width);
        const hf: f32 = @floatFromInt(self.height);
        min_x = std.math.clamp(min_x, 0, wf - 1);
        max_x = std.math.clamp(max_x, 0, wf - 1);
        min_y = std.math.clamp(min_y, 0, hf - 1);
        max_y = std.math.clamp(max_y, 0, hf - 1);

        const inv_area = 1.0 / area;
        var y: i32 = @intFromFloat(min_y);
        const y_end: i32 = @intFromFloat(max_y);
        while (y <= y_end) : (y += 1) {
            const py = @as(f32, @floatFromInt(y)) + 0.5;
            var x: i32 = @intFromFloat(min_x);
            const x_end: i32 = @intFromFloat(max_x);
            while (x <= x_end) : (x += 1) {
                const px = @as(f32, @floatFromInt(x)) + 0.5;
                const w0 = edge(b.x, b.y, c.x, c.y, px, py) * inv_area;
                if (w0 < -0.00001) continue;
                const w1 = edge(c.x, c.y, a.x, a.y, px, py) * inv_area;
                if (w1 < -0.00001) continue;
                const w2 = 1.0 - w0 - w1;
                if (w2 < -0.00001) continue;

                const iz = w0 * a.iz + w1 * b.iz + w2 * c.iz;
                const index: usize = @as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(x));

                switch (mode) {
                    .solid => {
                        if (iz <= self.depth[index]) continue;
                        self.depth[index] = iz;
                        self.ids[index] = id;
                        self.color_buf[index] = tri_color;
                        self.stats.drawn += 1;
                    },
                    .additive => {
                        if (iz < self.depth[index] - 0.000003) continue;
                        if (alpha <= 0.0) continue;
                        self.color_buf[index] = addColor(self.color_buf[index], tri_color, alpha);
                    },
                    .shadow => {
                        if (iz < self.depth[index] - 0.000003) continue;
                        self.color_buf[index] = color.scale(self.color_buf[index], 0.62);
                    },
                }
            }
        }
    }

    fn addColor(dst: u32, src: u32, alpha: f32) u32 {
        const a = color.unpack(dst);
        const b = color.unpack(src);
        const ar: f32 = @floatFromInt(a.r);
        const ag: f32 = @floatFromInt(a.g);
        const ab: f32 = @floatFromInt(a.b);
        const br: f32 = @as(f32, @floatFromInt(b.r)) * alpha;
        const bg: f32 = @as(f32, @floatFromInt(b.g)) * alpha;
        const bb: f32 = @as(f32, @floatFromInt(b.b)) * alpha;
        return color.pack(
            @intFromFloat(@min(255.0, ar + br)),
            @intFromFloat(@min(255.0, ag + bg)),
            @intFromFloat(@min(255.0, ab + bb)),
        );
    }

    pub fn drawShadowDisc(self: *Renderer, center: math.Vec3, radius: f32) void {
        self.drawShadow(center, radius);
    }

    // ------------------------------------------------------------ billboards
    pub fn drawGlow(self: *Renderer, world: math.Vec3, radius_world: f32, rgb: u32, intensity: f32) void {
        const p = world.sub(self.cam_pos);
        const view_p = self.view.mulPoint(world);
        if (view_p.z >= -self.near) return;
        _ = p;
        const inv = 1.0 / -view_p.z;
        const proj = self.projectView(view_p);
        const radius: f32 = std.math.clamp(radius_world * self.focal * @as(f32, @floatFromInt(self.height)) * 0.5 * inv, 1.0, 64.0);
        const cx = proj.x;
        const cy = proj.y;
        const ix: i32 = @intFromFloat(@floor(cx - radius));
        const iy: i32 = @intFromFloat(@floor(cy - radius));
        const ex: i32 = @intFromFloat(@ceil(cx + radius));
        const ey: i32 = @intFromFloat(@ceil(cy + radius));
        const wf: i32 = @intCast(self.width);
        const hf: i32 = @intCast(self.height);
        var y = @max(iy, 0);
        while (y <= @min(ey, hf - 1)) : (y += 1) {
            var x = @max(ix, 0);
            while (x <= @min(ex, wf - 1)) : (x += 1) {
                const dx = (@as(f32, @floatFromInt(x)) + 0.5 - cx) / radius;
                const dy = (@as(f32, @floatFromInt(y)) + 0.5 - cy) / radius;
                const d2 = dx * dx + dy * dy;
                if (d2 > 1.0) continue;
                const index: usize = @as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(x));
                if (self.depth[index] > proj.iz + 0.00001) continue;
                const fall = (1.0 - d2) * (1.0 - d2) * intensity;
                if (fall <= 0.01) continue;
                self.color_buf[index] = addColor(self.color_buf[index], rgb, fall);
            }
        }
    }

    pub fn drawFlame(self: *Renderer, world: math.Vec3, size_world: f32, seed: u32) void {
        const view_p = self.view.mulPoint(world);
        if (view_p.z >= -self.near) return;
        const proj = self.projectView(view_p);
        const inv = 1.0 / -view_p.z;
        const radius: f32 = std.math.clamp(size_world * self.focal * @as(f32, @floatFromInt(self.height)) * 0.5 * inv, 3.0, 48.0);
        const cx = proj.x;
        const cy = proj.y;
        const wf: i32 = @intCast(self.width);
        const hf: i32 = @intCast(self.height);
        const ix: i32 = @intFromFloat(@floor(cx - radius * 0.7));
        const iy: i32 = @intFromFloat(@floor(cy - radius));
        const ex: i32 = @intFromFloat(@ceil(cx + radius * 0.7));
        const ey: i32 = @intFromFloat(@ceil(cy + radius * 0.6));
        var y = @max(iy, 0);
        while (y <= @min(ey, hf - 1)) : (y += 1) {
            var x = @max(ix, 0);
            while (x <= @min(ex, wf - 1)) : (x += 1) {
                const nx = (@as(f32, @floatFromInt(x)) + 0.5 - cx) / radius;
                const ny = (@as(f32, @floatFromInt(y)) + 0.5 - cy) / radius;
                if (ny > 0.62 or ny < -1.02) continue;
                const h = std.math.clamp((0.62 - ny) / 1.64, 0.0, 1.0);
                const wobble = (color.hashFloat(seed + @as(u32, @intFromFloat(h * 9.0)) * 17 + @as(u32, @intFromFloat(self.time * 9.0)) * 31) - 0.5) * 0.32 * h;
                const width = (1.0 - h) * 0.62 + 0.04;
                const dx = @abs(nx - wobble);
                if (dx > width) continue;
                const shape = 1.0 - dx / width;
                const index: usize = @as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(x));
                if (self.depth[index] > proj.iz + 0.00001) continue;
                const heat = std.math.clamp(shape * (0.55 + 0.45 * (1.0 - h)), 0.0, 1.0);
                var c = if (heat > 0.72) color.pack(255, 242, 168) else if (heat > 0.45) color.pack(255, 178, 54) else color.pack(226, 96, 41);
                if (heat < 0.18) c = color.pack(184, 58, 69);
                self.color_buf[index] = addColor(self.color_buf[index], c, heat);
            }
        }
    }

    // --------------------------------------------------------------- resolve
    pub fn resolve(self: *Renderer) void {
        const wf: f32 = @floatFromInt(self.width);
        const hf: f32 = @floatFromInt(self.height);
        const cx = wf * 0.5;
        const cy = hf * 0.5;
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const idx = y * self.width + x;
                const dx = (@as(f32, @floatFromInt(x)) - cx) / cx;
                const dy = (@as(f32, @floatFromInt(y)) - cy) / cy;
                const d2 = dx * dx + dy * dy;
                const vig: f32 = 1.0 - 0.16 * d2;
                const c = color.scale(self.color_buf[idx], vig);
                self.color_buf[idx] = self.palette_state.quantize(c, x, y);
            }
        }

        // silhouette outlines from object ids + depth discontinuities
        y = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const idx = y * self.width + x;
                const id = self.ids[idx];
                if (id == 0) continue;
                var out = false;
                if (x > 0) out = out or self.edgeAt(idx, idx - 1);
                if (x + 1 < self.width) out = out or self.edgeAt(idx, idx + 1);
                if (y > 0) out = out or self.edgeAt(idx, idx - self.width);
                if (y + 1 < self.height) out = out or self.edgeAt(idx, idx + self.width);
                if (out) self.color_buf[idx] = palette.outline;
            }
        }
    }

    fn edgeAt(self: *Renderer, a: usize, b: usize) bool {
        const ia = self.ids[a];
        const ib = self.ids[b];
        if (ia == ib) return false;
        if (ib == 0) return true;
        const da = if (self.depth[a] > 0) 1.0 / self.depth[a] else 0.0;
        const db = if (self.depth[b] > 0) 1.0 / self.depth[b] else 0.0;
        return @abs(da - db) > 0.12;
    }

    // ------------------------------------------------------------------- HUD
    pub fn putPixel(self: *Renderer, x: i32, y: i32, c: u32) void {
        if (x < 0 or y < 0 or x >= @as(i32, @intCast(self.width)) or y >= @as(i32, @intCast(self.height))) return;
        self.color_buf[@as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(x))] = c;
    }

    pub fn getPixel(self: *Renderer, x: i32, y: i32) u32 {
        if (x < 0 or y < 0 or x >= @as(i32, @intCast(self.width)) or y >= @as(i32, @intCast(self.height))) return 0;
        return self.color_buf[@as(usize, @intCast(y)) * @as(usize, self.width) + @as(usize, @intCast(x))];
    }

    pub fn fillRect(self: *Renderer, x: i32, y: i32, w: i32, h: i32, c: u32) void {
        var yy = y;
        while (yy < y + h) : (yy += 1) {
            var xx = x;
            while (xx < x + w) : (xx += 1) {
                self.putPixel(xx, yy, c);
            }
        }
    }

    pub fn strokeRect(self: *Renderer, x: i32, y: i32, w: i32, h: i32, c: u32) void {
        self.fillRect(x, y, w, 1, c);
        self.fillRect(x, y + h - 1, w, 1, c);
        self.fillRect(x, y, 1, h, c);
        self.fillRect(x + w - 1, y, 1, h, c);
    }

    pub fn drawIcon(self: *Renderer, icon: icons.Icon, x: i32, y: i32, c: u32, scale: i32) void {
        const rows = icons.rows(icon);
        for (rows, 0..) |bits, row| {
            var col: usize = 0;
            while (col < 12) : (col += 1) {
                if ((bits & (@as(u16, 1) << @intCast(11 - col))) == 0) continue;
                self.fillRect(
                    x + @as(i32, @intCast(col)) * scale,
                    y + @as(i32, @intCast(row)) * scale,
                    scale,
                    scale,
                    c,
                );
            }
        }
    }

    pub fn drawText(self: *Renderer, x: i32, y: i32, text: []const u8, c: u32, scale: i32, shadow: bool) void {
        if (shadow) self.drawTextRaw(x + scale, y + scale, text, palette.outline, scale);
        self.drawTextRaw(x, y, text, c, scale);
    }

    fn drawTextRaw(self: *Renderer, x: i32, y: i32, text: []const u8, c: u32, scale: i32) void {
        var px = x;
        var i: usize = 0;
        const ascii_adv: i32 = @intCast(font.advance);
        while (font.nextCodepoint(text, &i)) |cp| {
            if (cp == ' ') {
                px += ascii_adv * scale;
                continue;
            }
            if (cp < 0x80) {
                const rows = font.glyph(@intCast(cp));
                var row: usize = 0;
                while (row < font.glyph_height) : (row += 1) {
                    var col: usize = 0;
                    while (col < font.glyph_width) : (col += 1) {
                        const bit = (@as(u8, 1) << @intCast(4 - col));
                        if ((rows[row] & bit) == 0) continue;
                        self.fillRect(
                            px + @as(i32, @intCast(col)) * scale,
                            y + (3 + @as(i32, @intCast(row))) * scale,
                            scale,
                            scale,
                            c,
                        );
                    }
                }
                px += ascii_adv * scale;
                continue;
            }
            if (font.cjk.find(cp)) |glyph| {
                const gw: usize = @intCast(font.cjk.width);
                for (glyph.rows, 0..) |bits, row| {
                    var col: usize = 0;
                    while (col < gw) : (col += 1) {
                        const mask = @as(u16, 1) << @intCast(gw - 1 - col);
                        if ((bits & mask) == 0) continue;
                        self.fillRect(
                            px + @as(i32, @intCast(col)) * scale,
                            y + @as(i32, @intCast(row)) * scale,
                            scale,
                            scale,
                            c,
                        );
                    }
                }
            } else {
                self.strokeRect(px + 2 * scale, y + 3 * scale, 9 * scale, 8 * scale, c);
            }
            px += @as(i32, @intCast(font.cjk.advance)) * scale;
        }
    }

    pub fn textWidth(text: []const u8, scale: i32) i32 {
        if (text.len == 0) return 0;
        return @intCast(font.textWidth(text, @intCast(@max(scale, 0))));
    }

    pub fn textCentered(self: *Renderer, cx: i32, y: i32, text: []const u8, c: u32, scale: i32, shadow: bool) void {
        self.drawText(cx - @divTrunc(textWidth(text, scale), 2), y, text, c, scale, shadow);
    }
};

test "renderer allocates and clears" {
    const gpa = std.testing.allocator;
    var r = try Renderer.init(gpa, 64, 36);
    defer r.deinit();
    const cam = math.OrbitCamera{};
    r.begin(cam, 0);
    try std.testing.expectEqual(@as(usize, 0), r.light_count);
    r.resolve();
    try std.testing.expect(r.color_buf[0] != 0);
}

test "hud icon atlas has silhouettes and blank margins" {
    const all = [_]icons.Icon{ .bag, .hero, .coin, .sword, .shield, .potion, .time, .fire, .skull, .heart, .save, .stairs, .gear };
    for (all) |icon| {
        const rows = icons.rows(icon);
        var bits: usize = 0;
        for (rows) |row| bits += @popCount(row);
        try std.testing.expect(bits > 8);
    }
    try std.testing.expectEqual(@as(u16, 0), icons.rows(.bag)[0]);
    try std.testing.expectEqual(@as(u16, 0), icons.rows(.bag)[11]);
}
