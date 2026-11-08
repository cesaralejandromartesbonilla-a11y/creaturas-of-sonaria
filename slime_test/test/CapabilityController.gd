extends Node
class_name CapabilityController

## Etapa 2 — integración profunda.
##
## Responsabilidad ÚNICA: saber qué puede hacer esta criatura, según las
## piezas que tenga acopladas. No ejecuta ninguna de esas capacidades —
## no vuela, no agarra, no ataca. Solo responde preguntas.
##
## Por qué vive acá y no en simple_body.gd: simple_body es el núcleo
## compartido de 8 clases de cuerpo del proyecto grande; meterle lógica de
## quimeras lo ensuciaría para todos. Y por qué no en AssemblerModule: ese
## arma cuerpos, no decide reglas de juego — mezclarlos repetiría el
## problema original de "todo junto en un script" que Fase 0 resolvió.
##
## El resto del juego pregunta acá (has_capability), nunca asume que un
## cuerpo puede hacer algo por defecto. Esa indirección es a propósito:
## si algún día se va a Etapa 3 (sistema físico sin dummy), las
## capacidades siguen siendo datos consultables y no hay que reescribirlas.

signal capabilities_changed(new_flags: int)

var active_capabilities: int = CreatureCapabilities.NINGUNA


## Recalcula desde cero a partir del ADN. Se llama cada vez que cambian las
## piezas — barato, es solo un OR de ints.
func recalculate_from_dna(dna: CreatureDNA) -> void:
	var flags := CreatureCapabilities.NINGUNA

	if dna:
		for part_info in dna.attached_parts:
			if not part_info or not part_info.has("part_data"):
				continue
			var part: CreaturePartData = part_info["part_data"]
			if part:
				flags |= part.granted_capabilities

	if flags != active_capabilities:
		active_capabilities = flags
		capabilities_changed.emit(flags)
		print("CapabilityController: capacidades activas -> ", CreatureCapabilities.to_names(flags))


## La pregunta que hace el resto del juego.
## Ej: if capability_controller.has_capability(CreatureCapabilities.VOLAR):
func has_capability(capability_flag: int) -> bool:
	return (active_capabilities & capability_flag) != 0


## Lista legible — para UI, depuración o tooltips.
func get_capability_names() -> Array[String]:
	return CreatureCapabilities.to_names(active_capabilities)
