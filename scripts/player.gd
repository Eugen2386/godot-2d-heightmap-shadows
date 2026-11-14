extends CharacterBody2D

@onready var anim_player: AnimationPlayer = $AnimationPlayer

const SPEED = 300.0


func _physics_process(delta: float) -> void:
	var direction = Input.get_vector("Left", "Right", "Up", "Down")
	if direction:
		velocity = direction * SPEED
		anim_player.play("walk")
	else:
		velocity = Vector2.ZERO
		anim_player.stop()

	move_and_slide()
