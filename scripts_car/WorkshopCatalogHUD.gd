extends CanvasLayer
class_name WorkshopCatalogHUD

## Catálogo mínimo del taller: 3 botones en pantalla que reemplazan al
## selector por teclado (1/2/3) por algo que un jugador de verdad vería y
## podría tocar con el mouse. Sigue siendo un placeholder — la Fase 2
## completa esto crece a categorías/íconos/guardado — pero ya es un primer
## paso real hacia "taller" en vez de atajos escondidos en el teclado.
##
## A propósito NO uso Tab para mostrar/ocultar esto: tu CameraController
## ya usa "press_tab" para el buceo, y pisarlo iba a generar un conflicto
## real (las dos cosas reaccionando a la misma tecla). Por ahora los
## botones quedan siempre visibles; cuando decidamos una tecla/gesto para
## esconderlo, la sumamos sin tocar el resto.

var ensamblador_ui: MechanicalAssemblerUI
var ensamblador: MechanicalAssembler
var bootstrapper: AssemblerBootstrapper


func configurar(ui: MechanicalAssemblerUI, ensamblador_ref: MechanicalAssembler, bootstrapper_ref: AssemblerBootstrapper, motor: MechanicalPartData, engranaje: MechanicalPartData, rueda: MechanicalPartData) -> void:
	ensamblador_ui = ui
	ensamblador = ensamblador_ref
	bootstrapper = bootstrapper_ref
	layer = 10

	var contenedor := HBoxContainer.new()
	contenedor.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	contenedor.position -= Vector2(280, 70)
	contenedor.add_theme_constant_override("separation", 12)
	add_child(contenedor)

	_agregar_boton(contenedor, "Motor", motor)
	_agregar_boton(contenedor, "Engranaje", engranaje)
	_agregar_boton(contenedor, "Rueda", rueda)
	_agregar_boton_accion(contenedor, "Guardar", func(): bootstrapper.guardar_construccion())
	_agregar_boton_accion(contenedor, "Cargar", func(): bootstrapper.cargar_construccion())
	_agregar_boton_accion(contenedor, "Lanzar al mundo", func(): ensamblador.lanzar_al_mundo())


func _agregar_boton(padre: Control, texto: String, datos: MechanicalPartData) -> void:
	var boton := Button.new()
	boton.text = texto
	boton.custom_minimum_size = Vector2(100, 44)
	boton.pressed.connect(func():
		ensamblador_ui.set_selected_part(datos)
		print("WorkshopCatalogHUD: pieza seleccionada -> ", texto, ". Apuntá a un socket libre y hacé clic.")
	)
	padre.add_child(boton)


## Reemplaza a _agregar_boton_lanzar(): ahora genérico para cualquier
## botón de ACCIÓN (no selección de pieza) — Guardar, Cargar y Lanzar al
## mundo comparten esta misma forma, cada uno con su propio callback.
func _agregar_boton_accion(padre: Control, texto: String, accion: Callable) -> void:
	var boton := Button.new()
	boton.text = texto
	boton.custom_minimum_size = Vector2(140, 44)
	boton.pressed.connect(accion)
	padre.add_child(boton)
