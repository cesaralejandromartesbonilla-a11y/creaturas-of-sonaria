extends Node3D
class_name AssemblerBootstrapper

## Mismo espíritu que RequirementsBootstrapper.gd del proyecto de criaturas:
## genera toda la jerarquía por código en vez de armarla a mano en el editor.
## Poné este script en una escena vacía y dale a jugar — vas a tener el
## larguero, los 3 sockets, el ensamblador, la UI y hasta el catálogo de
## piezas (con mesh y colisión placeholder) ya armados y cableados. Después,
## si querés, seleccioná esta rama en el árbol remoto y "Guardar rama como
## escena" para tener un .tscn de verdad — mismo flujo que ya usaste con el
## constructor de criaturas.
##
## Este nodo hace de "Construccion" (el contenedor común del diagrama de
## LEEME.md) — Chassis, MechanicalAssembler y MechanicalAssemblerUI cuelgan
## directo de acá.

## Capa de colisión para los MechanicalSocket. Uso la 11 (1 << 10) y no la 10
## porque tu CameraController.gd ya usa collision_mask = 513 (capas 1 y 10)
## para el internal_ray del buceo. No debería chocar en la práctica (esa
## raycast solo mira bodies, no areas) pero mejor no pisar una capa que ya
## está en uso — confirmá en Project Settings > Layer Names > 3D Physics
## que la 11 esté libre en tu proyecto.
const CAPA_SOCKETS := 1 << 10

@export var camera: Camera3D  # opcional — si no la asignás, la busca vía CameraController o en el viewport
@export var colocar_piezas_automaticamente: bool = false  # true = arma el vehículo completo al arrancar, sin pasar por la UI de clic — útil para volver a aislar física pura si algo se rompe más adelante, pero ya cumplió su función
@export var congelar_larguero_diagnostico: bool = false  # TEMPORAL: si el larguero también rota (por el torque de reacción de los 3 motores), eso se mezcla con el giro propio de cada pieza. Congelarlo aísla si el problema viene de ahí. Confirmado que no era la causa — queda en false por defecto; un chasis de verdad tiene que poder rotar.
@export var crear_controlador_vehiculo: bool = true  # true = genera un ControladorVehiculo y lo mete solo en el grupo "controlador_vehiculo" — así MotorPart tiene dónde registrarse sin que armes nada a mano

var controlador_vehiculo: ControladorVehiculo
var camera_controller: Node

var larguero: Chassis
var ensamblador: MechanicalAssembler
var ensamblador_ui: MechanicalAssemblerUI
var catalogo_hud: WorkshopCatalogHUD
var datos_motor: MechanicalPartData
var datos_engranaje: MechanicalPartData
var datos_rueda: MechanicalPartData
var socket_motor: MechanicalSocket
var socket_engranaje: MechanicalSocket
var socket_rueda: MechanicalSocket


func _ready() -> void:
	_crear_larguero()
	_crear_ensamblador()

	if crear_controlador_vehiculo:
		_crear_controlador_vehiculo()

	camera_controller = _encontrar_camera_controller()
	if camera_controller:
		print("AssemblerBootstrapper: CameraController encontrado -> ", camera_controller.get_path())
	else:
		push_warning("AssemblerBootstrapper: no encontré ni un autoload en /root/PlayerCamera ni un nodo en el grupo 'camara_principal' — por eso no hay reenvío de input ni de process_camera(), la cámara queda completamente inerte.")
	_crear_ui(camera_controller)
	_activar_orbital(camera_controller)
	_crear_catalogo()

	catalogo_hud = WorkshopCatalogHUD.new()
	add_child(catalogo_hud)
	catalogo_hud.configurar(ensamblador_ui, ensamblador, self, datos_motor, datos_engranaje, datos_rueda)

	if colocar_piezas_automaticamente:
		_colocar_piezas_automaticamente()

	_set_owner_recursivo(self, self)
	print("AssemblerBootstrapper: jerarquía generada. Mirala en el árbol remoto mientras corre la escena — datos_motor / datos_engranaje / datos_rueda ya están listos para ensamblador_ui.set_selected_part().")


## Prueba primero /root/PlayerCamera (el mismo camino que usa simple_body.gd
## en tu proyecto real — si es autoload, siempre está ahí, sin depender de
## que nadie tilde un grupo a mano en el editor). Si no existe con ese
## nombre, cae al grupo "camara_principal" como respaldo, para que esto
## también funcione en un proyecto donde CameraController no sea autoload.
func _encontrar_camera_controller() -> Node:
	var autoload := get_node_or_null("/root/PlayerCamera")
	if autoload:
		return autoload
	return get_tree().get_first_node_in_group("camara_principal")


func _crear_larguero() -> void:
	larguero = Chassis.new()
	larguero.name = "Chassis"
	larguero.lock_rotation = congelar_larguero_diagnostico
	add_child(larguero)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 0.3, 0.6)
	mesh.mesh = box
	mesh.material_override = _material(Color.SLATE_GRAY)
	larguero.add_child(mesh)

	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	col.shape = box_shape
	larguero.add_child(col)

	socket_motor = _crear_socket("SocketMotor", Vector3(-0.7, 0.6, 0))
	socket_engranaje = _crear_socket("SocketEngranaje", Vector3(0.0, 0.6, 0))
	socket_rueda = _crear_socket("SocketRueda", Vector3(0.7, 0.6, 0))


func _crear_socket(nombre: String, posicion_local: Vector3) -> MechanicalSocket:
	var socket := MechanicalSocket.new()
	socket.name = nombre
	socket.socket_name = nombre
	socket.collision_layer = CAPA_SOCKETS
	socket.position = posicion_local
	socket.rotation_degrees.y = 90.0  # eje de giro (+Z local) apuntando de costado — ajustalo cuando tengas mallas reales
	larguero.add_child(socket)
	return socket


func _crear_ensamblador() -> void:
	ensamblador = MechanicalAssembler.new()
	ensamblador.name = "MechanicalAssembler"
	add_child(ensamblador)
	ensamblador.larguero = larguero


## Genera el ControladorVehiculo y lo agrupa solo — así respondo tu duda:
## joints_traccion NO lo llenás vos a mano, MotorPart.al_ser_montada() hace
## controlador.joints_traccion.append(joint_montaje) apenas se coloca cada
## motor. Lo único que hacía falta era que este nodo existiera y estuviera
## en el grupo "controlador_vehiculo" ANTES de que _colocar_piezas_automaticamente()
## corra — por eso esta función va antes que esa en _ready().
func _crear_controlador_vehiculo() -> void:
	controlador_vehiculo = ControladorVehiculo.new()
	controlador_vehiculo.name = "ControladorVehiculo"
	add_child(controlador_vehiculo)
	controlador_vehiculo.add_to_group("controlador_vehiculo")


func _crear_ui(camera_controller: Node) -> void:
	ensamblador_ui = MechanicalAssemblerUI.new()
	ensamblador_ui.name = "MechanicalAssemblerUI"
	add_child(ensamblador_ui)
	ensamblador_ui.ensamblador = ensamblador
	ensamblador_ui.socket_collision_mask = CAPA_SOCKETS
	ensamblador_ui.hologram_material = _material(Color(1, 1, 1, 0.4), true)

	if camera_controller and camera_controller.has_method("get_camera"):
		ensamblador_ui.camera = camera_controller.get_camera()
	elif camera:
		ensamblador_ui.camera = camera
	else:
		ensamblador_ui.camera = get_viewport().get_camera_3d()
		push_warning("AssemblerBootstrapper: no encontré un CameraController en el grupo 'camara_principal' ni asignaste 'camera' a mano — uso la cámara activa del viewport como último recurso.")


func _activar_orbital(camera_controller: Node) -> void:
	if not camera_controller:
		push_warning("AssemblerBootstrapper: no hay ningún nodo en el grupo 'camara_principal'. Agregá tu CameraController a ese grupo (panel Node > Groups), o llamá a mano a camera_controller.asignar_objetivo_orbital(larguero).")
		return
	if camera_controller.has_method("asignar_objetivo_orbital"):
		camera_controller.asignar_objetivo_orbital(larguero)
	else:
		push_warning("AssemblerBootstrapper: el nodo en 'camara_principal' no tiene asignar_objetivo_orbital() — ¿es una copia de CameraController.gd desactualizada?")


func _crear_catalogo() -> void:
	datos_motor = _crear_datos("Motor", MechanicalPartData.PartType.MOTOR, MotorPart, Color.ORANGE_RED, Vector3(0.3, 0.3, 0.3))
	datos_engranaje = _crear_datos("Engranaje", MechanicalPartData.PartType.ENGRANAJE, GearPart, Color.STEEL_BLUE, Vector3(0.25, 0.25, 0.25))
	datos_rueda = _crear_datos("Rueda", MechanicalPartData.PartType.RUEDA, WheelPart, Color.FOREST_GREEN, Vector3(0.35, 0.35, 0.35))


## A propósito salteamos MechanicalAssemblerUI acá: nada de raycast, nada de
## mouse, nada de socket.is_occupied dependiendo de un click que nunca pasa.
## Esto llama a MechanicalAssembler.acoplar_pieza() directo, tres veces, para
## aislar si el problema estaba en la física (joints + propagación) o en la
## UI — si ves 3 cajas de colores prendidas de la barra gris al arrancar,
## la física anda. Poné colocar_piezas_automaticamente en false cuando
## quieras volver a probar con clic.
func _colocar_piezas_automaticamente() -> void:
	var motor := ensamblador.acoplar_pieza(socket_motor, datos_motor)
	var engranaje := ensamblador.acoplar_pieza(socket_engranaje, datos_engranaje)
	var rueda := ensamblador.acoplar_pieza(socket_rueda, datos_rueda)
	if motor and engranaje and rueda:
		print("AssemblerBootstrapper: vehículo armado automáticamente. Si ves 3 cajas de colores sobre la barra gris, la física funcionó — dale al acelerador de ControladorVehiculo y fijate si giran.")
		_diagnosticar_posiciones(motor, engranaje, rueda)
	else:
		push_error("AssemblerBootstrapper: algo falló acoplando una pieza automática — mirá los mensajes de arriba en la consola (Output), ahí dice cuál.")


## Diagnóstico temporal para el problema de posiciones en Y — imprime
## global_position.y de larguero, sockets y piezas TODO por código, sin
## depender de leer campos del Inspector a mano (ahí es fácil confundir
## Transform > Position local con Global Transform). Corre dos veces: apenas
## se colocan, y de nuevo 1 segundo después — así vemos si el problema está
## desde el instante cero o si algo las mueve después.
func _diagnosticar_posiciones(motor: MechanicalPart, engranaje: MechanicalPart, rueda: MechanicalPart) -> void:
	_imprimir_posiciones("INSTANTE 0 (recién colocadas)", motor, engranaje, rueda)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(motor) and is_instance_valid(engranaje) and is_instance_valid(rueda):
		_imprimir_posiciones("1 SEGUNDO DESPUÉS", motor, engranaje, rueda)


func _imprimir_posiciones(etiqueta: String, motor: MechanicalPart, engranaje: MechanicalPart, rueda: MechanicalPart) -> void:
	print("--- DIAGNÓSTICO DE POSICIONES (Y global, por código) — ", etiqueta, " ---")
	print("Chassis.global_position.y = ", larguero.global_position.y)
	print("SocketMotor.global_position.y = ", socket_motor.global_position.y, "  |  Motor.global_position.y = ", motor.global_position.y)
	print("SocketEngranaje.global_position.y = ", socket_engranaje.global_position.y, "  |  Engranaje.global_position.y = ", engranaje.global_position.y)
	print("SocketRueda.global_position.y = ", socket_rueda.global_position.y, "  |  Rueda.global_position.y = ", rueda.global_position.y)


## Arma una escena mínima (RigidBody3D + caja de mesh/colisión) por código y
## la empaqueta en un PackedScene — así tenés un MechanicalPartData de
## verdad para probar sin guardar un solo .tscn a mano.
func _crear_datos(nombre: String, tipo: MechanicalPartData.PartType, script: Script, color: Color, tamano: Vector3) -> MechanicalPartData:
	var raiz := RigidBody3D.new()
	raiz.set_script(script)
	raiz.name = nombre

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = tamano
	mesh.mesh = box
	mesh.material_override = _material(color)
	raiz.add_child(mesh)
	mesh.owner = raiz

	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = tamano
	col.shape = box_shape
	raiz.add_child(col)
	col.owner = raiz

	var paquete := PackedScene.new()
	paquete.pack(raiz)

	var datos := MechanicalPartData.new()
	datos.display_name = nombre
	datos.part_type = tipo
	datos.part_scene = paquete
	return datos


func _material(color: Color, transparente: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if transparente:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _set_owner_recursivo(nodo: Node, dueno: Node) -> void:
	for hijo in nodo.get_children():
		if hijo.owner == null:
			hijo.owner = dueno
		_set_owner_recursivo(hijo, dueno)


const SAVE_PATH := "user://saved_build.tres"

## Guarda la construcción actual del taller en disco — sobrevive cerrar el
## juego, a diferencia de PendingBuild (que solo sobrevive un cambio de
## escena). Mismo BuildData que ya usa lanzar_al_mundo(): acá en vez de
## cruzar a otra escena por el autoload, se serializa directo a user://.
func guardar_construccion() -> void:
	var data := ensamblador.exportar_construccion()
	var err := ResourceSaver.save(data, SAVE_PATH)
	if err == OK:
		print("AssemblerBootstrapper: construcción guardada en ", SAVE_PATH)
	else:
		push_error("AssemblerBootstrapper: no se pudo guardar (error %d)." % err)


## Carga la construcción guardada y la reconstruye sobre el larguero
## actual. Saca primero cualquier pieza que ya esté puesta (quitar_pieza
## por cada socket ocupado) para no terminar con piezas mezcladas de dos
## construcciones distintas.
func cargar_construccion() -> void:
	if not ResourceLoader.exists(SAVE_PATH):
		push_warning("AssemblerBootstrapper: no hay ninguna construcción guardada todavía en '%s'." % SAVE_PATH)
		return

	var data: BuildData = ResourceLoader.load(SAVE_PATH)
	if not data:
		push_error("AssemblerBootstrapper: '%s' existe pero no se pudo leer como BuildData." % SAVE_PATH)
		return

	for socket in larguero.get_sockets():
		if socket.is_occupied:
			ensamblador.quitar_pieza(socket)

	var catalogo := {
		MechanicalPartData.PartType.MOTOR: datos_motor,
		MechanicalPartData.PartType.ENGRANAJE: datos_engranaje,
		MechanicalPartData.PartType.RUEDA: datos_rueda,
	}
	for socket in larguero.get_sockets():
		if data.socket_a_tipo.has(socket.socket_name):
			var tipo: MechanicalPartData.PartType = data.socket_a_tipo[socket.socket_name]
			ensamblador.acoplar_pieza(socket, catalogo[tipo])

	print("AssemblerBootstrapper: construcción cargada — ", data.socket_a_tipo.size(), " piezas.")


## Equivalente mínimo a lo que hace simple_body.gd con PlayerCamera en tu
## proyecto real: CameraController no se mueve solo, necesita que algo le
## llame process_camera(delta) cada frame y handle_input(event) en cada
## evento. Sin esto, is_build_mode/orbital_target pueden estar perfectos
## y aun así no pasa nada — no era el target, era que nadie lo llamaba.
func _physics_process(delta: float) -> void:
	if camera_controller and camera_controller.has_method("process_camera"):
		camera_controller.process_camera(delta)


## Selector TEMPORAL por teclado (1/2/3) — un stand-in del catálogo de
## verdad que viene en la Fase 2 del taller — fusionado acá con el reenvío
## de input a la cámara, porque _unhandled_input solo puede existir una vez.
func _unhandled_input(event: InputEvent) -> void:
	if camera_controller and camera_controller.has_method("handle_input"):
		camera_controller.handle_input(event)

	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_1:
			ensamblador_ui.set_selected_part(datos_motor)
			print("AssemblerBootstrapper: pieza seleccionada -> Motor. Apuntá a un socket libre y hacé clic.")
		KEY_2:
			ensamblador_ui.set_selected_part(datos_engranaje)
			print("AssemblerBootstrapper: pieza seleccionada -> Engranaje. Apuntá a un socket libre y hacé clic.")
		KEY_3:
			ensamblador_ui.set_selected_part(datos_rueda)
			print("AssemblerBootstrapper: pieza seleccionada -> Rueda. Apuntá a un socket libre y hacé clic.")
