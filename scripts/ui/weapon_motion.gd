class_name WeaponMotion
extends Node2D
## Code-native weapon/arm animation. Long sleeves overlap the unchanged V2 torso.
const EDGE := Color("#252631")
const BLUE := Color("#267fea")
const GOLD := Color("#f1c459")
const LEATHER := Color("#986027")
var preset := "sword"
var sex := "male"
var clip := "idle"
var phase := 0.
var active := false

func _blend(a: Vector2, b: Vector2, c: Vector2, p: float) -> Vector2:
	if p < .3:
		return a.lerp(b, smoothstep(0., .3, p))
	if p < .58:
		return b.lerp(c, smoothstep(.3, .58, p))
	return c.lerp(a, smoothstep(.58, 1., p))

func _angle(a: float, b: float, c: float, p: float) -> float:
	return _blend(Vector2(a,0),Vector2(b,0),Vector2(c,0),p).x

func _arm(shoulder: Vector2, target: Vector2, bend: float) -> Vector2:
	var delta := target - shoulder
	var distance := clampf(delta.length(), 4., 79.)
	var hand := shoulder + delta.normalized() * distance
	var direction_to_hand := delta.normalized()
	var elbow := (shoulder + hand) * .5 + Vector2(-direction_to_hand.y,direction_to_hand.x) * sqrt(1600. - distance * distance * .25) * bend
	var points := PackedVector2Array([shoulder,elbow,hand])
	# Draw the silhouette first, then one continuous sleeve: no internal elbow outline.
	draw_polyline(points, EDGE, 24., true)
	for point in points:
		draw_circle(point, 12., EDGE)
	draw_polyline(points, BLUE, 18., true)
	for point in points:
		draw_circle(point, 9., BLUE)
	var direction := (hand - elbow).normalized()
	var cuff := hand - direction * 11.
	draw_line(cuff - direction.orthogonal() * 10., cuff + direction.orthogonal() * 10., GOLD, 11., true)
	draw_circle(hand, 11., EDGE)
	draw_circle(hand, 8., LEATHER)
	return hand

func _sword(hand: Vector2, angle: float, heavy: bool = false) -> void:
	draw_set_transform(hand, deg_to_rad(angle))
	var length := 153. if heavy else 116.
	var hilt := 44. if heavy else 17.
	var outline := PackedVector2Array([Vector2(-hilt,-5),Vector2(7,-5),Vector2(7,-12),Vector2(length-15,-9),Vector2(length,0),Vector2(length-15,9),Vector2(7,12),Vector2(7,5),Vector2(-hilt,5)])
	draw_colored_polygon(outline, EDGE)
	draw_colored_polygon(PackedVector2Array([Vector2(9,-8),Vector2(length-16,-6),Vector2(length-4,0),Vector2(9,7)]),Color("#cbd3df"))
	draw_line(Vector2(12,-5),Vector2(length-17,-4),Color("#f1f2f5"),2.,true)
	draw_line(Vector2(-hilt+2,0),Vector2(4,0),LEATHER,6.,true)
	draw_line(Vector2(6,-16),Vector2(6,16),EDGE,8.,true)
	draw_line(Vector2(6,-14),Vector2(6,14),Color("#aab3c5"),4.,true)
	draw_set_transform(Vector2.ZERO)

func _shield(center: Vector2, angle: float = 0.) -> void:
	draw_set_transform(center,angle)
	var contour := PackedVector2Array([Vector2(-49,-57),Vector2(9,-48),Vector2(48,-29),Vector2(39,22),Vector2(10,55),Vector2(-12,64),Vector2(-43,30),Vector2(-54,-13)])
	draw_colored_polygon(contour,EDGE)
	var rim := PackedVector2Array()
	var inner := PackedVector2Array()
	for p in contour:
		rim.append(p * .94)
		inner.append(p * .78)
	draw_colored_polygon(rim,Color("#c6d0df"))
	draw_colored_polygon(inner,Color("#2363b3"))
	draw_line(Vector2(-10,-37),Vector2(-24,24),Color("#4389dc"),7.,true)
	draw_set_transform(Vector2.ZERO)

func _bow(bow_hand: Vector2, pull_hand: Vector2, released: bool) -> void:
	var top := bow_hand + Vector2(-3,-81)
	var bottom := bow_hand + Vector2(-3,81)
	var curve := PackedVector2Array()
	for i in 25:
		var t := i / 24.
		curve.append(top.lerp(bottom,t) + Vector2(sin(t*PI)*25.,0))
	draw_polyline(curve,EDGE,9.,true)
	draw_polyline(curve,Color("#a66a2c"),5.,true)
	var notch := bow_hand if released else pull_hand
	draw_polyline(PackedVector2Array([top,notch,bottom]),Color("#e6dfc4"),1.7,true)
	if not released:
		draw_line(notch,notch+Vector2(105,0),Color("#805c32"),3.,true)
		draw_colored_polygon(PackedVector2Array([notch+Vector2(110,0),notch+Vector2(99,-4),notch+Vector2(99,4)]),Color("#d4dce7"))
		draw_line(notch+Vector2(7,-4),notch+Vector2(15,4),Color("#ddd9c5"),3.,true)

func _draw() -> void:
	if not active:
		if preset == "sword_shield":
			# Front layer covers the complete glove, wrist, cuff and old baked shield.
			_shield(Vector2(166,251) if sex == "male" else Vector2(190,245))
		return
	var left_shoulder := Vector2(169,195) if sex == "male" else Vector2(183,195)
	var right_shoulder := Vector2(237,195)
	if sex == "female":
		# Restore the small trouser area originally hidden by the baked glove.
		draw_colored_polygon(PackedVector2Array([Vector2(182,276),Vector2(191,276),Vector2(190,294),Vector2(177,298),Vector2(178,287)]),Color("#343442"))
		draw_line(Vector2(181,277),Vector2(177,296),EDGE,2.,true)
	if preset == "bow":
		var tension := smoothstep(0.,.42,phase)
		var recoil := maxf(0.,1.-(phase-.44)/.56)
		var released := phase >= .44
		var hold := _arm(right_shoulder,Vector2(304,216),-1.)
		var pull := Vector2(276,237).lerp(Vector2(228,206),tension)
		if released:
			pull += Vector2(-13,-3)*recoil
		pull = _arm(left_shoulder,pull,1.)
		_bow(hold,pull,released)
		return
	if clip == "shield_bash":
		var pulse := sin(phase*PI)
		var hand := _arm(left_shoulder,Vector2(183,248)+Vector2(36,-22)*pulse,1.)
		var sword_hand := _arm(right_shoulder,Vector2(278,230),-1.)
		_sword(sword_hand,-65.)
		_shield(hand+Vector2(4,0),-.12*pulse)
		return
	if preset == "greatsword":
		var hand := _blend(Vector2(255,215),Vector2(232,174),Vector2(285,222),phase)
		var angle := _angle(-63.,-123.,8.,phase)
		_arm(left_shoulder,hand-Vector2(42,0).rotated(deg_to_rad(angle)),1.)
		hand = _arm(right_shoulder,hand,-1.)
		_sword(hand,angle,true)
		return
	if preset == "sword_shield":
		var hand := _arm(right_shoulder,_blend(Vector2(279,234),Vector2(250,169),Vector2(305,222),phase),-1.)
		_sword(hand,_angle(-65.,-118.,12.,phase))
		var shield_hand := _arm(left_shoulder,Vector2(180,248),1.)
		_shield(shield_hand+Vector2(4,0))
		return
	var hand := _arm(left_shoulder,_blend(Vector2(160,263),Vector2(175,180),Vector2(240,220),phase),1.)
	_sword(hand,_angle(135. if preset == "dual_swords" else 26.,-135.,8.,phase))
	if preset == "dual_swords":
		var other_phase := clampf((phase-.12)/.88,0.,1.)
		var other := _arm(right_shoulder,_blend(Vector2(262,266),Vector2(249,171),Vector2(304,230),other_phase),-1.)
		_sword(other,_angle(43.,-110.,15.,other_phase))
	else:
		_arm(right_shoulder,Vector2(260,266),-1.)
