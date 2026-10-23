const std = @import("std");
const vx = @import("vx");

const Options = struct {
    headless: bool = false,
    out: ?[]const u8 = null,
    frames: u32 = 0,
    hero: u32 = 0,
    hero_set: bool = false,
    start_menu: bool = false,
    seed: u64 = 12345,
    arena: bool = false,
    yaw: f32 = -0.35,
    pitch: f32 = 0.70,
    dist: f32 = 8.2,
    width: u32 = 640,
    height: u32 = 360,
    scale: u32 = 3,
    run_seconds: f32 = 0,
    walk: bool = false,
    cast: bool = false,
    auto_demo: bool = false,
    enemy_phase_shot: bool = false,
    slots_shot: bool = false,
    auto_slots_shot: bool = false,
    debug: bool = false,
    lineup: bool = false,
    inventory: bool = false,
    character: bool = false,
    loot: u32 = 0,
    aim: ?u32 = null,
    hide_hud: bool = false,
    help: bool = false,
    help_screen: bool = false,
};

fn usage() void {
    std.debug.print(
        \\VX - real 3D models rendered in a pixel-art palette
        \\
        \\Usage: vx [options]
        \\  --headless        render without opening a window
        \\  --out PATH        screenshot path (default: shots/vx.png)
        \\  --frames N        simulation frames before a headless capture; window auto-quit
        \\  --run-seconds S   window mode: capture and quit after S seconds
        \\  --hero N          start as hero 0=Berserker 1=Archmage 2=Chronomancer (skips the class menu)
        \\  --start-menu      force the class-selection cards (headless screenshots/QA)
        \\  --yaw DEG         camera yaw (default -20)
        \\  --pitch DEG       camera pitch (default 40)
        \\  --dist U          camera orbit distance (default 8.2)
        \\  --res WxH         internal pixel resolution (default 640x360)
        \\  --scale N         integer window scale in window mode (default 3)
        \\  --walk            headless: hold W so the party walks into frame
        \\  --cast            headless: cast once at the end
        \\  --auto            headless demo: cast every 1.5s
        \\  --enemy-phase     headless: wait once and capture the enemy-phase HUD
        \\  --slots           open the save-slot panel (screenshots/QA)
        \\  --auto-slots      open the auto-backup panel (screenshots/QA)
        \\  --aim N           headless: open aim on talent N for screenshots (no confirm)
        \\  --help-screen     show the in-game controls panel for screenshots
        \\  --debug           show the debug HUD
        \\  --lineup          class showcase camera (for documentation shots)
        \\  --hide-hud        render without the HUD
        \\  --help            this text
        \\
        \\Controls: WASD move, 1/2/3 aim talent, SPACE or same key confirm,
        \\          TAB switch target, ESC cancel aim/close panel/quit,
        \\          Q/E or right-drag orbit, wheel zoom, I inventory, C character,
        \\          R reset, F5 save, F9 load, H help, F1 debug, F12 shot.
        \\
    , .{});
}

fn argAt(argv: []const [:0]const u8, index: *usize) ![]const u8 {
    index.* += 1;
    if (index.* >= argv.len) return error.MissingValue;
    return argv[index.*];
}

fn parseResolution(text: []const u8) !struct { w: u32, h: u32 } {
    const x = std.mem.indexOfScalar(u8, text, 'x') orelse return error.BadResolution;
    const w = try std.fmt.parseInt(u32, text[0..x], 10);
    const h = try std.fmt.parseInt(u32, text[x + 1 ..], 10);
    if (w < 480 or h < 270 or w > 1024 or h > 768) return error.BadResolution;
    return .{ .w = w, .h = h };
}

fn parseOptions(argv: []const [:0]const u8) !Options {
    var o = Options{};
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--headless")) {
            o.headless = true;
        } else if (std.mem.eql(u8, a, "--out")) {
            o.out = try argAt(argv, &i);
        } else if (std.mem.eql(u8, a, "--frames")) {
            o.frames = try std.fmt.parseInt(u32, try argAt(argv, &i), 10);
        } else if (std.mem.eql(u8, a, "--hero")) {
            o.hero = try std.fmt.parseInt(u32, try argAt(argv, &i), 10);
            o.hero_set = true;
        } else if (std.mem.eql(u8, a, "--start-menu")) {
            o.start_menu = true;
        } else if (std.mem.eql(u8, a, "--seed")) {
            o.seed = try std.fmt.parseInt(u64, try argAt(argv, &i), 10);
        } else if (std.mem.eql(u8, a, "--arena")) {
            o.arena = true;
        } else if (std.mem.eql(u8, a, "--yaw")) {
            o.yaw = try std.fmt.parseFloat(f32, try argAt(argv, &i)) * std.math.pi / 180.0;
        } else if (std.mem.eql(u8, a, "--pitch")) {
            o.pitch = try std.fmt.parseFloat(f32, try argAt(argv, &i)) * std.math.pi / 180.0;
        } else if (std.mem.eql(u8, a, "--dist")) {
            o.dist = try std.fmt.parseFloat(f32, try argAt(argv, &i));
        } else if (std.mem.eql(u8, a, "--res")) {
            const r = try parseResolution(try argAt(argv, &i));
            o.width = r.w;
            o.height = r.h;
        } else if (std.mem.eql(u8, a, "--scale")) {
            o.scale = try std.fmt.parseInt(u32, try argAt(argv, &i), 10);
        } else if (std.mem.eql(u8, a, "--run-seconds")) {
            o.run_seconds = try std.fmt.parseFloat(f32, try argAt(argv, &i));
        } else if (std.mem.eql(u8, a, "--walk")) {
            o.walk = true;
        } else if (std.mem.eql(u8, a, "--cast")) {
            o.cast = true;
        } else if (std.mem.eql(u8, a, "--auto")) {
            o.auto_demo = true;
        } else if (std.mem.eql(u8, a, "--enemy-phase")) {
            o.enemy_phase_shot = true;
        } else if (std.mem.eql(u8, a, "--slots")) {
            o.slots_shot = true;
        } else if (std.mem.eql(u8, a, "--auto-slots")) {
            o.auto_slots_shot = true;
        } else if (std.mem.eql(u8, a, "--debug")) {
            o.debug = true;
        } else if (std.mem.eql(u8, a, "--lineup")) {
            o.lineup = true;
        } else if (std.mem.eql(u8, a, "--inventory")) {
            o.inventory = true;
        } else if (std.mem.eql(u8, a, "--character")) {
            o.character = true;
        } else if (std.mem.eql(u8, a, "--loot")) {
            o.loot = try std.fmt.parseInt(u32, try argAt(argv, &i), 10);
        } else if (std.mem.eql(u8, a, "--aim")) {
            o.aim = try std.fmt.parseInt(u32, try argAt(argv, &i), 10);
        } else if (std.mem.eql(u8, a, "--help-screen")) {
            o.help_screen = true;
        } else if (std.mem.eql(u8, a, "--hide-hud")) {
            o.hide_hud = true;
        } else if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            o.help = true;
        } else {
            std.debug.print("vx: unknown option '{s}'\n", .{a});
            usage();
            return error.UnknownOption;
        }
    }
    return o;
}

fn ensureParent(io: std.Io, path: []const u8) void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len == 0) return;
        std.Io.Dir.cwd().createDirPath(io, dir) catch {};
    }
}

fn snapCamera(game: *vx.Game, options: Options) void {
    game.camera.yaw = options.yaw;
    game.camera.pitch = options.pitch;
    game.camera.distance = options.dist;
    game.camera.target = game.camera_target;
}

fn runHeadless(game: *vx.Game, io: std.Io, options: Options) !void {
    const frames: u32 = if (options.frames == 0) 1 else options.frames;
    var frame: u32 = 0;
    while (frame < frames) : (frame += 1) {
        var input = vx.game.InputFrame{};
        if (options.walk) input.move_z = 1.0;
        if (options.cast and frame + 1 == frames) input.cast = true;
        if (options.auto_demo and frame % 90 == 0) input.cast = true;
        game.update(input, 1.0 / 60.0);
    }
    game.render();

    const path = options.out orelse "shots/vx.png";
    ensureParent(io, path);
    try game.saveScreenshot(io, path);
    std.debug.print(
        "headless: {d}x{d} tris={d} drawn={d} time={d:.2}s -> {s}\n",
        .{ game.renderer.width, game.renderer.height, game.renderer.stats.tris, game.renderer.stats.drawn, game.time, path },
    );
}

fn runWindow(game: *vx.Game, io: std.Io, options: Options) !void {
    var platform = vx.platform.Platform.init("VX - Aether Keep", options.width, options.height, options.scale) catch |err| {
        std.debug.print("vx: could not open a window ({s}); use --headless for an off-screen capture.\n", .{@errorName(err)});
        return err;
    };
    defer platform.deinit();

    const freq: f64 = @floatFromInt(vx.platform.performanceFrequency());
    var last = vx.platform.performanceNow();
    var elapsed: f32 = 0;
    var quit = false;
    var captured = false;
    std.debug.print("window: {d}x{d} logical, {d}x scale - WASD move, Q/E orbit, TAB switch, ESC quit\n", .{
        options.width, options.height, options.scale,
    });

    while (!quit) {
        const now = vx.platform.performanceNow();
        const dt_seconds: f64 = @as(f64, @floatFromInt(now - last)) / freq;
        const dt64: f32 = @floatCast(dt_seconds);
        const dt: f32 = @min(0.05, dt64);
        last = now;
        elapsed += dt;

        const pin = platform.poll(dt);
        if (pin.quit or pin.escape) break;
        if (pin.toggle_debug) game.debug = !game.debug;

        const input = vx.game.InputFrame{
            .move_x = pin.move_x,
            .move_z = pin.move_z,
            .yaw_delta = pin.yaw_delta,
            .zoom_delta = pin.zoom_delta,
            .toggle_hero = pin.toggle_hero,
            .cast = pin.cast,
            .interrupt = pin.interrupt,
            .inventory = pin.inventory,
            .reset = pin.reset,
        };
        game.update(input, dt);
        game.render();
        platform.present(game.renderer.color_buf);

        if (pin.screenshot) {
            const path = std.fmt.allocPrint(std.heap.page_allocator, "shots/capture-{d}.png", .{game.frame}) catch "shots/capture.png";
            ensureParent(io, path);
            game.saveScreenshot(io, path) catch |err| {
                std.debug.print("vx: screenshot failed: {s}\n", .{@errorName(err)});
            };
            std.debug.print("screenshot -> {s}\n", .{path});
        }

        if (options.run_seconds > 0 and elapsed >= options.run_seconds) {
            captured = true;
            quit = true;
        } else if (options.frames > 0 and game.frame >= options.frames) {
            captured = true;
            quit = true;
        }
    }

    if (captured) {
        const path = options.out orelse "shots/window.png";
        ensureParent(io, path);
        game.render();
        try game.saveScreenshot(io, path);
        std.debug.print("window capture -> {s}\n", .{path});
    }
}

fn runRunHeadless(game: *vx.RunGame, io: std.Io, options: Options) !void {
    const frames: u32 = if (options.frames == 0) 1 else options.frames;
    var frame: u32 = 0;
    while (frame < frames) : (frame += 1) {
        var input = vx.run_game.Input{};
        if (options.enemy_phase_shot and frame == 0) input.wait = true;
        if (options.walk and frame % 12 == 0) input.step_y = -1;
        if (options.auto_demo and frame % 10 == 0) {
            game.autoPlayStep();
        }
        // Casting a targeted talent is two key events now: aim on the
        // penultimate frame, confirm on the last one.
        if (options.cast and frame + 2 == frames) input.talent = 0;
        if (options.cast and frame + 1 == frames) input.confirm = true;
        if (options.aim) |aim_talent| {
            if (frame + 1 == frames) input.talent = @intCast(aim_talent);
        }
        game.update(input, 1.0 / 60.0);
        if (game.autosave_pending) game.flushAutosave(io);
    }
    game.render();
    const path = options.out orelse "shots/run.png";
    ensureParent(io, path);
    try game.saveScreenshot(io, path);
    std.debug.print(
        "run headless: {d}x{d} tris={d} drawn={d} floor={d} turn={d} hp={d:.0} -> {s}\n",
        .{ game.renderer.width, game.renderer.height, game.renderer.stats.tris, game.renderer.stats.drawn, game.sim.floor, game.sim.turn, game.sim.hero.hp, path },
    );
}

fn runRunWindow(game: *vx.RunGame, io: std.Io, options: Options) !void {
    var platform = vx.platform.Platform.init("VX - Aether Keep: Depths", options.width, options.height, options.scale) catch |err| {
        std.debug.print("vx: could not open a window ({s}); use --headless for an off-screen capture.\n", .{@errorName(err)});
        return err;
    };
    defer platform.deinit();

    const freq: f64 = @floatFromInt(vx.platform.performanceFrequency());
    var last = vx.platform.performanceNow();
    var elapsed: f32 = 0;
    var quit = false;
    var captured = false;
    var slot_frame = false;
    std.debug.print("run: {d}x{d} logical, {d}x scale - class menu 1/2/3, WASD step, 1/2/3 aim, SPACE confirm, ESC cancel, I/C panels, Q/E orbit, R restart\n", .{
        options.width, options.height, options.scale,
    });

    while (!quit) {
        const now = vx.platform.performanceNow();
        const dt_seconds: f64 = @as(f64, @floatFromInt(now - last)) / freq;
        const dt64: f32 = @floatCast(dt_seconds);
        const dt: f32 = @min(0.05, dt64);
        last = now;
        elapsed += dt;

        const pin = platform.poll(dt);
        if (pin.quit) break;
        // Escape is hierarchical: cancel aim first (never lose the run just
        // for cancelling a target), then close a modal panel, then quit.
        if (pin.escape) {
            if (game.slot_menu != .none) {
                game.closeSlotMenu();
                slot_frame = true;
            } else if (!game.cancelAim()) {
                if (game.show_help) {
                    game.show_help = false;
                } else if (game.panel != .none) {
                    game.panel = .none;
                } else {
                    break;
                }
            }
        }
        if (pin.toggle_debug) game.debug = !game.debug;
        if (pin.load_auto) {
            game.openAutoMenu(io);
            slot_frame = true;
        }
        if (pin.save_slot) {
            game.openSlotMenu(io, .save);
            slot_frame = true;
        }
        if (pin.load_slot) {
            game.openSlotMenu(io, .load);
            slot_frame = true;
        }
        if (game.slot_menu != .none) {
            var chosen: ?usize = null;
            if (pin.talent_1) chosen = 0;
            if (pin.talent_2) chosen = 1;
            if (pin.talent_3) chosen = 2;
            if (chosen) |idx| {
                switch (game.slot_menu) {
                    .save => game.saveSlot(io, idx),
                    .load => game.loadSlot(io, idx),
                    .auto_load => game.loadAutoSlot(io, idx),
                    .none => {},
                }
                slot_frame = true;
            }
        }

        var input = vx.run_game.Input{};
        if (!slot_frame) {
            input.step_x = @as(i32, @intFromBool(pin.step_e)) - @as(i32, @intFromBool(pin.step_w));
            input.step_y = @as(i32, @intFromBool(pin.step_s)) - @as(i32, @intFromBool(pin.step_n));
            if (pin.talent_1) input.talent = 0;
            if (pin.talent_2) input.talent = 1;
            if (pin.talent_3) input.talent = 2;
            input.confirm = pin.cast;
            input.wait = pin.wait;
            input.target_next = pin.toggle_hero;
            input.inventory = pin.inventory;
            input.character = pin.character;
            input.restart = pin.reset;
            input.help = pin.help;
            input.mouse_x = pin.mouse_x;
            input.mouse_y = pin.mouse_y;
            input.click = pin.click;
            input.stat = pin.stat;
            input.yaw_delta = pin.yaw_delta;
            input.zoom_delta = pin.zoom_delta;
        }

        game.update(input, dt);
        if (game.autosave_pending) game.flushAutosave(io);
        game.render();
        platform.present(game.renderer.color_buf);

        if (pin.screenshot) {
            const path = std.fmt.allocPrint(std.heap.page_allocator, "shots/run-{d}.png", .{game.frame}) catch "shots/run.png";
            ensureParent(io, path);
            game.saveScreenshot(io, path) catch |err| {
                std.debug.print("vx: screenshot failed: {s}\n", .{@errorName(err)});
            };
            std.debug.print("screenshot -> {s}\n", .{path});
        }

        if (options.run_seconds > 0 and elapsed >= options.run_seconds) {
            captured = true;
            quit = true;
        } else if (options.frames > 0 and game.frame >= options.frames) {
            captured = true;
            quit = true;
        }
    }

    if (captured) {
        const path = options.out orelse "shots/run-window.png";
        ensureParent(io, path);
        game.render();
        try game.saveScreenshot(io, path);
        std.debug.print("run window capture -> {s}\n", .{path});
    }
}

pub fn main(init: std.process.Init.Minimal) !void {
    const gpa = std.heap.page_allocator;
    const argv = try init.args.toSlice(gpa);
    const options = parseOptions(argv) catch |err| switch (err) {
        error.MissingValue, error.BadResolution, error.UnknownOption => return err,
        else => return err,
    };
    if (options.help) {
        usage();
        return;
    }
    if (options.hero > 2) {
        std.debug.print("vx: --hero must be 0, 1 or 2\n", .{});
        return error.BadHero;
    }
    if (options.aim) |aim| {
        if (aim > 2) {
            std.debug.print("vx: --aim must be 0, 1 or 2\n", .{});
            return error.BadAim;
        }
    }

    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    if (options.arena) {
        const game = try vx.Game.create(gpa, options.width, options.height);
        defer game.destroy();

        game.selectHero(options.hero);
        snapCamera(game, options);
        game.debug = options.debug;
        game.show_hud = !options.hide_hud;
        if (options.lineup) game.lineup();
        if (options.inventory) game.inventory_open = true;

        if (options.headless) {
            try runHeadless(game, io, options);
        } else {
            try runWindow(game, io, options);
        }
        return;
    }

    const class = vx.run_sim.classFromIndex(@intCast(options.hero));
    const game = try vx.RunGame.create(gpa, options.width, options.height, class, options.seed);
    defer game.destroy();

    game.debug = options.debug;
    game.show_hud = !options.hide_hud;
    game.presentation = !options.auto_demo and !options.headless;
    if (options.enemy_phase_shot) game.presentation = true;
    game.camera.yaw = options.yaw;
    game.camera.pitch = options.pitch;
    game.camera.distance = @max(options.dist, 15.2);
    game.show_help = options.help_screen;

    // Window play starts on the class cards; headless QA keeps its old
    // instant-start behaviour unless --start-menu is explicit. --hero always
    // skips the menu so scripted screenshots stay stable.
    const wants_menu = !options.hero_set and (options.start_menu or !options.headless);
    if (wants_menu and !options.hide_hud and !options.inventory and !options.character and options.loot == 0) {
        game.openMenu();
    }

    if (options.inventory) game.panel = .inventory;
    if (options.character) game.panel = .character;
    if (options.slots_shot) game.openSlotMenu(io, .save);
    if (options.auto_slots_shot) game.openAutoMenu(io);
    if (options.loot > 0) game.debugGrantLoot(options.loot);

    if (options.headless) {
        try runRunHeadless(game, io, options);
    } else {
        try runRunWindow(game, io, options);
    }
}
