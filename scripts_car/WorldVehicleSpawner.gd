extends AssemblerBootstrapper
class_name WorldVehicleSpawner

## Versión del bootstrapper para la escena de MUNDO, no el taller: en vez
## de armar un vehículo de prueba fijo, consume lo que haya quedado
## guardado en PendingBuild (staged por
## MechanicalAssembler.lanzar_al_mundo() en el taller) y lo reconstruye
## acá — mismo patrón que WorldCreatureSpawner.gd + PendingSpawnData.gd
## del proyecto de criaturas.
##
## Hereda de AssemblerBootstrapper para reusar _crear_larguero(),
## _crear_ensamblador(), _crear_datos() y _crear_controlador_vehiculo()
## tal cual — el mundo no necesita reinventar cómo se arma un larguero o
## un catálogo, solo qué hacer con ellos una vez armados. A propósito NO
## llama a _crear_ui() ni _activar_orbital(): acá no hay taller de
## construcción ni cámara orbital, es donde se maneja de verdad.

func _ready() -> void:
	_crear_larguero()
	_crear_ensamblador()
	_crear_catalogo()

	if crear_controlador_vehiculo:
		_crear_controlador_vehiculo()

	camera_controller = _encontrar_camera_controller()
	if not camera_controller:
		push_warning("WorldVehicleSpawner: no encontré CameraController — la cámara va a quedar inerte, igual que en el taller si esto falta ahí.")

	_reconstruir_desde_pendiente()
	_set_owner_recursivo(self, self)


## Reemplaza al _unhandled_input() heredado: acá no hay ensamblador_ui, así
## que el selector 1/2/3 del taller no tiene sentido — solo reenviamos
## input a la cámara.
func _unhandled_input(event: InputEvent) -> void:
	if camera_controller and camera_controller.has_method("handle_input"):
		camera_controller.handle_input(event)


func _reconstruir_desde_pendiente() -> void:
	if not PendingBuild.has_pending:
		push_warning("WorldVehicleSpawner: no hay ninguna construcción pendiente — ¿se llegó a esta escena sin pasar por MechanicalAssembler.lanzar_al_mundo() en el taller?")
		return

	var data: BuildData = PendingBuild.consume()
	var catalogo := {
		MechanicalPartData.PartType.MOTOR: datos_motor,
		MechanicalPartData.PartType.ENGRANAJE: datos_engranaje,
		MechanicalPartData.PartType.RUEDA: datos_rueda,
	}

	for socket in larguero.get_sockets():
		if data.socket_a_tipo.has(socket.socket_name):
			var tipo: MechanicalPartData.PartType = data.socket_a_tipo[socket.socket_name]
			ensamblador.acoplar_pieza(socket, catalogo[tipo])

	print("WorldVehicleSpawner: construcción reconstruida — ", data.socket_a_tipo.size(), " piezas.")
