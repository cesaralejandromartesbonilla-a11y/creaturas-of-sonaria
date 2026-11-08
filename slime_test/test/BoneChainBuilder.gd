extends Node
class_name BoneChainBuilder

## Sistema de creación de huesos — Parte 1 de 3.
## (1: esto — huesos. 2: capa visual, cilindros/cápsulas. 3: crecer segmentos
## nuevos a partir de los anteriores, usando 1 y 2 juntos.)
##
## Envuelve un Skeleton3D y agrega huesos en cadena, cada uno naciendo en la
## PUNTA del anterior. Todavía sin nada visual a propósito — eso es la Parte 2.
##
## Nota técnica: Skeleton3D tiene un bug conocido (godotengine/godot#103623)
## donde set_bone_rest() por código no actualiza get_bone_global_rest()
## correctamente. Por eso acá NUNCA se lee el rest global — todo se calcula
## en espacio local del padre, llevando la cuenta de longitudes nosotros
## mismos. Si en algún momento hace falta la posición global de verdad, hay
## que confirmar primero si ese bug sigue vivo en tu versión de Godot.
##
## Ya NO auto-arma una cadena de prueba en _ready() — eso ahora lo dispara
## RequirementsBootstrapper.ensure_bone_tools(), explícito, en vez de
## depender del orden de _ready() entre nodos creados dinámicamente.

@export var skeleton: Skeleton3D

## bone_name -> longitud. Skeleton3D no tiene un campo nativo de "longitud
## de hueso" (es más bien convención de Blender/Maya) — lo llevamos acá
## para que cada hueso nuevo sepa dónde nace: en la punta de su padre.
var _bone_lengths: Dictionary = {}


## Ancla esta cadena a un nodo existente — un InteractiveSocket del chasis,
## o un BoneAttachment3D de otra pieza (para nacer desde un segmento ajeno).
## El Skeleton3D pasa a ser hijo directo de 'anchor': la cadena nace
## exactamente en su posición y orientación, sin ningún cálculo de hueso
## de por medio, solo parentesco normal de escena. Sin llamar esto, la
## cadena sigue naciendo en el origen local de su propio Skeleton3D
## (comportamiento actual, sin cambios, para seguir probando aislado).
func anchor_to(anchor: Node3D) -> void:
	if not skeleton:
		push_error("BoneChainBuilder: no hay Skeleton3D para anclar.")
		return
	if not anchor:
		push_error("BoneChainBuilder: 'anchor' es null.")
		return

	var old_parent := skeleton.get_parent()
	if old_parent:
		old_parent.remove_child(skeleton)
	anchor.add_child(skeleton)
	skeleton.position = Vector3.ZERO
	skeleton.rotation = Vector3.ZERO


## Descarta el Skeleton3D actual y genera uno nuevo, vacío — para poder
## empezar a armar la siguiente pieza desde cero sin recargar la escena.
## No hay una forma segura de "vaciar" huesos de un Skeleton3D existente
## uno por uno, así que se reemplaza entero.
func reset() -> void:
	if skeleton:
		var old_parent := skeleton.get_parent()
		if old_parent:
			old_parent.remove_child(skeleton)
		skeleton.queue_free()

	var new_skeleton := Skeleton3D.new()
	new_skeleton.name = "GeneratedSkeleton"
	add_child(new_skeleton)
	skeleton = new_skeleton
	_bone_lengths.clear()


func _ready() -> void:
	if not skeleton:
		skeleton = Skeleton3D.new()
		skeleton.name = "GeneratedSkeleton"
		add_child(skeleton)
		print("BoneChainBuilder: no había Skeleton3D asignado, generé uno nuevo.")


## Agrega un hueso nuevo de 'length' unidades, extendiéndose a lo largo del
## eje +Y local (misma convención que ya usamos en los esqueletos de piezas).
## 'parent_bone_name' vacío = hueso raíz de la cadena.
## 'direction_degrees' rota el hueso respecto a su padre — es lo que permite
## que dos hermanos del mismo padre salgan en direcciones distintas en vez
## de superpuestos (ej. Vector3(0,0,30) y Vector3(0,0,-30) para una V).
## Devuelve el nombre del hueso creado, o "" si falló.
func add_segment(bone_name: String, length: float, parent_bone_name: String = "", direction_degrees: Vector3 = Vector3.ZERO) -> String:
	if not skeleton:
		push_error("BoneChainBuilder: no hay Skeleton3D asignado.")
		return ""
	if skeleton.find_bone(bone_name) != -1:
		push_error("BoneChainBuilder: ya existe un hueso llamado '%s'." % bone_name)
		return ""

	var parent_idx := -1
	if parent_bone_name != "":
		parent_idx = skeleton.find_bone(parent_bone_name)
		if parent_idx == -1:
			push_error("BoneChainBuilder: no existe el hueso padre '%s'." % parent_bone_name)
			return ""

	skeleton.add_bone(bone_name)
	# No confío en que add_bone() devuelva el índice — lo busco por nombre,
	# así funciona sin importar la versión exacta de Godot.
	var new_idx := skeleton.find_bone(bone_name)
	if new_idx == -1:
		push_error("BoneChainBuilder: add_bone() no generó el hueso esperado.")
		return ""

	skeleton.set_bone_parent(new_idx, parent_idx)

	# Origen local: (0,0,0) si es raíz, o la punta del padre si tiene uno —
	# calculado a mano, nunca leído de get_bone_global_rest() (ver nota del bug arriba).
	var local_origin := Vector3.ZERO
	if parent_bone_name != "":
		var parent_length: float = _bone_lengths.get(parent_bone_name, 0.0)
		local_origin = Vector3(0, parent_length, 0)

	# La rotación va en el rest LOCAL, respecto al padre. Componer estos
	# rests locales es lo que después reconstruye la posición real de cada
	# hueso en get_chain_transform(), sin tocar nunca el rest global.
	var local_basis := Basis.from_euler(Vector3(
		deg_to_rad(direction_degrees.x),
		deg_to_rad(direction_degrees.y),
		deg_to_rad(direction_degrees.z)
	))

	skeleton.set_bone_rest(new_idx, Transform3D(local_basis, local_origin))
	_bone_lengths[bone_name] = length

	print("BoneChainBuilder: hueso '%s' creado (largo %.2f, padre '%s', dir %s)." % [bone_name, length, parent_bone_name if parent_bone_name != "" else "(raíz)", direction_degrees])
	return bone_name


## Transform acumulado de un hueso, compuesto desde la raíz sumando los rests
## LOCALES (que sí son confiables — el bug #103623 es sobre el rest GLOBAL).
## Esto reemplaza al viejo cálculo de "offset acumulado" en float, que solo
## sabía apilar sobre +Y y no podía expresar direcciones.
func get_chain_transform(bone_name: String) -> Transform3D:
	if not skeleton:
		return Transform3D.IDENTITY

	var idx := skeleton.find_bone(bone_name)
	if idx == -1:
		return Transform3D.IDENTITY

	# Camino desde la raíz hasta este hueso.
	var path: Array[int] = []
	var cursor := idx
	while cursor != -1:
		path.push_front(cursor)
		cursor = skeleton.get_bone_parent(cursor)

	var accum := Transform3D.IDENTITY
	for bone_idx in path:
		accum = accum * skeleton.get_bone_rest(bone_idx)
	return accum


## Longitud guardada de un hueso ya creado (0.0 si no existe).
func get_bone_length(bone_name: String) -> float:
	return _bone_lengths.get(bone_name, 0.0)


## Nombres de huesos en orden de creación (equivale al orden de la cadena
## si cada uno se agregó con el anterior como padre).
func get_chain() -> Array[String]:
	var names: Array[String] = []
	for bone_name in _bone_lengths:
		names.append(bone_name)
	return names
