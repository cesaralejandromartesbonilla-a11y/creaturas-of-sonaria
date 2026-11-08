extends Node

## Autoload — registralo en Project Settings > Autoload como
## "PendingBuild". Mismo patrón exacto que PendingSpawnData.gd
## del proyecto de criaturas: el único lugar seguro para pasar la
## construcción del Taller (una escena) al Mundo (otra escena
## completamente distinta) — los autoloads son los únicos nodos que Godot
## garantiza que sobreviven un change_scene_to_file().

var has_pending: bool = false
var pending_data: BuildData = null


## Llamado por MechanicalAssembler.lanzar_al_mundo() justo antes de cambiar de escena.
func stage(data: BuildData) -> void:
	pending_data = _duplicar(data)
	has_pending = true


## Se "consume": una vez leído, se limpia solo — así un reload accidental
## del mundo no vuelve a spawnear la misma construcción de nuevo.
func consume() -> BuildData:
	var data := pending_data
	pending_data = null
	has_pending = false
	return data


func _duplicar(origen: BuildData) -> BuildData:
	var copia := BuildData.new()
	# duplicate(true): copia el Dictionary de adentro — así el taller puede
	# seguir editando su propio dato sin afectar a la copia que ya cruzó.
	copia.socket_a_tipo = origen.socket_a_tipo.duplicate(true)
	return copia
