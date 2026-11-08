class_name CreatureCapabilities

## Etapa 2 — vocabulario de capacidades.
##
## Son flags de bits (no un enum secuencial) para que una pieza pueda otorgar
## varias a la vez con un solo int, y para que Godot las muestre como
## casillas en el Inspector vía @export_flags.
##
## IMPORTANTE: los valores existentes nunca se renumeran — cualquier
## CreaturePartData ya guardado en disco quedaría con capacidades
## equivocadas. Para agregar una nueva, seguir duplicando: 32, 64, 128...
##
## El orden acá debe coincidir EXACTO con el string de @export_flags en
## CreaturePartData.granted_capabilities.

const NINGUNA := 0
const VOLAR := 1
const AGARRAR := 2
const ATACAR_CUERPO_A_CUERPO := 4
const NADAR := 8
const TREPAR := 16

## Para mostrar en UI/depuración — orden alineado con los bits de arriba.
const NOMBRES := {
	VOLAR: "Volar",
	AGARRAR: "Agarrar",
	ATACAR_CUERPO_A_CUERPO: "Atacar cuerpo a cuerpo",
	NADAR: "Nadar",
	TREPAR: "Trepar",
}


## Convierte un int de flags en una lista legible de nombres.
static func to_names(flags: int) -> Array[String]:
	var names: Array[String] = []
	for flag in NOMBRES:
		if flags & flag:
			names.append(NOMBRES[flag])
	return names
