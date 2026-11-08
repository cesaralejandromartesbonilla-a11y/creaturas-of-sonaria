extends Resource
class_name BuildData

## Snapshot serializable de qué pieza fue a qué socket — lo que cruza del
## taller al mundo. Deliberadamente simple mientras el catálogo sea
## motor/engranaje/rueda; si más adelante hay más tipos o varias piezas
## del mismo tipo (ver la nota pendiente de Fase 3), esto va a necesitar
## crecer — hoy alcanza con esto, igual que CreatureDNA.attached_parts
## alcanzaba con una lista simple antes de que el proyecto de criaturas
## creciera a 20 módulos.

@export var socket_a_tipo: Dictionary = {}  # String (socket_name) -> MechanicalPartData.PartType
