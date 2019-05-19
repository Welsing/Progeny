"""
The base character class which is meant to be
inherited by all characters. It contains necessary
common functions for it to behave like a character.
It is designed to be inherited in particular by
player characters and bots.

Functions are to be as pure as possible, meaning
that they should cause no or as few side effects as
possible, and they should ideally always return
the same value when the arguments provided have the
same value. This makes it much easier to predict
the results and also allows for easier syncing
between clients over a network.
"""
class_name Prog
extends Area2D

signal player_killed()
signal player_respawned()

# Your Prog's very own beautiful color scheme
export(Color) sync var primary_color
export(Color) sync var secondary_color
#export(NodePath) var player: NodePath
#onready var nd_player: Player = get_node(player) as Player

const WEP_CD = 1.0    # Weapon cooldown
const JUMP_CD = 0.1    # Jump cooldown after landing
const MAX_SPEED = 1500    # Max horizontal (ground) speed
const MAX_JUMP_RANGE = 1000    # How far you can jump from any given starting pos
const JUMP_Q_LIM = 2    # Jump queue limit
const G = 9.8 * 1000

onready var nd_sprite = get_node("Sprite")
#onready var nd_insignia = get_node("Sprite/Insignia/InsigniaViewport/InsigniaSprite")
onready var nd_shadow = get_node("Shadow")
onready var nd_shadow_opacity = nd_shadow.modulate.a
onready var nd_shadow_scale = nd_shadow.get_scale()
#onready var nd_hud = game_state.nd_game_round.get_node("HUD")
onready var game_state = $"/root/GameState"

# "enums"
# enum Condition {OK, DEAD, RESPAWNING, STUNNED}
# enum Action {IDLE, MOVING, ATTACKING, BUSY}
# enum ""{GOOD, MOVING, ATTACKING, STUNNED, RESPAWNING, DEAD}
# enum Power {ON, OFF}

var mouse_pos = Vector2()

remotesync var damaged_by = null

#puppet var puppet_pos = Vector2()
puppet var puppet_atk_loc = Vector2()
#puppet var puppet_motion = Vector2()
#puppet var puppet_focus = Vector2()

# Counters
#var points = 0
#var time_of_death = null    # If applicable


## Dicts

remotesync var state := {
    timers = {},
    target = null,
    motion = Vector2(),  # Horizontal
    height = 0,          # Vertical
    path   = {
        position = Vector2(),
        from     = null,
        to       = [],    # Take note that this is a jump queue array
        }
} setget set_state, get_state


###########################
## SetGetters / queries    ##
###########################

#-------------
# General state

remotesync func set_state(new_state: Dictionary):
    # if new_state["timers"].has("dead"):
    #     queue_free()
    if new_state["timers"].has("stunned"):
        var t = new_state["timers"]["stunned"]
        new_state["timers"].clear()
        new_state["timers"]["stunned"] = t
    state = set_motion_state(new_state)

func get_state():
    return state


#-------------

##########################


# func update_states(delta, timers):

#     if timers.size() > 0:
#         for timer in timers:
#             timers[timer] -= delta
#             if (timers[timer] <= 0.0):
#                 timers.erase(timer)

#     return timers


##################################################

# For rotating the insignia sprite towards the given point (point is in global coords)
master func new_rot(delta, current_pos, current_rot, point):
    var dir = point - current_pos
    dir.y *= 2

    # Use degrees 'cause it be more intuitive
    var new_rot_deg = rad2deg(dir.angle())
    var current_rot_deg = rad2deg(current_rot)

    # Always count rot in the positive
    while new_rot_deg < 0:
        new_rot_deg = new_rot_deg + 360
    while current_rot_deg < 0:
        current_rot_deg = current_rot_deg + 360

    var d_angle_deg = new_rot_deg - current_rot_deg

    var s = sign(d_angle_deg)
    d_angle_deg = abs(d_angle_deg)

    # Don't go the long way around, it's stupid
    if d_angle_deg > 180:
        s *= -1
        d_angle_deg = 360 - d_angle_deg

    # Now go back to radians to make Godot happy
    var d_angle = deg2rad(d_angle_deg)

    var rot_speed = 3
    var min_rot_speed = 0.04

    var smooth_rot_speed = delta * rot_speed * d_angle * d_angle
    var d_rot = s * min(d_angle, max(smooth_rot_speed, min_rot_speed))
    var new_rot = current_rot + d_rot

    # Don't keep inflating the rot value
    if new_rot > 2*PI:
        new_rot -= 2*PI
    elif new_rot < 0:
        new_rot += 2*PI

    return new_rot


# Well, this one makes you respawn
func respawn(pos = game_state.rand_loc(Vector2(0,0),0,1000)):

    set_monitorable(true)    # Enable detection by other bodies and areas
    self.hide()
    position = (pos)

    state["timers"]["shield"] = 2.0
    state["path"] = { "position" : pos, "from" : null, "to" : [] }
    rpc("set_state", state)
    emit_signal("player_respawned", get_name())


func _area_enter(nd_area):
    if nd_area.is_in_group("Damaging"):
        var wielder = nd_area.wielder
        var my_name = get_name()
        if not wielder == my_name:
            rset("damaged_by", nd_area.wielder)


func die(state, killer):
    set_monitorable(false)
    self.hide()

#    var nd_death_anim = preload("res://common/DeathEffect.tscn").instance()
#    nd_death_anim.position = (self.position)
#    get_parent().add_child(nd_death_anim)

    state["timers"]["dead"] = game_state.nd_game_round.get_respawn_time()

    emit_signal("player_killed", get_name(), killer, state["timers"]["dead"])

    return state


func shield_deflect(state):
    # Fancy shield deflection animation
    return state


sync func spawn_energy_beam(from, to):
    var nd_energy_beam = preload("res://scenes/weapon/EnergyBeam.tscn").instance()
    nd_energy_beam.wielder = get_name()
    nd_energy_beam.destination = to
    nd_energy_beam.global_position = from
    get_parent().add_child(nd_energy_beam)

#    var nd_beam_impact = preload("res://scenes/weapon/EnergyBeamImpact.tscn").instance()
#    nd_beam_impact.wielder = nd_energy_beam.wielder
#    nd_beam_impact.position = (to)
#    get_parent().add_child(nd_beam_impact)


puppet func puppet_attack(loc):
    spawn_energy_beam(self.position, loc)
    puppet_atk_loc = null


# Attack given location (not relative to prog)
master func attack(state):
    rpc("spawn_energy_beam", self.position, state["target"])
    spawn_energy_beam(self.position, state["target"])

    state["timers"]["attacking"] = 0.2
    state["timers"]["weapon_cd"] = WEP_CD
    state["target"] = null

    return state


sync func set_colors(primary, _secondary):

    if primary_color != null:
        nd_sprite.set_modulate(primary)
        # nd_sprite.rpc("set_modulate", primary_color)
#    if secondary_color != null:
#        nd_insignia.set_modulate(secondary)
        # nd_insignia.rpc("set_modulate", secondary_color)
    return


sync func animate_jump(state):
    var jump_height = state["height"]
#    print(jump_height)
    # If we're not in the air, just set everything
    # accordingly and skip the calculations.
    if jump_height <= 0:
        self.z_index = 1    # Back onto ground
        nd_sprite.position = (Vector2(0, 0))
        nd_shadow.modulate.a = nd_shadow_opacity
        nd_shadow.set_scale(nd_shadow_scale)
    else:
        # Set sprite vertical pos based on height and
        # adjusted for the perspective
        var sprite_pos = Vector2(0, -1) * (jump_height)

        # Since the lightsource is ~26 degrees rotated downwards vertically
        # the shadow should project about halfway between directly below
        # and (from the camera's perspective) directly behind the Prog.
        var shadow_pos = sprite_pos * 0.5

        var no_shadow_h = 600
        var shadow_opacity = 1 - clamp(jump_height / no_shadow_h, 0, 1)
        shadow_opacity *= nd_shadow_opacity

        nd_sprite.position = sprite_pos
        nd_shadow.position = shadow_pos
        nd_shadow.modulate.a = shadow_opacity
        self.z_index = jump_height + 1    # +1 to render after everything below

        state["timers"]["moving"] = 10.0
    return


func set_motion_state(state_: Dictionary) -> Dictionary:

    var path = state_["path"]
    # Check if there are any jumps queued and
    # if so pop any that hold our current pos.
    # Use while loop to catch any duplicates.
    while path["to"].size() > 0 and path["position"] == path["to"][0]:
        path["to"].pop_front()
        path["from"] = path["position"] if path["to"].size() > 0 else null

    # Check if (supposed to be) moving and apply motion
    if (state_["motion"].length() > 0 or path["to"].size() > 0):
        # Disable detection by other bodies and areas.
        # This is to avoid hitting or being hit by anything while jumping.
        set_monitorable(false)
        self.position = (path["position"] + state_["motion"])
    # Stun on landing
    elif state_["timers"].has("moving"):
        set_monitorable(true)
        state_["timers"]["stunned"] = JUMP_CD
        set_state(state_)

    state_["path"] = path
    return state_


# Update the state_ of motion to reflect what is desired
static func new_motion_state(delta: float, state_: Dictionary) -> Dictionary:

    var path = state_["path"]
    var dist_covered = path["position"] - path["from"]
    dist_covered.y *= 2
    dist_covered = dist_covered.length()

    var dist_total = path["to"][0] - path["from"]
    dist_total.y *= 2
    dist_total = dist_total.length()

    var dir = path["to"][0] - path["position"]
    dir.y *= 2
    dir = dir.normalized()


    # Where to put ourselves next
    var speed = min(dist_total*2, MAX_SPEED)
    state_["motion"] = dir * speed * delta
    state_["motion"].y *= 0.5
    # If about to overshoot destination
    var current_speed = state_["motion"].length()
    var dist = path["position"].distance_to(path["to"][0])
    var coming_in_hot = ( current_speed > 0 ) and ( current_speed >= dist )
    if coming_in_hot:
        state_["motion"] = path["to"][0] - path["position"]

    var jump_completion = dist_covered / dist_total if dist_total > 0 else 1
    var total_time = dist_total / speed
    var t = total_time * jump_completion
    state_["height"] = height_at(t, total_time)

    state_["path"] = path
    return state_


static func height_at(t, t_total):
    # d_y = v_0y * t + (1/2)(-g)(t^2) when
    # t is total_time and
    # d_y (displacement in height) is 0 we get the initial velocity:
    var v_0y = 0.5 * G * t_total
    # and now we can use the original formula above
    return v_0y * t + 0.5 * (-G) * t * t



static func fake_mouse_move(bot_pos, mouse_pos, chance):
    var move_fake_mouse = rand_range(0, 100) <= chance
    return GameState.rand_loc(bot_pos, 0, 1) if move_fake_mouse else mouse_pos


func _physics_process(delta):

    var state_ = get_state()

    var incapacitated = false

    # Update all state_ timers.
    var updated_timers = {}
    for timer in state_["timers"]:
        var time = state_["timers"][timer] - delta
        var expired = time <= 0
        match timer:
            { "stunned": _, .. }:
                incapacitated = !expired
            { "dead": _, .. }:
                if expired:
                    respawn()
                    state_["timers"] = {}
                    return
                else:
                    state_["timers"] = { "dead": timer["dead"] }
                    return
        if not expired:
            updated_timers[timer] = time

    state_["timers"] = updated_timers

    if incapacitated:
        return

    if damaged_by != null:
        if state_["height"] < 10:
            var shielded = state_["timers"].has("shield")
            state_ = shield_deflect(state_) if shielded else die(state_, damaged_by)
        damaged_by = null

#    if not self.is_network_master():
#        return

#    print("Am network master")
    state_["path"]["position"] = self.position


#    var is_bot = is_in_group("Bot")
#    if is_bot:
#        var botbrain = ai_processing(delta, get_botbrain(), state_)
#        state_["target"] = botbrain["attack_location"]
#        botbrain["attack_location"] = null
#        rpc("set_botbrain", botbrain)

#    if is_bot:
#        self.mouse_pos = fake_mouse_move(self.position, mouse_pos, 60 * delta)
#    else:
    mouse_pos = get_global_mouse_position()

#    var path = get_botbrain()["path"] if is_bot else state_["path"]
    var path = state_["path"]
    if not path["to"].empty():
        if path["to"].size() > JUMP_Q_LIM:
            path["to"].resize(JUMP_Q_LIM + 1)
        if path["from"] == null:
            path["from"] = path["position"]
        state_["path"] = path
        state_ = new_motion_state(delta, state_)

    if not state_["timers"].has("weapon_cd") and state_["target"] != null:
        state_ = attack(state_)
        print("attacking")

    # While insignia is broken, focus is useless
#    var is_attacking = state_["target"] != null and state_["timers"].has("attacking")
#    var dest_or_mpos = path["to"][0] if not path["to"].empty() else mouse_pos
#    var focus = state_["target"] if is_attacking else dest_or_mpos

    state_["path"] = path
#    rset("puppet_focus", focus)
    rpc("set_state", state_)
    rpc("animate_jump", state_)

    # Insignia broke while porting to 3.0.
#    nd_insignia.set_rot(new_rot(delta, path["position"], nd_insignia.get_rot(), focus))

    return


static func rand_color():
    return Color(
        rand_range(0, 0.7),
        rand_range(0, 0.7),
        rand_range(0, 0.7),
        rand_range(0.5, 0.7))

######################
######################
######################


func _ready():
    if is_network_master():
        self.connect("area_enter", self, "_area_enter")
        # if is_in_group("Bot"):
        rset("primary_color", rand_color())
        rset("secondary_color", rand_color())
        rpc("set_colors", primary_color, secondary_color)

    set_physics_process(true)