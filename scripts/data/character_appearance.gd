class_name CharacterAppearance
extends RefCounted
## Cosmetic-only, JSON-safe state shared by client, server and public snapshots.
const HAIR_NAMES := {
	"male": ["Короткий пробор", "Короткая стрижка", "Зачёс назад", "Средние волнистые", "Низкий хвост"],
	"female": ["Короткая пикси", "Каре", "До плеч", "Высокий хвост", "Коса"]
}

static func hair_ids(sex: String) -> Array:
	var prefix := "f" if sex == "female" else "m"
	return [prefix + "01", prefix + "02", prefix + "03", prefix + "04", prefix + "05"]

static func valid(sex: String, hair: String) -> bool:
	return sex in ["male", "female"] and hair in hair_ids(sex)

static func normalize(value: Variant) -> Dictionary:
	var data: Dictionary = value if value is Dictionary else {}
	var sex := str(data.get("sex", "male"))
	if sex not in ["male", "female"]:
		sex = "male"
	var hair := str(data.get("hair", ""))
	if hair not in hair_ids(sex):
		hair = hair_ids(sex)[0]
	return {"sex": sex, "hair": hair}

static func for_identity(identity: String) -> Dictionary:
	# Does not consume the gameplay RNG or alter equipment/loot generation.
	var code := absi(identity.hash())
	var sex := "female" if code % 2 else "male"
	return {"sex": sex, "hair": hair_ids(sex)[(code / 2) % 5]}
