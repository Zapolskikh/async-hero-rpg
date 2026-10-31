class_name Shop
extends RefCounted
## Crystals (premium currency) and what they buy. Prototype: purchases are fake
## ("Купить (тест)" just grants the pack); real payments come later through
## Google Play Billing / Apple IAP / Steam with server-side receipt checks.

## Packs shown in the shop. `price` is display only in the prototype.
const PACKS := [
	{"id": "c100", "crystals": 100, "price": "0,99 $"},
	{"id": "c550", "crystals": 550, "price": "4,99 $"},
	{"id": "c1200", "crystals": 1200, "price": "9,99 $"},
]

## Free crystals: first clear of every 5th campaign level (boss of a chapter half).
const CRYSTALS_FIRST_CLEAR_EVERY := 5
const CRYSTALS_FIRST_CLEAR := 40

## Cosmetics: glow around worn gear, aura under the feet. Pure looks, no stats.
const COSMETICS := {
	"glow_gold":   {"slot": "glow", "name": "Золотое сияние", "color": "#ffd23a", "price": 120},
	"glow_frost":  {"slot": "glow", "name": "Морозное сияние", "color": "#7ad8ff", "price": 120},
	"glow_fel":    {"slot": "glow", "name": "Ядовитое сияние", "color": "#7aff5a", "price": 160},
	"glow_void":   {"slot": "glow", "name": "Сияние бездны", "color": "#b45aff", "price": 160},
	"aura_fire":   {"slot": "aura", "name": "Аура пламени", "color": "#ff6a2a", "price": 200},
	"aura_holy":   {"slot": "aura", "name": "Святая аура", "color": "#fff0a0", "price": 200},
	"aura_nature": {"slot": "aura", "name": "Аура природы", "color": "#5aff9a", "price": 250},
	"aura_shadow": {"slot": "aura", "name": "Аура теней", "color": "#8a4aff", "price": 250},
}
const COSMETIC_SLOTS := {"glow": "Сияние", "aura": "Аура"}

## Finish a gathering or craft now: 1 crystal per started 10 minutes left.
const RUSH_SECONDS_PER_CRYSTAL := 600.0

## Farm boost: x2 gold and XP from farming (not items, not rare drops) for 2 hours.
const BOOST_PRICE := 60
const BOOST_SECONDS := 7200.0
const BOOST_MULT := 2.0

## Spell boxes for crystals (no daily limit).
const BOX_CRYSTALS := 20
const BOX_PACK_CRYSTALS := 180

static func rush_cost(seconds_left: float) -> int:
	return max(1, int(ceil(seconds_left / RUSH_SECONDS_PER_CRYSTAL)))
