extends Node
class_name BoneVisualLayer

## Sistema de creación de huesos — Parte 2 de 3.
## (1: BoneChainBuilder — huesos. 2: esto — cilindros/cápsulas simples,
## una por hueso. 3: crecer segmentos nuevos usando 1 y 2 juntos.)
##
## Genera un MeshInstance3D primitivo (cápsula o cilindro) por hueso de un
## BoneChainBuilder. Nada de skinning, nada de detalle — solo la silueta
## cruda de la cadena.
##
## A propósito NO usa BoneAttachment3D: Skeleton3D tiene un bug conocido
## (godotengine/godot#103623) donde huesos armados en cadena por código no
## propagan bien su pose global, y ni forzar la actualización lo resolvió
## de forma confiable en pruebas reales. La posición de cada cápsula se
## calcula a mano, sumando las longitudes de BoneChainBuilder (dato propio,
## confiable) — nunca se lee la pose del hueso. Costo real de esta decisión:
## estas cápsulas son estáticas, NO van a seguir al hueso si más adelante se
## anima o se le aplica IK. No es un problema para esta etapa.

enum PrimitiveShape { CAPSULE, CYLINDER }

@export var shape: PrimitiveShape = PrimitiveShape.CAPSULE
## radio = longitud del hueso * este valor. Provisorio: la Parte 1 todavía
## no guarda un grosor propio por hueso, así que se deriva de la longitud.
@export var thickness_ratio: float = 0.18


## Genera cápsulas/cilindros para TODOS los huesos de 'builder' que todavía
## no tengan una — colgadas como hijas directas de su Skeleton3D. Pensado
## para el batch inicial; para agregar de a un hueso por vez (Parte 3),
## usar generate_single() en su lugar y evitar duplicados.
func generate_from(builder: BoneChainBuilder) -> Array[MeshInstance3D]:
	var created: Array[MeshInstance3D] = []

	if not builder or not builder.skeleton:
		push_error("BoneVisualLayer: el BoneChainBuilder no tiene Skeleton3D.")
		return created

	for bone_name in builder.get_chain():
		var mesh_instance := generate_single(builder, bone_name)
		if mesh_instance:
			created.append(mesh_instance)

	print("BoneVisualLayer: %d mallas primitivas generadas para '%s'." % [created.size(), builder.skeleton.name])
	return created


## Genera la cápsula/cilindro de UN solo hueso ya existente en 'builder'.
## Es lo que usa Parte 3 al agregar un segmento a demanda — así no hace
## falta regenerar (y duplicar) los que ya estaban.
func generate_single(builder: BoneChainBuilder, bone_name: String) -> MeshInstance3D:
	if not builder or not builder.skeleton:
		push_error("BoneVisualLayer: el BoneChainBuilder no tiene Skeleton3D.")
		return null

	var skeleton := builder.skeleton
	if skeleton.find_bone(bone_name) == -1:
		push_error("BoneVisualLayer: '%s' no existe en el Skeleton3D." % bone_name)
		return null
	if skeleton.has_node("Primitive_" + bone_name):
		push_warning("BoneVisualLayer: '%s' ya tiene una malla generada, no se duplica." % bone_name)
		return null

	var length := builder.get_bone_length(bone_name)
	var chain_transform := builder.get_chain_transform(bone_name)
	return _create_primitive_for_bone(skeleton, bone_name, length, chain_transform)


func _create_primitive_for_bone(skeleton: Skeleton3D, bone_name: String, length: float, chain_transform: Transform3D) -> MeshInstance3D:
	var radius: float = max(0.01, length * thickness_ratio)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Primitive_" + bone_name

	match shape:
		PrimitiveShape.CAPSULE:
			var capsule := CapsuleMesh.new()
			capsule.radius = radius
			capsule.height = max(length, radius * 2.0)  # la cápsula no puede ser más corta que su propio diámetro
			mesh_instance.mesh = capsule
		PrimitiveShape.CYLINDER:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = radius
			cylinder.bottom_radius = radius
			cylinder.height = length
			mesh_instance.mesh = cylinder

	# Posición Y orientación calculadas desde el transform compuesto de la
	# cadena (rests locales encadenados), más medio segmento sobre el +Y
	# propio del hueso — los primitivos de Godot nacen centrados en su
	# origen. Nunca se lee la pose global del esqueleto.
	mesh_instance.transform = chain_transform * Transform3D(Basis.IDENTITY, Vector3(0, length * 0.5, 0))

	skeleton.add_child(mesh_instance)
	return mesh_instance
