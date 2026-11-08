extends Node
class_name MechanicalAssembler

## Equivalente a AssemblerModule del proyecto de criaturas, pero para piezas
## físicas de verdad. La diferencia central: allá, acoplar era
## "socket.add_child(pieza)" — puro parentesco de escena, cero física. Acá,
## acoplar significa instanciar un RigidBody3D independiente y crear un
## HingeJoint3D real que lo une al larguero. Nunca Generic6DOFJoint3D: el
## larguero es el único cuerpo estructural, todo lo demás es una pieza
## rotativa con un solo hinge.

@export var larguero: Chassis
@export var world_scene_path: String = "res://slime_test/escenario.tscn"

var motor_actual: MotorPart = null
var engranaje_actual: TransmissionPart = null
var rueda_actual: TransmissionPart = null


func acoplar_pieza(socket: MechanicalSocket, datos: MechanicalPartData) -> MechanicalPart:
	if not larguero:
		push_error("MechanicalAssembler: falta asignar 'larguero' en el Inspector.")
		return null
	if socket.is_occupied:
		push_warning("MechanicalAssembler: el socket '%s' ya está ocupado." % socket.socket_name)
		return null
	if not datos or not datos.part_scene:
		push_error("MechanicalAssembler: MechanicalPartData sin part_scene asignada.")
		return null

	var contenedor := larguero.get_parent()
	if not contenedor:
		push_error("MechanicalAssembler: 'larguero' no tiene nodo padre — necesita un contenedor común (ej. 'Construccion') donde agregar las piezas nuevas.")
		return null

	var instancia := datos.part_scene.instantiate() as MechanicalPart
	if not instancia:
		push_error("MechanicalAssembler: la raíz de la escena de '%s' no es una MechanicalPart." % datos.display_name)
		return null

	contenedor.add_child(instancia)
	instancia.global_transform = socket.global_transform

	instancia.joint_montaje = _crear_joint_hinge(socket, instancia)
	instancia.socket_origen = socket
	larguero.add_collision_exception_with(instancia)
	for otra in [motor_actual, engranaje_actual, rueda_actual]:
		if otra and otra != instancia:
			instancia.add_collision_exception_with(otra)
	socket.is_occupied = true

	_registrar_y_conectar(datos.part_type, instancia)
	instancia.al_ser_montada()

	print("MechanicalAssembler: '%s' acoplada en socket '%s'." % [datos.display_name, socket.socket_name])
	return instancia


## Ver el comentario de _crear_joint_hinge() más abajo — ahí está la
## explicación actualizada de cómo se posiciona el joint.
## Hijo DIRECTO del socket, sin tocarle el transform. Un nodo recién
## agregado con transform local en identidad hereda exactamente la
## posición/orientación global de su padre — cero cálculo, cero riesgo de
## desfasarse. La versión anterior (add_child + global_transform a mano)
## tenía el orden más o menos bien, pero setear global_transform en un
## nodo TODAVÍA SIN PADRE no calcula bien qué local hace falta para llegar
## ahí — el offset del socket terminaba aplicándose dos veces. Esto lo
## evita de raíz, no reordenando sino sacando el cálculo del medio.
func _crear_joint_hinge(socket: MechanicalSocket, pieza: RigidBody3D) -> HingeJoint3D:
	var joint := HingeJoint3D.new()
	socket.add_child(joint)
	joint.node_a = larguero.get_path()  # el cuerpo físico real — socket es solo dónde vive el nodo del joint, no lo que conecta
	joint.node_b = pieza.get_path()
	return joint


## Cablea 'fuente' según qué se montó y qué había antes — funciona sin
## importar el orden de armado (motor primero, rueda primero, etc.) porque
## SIEMPRE re-revisa las tres referencias actuales, no asume una secuencia.
func _registrar_y_conectar(tipo: MechanicalPartData.PartType, pieza: MechanicalPart) -> void:
	match tipo:
		MechanicalPartData.PartType.MOTOR:
			motor_actual = pieza as MotorPart
			if engranaje_actual:
				engranaje_actual.fuente = motor_actual
			elif rueda_actual:
				rueda_actual.fuente = motor_actual  # todavía no hay engranaje: rueda a motor directo

		MechanicalPartData.PartType.ENGRANAJE:
			engranaje_actual = pieza as TransmissionPart
			if motor_actual:
				engranaje_actual.fuente = motor_actual
			if rueda_actual:
				rueda_actual.fuente = engranaje_actual  # la rueda pasa a escuchar al engranaje, no al motor

		MechanicalPartData.PartType.RUEDA:
			rueda_actual = pieza as TransmissionPart
			if engranaje_actual:
				rueda_actual.fuente = engranaje_actual
			elif motor_actual:
				rueda_actual.fuente = motor_actual


## Inspirado en AssemblerModule._clear_modular_attachments(): desconectar
## lo que dependía de la pieza ANTES de borrarla. A diferencia de ese
## original, acá NO reconstruyo todo de nuevo — para piezas físicas con
## joints, destruir y recrear todo en cada cambio arriesga más (pops,
## sleep, colisiones) que sacar solo lo que cambió y re-cablear lo
## puntual que dependía de eso.
func quitar_pieza(socket: MechanicalSocket) -> void:
	if not socket.is_occupied:
		return

	var pieza: MechanicalPart = null
	if motor_actual and motor_actual.socket_origen == socket:
		pieza = motor_actual
		motor_actual = null
		if engranaje_actual:
			engranaje_actual.fuente = null  # sin motor, el engranaje no tiene de dónde leer giro

	elif engranaje_actual and engranaje_actual.socket_origen == socket:
		pieza = engranaje_actual
		engranaje_actual = null
		if rueda_actual:
			rueda_actual.fuente = motor_actual  # la rueda salta directo al motor si existe, o queda sin fuente

	elif rueda_actual and rueda_actual.socket_origen == socket:
		pieza = rueda_actual
		rueda_actual = null

	if not pieza:
		push_warning("MechanicalAssembler: el socket '%s' figura ocupado pero no encontré qué pieza tiene montada." % socket.socket_name)
		socket.is_occupied = false
		return

	if pieza.joint_montaje:
		pieza.joint_montaje.queue_free()
	pieza.queue_free()
	socket.is_occupied = false
	print("MechanicalAssembler: pieza quitada de '%s'." % socket.socket_name)


## Arma el snapshot serializable de la construcción actual — lo que cruza
## al mundo por PendingBuild. Mismo espíritu que como CreatureDNA
## guarda attached_parts, adaptado a que acá alcanza con "qué tipo fue a
## qué socket" en vez de una lista con paths de nodo.
func exportar_construccion() -> BuildData:
	var data := BuildData.new()
	if motor_actual and motor_actual.socket_origen:
		data.socket_a_tipo[motor_actual.socket_origen.socket_name] = MechanicalPartData.PartType.MOTOR
	if engranaje_actual and engranaje_actual.socket_origen:
		data.socket_a_tipo[engranaje_actual.socket_origen.socket_name] = MechanicalPartData.PartType.ENGRANAJE
	if rueda_actual and rueda_actual.socket_origen:
		data.socket_a_tipo[rueda_actual.socket_origen.socket_name] = MechanicalPartData.PartType.RUEDA
	return data


## Cierra la edición en el taller y dispara el cruce de escena — mismo
## patrón que AssemblerModule.finalize_creature() del proyecto de
## criaturas, incluyendo apagar el modo orbital ANTES de cambiar de
## escena: is_build_mode vive en el autoload PlayerCamera, sobrevive el
## cambio, y si no lo apagamos acá la cámara del mundo se queda mirando
## para siempre a un orbital_target (el larguero del taller) que ya no
## existe. Conectalo al botón de "lanzar al mundo" del HUD.
func lanzar_al_mundo() -> void:
	var data := exportar_construccion()
	PendingBuild.stage(data)

	var player_camera := get_node_or_null("/root/PlayerCamera")
	if player_camera and player_camera.has_method("asignar_objetivo_orbital"):
		player_camera.asignar_objetivo_orbital(null, false)

	var err := get_tree().change_scene_to_file(world_scene_path)
	if err != OK:
		push_error("MechanicalAssembler: no se pudo cambiar a '%s' (error %d) — ¿existe una escena GUARDADA en esa ruta? 'res://escenas/Mundo.tscn' es un path de ejemplo, no una escena real: ajustá world_scene_path en el Inspector a la ruta de tu escena de mundo de verdad." % [world_scene_path, err])
