extends "res://scripts/fusion_3d/town_network.gd"
## Keep presence scoped to the existing island or SO1 while sharing one port.
var coordinator: Node

func _publish_positions(recipient: int) -> void:
	if coordinator == null or coordinator.orchard_authority == null:
		super._publish_positions(recipient)
		return
	if not positions.has(recipient):return
	var center: Vector3 = positions[recipient]
	var nearby_positions: Dictionary = {}
	var nearby_rotations: Dictionary = {}
	for peer in positions:
		if not coordinator.orchard_authority.same_peer_world(recipient, int(peer)):continue
		var offset: Vector3 = positions[peer] - center
		if Vector2(offset.x, offset.z).length() > POSITION_INTEREST_METRES:continue
		nearby_positions[peer] = positions[peer]
		nearby_rotations[peer] = rotations.get(peer, 0.0)
	var snapshot_hash := hash([nearby_positions, nearby_rotations])
	if int(position_snapshot_hashes.get(recipient, 0)) == snapshot_hash:return
	position_snapshot_hashes[recipient] = snapshot_hash
	receive_positions.rpc_id(recipient, nearby_positions, nearby_rotations)

func _broadcast_appearance(peer_id: int, value: Dictionary) -> void:
	if not connected or not multiplayer.is_server():return
	for recipient in _recipients():
		if coordinator.orchard_authority.same_peer_world(peer_id, recipient) or value.is_empty():
			receive_appearance_update.rpc_id(recipient, peer_id, value)

func set_verified_character(peer: int, snapshot: Dictionary, player_name: String = "") -> void:
	var previous: Dictionary = verified_characters.get(peer, {})
	verified_characters[peer] = {"snapshot":snapshot.duplicate(true), "name":player_name if not player_name.is_empty() else str(previous.get("name", "冒险者"))}
	accept_verified_appearance(peer, appearances.get(peer, {}))
	if connected and multiplayer.is_server() and peer in multiplayer.get_peers():
		var visible: Dictionary = {}
		for other in appearances:
			if coordinator.orchard_authority.same_peer_world(peer, int(other)):visible[other] = appearances[other]
		receive_appearances.rpc_id(peer, visible)
