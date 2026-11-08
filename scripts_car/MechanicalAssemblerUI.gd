extends Node3D
class_name MechanicalAssemblerUI

## Adaptado casi directo de BuildingSocketsManager.gd (proyecto de
## criaturas) — mismo flujo de raycast + holograma + click. Lo único que
## cambia son los tipos (MechanicalSocket en vez de InteractiveSocket,
## MechanicalPartData en vez de CreaturePartData) y que _confirmar_pieza()
## llama a MechanicalAssembler.acoplar_pieza() en vez de
## AssemblerModule.add_dynamic_part().

@export var camera: Camera3D
@export var ensamblador: MechanicalAssembler
@export var hologram_material: Material
@export var socket_collision_mask: int = 1 << 10  # capa 11 por defecto — debe coincidir con la collision_layer de tus MechanicalSocket

var is_active: bool = false
var hologram_instance: Node3D = null
var current_hovered_socket: MechanicalSocket = null
var selected_part_data: MechanicalPartData

var socket_ocupado_bajo_mouse: MechanicalSocket = null  # independiente del flujo de agregar — activo cuando NO estás colocando nada


func set_selected_part(datos: MechanicalPartData) -> void:
	selected_part_data = datos
	is_active = true


func _physics_process(_delta: float) -> void:
	if is_active and selected_part_data:
		_handle_raycast()
	else:
		_handle_raycast_quitar()


func _handle_raycast() -> void:
	if not camera:
		push_warning("MechanicalAssemblerUI: falta asignar 'camera' en el Inspector.")
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_pos) * 15.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = socket_collision_mask

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result and result.collider is MechanicalSocket and not result.collider.is_occupied:
		_update_hologram(result.collider)
	else:
		_clear_hologram()


func _update_hologram(socket: MechanicalSocket) -> void:
	if current_hovered_socket == socket:
		return
	_clear_hologram()
	current_hovered_socket = socket

	if selected_part_data and selected_part_data.part_scene:
		hologram_instance = selected_part_data.part_scene.instantiate()
		socket.add_child(hologram_instance)
		if hologram_instance is RigidBody3D:
			hologram_instance.freeze = true
			hologram_instance.collision_layer = 0
			hologram_instance.collision_mask = 0
		if hologram_material:
			_apply_hologram_material(hologram_instance)


func _clear_hologram() -> void:
	if hologram_instance:
		hologram_instance.queue_free()
		hologram_instance = null
	current_hovered_socket = null


## Camino PARALELO al de agregar — comparte la misma lógica de rayo pero
## busca sockets OCUPADOS en vez de libres, y solo corre cuando no estás
## colocando nada. Cero superposición con _handle_raycast(): no se pisan.
func _handle_raycast_quitar() -> void:
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_pos) * 15.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = socket_collision_mask

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result and result.collider is MechanicalSocket and result.collider.is_occupied:
		socket_ocupado_bajo_mouse = result.collider
	else:
		socket_ocupado_bajo_mouse = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and socket_ocupado_bajo_mouse:
		if ensamblador:
			ensamblador.quitar_pieza(socket_ocupado_bajo_mouse)
		socket_ocupado_bajo_mouse = null
		get_viewport().set_input_as_handled()
		return

	if not is_active or not selected_part_data or not current_hovered_socket:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_confirmar_pieza()
		get_viewport().set_input_as_handled()


func _confirmar_pieza() -> void:
	if not ensamblador:
		push_error("MechanicalAssemblerUI: falta asignar 'ensamblador' en el Inspector.")
		return

	var socket := current_hovered_socket
	_clear_hologram()
	ensamblador.acoplar_pieza(socket, selected_part_data)


func _apply_hologram_material(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = hologram_material
	for child in node.get_children():
		_apply_hologram_material(child)
