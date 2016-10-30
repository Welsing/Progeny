extends KinematicBody2D

########################
### Global variables ###
########################
# ATTK_CD = attack cooldown
# DEST_R = radius for destination approximation 
# MAX_SPEED =  max movement ground_speed (magnitude)
# JUMP_CD = cooldown for jump
# ROT_SPEED = (visual) turning ground_speed for character
const ATTK_CD = 0.5
const DEST_R = 5.0
const MAX_SPEED = 1000
const JUMP_CD = 0.1
const ROT_SPEED = 2

## Cooldowns
# Set and updated by status update func
var attk_cd = 0
var rooted_timer = 0
var stunned_timer = 0
var busy_cd = 0
var attk_dur = 0

## Impediments
# Set and updated by status update func
var attacking = false		# Shared with fixed process and set by attack function
var rooted = false
var stunned = false
var impeded = false			# Shared with functions here and there
var busy = false

## Movement booleans
var moving = false

## Movement vectors
var start_pos = Vector2()	# Shared between input process and movement functions
var motion = Vector2(0,0)

## Misc
var mouse_pos = Vector2()	# Shared all over

## action dicts
var jump = {
	"start_pos"			:	Vector2(),
	"target_coords"		:	[]
}
var attack = {
	"target_coords"		:	Vector2()
}


#########################
#########################
#########################


func update_states(delta):

	if motion > Vector2(0,0):
		moving = true
	else:
		moving = false

	if rooted or stunned or busy:
		impeded = true
	else:
		impeded = false
	
	# Various status effects and their cooldowns
	if rooted_timer > 0:
		rooted = true
		rooted_timer -= delta
	else:
		rooted = false
		
	if stunned_timer > 0:
		stunned = true
		stunned_timer -= delta
	else:
		stunned = false
	
	# attack cooldowns
	if attk_cd > 0:
		attk_cd -= delta
	
	# attack duration
	if attk_dur > 0:
		attacking = true
		attk_dur -= delta
	else:
		attacking = false
		
	# apply busy status if busy doing stuff
	if attacking:
		busy = true
	else:
		busy = false


func dir_vscaled(from, to):
	
	var dir_vscaled = to - from
	dir_vscaled.y /= GLOBALS.VSCALE # Compensate for velocity_magnitude.y*=GLOBALS.VSCALE
	dir_vscaled = dir_vscaled.normalized()
	return dir_vscaled
	
##################################################


# Create a transparent, ghost-like character sprite to represent it as if 
# it had already arrived at its destination
func update_predictor(): 

	var indicator = get_node("Indicator")
	
	# If there's a destination, put there, otherwise, put on char pos
	if jump.target_coords.size() > 0:
		indicator.set_global_pos(jump.target_coords[0])
		indicator.show()
	else:
		indicator.set_global_pos(get_pos())
		indicator.hide()


func face_dir(focus):
	
	var face_dir = dir_vscaled(get_pos(), focus) * -1
	
	# Need to compensate with offset of the face_dir because the viewport only includes quadrant IV so sprite had to be moved into it 
	# Don't waste any more time looking at this. Just leave it. This is how it is.
	var insignia = get_node("CharacterSprite/InsigniaViewport/Insignia")
	var dir_compensated = face_dir + insignia.get_pos()
	
	var angle = insignia.get_angle_to(dir_compensated)
	var s = sign(angle)
	angle = abs(angle)
	
	insignia.rotate(min(angle, (get_fixed_process_delta_time()*ROT_SPEED*angle*angle)+0.1)*s)

func die():
	# Dramatic animation goes here
	print(get_collider().get_name() + " killed " + get_name())
	queue_free()

func attack():
	
	attk_cd = ATTK_CD
	attk_dur = 0.5
	
	# Spawn projectile
	if not attacking:
		var projectile = preload("res://common/Projectile/projectile.tscn").instance()
		var attack_dir = dir_vscaled(get_pos(), attack.target_coords)
		
		# Initial position and direction
		projectile.advance_dir = attack_dir
		projectile.set_pos( get_pos() + attack_dir * Vector2(128,64) )
		get_parent().add_child(projectile)
	

func stop_moving():
	
	motion = Vector2(0,0)
	set_pos(jump.target_coords[0])
	moving = false
	
	jump.target_coords.pop_front()
	stunned_timer = JUMP_CD
	
	
func move_towards_destination(delta):
	
	var dir = dir_vscaled(get_pos(), jump.target_coords[0])
	
#	if motion == Vector2(0,0):
	motion = dir * MAX_SPEED * delta
	motion.y *= GLOBALS.VSCALE
	move(motion)


func supposed_to_be_moving():
	
	var current_pos = get_pos()
	
	# Check if no jumps are queued
	if jump.target_coords.size() == 0:
		return false
		
	# Keep number of jumps in queue under a limit
	if jump.target_coords.size() > 3: 
		jump.target_coords.resize(3)
	
	# If not impeded and not at dest
	if not impeded and current_pos != jump.target_coords[0]:
		# If speed is greater than distance to dest
		if moving and motion.length() > current_pos.distance_to(jump.target_coords[0]):
			return false
#			if motion.length() >= (jump.target_coords[0] - current_pos).length():
#			if motion.length() > current_pos.distance_to(jump.target_coords[0]).length():
		else:
			return true
	else:
		false


#####################################################################
#####################################################################
#####################################################################


func _fixed_process(delta):
	
	# Update the state the character is in
	update_states(delta)
	
	# Update the location of the destination prediction indicator
	update_predictor()
	
	# Do nothing if stunned
	if stunned:
		return
	
	if supposed_to_be_moving():
		move_towards_destination(delta)	
		face_dir(jump.target_coords[0])
	elif moving:
		stop_moving()
	
	if not impeded: # If idling, always stay turned towards pointer location
		face_dir(mouse_pos)
	