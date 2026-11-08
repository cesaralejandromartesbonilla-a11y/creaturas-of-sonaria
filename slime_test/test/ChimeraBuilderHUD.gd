extends Control
class_name ChimeraBuilderHUD

@onready var tabs_container = $LeftPanel/MainVBox/TabScroll/TabContainer
@onready var item_grid = $LeftPanel/MainVBox/GridScroll/ItemGrid
@onready var assembler = $AssemblerModule
@onready var sockets_manager = $BuildingSocketsManager
@onready var bootstrapper = $RequirementsBootstrapper
@export var player_dummy: CharacterBody3D

var bone_chain_builder: BoneChainBuilder
var bone_visual_layer: BoneVisualLayer
var _parent_bone_option: OptionButton
var _segment_length_spinbox: SpinBox
var _angle_x_spinbox: SpinBox
var _angle_z_spinbox: SpinBox
var _socket_option: OptionButton
var _available_sockets: Dictionary = {}  # nombre visible -> InteractiveSocket
var _player_camera: Node  # PlayerCamera (CameraController), buscado una sola vez en _ready()

var categories: Array[String] = [
	"Pies", "Manos", "Extensiones", "Chasis", 
	"Torsos", "Caderas", "Cabezas", "Decoraciones"
]

func _ready():
	_setup_tabs()
	bootstrapper.bootstrap(player_dummy, assembler)
	_evaluate_zero_state() # <- Revisar si nacemos de la nada
	_setup_finalize_button() # <- Paso 1a.5: botón "Crear"
	_setup_reset_button() # <- Paso 1a.6: botón "Nueva criatura"
	bootstrapper.ensure_bone_tools(self) # <- Fase 3: crea y arma BoneChainBuilder/BoneVisualLayer solo, sin nodos manuales
	bone_chain_builder = get_node_or_null("BoneChainBuilder")
	bone_visual_layer = get_node_or_null("BoneVisualLayer")
	_setup_bone_growth_controls() # <- Fase 3, Parte 3: agregar segmentos a demanda
	_setup_socket_anchor_controls() # <- Fase 3: anclar la cadena a un socket real del chasis
	_player_camera = get_node_or_null("/root/PlayerCamera")
	_activate_orbital_camera() # <- cámara orbital sobre player_dummy, mismo patrón que EnsambladorBootstrapper


# --- Cámara orbital de la Taller ---
# player_dummy nunca está "poseído" acá (no hay activate_control() en la
# mesa de construcción), así que simple_body.gd nunca dispara
# process_camera()/handle_input() por su cuenta — el HUD tiene que hacerlo
# él mismo, igual que EnsambladorBootstrapper lo hace para su Larguero.

func _activate_orbital_camera():
	if not player_dummy:
		push_warning("HUD: player_dummy no asignado, no puedo activar la cámara orbital.")
		return
	if not _player_camera:
		push_warning("HUD: no encontré el autoload PlayerCamera — la cámara del Taller queda inerte.")
		return
	if not _player_camera.has_method("asignar_objetivo_orbital"):
		push_warning("HUD: PlayerCamera no tiene asignar_objetivo_orbital() — ¿versión desactualizada de CameraController.gd?")
		return
	_player_camera.asignar_objetivo_orbital(player_dummy, true)
	print("HUD: cámara orbital activada sobre player_dummy.")


func _physics_process(delta: float) -> void:
	if _player_camera and _player_camera.has_method("process_camera"):
		_player_camera.process_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Nunca reenviar el clic izquierdo — es lo que usa BuildingSocketsManager
	# para acoplar una pieza en el socket resaltado. La cámara orbital solo
	# necesita clic derecho (rotar) y rueda (zoom), nunca izquierdo.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return
	if _player_camera and _player_camera.has_method("handle_input"):
		_player_camera.handle_input(event)

func _setup_tabs():
	for i in categories.size():
		var category = categories[i]
		var btn = Button.new()
		btn.text = category
		# Pasamos el índice entero 'i' en lugar de la cadena de texto
		btn.pressed.connect(func(): _on_tab_selected(i))
		tabs_container.add_child(btn)

func _on_tab_selected(category_index: int):
	_clear_grid()
	
	# Ahora enviamos el número entero sin problemas de tipo
	var parts = InventoryManager.get_parts_by_category(category_index)
	
	for part in parts:
		var item_btn = Button.new()
		item_btn.text = part.display_name
		item_btn.pressed.connect(func(): _select_part_for_building(part))
		item_grid.add_child(item_btn)

func _clear_grid():
	for child in item_grid.get_children():
		child.queue_free()

func _select_part_for_building(part: CreaturePartData):
	if part.slot_type == CreaturePartData.SlotType.CHASIS:
		# 1. Limpiamos las piezas viejas del ADN para empezar fresco
		assembler.active_dna.attached_parts.clear()
		# 2. Le asignamos la escena del chasis al ADN
		assembler.active_dna.chassis_scene = part.part_scene
		
		# 3. Forzamos el nacimiento del nuevo cuerpo usando la referencia exportada
		if player_dummy:
			assembler.apply_dna_transformation(player_dummy)
			_refresh_socket_options() # el chasis nuevo trae sus propios sockets
		else:
			push_error("HUD: No se ha asignado el PlayerDummy en el Inspector.")
		
		_unlock_all_tabs()
		
	else:
		if sockets_manager and sockets_manager.has_method("set_selected_part"):
			sockets_manager.set_selected_part(part)
		else:
			push_error("HUD: No se ha asignado el SocketsManager en el Inspector.")

func _evaluate_zero_state():
	if not assembler.active_dna or not assembler.active_dna.chassis_scene:
		# Pasamos el índice del Chasis (3) en lugar del String
		_lock_tabs_except(CreaturePartData.SlotType.CHASIS)
		_on_tab_selected(CreaturePartData.SlotType.CHASIS)
		print("Estado Cero detectado: Selecciona un Núcleo Base primero.")
	else:
		_unlock_all_tabs()
		_on_tab_selected(CreaturePartData.SlotType.CHASIS)

func _lock_tabs_except(allowed_category_index: int):
	for i in tabs_container.get_child_count():
		var btn = tabs_container.get_child(i)
		if btn is Button:
			# Bloquea el botón si su posición no coincide con la permitida
			btn.disabled = (i != allowed_category_index)

func _unlock_all_tabs():
	for btn in tabs_container.get_children():
		if btn is Button:
			btn.disabled = false


# --- Paso 1a.5: finalizar y tirar la criatura al mundo ---

func _setup_finalize_button():
	var btn := Button.new()
	btn.text = "Crear"
	btn.pressed.connect(_on_finalize_pressed)
	$LeftPanel/BoxContainer.add_child(btn)

func _on_finalize_pressed():
	if not assembler.active_dna or not assembler.active_dna.chassis_scene:
		push_warning("HUD: no se puede finalizar sin al menos un Chasis elegido.")
		return
	assembler.finalize_creature()


# --- Paso 1a.6: abandonar y empezar de nuevo, sin salir del Taller ---

func _setup_reset_button():
	var btn := Button.new()
	btn.text = "Nueva criatura"
	btn.pressed.connect(_on_reset_pressed)
	$LeftPanel/BoxContainer.add_child(btn)

func _on_reset_pressed():
	assembler.reset_table()
	_evaluate_zero_state() # vuelve a bloquear todo menos Chasis, igual que al arrancar


# --- Fase 3, Parte 3: agregar un segmento nuevo a demanda, ramificando ---
# desde cualquier hueso existente (no solo el último agregado).

func _setup_bone_growth_controls():
	if not bone_chain_builder or not bone_visual_layer:
		push_error("HUD: faltan BoneChainBuilder/BoneVisualLayer — ¿corrió ensure_bone_tools()?")
		return

	var container := $LeftPanel/BoxContainer

	_parent_bone_option = OptionButton.new()
	container.add_child(_parent_bone_option)
	_refresh_parent_options()

	_segment_length_spinbox = SpinBox.new()
	_segment_length_spinbox.prefix = "Largo:"
	_segment_length_spinbox.min_value = 0.02
	_segment_length_spinbox.max_value = 2.0
	_segment_length_spinbox.step = 0.01
	_segment_length_spinbox.value = 0.2
	container.add_child(_segment_length_spinbox)

	# Ángulos respecto al hueso padre — es lo que separa dos hermanos que
	# si no saldrían exactamente superpuestos.
	_angle_x_spinbox = SpinBox.new()
	_angle_x_spinbox.prefix = "Áng X:"
	_angle_x_spinbox.min_value = -180.0
	_angle_x_spinbox.max_value = 180.0
	_angle_x_spinbox.step = 5.0
	_angle_x_spinbox.value = 0.0
	container.add_child(_angle_x_spinbox)

	_angle_z_spinbox = SpinBox.new()
	_angle_z_spinbox.prefix = "Áng Z:"
	_angle_z_spinbox.min_value = -180.0
	_angle_z_spinbox.max_value = 180.0
	_angle_z_spinbox.step = 5.0
	_angle_z_spinbox.value = 0.0
	container.add_child(_angle_z_spinbox)

	var add_btn := Button.new()
	add_btn.text = "Agregar segmento"
	add_btn.pressed.connect(_on_add_segment_pressed)
	container.add_child(add_btn)


func _refresh_parent_options():
	_parent_bone_option.clear()
	for bone_name in bone_chain_builder.get_chain():
		_parent_bone_option.add_item(bone_name)


func _on_add_segment_pressed():
	if _parent_bone_option.item_count == 0:
		push_warning("HUD: no hay ningún hueso todavía para elegir como padre.")
		return

	var parent_name := _parent_bone_option.get_item_text(_parent_bone_option.selected)
	var new_name := "Segmento_%d" % bone_chain_builder.get_chain().size()
	var length: float = _segment_length_spinbox.value
	var direction := Vector3(_angle_x_spinbox.value, 0.0, _angle_z_spinbox.value)

	var created := bone_chain_builder.add_segment(new_name, length, parent_name, direction)
	if created != "":
		bone_visual_layer.generate_single(bone_chain_builder, created)
		_refresh_parent_options() # el hueso nuevo también queda disponible como padre


# --- Fase 3: anclar la cadena de huesos a un socket real del chasis ---
# Convive con el flujo normal de Fase 1/2 (grilla + clic en socket) — esto
# no lo reemplaza, es una segunda forma de originar una pieza: en vez de
# elegir una ya hecha, construirla en vivo desde acá, arrancando en el
# mismo punto donde una pieza prehecha se hubiera acoplado.

func _setup_socket_anchor_controls():
	if not bone_chain_builder:
		push_error("HUD: falta BoneChainBuilder, no puedo armar el selector de sockets.")
		return

	var container := $LeftPanel/BoxContainer

	_socket_option = OptionButton.new()
	container.add_child(_socket_option)
	_refresh_socket_options()

	var anchor_btn := Button.new()
	anchor_btn.text = "Anclar a socket"
	anchor_btn.pressed.connect(_on_anchor_to_socket_pressed)
	container.add_child(anchor_btn)

	var register_btn := Button.new()
	register_btn.text = "Registrar como pieza"
	register_btn.pressed.connect(_on_register_as_part_pressed)
	container.add_child(register_btn)


func _refresh_socket_options():
	if not _socket_option:
		return # todavía no se armó el control (ej. primer _evaluate_zero_state, antes de _setup_socket_anchor_controls)

	_socket_option.clear()
	_available_sockets.clear()

	var chassis: Node3D = assembler.current_instanced_chassis
	if not chassis or not (chassis is CreatureChassis):
		_socket_option.add_item("(sin chasis elegido)")
		_socket_option.disabled = true
		return

	_socket_option.disabled = false
	for socket_name in (chassis as CreatureChassis).get_all_socket_names():
		_available_sockets[socket_name] = (chassis as CreatureChassis).get_socket(socket_name)
		_socket_option.add_item(socket_name)


func _on_anchor_to_socket_pressed():
	if _socket_option.disabled or _socket_option.item_count == 0:
		push_warning("HUD: no hay ningún socket disponible para anclar todavía — elegí un Chasis primero.")
		return

	var socket_name := _socket_option.get_item_text(_socket_option.selected)
	var socket: InteractiveSocket = _available_sockets.get(socket_name)
	if not socket:
		push_error("HUD: no encontré el socket '%s'." % socket_name)
		return

	bone_chain_builder.anchor_to(socket)
	print("HUD: BoneChainBuilder anclado al socket '%s'." % socket_name)


# --- Fase 3: convertir la cadena de huesos actual en una pieza real ---
# Esto es lo que hace que Fase 3 y Fase 1/2 trabajen sobre la MISMA
# criatura: empaqueta lo armado como part_scene real y lo registra en
# active_dna.attached_parts, la misma puerta que usa cualquier pieza
# prehecha. Desde ese momento el sistema no distingue una cosa de la otra.

const CUSTOM_PART_WEIGHT_PER_LENGTH := 5.0  ## peso = largo total de huesos * esta constante

func _on_register_as_part_pressed():
	if not bone_chain_builder or not bone_chain_builder.skeleton:
		push_warning("HUD: no hay nada armado en BoneChainBuilder todavía.")
		return

	var anchor_socket := bone_chain_builder.skeleton.get_parent()
	if not (anchor_socket is InteractiveSocket):
		push_warning("HUD: anclá la cadena a un socket ('Anclar a socket') antes de registrarla como pieza.")
		return

	var chain := bone_chain_builder.get_chain()
	if chain.is_empty():
		push_warning("HUD: la cadena no tiene ningún hueso todavía.")
		return

	var total_length := 0.0
	for bone_name in chain:
		total_length += bone_chain_builder.get_bone_length(bone_name)

	# PackedScene.pack() solo incluye nodos cuyo 'owner' apunta a la raíz
	# empaquetada. Las cápsulas de BoneVisualLayer nacieron por código en
	# runtime, nunca tuvieron owner asignado (eso solo pasa solo al armar
	# a mano en el editor) — sin este paso, se empaquetaría un esqueleto
	# vacío, sin ninguna cápsula adentro.
	_fix_owners_for_packing(bone_chain_builder.skeleton, bone_chain_builder.skeleton)

	var packed := PackedScene.new()
	var pack_err := packed.pack(bone_chain_builder.skeleton)
	if pack_err != OK:
		push_error("HUD: no se pudo empaquetar la pieza (error %d)." % pack_err)
		return

	var part_data := CreaturePartData.new()
	part_data.id = "custom_%d" % Time.get_ticks_msec()
	part_data.display_name = "Pieza personalizada (%.2f)" % total_length
	part_data.part_scene = packed
	part_data.weight = total_length * CUSTOM_PART_WEIGHT_PER_LENGTH
	part_data.speed_mod = 0.0  # el peso ya penaliza velocidad solo en recalculate_stats() — no duplicar el castigo acá
	part_data.fire_resistance_mod = 0.0

	# Sacar el Skeleton3D original del socket ANTES de que add_dynamic_part
	# instancie una copia nueva del part_scene recién empaquetado — si no,
	# quedan dos copias superpuestas en el mismo lugar.
	anchor_socket.remove_child(bone_chain_builder.skeleton)

	assembler.add_dynamic_part(anchor_socket, part_data, player_dummy)
	print("HUD: pieza personalizada registrada — largo total %.2f, peso %.2f." % [total_length, part_data.weight])

	# El Skeleton3D se fue con la pieza — armamos uno nuevo, vacío, para
	# poder construir la siguiente pieza personalizada sin reiniciar nada.
	bone_chain_builder.reset()
	_refresh_parent_options()
	_refresh_socket_options()


func _fix_owners_for_packing(node: Node, root: Node) -> void:
	if node != root:
		node.owner = root
	for child in node.get_children():
		_fix_owners_for_packing(child, root)
