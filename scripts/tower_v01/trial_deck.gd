extends DeckStateV2
## Preserve the shared opening curve, then swap actual instances for the two guarantees.
var actor_ref: WeakRef
var actor: BattleUnitStateV2:
	get:return actor_ref.get_ref() if actor_ref!=null else null
	set(value):actor_ref=weakref(value) if value!=null else null
var cost: CostResolverV2
var adjusted := false

func draw_opening_hand() -> Array[CardInstanceV2]:
	super.draw_opening_hand()
	_guarantee(func(card):return card.definition.school_id == actor.school_id and card.definition.effects.any(func(e):return str(e.type) in ["damage","drain"]) and cost.can_pay(actor,card.definition), false)
	_guarantee(func(card):return card.definition.school_id == actor.school_id and (card.definition.effects.any(func(e):return str(e.type) not in ["damage","drain"]) or card.definition.effects.size()>1), true)
	return hand.duplicate()

func _guarantee(predicate: Callable, protect_attack: bool) -> void:
	if hand.any(predicate):return
	for index in range(draw_pile.size()-1,-1,-1):
		if not predicate.call(draw_pile[index]):continue
		for slot in range(hand.size()-1,-1,-1):
			var card := hand[slot]
			if protect_attack and card.definition.school_id==actor.school_id and card.definition.effects.any(func(e):return str(e.type) in ["damage","drain"]) and cost.can_pay(actor,card.definition):continue
			var other := draw_pile[index];draw_pile[index]=card;hand[slot]=other;adjusted=true;return
