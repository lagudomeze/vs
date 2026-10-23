//! Turn order and speed cadence for the turn-based 3D pixel roguelike.
//!
//! This module is pure data: no ECS, Game, renderer, input or realtime clock.
//! The caller maps `Actor.id` to an entity and owns all action legality and
//! animation; this module only decides who acts, when, and how many times.
//!
//! v1 cadence (rounds are 1-based):
//!
//!   * player-side actors always act first, once per round;
//!   * enemy speed >= 150: 1 action on odd rounds, 2 on even rounds;
//!   * enemy speed <= 75:  1 action on odd rounds, 0 on even rounds;
//!   * enemy speed 76..149: 1 action every round;
//!   * speed 0 never acts.
//!
//! The even-round bonus/skip gives exactly one extra/fewer action per two
//! rounds. It is pure round parity plus a stable speed sort, so it needs no
//! dt, RNG or accumulated float energy.
//!
//! Two equivalent ways to drive it:
//!
//!   // iterator style: automatically starts the next round
//!   var order = try TurnOrder.init(&actors);
//!   while (order.nextTurn()) |turn| {
//!       if (turn.round_started) tickCooldowns(...);
//!       if (turn.actor.side == .player) handlePlayer(turn) else handleEnemy(turn);
//!   }
//!
//!   // manual style: current() + endActor()
//!   order.beginRound();
//!   while (order.current()) |actor| { ...; _ = order.endActor(); }
//!
//! Cooldowns/resources are per-round; call `tickCooldowns` once on
//! `round_started`, never per frame.

const std = @import("std");

/// Entity ids (zflecs `entity_t`) convert to this losslessly.
pub const Entity = u64;

/// Dungeon floors have one player plus a few enemies; 32 is plenty.
pub const max_actors: usize = 32;

/// A speed >= 150 actor can take two actions in a round.
pub const max_actions: usize = max_actors * 2;

pub const Side = enum {
    player,
    enemy,
};

/// Plain actor descriptor. `speed` uses the turn-based convention: 100 = normal,
/// 150 = fast, 75 or below = slow. The player is always first regardless of
/// this value.
pub const Actor = struct {
    id: Entity = 0,
    speed: u16 = 100,
    side: Side = .enemy,
};

/// Action kinds accepted by the turn system. Legality (AP/cooldown/range/target)
/// is entirely the caller's job; every kind consumes the actor's turn.
pub const ActionKind = enum {
    move,
    attack,
    talent,
    wait,
};

/// One yielded action slot.
pub const Turn = struct {
    /// 1-based round number.
    round: u32 = 0,
    actor: Actor = .{},
    /// 0-based action index for this actor in this round (0, or 1 for the
    /// second action of a fast actor on an even round).
    action_index: u8 = 0,
    /// True only for the first action of a round. Tick per-round cooldowns,
    /// statuses and resource regeneration when this is set.
    round_started: bool = false,
};

/// How many actions `speed` gets in `round` (1-based). Exposed for HUD/QA.
/// The player's speed is intentionally not passed here: the caller always gives
/// the player one action per round.
pub fn actionsForRound(speed: u16, round: u32) u8 {
    std.debug.assert(round > 0);
    if (speed == 0) return 0;
    if (speed >= 150) return if (round % 2 == 0) 2 else 1;
    if (speed <= 75) return if (round % 2 == 0) 0 else 1;
    return 1;
}

const QueueEntry = struct {
    /// Index into TurnOrder.actors.
    actor: u8 = 0,
    /// 0-based action index within the round.
    action: u8 = 0,
};

pub const TurnOrder = struct {
    actors: [max_actors]Actor = undefined,
    actor_count: usize = 0,

    queue: [max_actions]QueueEntry = undefined,
    queue_len: usize = 0,
    cursor: usize = 0,

    round: u32 = 0,
    started: bool = false,

    pub const InitError = error{TooManyActors};

    /// Copies the actor descriptors. Re-init (or `setActors`) when the roster
    /// changes; `actorAt` can update speed/id in place between rounds.
    pub fn init(actors: []const Actor) InitError!TurnOrder {
        var self = TurnOrder{};
        try self.setActors(actors);
        return self;
    }

    /// Replaces the roster and resets the order to "not started". Use this on a
    /// new floor or after the party changes.
    pub fn setActors(self: *TurnOrder, actors: []const Actor) InitError!void {
        if (actors.len > max_actors) return error.TooManyActors;
        self.actor_count = actors.len;
        for (actors, 0..) |actor, index| self.actors[index] = actor;
        self.queue_len = 0;
        self.cursor = 0;
        self.round = 0;
        self.started = false;
    }

    /// Mutable access for speed/id updates between rounds. Changes apply to the
    /// next `beginRound`; the current queue is already built.
    pub fn actorAt(self: *TurnOrder, index: usize) ?*Actor {
        if (index >= self.actor_count) return null;
        return &self.actors[index];
    }

    pub fn roundNumber(self: *const TurnOrder) u32 {
        return self.round;
    }

    pub fn actorCount(self: *const TurnOrder) usize {
        return self.actor_count;
    }

    /// True before the first beginRound and after the last action of a round.
    pub fn isRoundOver(self: *const TurnOrder) bool {
        return !self.started or self.cursor >= self.queue_len;
    }

    /// The actor whose action is next, or null when the round is over / not
    /// started. Pair with `endActor` for manual control.
    pub fn current(self: *const TurnOrder) ?Actor {
        if (!self.started or self.cursor >= self.queue_len) return null;
        return self.actors[self.queue[self.cursor].actor];
    }

    /// Starts the next round: increments `roundNumber`, rebuilds the queue and
    /// points at the first actor. Player-side actors are always first (input
    /// order); enemies follow sorted by speed descending, ties by input order.
    /// Callers should tick cooldowns once per round themselves.
    pub fn beginRound(self: *TurnOrder) void {
        self.round += 1;
        self.started = true;
        self.cursor = 0;
        self.queue_len = 0;

        // Player-side actors open the round, in input order. v1 has one player.
        for (self.actors[0..self.actor_count], 0..) |actor, index| {
            if (actor.side != .player) continue;
            self.append(@intCast(index), 0);
        }

        // Enemies sorted by speed, descending; stable for equal speeds.
        var enemy_indices: [max_actors]u8 = undefined;
        var enemy_count: usize = 0;
        for (self.actors[0..self.actor_count], 0..) |actor, index| {
            if (actor.side != .enemy) continue;
            enemy_indices[enemy_count] = @intCast(index);
            enemy_count += 1;
        }

        var i: usize = 1;
        while (i < enemy_count) : (i += 1) {
            const value = enemy_indices[i];
            var j = i;
            while (j > 0 and self.enemyBefore(value, enemy_indices[j - 1])) : (j -= 1) {
                enemy_indices[j] = enemy_indices[j - 1];
            }
            enemy_indices[j] = value;
        }

        for (enemy_indices[0..enemy_count]) |index| {
            const actions = actionsForRound(self.actors[index].speed, self.round);
            var action: u8 = 0;
            while (action < actions) : (action += 1) {
                self.append(index, action);
            }
        }
    }

    /// Ends the current actor's action and returns the next actor, or null when
    /// the round is over. Does not begin the next round.
    pub fn advance(self: *TurnOrder) ?Actor {
        if (!self.started) return null;
        if (self.cursor < self.queue_len) self.cursor += 1;
        return self.current();
    }

    /// Semantic alias for `advance`: the current actor has finished acting.
    pub fn endActor(self: *TurnOrder) ?Actor {
        return self.advance();
    }

    /// Iterator driver: returns the next action in sequence and consumes it.
    /// When the current round is exhausted it starts the next round first, so
    /// the sequence is "player action -> every enemy action -> new round".
    ///
    /// `round_started` is set on the first action of each round. A round with
    /// no actions at all (e.g. only slow enemies and no player on an even
    /// round) is skipped; the next call starts the following round.
    ///
    /// Do not mix this with a manual `endActor` for the same turn: nextTurn
    /// already advanced the cursor.
    pub fn nextTurn(self: *TurnOrder) ?Turn {
        if (self.actor_count == 0) return null;

        if (!self.started or self.cursor >= self.queue_len) {
            self.beginRound();
            if (self.cursor >= self.queue_len) return null;
        }

        const entry = self.queue[self.cursor];
        const turn = Turn{
            .round = self.round,
            .actor = self.actors[entry.actor],
            .action_index = entry.action,
            .round_started = self.cursor == 0,
        };
        self.cursor += 1;
        return turn;
    }

    fn append(self: *TurnOrder, actor_index: u8, action_index: u8) void {
        std.debug.assert(self.queue_len < max_actions);
        self.queue[self.queue_len] = .{
            .actor = actor_index,
            .action = action_index,
        };
        self.queue_len += 1;
    }

    fn enemyBefore(self: *const TurnOrder, lhs: u8, rhs: u8) bool {
        const a = self.actors[lhs];
        const b = self.actors[rhs];
        if (a.speed != b.speed) return a.speed > b.speed;
        return lhs < rhs;
    }
};

/// Decrements each positive cooldown by `turns`, saturating at zero. Call once
/// per round (on `Turn.round_started`), never per frame.
pub fn tickCooldowns(cooldowns: []u16, turns: u16) void {
    for (cooldowns) |*cooldown| {
        cooldown.* = if (cooldown.* > turns) cooldown.* - turns else 0;
    }
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

const TestActor = struct {
    id: Entity,
    speed: u16,
    side: Side,
};

fn actorsOf(specs: []const TestActor) [max_actors]Actor {
    var actors: [max_actors]Actor = undefined;
    for (specs, 0..) |spec, index| {
        actors[index] = .{ .id = spec.id, .speed = spec.speed, .side = spec.side };
    }
    return actors;
}

test "speed cadence: thresholds and round parity" {
    // Normal actors act once every round.
    try std.testing.expectEqual(@as(u8, 1), actionsForRound(76, 1));
    try std.testing.expectEqual(@as(u8, 1), actionsForRound(100, 1));
    try std.testing.expectEqual(@as(u8, 1), actionsForRound(149, 2));

    // Fast: one extra action every second round.
    try std.testing.expectEqual(@as(u8, 1), actionsForRound(150, 1));
    try std.testing.expectEqual(@as(u8, 2), actionsForRound(150, 2));
    try std.testing.expectEqual(@as(u8, 1), actionsForRound(150, 3));
    try std.testing.expectEqual(@as(u8, 2), actionsForRound(150, 4));
    try std.testing.expectEqual(@as(u8, 2), actionsForRound(400, 2));

    // Slow: one fewer action every second round.
    try std.testing.expectEqual(@as(u8, 1), actionsForRound(75, 1));
    try std.testing.expectEqual(@as(u8, 0), actionsForRound(75, 2));
    try std.testing.expectEqual(@as(u8, 1), actionsForRound(75, 3));
    try std.testing.expectEqual(@as(u8, 0), actionsForRound(75, 4));
    try std.testing.expectEqual(@as(u8, 0), actionsForRound(0, 1));
    try std.testing.expectEqual(@as(u8, 0), actionsForRound(0, 2));
}

test "nextTurn: player first, speed order, fast extra and slow skip" {
    // Deliberately shuffled input: player must still open every round.
    const specs = [_]TestActor{
        .{ .id = 30, .speed = 75, .side = .enemy },
        .{ .id = 20, .speed = 100, .side = .enemy },
        .{ .id = 1, .speed = 50, .side = .player },
        .{ .id = 10, .speed = 150, .side = .enemy },
    };
    var storage = actorsOf(&specs);
    var order = try TurnOrder.init(storage[0..specs.len]);

    const Expected = struct {
        round: u32,
        id: Entity,
        action: u8,
    };
    const expected = [_]Expected{
        .{ .round = 1, .id = 1, .action = 0 },
        .{ .round = 1, .id = 10, .action = 0 },
        .{ .round = 1, .id = 20, .action = 0 },
        .{ .round = 1, .id = 30, .action = 0 },

        .{ .round = 2, .id = 1, .action = 0 },
        .{ .round = 2, .id = 10, .action = 0 },
        .{ .round = 2, .id = 10, .action = 1 },
        .{ .round = 2, .id = 20, .action = 0 },

        .{ .round = 3, .id = 1, .action = 0 },
        .{ .round = 3, .id = 10, .action = 0 },
        .{ .round = 3, .id = 20, .action = 0 },
        .{ .round = 3, .id = 30, .action = 0 },

        .{ .round = 4, .id = 1, .action = 0 },
        .{ .round = 4, .id = 10, .action = 0 },
        .{ .round = 4, .id = 10, .action = 1 },
        .{ .round = 4, .id = 20, .action = 0 },
    };

    var last_round: u32 = 0;
    for (expected, 0..) |want, index| {
        const turn = order.nextTurn() orelse return error.ExpectedTurn;
        try std.testing.expectEqual(want.round, turn.round);
        try std.testing.expectEqual(want.id, turn.actor.id);
        try std.testing.expectEqual(want.action, turn.action_index);
        try std.testing.expectEqual(last_round != turn.round, turn.round_started);
        if (turn.round_started) {
            try std.testing.expectEqual(Side.player, turn.actor.side);
        }
        last_round = turn.round;
        _ = index;
    }

    // The next call has already begun round 5, still with the player first.
    const next = order.nextTurn() orelse return error.ExpectedTurn;
    try std.testing.expectEqual(@as(u32, 5), next.round);
    try std.testing.expectEqual(@as(Entity, 1), next.actor.id);
    try std.testing.expect(next.round_started);
}

test "manual API: beginRound, current, advance, endActor" {
    const specs = [_]TestActor{
        .{ .id = 1, .speed = 100, .side = .player },
        .{ .id = 10, .speed = 150, .side = .enemy },
        .{ .id = 20, .speed = 100, .side = .enemy },
        .{ .id = 30, .speed = 75, .side = .enemy },
    };
    var storage = actorsOf(&specs);
    var order = try TurnOrder.init(storage[0..specs.len]);

    try std.testing.expect(order.current() == null);
    try std.testing.expect(order.isRoundOver());
    try std.testing.expect(order.endActor() == null);

    order.beginRound();
    try std.testing.expectEqual(@as(u32, 1), order.roundNumber());
    try std.testing.expect(!order.isRoundOver());

    try std.testing.expectEqual(@as(Entity, 1), order.current().?.id);
    try std.testing.expectEqual(@as(Entity, 10), order.endActor().?.id);
    try std.testing.expectEqual(@as(Entity, 20), order.endActor().?.id);
    try std.testing.expectEqual(@as(Entity, 30), order.endActor().?.id);
    try std.testing.expect(order.endActor() == null);
    try std.testing.expect(order.isRoundOver());

    order.beginRound();
    try std.testing.expectEqual(@as(u32, 2), order.roundNumber());
    try std.testing.expectEqual(@as(Entity, 1), order.current().?.id);
    try std.testing.expectEqual(@as(Entity, 10), order.advance().?.id);
    try std.testing.expectEqual(@as(Entity, 10), order.advance().?.id);
    try std.testing.expectEqual(@as(Entity, 20), order.advance().?.id);
    try std.testing.expect(order.advance() == null); // slow enemy skipped on round 2
    try std.testing.expect(order.isRoundOver());
}

test "speed ties keep input order; speed 0 never acts" {
    const specs = [_]TestActor{
        .{ .id = 1, .speed = 100, .side = .player },
        .{ .id = 22, .speed = 100, .side = .enemy },
        .{ .id = 11, .speed = 100, .side = .enemy },
        .{ .id = 99, .speed = 0, .side = .enemy },
    };
    var storage = actorsOf(&specs);
    var order = try TurnOrder.init(storage[0..specs.len]);
    order.beginRound();

    try std.testing.expectEqual(@as(Entity, 1), order.current().?.id);
    try std.testing.expectEqual(@as(Entity, 22), order.endActor().?.id);
    try std.testing.expectEqual(@as(Entity, 11), order.endActor().?.id);
    try std.testing.expect(order.endActor() == null);
}

test "determinism: identical actors produce identical sequences" {
    const specs = [_]TestActor{
        .{ .id = 1, .speed = 100, .side = .player },
        .{ .id = 10, .speed = 150, .side = .enemy },
        .{ .id = 20, .speed = 100, .side = .enemy },
        .{ .id = 30, .speed = 75, .side = .enemy },
    };
    var storage = actorsOf(&specs);
    var first = try TurnOrder.init(storage[0..specs.len]);
    var second = try TurnOrder.init(storage[0..specs.len]);

    var index: usize = 0;
    while (index < 40) : (index += 1) {
        const a = first.nextTurn() orelse return error.ExpectedTurn;
        const b = second.nextTurn() orelse return error.ExpectedTurn;
        try std.testing.expectEqual(a.round, b.round);
        try std.testing.expectEqual(a.actor.id, b.actor.id);
        try std.testing.expectEqual(a.actor.speed, b.actor.speed);
        try std.testing.expectEqual(a.actor.side, b.actor.side);
        try std.testing.expectEqual(a.action_index, b.action_index);
        try std.testing.expectEqual(a.round_started, b.round_started);
    }
}

test "tickCooldowns decrements once per round and saturates" {
    var cooldowns = [_]u16{ 0, 1, 4, 12 };
    tickCooldowns(&cooldowns, 0);
    try std.testing.expectEqualSlices(u16, &[_]u16{ 0, 1, 4, 12 }, &cooldowns);

    tickCooldowns(&cooldowns, 1);
    try std.testing.expectEqualSlices(u16, &[_]u16{ 0, 0, 3, 11 }, &cooldowns);

    tickCooldowns(&cooldowns, 5);
    try std.testing.expectEqualSlices(u16, &[_]u16{ 0, 0, 0, 6 }, &cooldowns);

    tickCooldowns(&cooldowns, 100);
    try std.testing.expectEqualSlices(u16, &[_]u16{ 0, 0, 0, 0 }, &cooldowns);
}

test "init rejects more than max_actors; setActors resets the order" {
    var too_many: [max_actors + 1]Actor = undefined;
    for (&too_many, 0..) |*actor, index| {
        actor.* = .{ .id = index, .side = .enemy };
    }
    try std.testing.expectError(error.TooManyActors, TurnOrder.init(&too_many));

    const specs = [_]TestActor{
        .{ .id = 1, .speed = 100, .side = .player },
        .{ .id = 10, .speed = 100, .side = .enemy },
    };
    var storage = actorsOf(&specs);
    var order = try TurnOrder.init(storage[0..specs.len]);
    _ = order.nextTurn();
    try std.testing.expectEqual(@as(u32, 1), order.roundNumber());

    const replacement = [_]TestActor{
        .{ .id = 1, .speed = 100, .side = .player },
        .{ .id = 11, .speed = 150, .side = .enemy },
        .{ .id = 12, .speed = 150, .side = .enemy },
    };
    var replacement_storage = actorsOf(&replacement);
    try order.setActors(replacement_storage[0..replacement.len]);
    try std.testing.expectEqual(@as(u32, 0), order.roundNumber());
    try std.testing.expectEqual(@as(usize, 3), order.actorCount());
    try std.testing.expect(order.current() == null);
    try std.testing.expect(order.isRoundOver());
}
