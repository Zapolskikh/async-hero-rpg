extends SceneTree
var main: Node
const SETS := {'unarmed':[],'sword':['sword'],'dual':['sword','sword'],'shield':['sword','shield'],'greatsword':['greatsword'],'bow':['bow'],'staff':['staff']}
func _initialize() -> void:
 run.call_deferred()
func shot(name: String) -> void:
 await process_frame
 await RenderingServer.frame_post_draw
 if DisplayServer.get_name()!='headless': root.get_texture().get_image().save_png('res://build/qa/v3/'+name+'.png')
func actor_in(canvas: Control, sex: String, loadout: String, clip: String, phase: float, flip: bool, factor: float, ground: Vector2) -> CharacterActor:
 var actor := CharacterActor.new()
 canvas.add_child(actor)
 actor.configure({'sex':sex},[],SETS[loadout])
 actor.set_process(false)
 actor.position=ground
 actor.scale=Vector2(-factor if flip else factor,factor)
 actor.play_native(clip)
 actor.rig.seek_normalized(phase)
 return actor
func run() -> void:
 root.size=Vector2i(1280,720)
 DirAccess.make_dir_recursive_absolute('res://build/qa/v3')
 var probe := CharacterActor.new()
 root.add_child(probe)
 probe.configure({})
 var clips: Array = probe.rig.data.keys()
 probe.queue_free()
 for sex in ['male','female']:
  for flip in [false,true]:
   var board := UI.card(Style.CARD,8)
   board.set_anchors_preset(Control.PRESET_FULL_RECT)
   root.add_child(board)
   var grid := UI.grid(7,2)
   board.add_child(grid)
   for id in clips:
    var cell := UI.vbox(0)
    cell.custom_minimum_size=Vector2(175,94)
    grid.add_child(cell)
    var canvas := Control.new()
    canvas.custom_minimum_size=Vector2(175,72)
    cell.add_child(canvas)
    var loadout: String = V3RigActor._profile_cache['male'][id].meta.loadout
    actor_in(canvas,sex,loadout,id,.5,flip,.19,Vector2(85,71))
    cell.add_child(UI.label(id,10))
   await shot('all_'+sex+('_left' if flip else '_right'))
   board.queue_free()
   await process_frame
   board=UI.card(Style.CARD,8)
   board.set_anchors_preset(Control.PRESET_FULL_RECT)
   root.add_child(board)
   grid=UI.grid(7,2)
   board.add_child(grid)
   for stage in ['cast_instant_','cast_hold_','cast_release_']:
    for loadout in SETS:
     var cell := UI.vbox(0)
     cell.custom_minimum_size=Vector2(175,218)
     grid.add_child(cell)
     var canvas := Control.new()
     canvas.custom_minimum_size=Vector2(175,194)
     cell.add_child(canvas)
     var actor := actor_in(canvas,sex,loadout,stage+loadout,.35 if stage=='cast_instant_' else .5,flip,.46,Vector2(90,190))
     actor.rig.glow_visible=true
     actor.rig.glow_color=Color('#ff8a2a')
     cell.add_child(UI.label(stage.trim_suffix('_')+' '+loadout,11))
   await shot('magic_'+sex+('_left' if flip else '_right'))
   board.queue_free()
   await process_frame
 main=load('res://scenes/main.tscn').instantiate()
 root.add_child(main)
 await process_frame
 main._switch('hero')
 await create_timer(.2).timeout
 await shot('hero')
 main._dummy_popup()
 await process_frame
 var training=main.popup_layer.get_child(0).get_child(0)
 for loadout in ['sword','dual','shield','greatsword','bow','staff','unarmed']:
  training.session.weapons=SETS[loadout].duplicate()
  training.session.rotation=['aimed_shot','',''] if loadout=='bow' else ['fireball','','']
  training.session.source['appearance']={'sex':'female' if loadout in ['shield','bow','dual'] else 'male','hair':'f01' if loadout in ['shield','bow','dual'] else 'm01'}
  training._restart()
  await create_timer(.9).timeout
  await shot('live_'+loadout)
 for rate in [.25,1.,2.,4.,8.]:
  training.training_speed=rate
  training.speed_picker.selected=[.25,1.,2.,4.,8.].find(rate)
  training.session.weapons=['bow']
  training.session.rotation=['aimed_shot','','']
  training._restart()
  await create_timer(1.3/rate).timeout
  await shot('speed_'+str(rate).replace('.','_'))
 main.queue_free()
 await process_frame
 var game = root.get_node('Game')
 if game.expedition!=null and game.expedition.sim!=null: game.expedition.sim.release()
 print('V3 VISUAL: all runtime clips, both profiles, both directions, seven live loadouts, five speeds rendered')
 quit()
