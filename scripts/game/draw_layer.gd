class_name DrawLayer
extends Node2D
## A blank canvas that lets another script do the painting.
## One manager (effects, pickups, decals...) can own several of these - for
## example one normal layer and one "additive" glow layer - and draw hundreds
## of things with very few nodes.

var painter: Callable


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
