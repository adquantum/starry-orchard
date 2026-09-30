class_name DeckStateV2
extends RefCounted

const HAND_LIMIT := 7

var draw_pile: Array[CardInstanceV2] = []
var hand: Array[CardInstanceV2] = []
var discard_pile: Array[CardInstanceV2] = []
var treasure_pile: Array[CardInstanceV2] = []
var removed_cards: Array[CardInstanceV2] = []
var discard_count_this_round: int = 0
var treasure_draw_count_this_round: int = 0
var fusion_draw_credits: int = 0
# Server-local recovery of unplayed cards, deliberately excluded by BattleWire.
# Treasure reservations keep their existing death/consumption policy.
var _death_hand: Array[CardInstanceV2] = []


func unlock_treasures() -> void:
	discard_count_this_round = 0
	treasure_draw_count_this_round = 0
	fusion_draw_credits = 0
	for card in hand:
		card.treasure_locked = false


func draw_to_limit() -> Array[CardInstanceV2]:
	var drawn: Array[CardInstanceV2] = []
	while hand.size() < HAND_LIMIT and not draw_pile.is_empty():
		var card: CardInstanceV2 = draw_pile.pop_back()
		hand.append(card)
		drawn.append(card)
	return drawn


func draw_opening_hand() -> Array[CardInstanceV2]:
	var drawn: Array[CardInstanceV2] = []
	# A stable opening curve: three cheap plays, one tactical card, two
	# mid-cost cards, then a final non-brick card whenever possible.
	_take_matching(drawn, 3, func(card: CardInstanceV2): return card.definition.pip_cost <= 2)
	_take_matching(drawn, 1, func(card: CardInstanceV2): return _is_tactical(card))
	_take_matching(drawn, 2, func(card: CardInstanceV2): return card.definition.pip_cost >= 3 and card.definition.pip_cost <= 4)
	_take_matching(drawn, HAND_LIMIT - hand.size(), func(card: CardInstanceV2): return card.definition.pip_cost <= 4)
	_take_matching(drawn, HAND_LIMIT - hand.size(), func(_card: CardInstanceV2): return true)
	return drawn


func _take_matching(drawn: Array[CardInstanceV2], count: int, predicate: Callable) -> void:
	for draw_index in maxi(0, count):
		var found_index := -1
		for index in range(draw_pile.size() - 1, -1, -1):
			if predicate.call(draw_pile[index]):
				found_index = index
				break
		if found_index < 0 or hand.size() >= HAND_LIMIT:
			return
		var card: CardInstanceV2 = draw_pile.pop_at(found_index)
		hand.append(card)
		drawn.append(card)


func _is_tactical(card: CardInstanceV2) -> bool:
	for tag in card.definition.tags:
		if tag in [&"utility", &"charm", &"ward", &"heal", &"hot"]:
			return true
	return false


func clear_hand_on_death() -> void:
	_death_hand.clear()
	for card in hand:
		if card.definition != null and not card.definition.treasure and card.inventory_token.is_empty():
			_death_hand.append(card)
	removed_cards.append_array(hand)
	hand.clear()
	discard_count_this_round = 0
	treasure_draw_count_this_round = 0
	fusion_draw_credits = 0


func restore_unplayed_cards_after_revive() -> void:
	# Reuse only instances from this death, never prior discards or spent item cards.
	# The existing next planning phase draws these; revival grants no immediate turn.
	for card in _death_hand:
		if not removed_cards.has(card) or card.definition == null or card.definition.treasure or not card.inventory_token.is_empty():
			continue
		removed_cards.erase(card)
		if not draw_pile.has(card) and not hand.has(card):
			draw_pile.push_front(card)
	_death_hand.clear()

