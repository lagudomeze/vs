//! Thin SDL3 window/input layer. Rendering itself is the software rasterizer;
//! SDL only provides a window, input, timing and an integer-scaled texture blit.
const std = @import("std");
const c = @import("sdl");

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
    screenshot: bool = false,
};

pub const Platform = struct {
    window: ?*c.SDL_Window = null,
    renderer: ?*c.SDL_Renderer = null,
    texture: [*c]c.SDL_Texture = null,
    logical_width: u32 = 384,
    logical_height: u32 = 216,
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
        };
    }

    pub fn deinit(self: *Platform) void {
        if (self.texture != null) c.SDL_DestroyTexture(self.texture);
        if (self.renderer) |r| c.SDL_DestroyRenderer(r);
        if (self.window) |w| c.SDL_DestroyWindow(w);
        c.SDL_Quit();
        self.* = .{};
    }

    pub fn poll(self: *Platform, dt: f32) FrameInput {
        var input = FrameInput{};
        var ev: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&ev)) {
            const t: u32 = ev.type;
            if (t == @as(u32, @intCast(c.SDL_EVENT_QUIT))) {
                input.quit = true;
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_KEY_DOWN))) {
                if (!ev.key.repeat) {
                    const sc = ev.key.scancode;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_ESCAPE))) input.escape = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_TAB))) input.toggle_hero = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_SPACE))) {
                        input.cast = true;
                        input.wait = true;
                    }
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_5)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_PERIOD))) input.wait = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_W))) input.step_n = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_S))) input.step_s = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_D))) input.step_e = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_A))) input.step_w = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_1))) input.talent_1 = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_2))) input.talent_2 = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_3))) input.talent_3 = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_C))) input.character = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F))) input.interrupt = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_I))) input.inventory = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_R))) input.reset = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F1))) input.toggle_debug = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F12))) input.screenshot = true;
                }
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_MOUSE_WHEEL))) {
                input.zoom_delta += ev.wheel.y * 0.55;
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_MOUSE_BUTTON_DOWN))) {
                if (ev.button.button == @as(u8, @intCast(c.SDL_BUTTON_RIGHT))) self.right_button_down = true;
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_MOUSE_BUTTON_UP))) {
                if (ev.button.button == @as(u8, @intCast(c.SDL_BUTTON_RIGHT))) self.right_button_down = false;
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_MOUSE_MOTION))) {
                if (self.right_button_down) {
                    input.yaw_delta -= ev.motion.xrel * 0.006;
                }
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
        if (held.key(keys, c.SDL_SCANCODE_Q) or held.key(keys, c.SDL_SCANCODE_LEFT)) input.yaw_delta += 1.7 * dt;
        if (held.key(keys, c.SDL_SCANCODE_E) or held.key(keys, c.SDL_SCANCODE_RIGHT)) input.yaw_delta -= 1.7 * dt;
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
