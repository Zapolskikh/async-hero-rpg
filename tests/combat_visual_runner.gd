extends Node
var main: Node
const OUT := "res://build/qa"

func _ready() -> void:
	main = get_parent()
	_run()

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT.path_join(name+".png"))
	print("QA screenshot: ",name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Game.hero["level"] = 40
	for id in Db.SPELLS:
		if not Db.SPELLS[id].get("enemy",false) and not Db.SPELLS[id].get("hidden",false):
			Game.collection[id] = {"lvl":1,"copies":0}
	main._switch("hero")
	for branch in 4:
		Game.hero["talents"] = {}
		var last := ""
		for id in Talents.TALENTS:
			if Talents.TALENTS[id]["branch"] == Talents.BRANCHES[branch]["id"]:
				Game.hero["talents"][id] = Talents.TALENTS[id]["ranks"]
				last = id
		TalentPanel.branch_index = branch
		TalentPanel.selected = last
		main._talents_popup()
		await wait(.35)
		await shot("talents_%d_top"%branch)
		var panel: TalentPanel = main.popup_layer.find_children("*","TalentPanel",true,false)[0]
		panel.scroller.scroll_vertical = 9999
		await wait(.15)
		await shot("talents_%d_deep"%branch)
	UI.clear(main.popup_layer)
	main._switch("spells")
	await wait(.35)
	await shot("collection")
	main._spell_popup("prayer")
	await wait(.25)
	await shot("prayer_details")
	UI.clear(main.popup_layer)
	main._switch("mercs")
	await wait(.35)
	await shot("mercenaries")
	main._merc_talents(Game.board[0])
	await wait(.25)
	await shot("mercenary_talents")
	UI.clear(main.popup_layer)
	var ex := Expedition.new()
	ex.level = 1
	ex.mode = "push"
	var allies := []
	for i in 4:
		var weapons: Array = [["sword","shield"],["bow"],["staff"],["staff"]][i]
		var talents: Dictionary = [{"readiness":3},{},{"fire_totem":3},{"healing_totem":3}][i]
		allies.append(BattleUnit.new(i,0,i,{"name":["Страж","Лучник","Маг","Лекарь"][i],"sprite":["tank","hunter","pyromancer","healer"][i],"ranged":i>0,"stats":{"hp":10000.,"atk":10.,"power":90.,"str":100.,"agi":100.},"weapons":weapons,"talents":talents,"spells":[]}))
	var foes := []
	for i in 4:
		foes.append({"name":"Противник","sprite":["brute","caster","e_tank","ranged"][i],"stats":{"hp":100000.,"atk":0.,"power":100.},"spells":[]})
	ex.allies = allies
	ex.sim = BattleSim.new()
	ex.sim.setup(allies,foes,123)
	Game.expedition = ex
	main._open_watch()
	await wait(.4)
	var attacks := ["fireball","frostbolt","chain_lightning","avenger","whirlwind","arrow_rain","penance","prayer","vengeance","explosive","seed","beast","bloodlust","shockwave","mass_dispel"]
	for id in attacks:
		var source: BattleUnit = allies[2]
		var target: BattleUnit = ex.sim.foes_of(source)[0]
		if id in ["avenger","whirlwind","vengeance","shockwave"]:
			source = allies[0]
		elif id in ["explosive","arrow_rain"]:
			source = allies[1]
		elif id in ["penance","prayer","mass_dispel"]:
			source = allies[3]
			target = allies[0]
			target.hp = 5000.
		ex.sim._cast(source,id,1,target)
		await wait(.12)
		await shot("fx_"+id)
		await wait(.6 if id not in ["arrow_rain","penance"] else 2.2)
	await wait(2.)
	await shot("fx_totems_and_beast")
	print("COMBAT VISUAL QA DONE")
	ex.sim.release()
	Game.expedition = null
	get_tree().quit()
