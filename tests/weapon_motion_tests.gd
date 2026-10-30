extends SceneTree
var failures := 0
var assertions := 0
var markers := []
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		print('FAIL ',message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280,720)
	var actor := CharacterActor.new()
	root.add_child(actor)
	actor.set_process(false)
	check(not actor.rig.is_processing(),'Nested rig never owns a second automatic clock')
	actor.marker.connect(func(id,event,socket,transform): markers.append({'id':id,'event':str(event),'socket':str(socket),'transform':transform}))
	var weapons := [[],['sword'],['sword','sword'],['sword','shield'],['greatsword'],['bow'],['staff']]
	for sex in ['male','female']:
		for held in weapons:
			actor.configure({'sex':sex},[],held)
			for hold in [.2,2.,10.]:
				markers.clear()
				actor.begin_magic(Color('#ff8a2a'))
				actor.advance_visual(.6)
				check(actor.clip=='cast_hold','Begin enters native hold')
				actor.advance_visual(hold)
				check(markers.is_empty(),'Hold never releases a spell')
				if actor.preset=='greatsword': check(actor.rig.right_grip_weight < .001,'Right grip releases greatsword')
				actor.begin_magic(Color('#ff8a2a'),false)
				actor.advance_visual(2.)
				check(markers.size()==1 and markers[0]['event']=='spell_release','One release after variable hold')
				check(actor.clip=='idle','Release returns to matching loadout')
			for before_cancel in [.2,.7,3.]:
				markers.clear()
				actor.begin_magic(Color.WHITE)
				actor.advance_visual(before_cancel)
				actor.cancel_cast()
				actor.advance_visual(10.)
				check(markers.is_empty(),'Cancel does not emit a spell release')
			markers.clear()
			actor.begin_magic(Color.WHITE,false)
			actor.advance_visual(.1)
			actor.begin_magic(Color.WHITE,false)
			actor.advance_visual(2.)
			check(markers.size()==1,'Repeated instant cancels stale pending marker')
			var action: int = markers[0]['id']
			actor.begin_magic(Color.WHITE,false)
			actor.advance_visual(2.)
			check(markers.size()==2 and markers[1]['id']!=action,'Replay gets unique action id')
			actor.begin_magic(Color.WHITE)
			actor.advance_visual(.7)
			actor.play('death')
			markers.clear()
			actor.advance_visual(5.)
			check(markers.is_empty() and actor.clip=='death','Death drops pending cast events')
			actor.play('idle')
			for rate in [.25,1.,2.,4.,8.]:
				actor.begin_magic(Color.WHITE,false)
				markers.clear()
				var time := 0.
				while time < .8:
					actor.advance_visual((1./60.)*rate)
					time += (1./60.)*rate
				check(markers.size()==1,'Exactly one marker at every playback speed')
			actor.position=Vector2(320,410)
			for flip in [-1.,1.]:
				actor.scale=Vector2(flip*.6,.6)
				var socket := actor.socket_world('right_hand')
				var raw: Array = actor.rig.sockets['right_hand']
				var expected := actor.to_global(Vector2(raw[0],raw[1])-CharacterActor.PIVOT)
				check(socket.origin.distance_to(expected)<.001,'Mirrored sockets follow the visual transform')
		actor.configure({'sex':sex},[],['bow'])
		for rate in [.25,1.,2.,4.,8.]:
			markers.clear()
			actor.play('shoot')
			var time := 0.
			while time < 2.:
				actor.advance_visual((1./60.)*rate)
				time += (1./60.)*rate
			check(markers.size()==1 and markers[0]['event']=='arrow_release','Bow draw/release emits exactly one arrow '+sex+' rate '+str(rate)+' events '+str(markers.size())+' clip '+actor.rig.current_clip)
		markers.clear()
		actor.play('shoot')
		actor.advance_visual(20.)
		check(markers.size()==1 and actor.clip=='idle','Large delta crosses bow phases without losing release')
		check(not actor.rig.arrow_loaded,'The released arrow stays hidden after returning idle')
		actor.begin_aim()
		check(actor.rig.arrow_loaded,'A new arrow appears only on the next preparation')
		actor.configure({'sex':sex},[],['sword','sword'])
		actor.play('attack')
		var first := actor.rig.current_clip
		actor.play('attack')
		check(first=='sword_right_slash_dual' and actor.rig.current_clip=='sword_left_slash','Second sword uses its own native clip')
		actor.play_native('dual_combo','idle_dual')
		markers.clear()
		actor.advance_visual(3.)
		check(markers.size()==3,'Combo retains its three visual contacts')
		actor.configure({'sex':sex},[],['staff'])
		actor.play('attack')
		check(actor.clip=='idle','Staff does not gain physical autoattacks')
		actor.begin_staff_magic(Color('#b68aff'))
		actor.advance_visual(.8)
		check(actor.rig.current_clip=='staff_cast_hold','Staff casting is separate from hand casting')
		actor.begin_staff_magic(Color('#b68aff'),false)
		markers.clear()
		actor.advance_visual(2.)
		check(markers.size()==1 and markers[0]['socket']=='staff_tip','Staff releases from staff_tip')
	actor.queue_free()
	await process_frame
	var view = load('res://scripts/ui/battle_view.gd').new()
	root.add_child(view)
	view.set_process(false)
	var allies := []
	for i in 4:
		allies.append(BattleUnit.new(i,0,i,{'name':'Test','sprite':'hero','stats':{'hp':1000.,'atk':10.,'power':100.},'weapons':[['staff'],['bow'],['sword'],['sword','shield']][i]}))
	var sim := BattleSim.new()
	sim.setup(allies,[{'name':'Dummy','stats':{'hp':1.e9,'atk':0.,'power':0.}}],7)
	view.training_sim=sim
	view._sync_characters(sim.units,false)
	for unit in allies: check(view._lunge_offset(unit,.2)==Vector2.ZERO,'Feet stay planted; no old root tween')
	view._shoot(allies[1],sim.units[4],Color.WHITE,'arrow')
	check(view.projectiles.is_empty(),'Arrow waits for native release event')
	view.characters[1]['actor'].advance_visual(.91)
	check(view.projectiles.size()==1,'Native bow event creates one projectile')
	view.characters[1]['actor'].advance_visual(10.)
	check(view.projectiles.size()==1,'Idle cannot duplicate projectile')
	view._shoot(allies[1],sim.units[4],Color.WHITE,'arrow')
	view.characters[1]['actor'].cancel_cast()
	view.characters[1]['actor'].advance_visual(10.)
	check(view.projectiles.size()==1,'Cancelled bow cannot spawn a late arrow')
	view._melee_motion(allies[2])
	var hp: float = sim.units[4].hp
	view.pending_actions[2]['damage'].append({'uid':4,'v':20.,'src':2})
	var count: int = view.floats.size()
	view.characters[2]['actor'].advance_visual(2.)
	check(view.floats.size()==count+1,'Melee label is synchronized to contact')
	check(sim.units[4].hp==hp and allies[2].dealt==0.,'Visual markers never deal extra damage')
	view.queue_free()
	await process_frame
	sim.release()
	print('WEAPON MOTION: %d assertions, %d failures' % [assertions,failures])
	quit(1 if failures else 0)
