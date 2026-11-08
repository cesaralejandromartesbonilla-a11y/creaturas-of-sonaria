extends TransmissionPart
class_name GearPart

## Sin lógica propia todavía — hereda todo de TransmissionPart (fuente +
## ratio). Separado en su propio archivo por dos razones: que el Inspector
## lo distinga de Rueda al armar el catálogo de MechanicalPartData, y que
## el día que quieras acercarte más a Screw Drivers (ratio calculado desde
## 'dientes' en vez de puesto a mano) tengas un solo lugar donde tocar sin
## afectar a Rueda.

@export var dientes: int = 12
