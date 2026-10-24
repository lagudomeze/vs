//! Thin SDL3 window/input layer. Rendering itself is the software rasterizer;
//! SDL only provides a window, input, timing and an integer-scaled texture blit.
const std = @import("std");
const c = @import("sdl");

/// SDL-owned per-user writable directory, e.g. %APPDATA%/lagudomeze/vx/.
/// Caller owns the returned slice and frees it with the same allocator.
pub fn prefPath(alloc: std.mem.Allocator) ![]u8 {
    const raw = c.SDL_GetPrefPath("lagudomeze", "vx") orelse return error.NoPrefPath;
    defer c.SDL_free(raw);
    return alloc.dupe(u8, std.mem.span(raw));
}

pub const FrameInput = struct {
    quit: bool = false,
    escape: bool = false,
    move_x: f32 = 0,
    move_z: f32 = 0,
    yaw_delta: f32 = 0,
    zoom_delta: f32 = 0,
    toggle_hero: bool = false,
    cast: bool = false,
    wait: bool = false,
    talent_1: bool = false,
    talent_2: bool = false,
    talent_3: bool = false,
    character: bool = false,
    step_n: bool = false,
    step_s: bool = false,
    step_e: bool = false,
    step_w: bool = false,
    interrupt: bool = false,
    inventory: bool = false,
    reset: bool = false,
    toggle_debug: bool = false,
    toggle_fullscreen: bool = false,
    settings: bool = false,
    screenshot: bool = false,
    save_slot: bool = false,
    load_slot: bool = false,
    load_auto: bool = false,
    help: bool = false,
    difficulty: bool = false,
    use_item: bool = false,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    click: bool = false,
    /// 0..5 when 1..6 was pressed; the character panel uses it to allocate
    /// level-up points. Talent keys 1..3 also set this, but gameplay only reads
    /// it while the character panel is open.
    stat: i8 = -1,
};

pub const Platform = struct {
    window: ?*c.SDL_Window = null,
    renderer: ?*c.SDL_Renderer = null,
    texture: [*c]c.SDL_Texture = null,
    logical_width: u32 = 384,
    logical_height: u32 = 216,
    window_width: u32 = 0,
    fullscreen: bool = false,
    window_scale: u8 = 3,
    window_height: u32 = 0,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    right_button_down: bool = false,

    pub fn init(title: [:0]const u8, width: u32, height: u32, window_scale: u32) !Platform {
        if (!c.SDL_Init(@intCast(c.SDL_INIT_VIDEO))) return error.SdlInitFailed;
        errdefer c.SDL_Quit();

        const win_w: c_int = @intCast(width * window_scale);
        const win_h: c_int = @intCast(height * window_scale);
        const win = c.SDL_CreateWindow(title.ptr, win_w, win_h, @intCast(c.SDL_WINDOW_RESIZABLE)) orelse
            return error.SdlWindowFailed;
        errdefer c.SDL_DestroyWindow(win);

        const ren = c.SDL_CreateRenderer(win, null) orelse return error.SdlRendererFailed;
        errdefer c.SDL_DestroyRenderer(ren);
        _ = c.SDL_SetRenderVSync(ren, 1);

        const tex = c.SDL_CreateTexture(
            ren,
            @intCast(c.SDL_PIXELFORMAT_ARGB8888),
            @intCast(c.SDL_TEXTUREACCESS_STREAMING),
            @intCast(width),
            @intCast(height),
        );
        if (tex == null) return error.SdlTextureFailed;
        _ = c.SDL_SetTextureScaleMode(tex, @intCast(c.SDL_SCALEMODE_NEAREST));
        _ = c.SDL_SetTextureBlendMode(tex, @intCast(c.SDL_BLENDMODE_NONE));
        _ = c.SDL_SetRenderLogicalPresentation(
            ren,
            @intCast(width),
            @intCast(height),
            @intCast(c.SDL_LOGICAL_PRESENTATION_INTEGER_SCALE),
        );

        return .{
            .window = win,
            .renderer = ren,
            .texture = tex,
            .logical_width = width,
            .logical_height = height,
            .window_width = @intCast(win_w),
            .window_height = @intCast(win_h),
        };
    }

    pub fn setFullscreen(self: *Platform, on: bool) void {
        if (self.window) |win| {
            _ = c.SDL_SetWindowFullscreen(win, on);
            self.fullscreen = on;
        }
    }

    pub fn toggleFullscreen(self: *Platform) bool {
        self.setFullscreen(!self.fullscreen);
        return self.fullscreen;
    }

    pub fn setVSync(self: *Platform, on: bool) void {
        if (self.renderer) |ren| _ = c.SDL_SetRenderVSync(ren, if (on) 1 else 0);
    }

    pub fn setWindowScale(self: *Platform, scale: u8) void {
        if (self.fullscreen) return;
        const s: u32 = @min(@as(u32, scale), 8);
        if (self.window) |win| {
            _ = c.SDL_SetWindowSize(win, @intCast(self.logical_width * s), @intCast(self.logical_height * s));
            self.window_width = self.logical_width * s;
            self.window_height = self.logical_height * s;
            self.window_scale = @intCast(s);
        }
    }

    pub fn deinit(self: *Platform) void {
        if (self.texture != null) c.SDL_DestroyTexture(self.texture);
        if (self.renderer) |r| c.SDL_DestroyRenderer(r);
        if (self.window) |w| c.SDL_DestroyWindow(w);
        c.SDL_Quit();
        self.* = .{};
    }

    pub fn poll(self: *Platform, dt: f32) FrameInput {
        var input = FrameInput{ .mouse_x = self.mouse_x, .mouse_y = self.mouse_y };
        var ev: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&ev)) {
            const t: u32 = ev.type;
            if (t == @as(u32, @intCast(c.SDL_EVENT_QUIT))) {
                input.quit = true;
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_KEY_DOWN))) {
                if (ev.key.repeat) {
                    const rsc = ev.key.scancode;
                    if (rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_W)) or rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_UP)) or rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_8))) input.step_n = true;
                    if (rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_S)) or rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_DOWN)) or rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_2))) input.step_s = true;
                    if (rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_D)) or rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_RIGHT)) or rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_6))) input.step_e = true;
                    if (rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_A)) or rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_LEFT)) or rsc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_4))) input.step_w = true;
                } else {
                    const sc = ev.key.scancode;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_ESCAPE))) input.escape = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_TAB))) input.toggle_hero = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_SPACE))) {
                        input.cast = true;
                        input.wait = true;
                    }
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_5)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_PERIOD))) input.wait = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_W)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_UP)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_8))) input.step_n = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_S)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_DOWN)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_2))) input.step_s = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_D)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_RIGHT)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_6))) input.step_e = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_A)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_LEFT)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_4))) input.step_w = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_1))) {
                        input.talent_1 = true;
                        input.stat = 0;
                    }
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_2))) {
                        input.talent_2 = true;
                        input.stat = 1;
                    }
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_3))) {
                        input.talent_3 = true;
                        input.stat = 2;
                    }
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_4))) input.stat = 3;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_5))) input.stat = 4;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_6))) input.stat = 5;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_C))) input.character = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F))) input.interrupt = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_I))) input.inventory = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_R))) input.reset = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F1))) input.toggle_debug = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F2))) input.settings = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F11))) input.toggle_fullscreen = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F12))) input.screenshot = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F5))) input.save_slot = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F9))) input.load_slot = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F10))) input.load_auto = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_H))) input.help = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_D))) input.difficulty = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_P))) input.use_item = true;
                }
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_MOUSE_WHEEL))) {
                input.zoom_delta += ev.wheel.y * 0.55;
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_MOUSE_BUTTON_DOWN))) {
                if (ev.button.button == @as(u8, @intCast(c.SDL_BUTTON_RIGHT))) self.right_button_down = true;
                if (ev.button.button == @as(u8, @intCast(c.SDL_BUTTON_LEFT))) {
                    input.click = true;
                    if (self.window_width > 0 and self.window_height > 0) {
                        self.mouse_x = ev.button.x * @as(f32, @floatFromInt(self.logical_width)) / @as(f32, @floatFromInt(self.window_width));
                        self.mouse_y = ev.button.y * @as(f32, @floatFromInt(self.logical_height)) / @as(f32, @floatFromInt(self.window_height));
                    }
                    input.mouse_x = self.mouse_x;
                    input.mouse_y = self.mouse_y;
                }
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_MOUSE_BUTTON_UP))) {
                if (ev.button.button == @as(u8, @intCast(c.SDL_BUTTON_RIGHT))) self.right_button_down = false;
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_MOUSE_MOTION))) {
                if (self.right_button_down) {
                    input.yaw_delta -= ev.motion.xrel * 0.006;
                }
                if (self.window_width > 0 and self.window_height > 0) {
                    self.mouse_x = ev.motion.x * @as(f32, @floatFromInt(self.logical_width)) / @as(f32, @floatFromInt(self.window_width));
                    self.mouse_y = ev.motion.y * @as(f32, @floatFromInt(self.logical_height)) / @as(f32, @floatFromInt(self.window_height));
                }
                input.mouse_x = self.mouse_x;
                input.mouse_y = self.mouse_y;
            }
        }

        const keys = c.SDL_GetKeyboardState(null);
        const held = struct {
            fn key(ks: [*c]const bool, scancode: c_int) bool {
                return ks[@intCast(scancode)];
            }
        };
        if (held.key(keys, c.SDL_SCANCODE_W)) input.move_z += 1;
        if (held.key(keys, c.SDL_SCANCODE_S)) input.move_z -= 1;
        if (held.key(keys, c.SDL_SCANCODE_D)) input.move_x += 1;
        if (held.key(keys, c.SDL_SCANCODE_A)) input.move_x -= 1;
        if (held.key(keys, c.SDL_SCANCODE_Q)) input.yaw_delta += 1.7 * dt;
        if (held.key(keys, c.SDL_SCANCODE_E)) input.yaw_delta -= 1.7 * dt;
        return input;
    }

    pub fn present(self: *Platform, pixels: []const u32) void {
        if (self.renderer == null or self.texture == null) return;
        const ren = self.renderer.?;
        _ = c.SDL_UpdateTexture(
            self.texture,
            null,
            @ptrCast(pixels.ptr),
            @intCast(@as(usize, self.logical_width) * @sizeOf(u32)),
        );
        _ = c.SDL_SetRenderDrawColor(ren, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(ren);
        _ = c.SDL_RenderTexture(ren, self.texture, null, null);
        _ = c.SDL_RenderPresent(ren);
    }
};

pub fn performanceNow() u64 {
    return c.SDL_GetPerformanceCounter();
}

pub fn performanceFrequency() u64 {
    return c.SDL_GetPerformanceFrequency();
}
