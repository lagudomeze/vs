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

pub const Sound = enum(u8) { step, hit, cast, pickup, death, ui };

pub const Ambience = enum { explore, danger, shop, death, victory };

pub const Bindings = struct {
    confirm: u32 = 44,
    potion: u32 = 19,
    bomb: u32 = 5,
    inventory: u32 = 12,
    character: u32 = 6,
    talent1: u32 = 30,
    talent2: u32 = 31,
    talent3: u32 = 32,
};

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
    feedback: bool = false,
    screenshot: bool = false,
    save_slot: bool = false,
    load_slot: bool = false,
    load_auto: bool = false,
    help: bool = false,
    difficulty: bool = false,
    use_item: bool = false,
    use_bomb: bool = false,
    key_code: u32 = 0,
    map: bool = false,
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
    audio: ?*c.SDL_AudioStream = null,
    gamepad: ?*c.SDL_Gamepad = null,
    pad_prev: u32 = 0,
    pad_dir: u8 = 0,
    pad_swap: bool = false,
    esdf: bool = false,
    bindings: Bindings = .{},
    audio_volume: f32 = 0.55,
    ambient: bool = true,
    ambient_phase: f32 = 0,
    ambience: Ambience = .explore,
    window_scale: u8 = 3,
    window_height: u32 = 0,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    right_button_down: bool = false,

    pub fn init(title: [:0]const u8, width: u32, height: u32, window_scale: u32) !Platform {
        if (!c.SDL_Init(@intCast(c.SDL_INIT_VIDEO))) return error.SdlInitFailed;
        errdefer c.SDL_Quit();
        _ = c.SDL_InitSubSystem(@intCast(c.SDL_INIT_AUDIO));
        _ = c.SDL_InitSubSystem(@intCast(c.SDL_INIT_GAMEPAD));

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

        var audio_spec = c.SDL_AudioSpec{ .format = c.SDL_AUDIO_F32, .channels = 1, .freq = 22050 };
        const audio = c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &audio_spec, null, null);
        if (audio) |stream| _ = c.SDL_ResumeAudioStreamDevice(stream);
        errdefer if (audio) |stream| c.SDL_DestroyAudioStream(stream);

        var pad_count: c_int = 0;
        const pad_ids = c.SDL_GetGamepads(&pad_count);
        var gamepad: ?*c.SDL_Gamepad = null;
        if (pad_ids != null) {
            if (pad_count > 0) gamepad = c.SDL_OpenGamepad(pad_ids[0]);
            c.SDL_free(pad_ids);
        }

        return .{
            .audio = audio,
            .gamepad = gamepad,
            .window = win,
            .renderer = ren,
            .texture = tex,
            .logical_width = width,
            .logical_height = height,
            .window_width = @intCast(win_w),
            .window_height = @intCast(win_h),
        };
    }

    fn pollGamepad(self: *Platform, pad: *c.SDL_Gamepad, input: *FrameInput) void {
        const btn = struct {
            fn down(p: *c.SDL_Gamepad, b: c_int) bool {
                return c.SDL_GetGamepadButton(p, @intCast(b));
            }
        };
        var mask: u32 = 0;
        const buttons = [_]c_int{
            c.SDL_GAMEPAD_BUTTON_SOUTH,
            c.SDL_GAMEPAD_BUTTON_EAST,
            c.SDL_GAMEPAD_BUTTON_WEST,
            c.SDL_GAMEPAD_BUTTON_NORTH,
            c.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,
            c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER,
            c.SDL_GAMEPAD_BUTTON_LEFT_STICK,
            c.SDL_GAMEPAD_BUTTON_START,
            c.SDL_GAMEPAD_BUTTON_BACK,
            c.SDL_GAMEPAD_BUTTON_DPAD_UP,
            c.SDL_GAMEPAD_BUTTON_DPAD_DOWN,
            c.SDL_GAMEPAD_BUTTON_DPAD_LEFT,
            c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT,
        };
        for (buttons) |b| {
            if (btn.down(pad, b)) mask |= @as(u32, 1) << @intCast(b);
        }
        const pressed = mask & ~self.pad_prev;
        self.pad_prev = mask;

        var south = pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_SOUTH)) != 0;
        var east = pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_EAST)) != 0;
        if (self.pad_swap) {
            const tmp = south;
            south = east;
            east = tmp;
        }
        if (south) {
            input.cast = true;
            input.wait = true;
        }
        if (east) input.escape = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_WEST)) != 0) input.inventory = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_NORTH)) != 0) input.character = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER)) != 0) input.talent_1 = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER)) != 0) input.talent_2 = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_LEFT_STICK)) != 0) input.talent_3 = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_START)) != 0) input.help = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_BACK)) != 0) input.settings = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_DPAD_UP)) != 0) input.step_n = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_DPAD_DOWN)) != 0) input.step_s = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_DPAD_LEFT)) != 0) input.step_w = true;
        if (pressed & (@as(u32, 1) << @intCast(c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT)) != 0) input.step_e = true;

        const ax = c.SDL_GetGamepadAxis(pad, @intCast(c.SDL_GAMEPAD_AXIS_LEFTX));
        const ay = c.SDL_GetGamepadAxis(pad, @intCast(c.SDL_GAMEPAD_AXIS_LEFTY));
        const dead: i32 = 16000;
        var dir: u8 = 0;
        if (@abs(@as(i32, ax)) > @abs(@as(i32, ay))) {
            if (ax > dead) dir = 4 else if (ax < -dead) dir = 3;
        } else {
            if (ay > dead) dir = 2 else if (ay < -dead) dir = 1;
        }
        if (dir != self.pad_dir) {
            switch (dir) {
                1 => input.step_n = true,
                2 => input.step_s = true,
                3 => input.step_w = true,
                4 => input.step_e = true,
                else => {},
            }
            self.pad_dir = dir;
        }
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

    pub fn setBindings(self: *Platform, bindings: Bindings) void {
        self.bindings = bindings;
    }

    pub fn setEsdf(self: *Platform, enabled: bool) void {
        self.esdf = enabled;
    }

    pub fn setPadSwap(self: *Platform, enabled: bool) void {
        self.pad_swap = enabled;
    }

    pub fn setAmbience(self: *Platform, mood: Ambience) void {
        self.ambience = mood;
    }

    pub fn setAmbient(self: *Platform, enabled: bool) void {
        self.ambient = enabled;
    }

    /// Keep a quiet procedural drone queued. Uses the same stream as SFX;
    /// skips generation while the queue is busy so one-shots stay responsive.
    pub fn updateAmbient(self: *Platform) void {
        if (!self.ambient) return;
        const stream = self.audio orelse return;
        if (c.SDL_GetAudioStreamQueued(stream) > 10000) return;

        const explore_notes = [_]f32{ 220.0, 261.63, 293.66, 329.63, 392.0, 329.63, 293.66, 261.63 };
        const danger_notes = [_]f32{ 110.0, 130.81, 146.83, 164.81, 196.0, 164.81, 146.83, 130.81 };
        const shop_notes = [_]f32{ 261.63, 329.63, 392.0, 523.25, 392.0, 329.63 };
        const death_notes = [_]f32{ 82.41, 98.0, 110.0, 98.0 };
        const victory_notes = [_]f32{ 261.63, 329.63, 392.0, 523.25, 659.25, 523.25, 392.0, 329.63 };

        const notes: []const f32, const beat: f32, const drone_gain: f32, const melody_gain: f32 = switch (self.ambience) {
            .explore => .{ &explore_notes, 0.55, 0.035, 0.010 },
            .danger => .{ &danger_notes, 0.40, 0.048, 0.014 },
            .shop => .{ &shop_notes, 0.80, 0.026, 0.006 },
            .death => .{ &death_notes, 1.10, 0.040, 0.005 },
            .victory => .{ &victory_notes, 0.50, 0.030, 0.012 },
        };

        var buf: [2048]f32 = undefined;
        var i: usize = 0;
        const phase = self.ambient_phase;
        while (i < buf.len) : (i += 1) {
            const t = phase + @as(f32, @floatFromInt(i)) / 22050.0;
            const lfo = 0.55 + 0.45 * @sin(t * 0.18);
            const drone = @sin(t * std.math.tau * 55.0) * 0.55 +
                @sin(t * std.math.tau * 82.41) * 0.28 +
                @sin(t * std.math.tau * 110.0) * 0.17;

            const step_f = @floor(t / beat);
            const note = notes[@as(usize, @intFromFloat(step_f)) % notes.len];
            const local = t - step_f * beat;
            const env = @sin(std.math.pi * local / beat);
            const melody = (@sin(t * std.math.tau * note) * melody_gain +
                @sin(t * std.math.tau * note * 2.0) * melody_gain * 0.30) * env;

            buf[i] = drone * lfo * drone_gain + melody;
        }
        self.ambient_phase = @mod(phase + @as(f32, @floatFromInt(buf.len)) / 22050.0, 1000.0);
        _ = c.SDL_PutAudioStreamData(stream, &buf, @intCast(buf.len * @sizeOf(f32)));
    }

    pub fn setAudioVolume(self: *Platform, volume: f32) void {
        self.audio_volume = std.math.clamp(volume, 0, 1);
        if (self.audio) |stream| _ = c.SDL_SetAudioStreamGain(stream, self.audio_volume);
    }

    pub fn playSound(self: *Platform, kind: Sound) void {
        const stream = self.audio orelse return;
        if (c.SDL_GetAudioStreamQueued(stream) > 24000) return;

        var buf: [8192]f32 = undefined;
        var n: usize = 0;
        const freq: f32, const dur: f32 = switch (kind) {
            .step => .{ 190, 0.045 },
            .hit => .{ 115, 0.085 },
            .cast => .{ 480, 0.12 },
            .pickup => .{ 740, 0.11 },
            .death => .{ 120, 0.32 },
            .ui => .{ 880, 0.035 },
        };
        const count: usize = @intFromFloat(@as(f32, 22050) * dur);
        const total = @min(count, buf.len);
        var rng = std.Random.DefaultPrng.init(@intCast(total));
        while (n < total) : (n += 1) {
            const t = @as(f32, @floatFromInt(n)) / 22050.0;
            const phase = t * freq;
            const attack = @min(1.0, t / 0.006);
            const release = @max(0.0, 1.0 - t / dur);
            const env = attack * release;
            const wave = switch (kind) {
                .step, .hit => if (@mod(phase, 1.0) < 0.5) @as(f32, 1.0) else -1.0,
                .death => @sin(phase * std.math.tau * (1.0 - t / dur * 0.7)),
                .cast => @sin(phase * std.math.tau),
                .pickup => @sin(phase * std.math.tau * 2.0),
                .ui => @sin(phase * std.math.tau),
            };
            const noise = if (kind == .hit) (rng.random().float(f32) * 2.0 - 1.0) * 0.35 else 0.0;
            buf[n] = (wave * 0.55 + noise) * env * 0.35;
        }
        _ = c.SDL_PutAudioStreamData(stream, &buf, @intCast(total * @sizeOf(f32)));
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
        if (self.gamepad) |pad| c.SDL_CloseGamepad(pad);
        if (self.audio) |stream| c.SDL_DestroyAudioStream(stream);
        if (self.texture != null) c.SDL_DestroyTexture(self.texture);
        if (self.renderer) |r| c.SDL_DestroyRenderer(r);
        if (self.window) |w| c.SDL_DestroyWindow(w);
        c.SDL_Quit();
        self.* = .{};
    }

    fn moveDir(self: *const Platform, sc: c.SDL_Scancode) u8 {
        const up = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_UP));
        const down = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_DOWN));
        const left = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_LEFT));
        const right = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_RIGHT));
        const kp8 = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_8));
        const kp2 = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_2));
        const kp4 = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_4));
        const kp6 = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_KP_6));
        if (sc == up or sc == kp8) return 1;
        if (sc == down or sc == kp2) return 2;
        if (sc == left or sc == kp4) return 3;
        if (sc == right or sc == kp6) return 4;
        if (self.esdf) {
            const e = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_E));
            const f = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F));
            const s_key = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_S));
            const d_key = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_D));
            if (sc == e) return 1;
            if (sc == s_key) return 2;
            if (sc == f) return 3;
            if (sc == d_key) return 4;
        } else {
            const w = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_W));
            const a = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_A));
            const s_key = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_S));
            const d_key = @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_D));
            if (sc == w) return 1;
            if (sc == s_key) return 2;
            if (sc == a) return 3;
            if (sc == d_key) return 4;
        }
        return 0;
    }

    pub fn poll(self: *Platform, dt: f32) FrameInput {
        var input = FrameInput{ .mouse_x = self.mouse_x, .mouse_y = self.mouse_y };
        var ev: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&ev)) {
            const t: u32 = ev.type;
            if (t == @as(u32, @intCast(c.SDL_EVENT_QUIT))) {
                input.quit = true;
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_GAMEPAD_ADDED))) {
                if (self.gamepad == null) {
                    self.gamepad = c.SDL_OpenGamepad(ev.gdevice.which);
                    self.pad_prev = 0;
                    self.pad_dir = 0;
                }
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_GAMEPAD_REMOVED))) {
                if (self.gamepad) |pad| c.SDL_CloseGamepad(pad);
                self.gamepad = null;
                self.pad_prev = 0;
                self.pad_dir = 0;
            } else if (t == @as(u32, @intCast(c.SDL_EVENT_KEY_DOWN))) {
                if (ev.key.repeat) {
                    const rsc = ev.key.scancode;
                    switch (self.moveDir(rsc)) {
                        1 => input.step_n = true,
                        2 => input.step_s = true,
                        3 => input.step_w = true,
                        4 => input.step_e = true,
                        else => {},
                    }
                } else {
                    const sc = ev.key.scancode;
                    input.key_code = @intCast(sc);
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_ESCAPE))) input.escape = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_TAB))) input.toggle_hero = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(self.bindings.confirm))) {
                        input.cast = true;
                        input.wait = true;
                    }
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_5)) or sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_PERIOD))) input.wait = true;
                    switch (self.moveDir(sc)) {
                        1 => input.step_n = true,
                        2 => input.step_s = true,
                        3 => input.step_w = true,
                        4 => input.step_e = true,
                        else => {},
                    }
                    if (sc == @as(c.SDL_Scancode, @intCast(self.bindings.talent1))) input.talent_1 = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(self.bindings.talent2))) input.talent_2 = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(self.bindings.talent3))) input.talent_3 = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_1))) input.stat = 0;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_2))) input.stat = 1;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_3))) input.stat = 2;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_4))) input.stat = 3;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_5))) input.stat = 4;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_6))) input.stat = 5;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_7))) input.stat = 6;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_8))) input.stat = 7;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_9))) input.stat = 8;
                    if (sc == @as(c.SDL_Scancode, @intCast(self.bindings.character))) input.character = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F))) input.interrupt = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(self.bindings.inventory))) input.inventory = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_R))) input.reset = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F1))) input.toggle_debug = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F2))) input.settings = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F3))) input.feedback = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F11))) input.toggle_fullscreen = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F12))) input.screenshot = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F5))) input.save_slot = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F9))) input.load_slot = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_F10))) input.load_auto = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_H))) input.help = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_M))) input.map = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(c.SDL_SCANCODE_D))) input.difficulty = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(self.bindings.potion))) input.use_item = true;
                    if (sc == @as(c.SDL_Scancode, @intCast(self.bindings.bomb))) input.use_bomb = true;
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

        if (self.gamepad) |pad| self.pollGamepad(pad, &input);
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

pub fn openUrl(url: [:0]const u8) bool {
    return c.SDL_OpenURL(url.ptr);
}
