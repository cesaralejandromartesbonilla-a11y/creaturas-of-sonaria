extends Resource
class_name CreaturePartData

enum SlotType { PIES, MANOS, EXTENSIONES, CHASIS, TORSOS, CADERAS, CABEZAS, DECORACIONES }

@export var id: String = ""
@export var display_name: String = ""
@export var slot_type: SlotType = SlotType.MANOS
# El puntero a la micro-escena 3D de la pieza
@export var part_scene: PackedScene
@export_group("Estadísticas Aportadas")
@export var weight: float = 0.0
@export var fire_resistance_mod: float = 0.0
@export var speed_mod: float = 0.0

@export_group("Capacidades Otorgadas")
## Etapa 2 — qué PUEDE hacer la criatura por tener esta pieza, no solo cuánto
## pesa. Flags de bits: el orden de estos nombres debe coincidir EXACTO con
## las constantes de CreatureCapabilities (VOLAR=1, AGARRAR=2, ...).
@export_flags("Volar", "Agarrar", "Atacar cuerpo a cuerpo", "Nadar", "Trepar")
var granted_capabilities: int = 0
