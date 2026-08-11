# Terry the Egg — vertical slice

Prototipo 2D para Godot 4.x escrito en GDScript. Utiliza una pantalla lógica de 320 × 288, escalado entero y una interfaz inspirada en mascotas virtuales clásicas. No usa entrada de texto libre, cámara, micrófono ni red.

## Ejecutar

1. Abre `project.godot` con Godot 4.x.
2. Pulsa **F5** para ejecutar el proyecto.
3. Pruebas automatizadas:

   `godot --headless --path . --script tests/test_runner.gd`

La escena principal es `res://scenes/main/main.tscn`.

## Controles

- Mantener el botón izquierdo y moverlo de lado a lado sobre un huevo: acariciar el cascarón.
- Mantener el botón izquierdo y recorrer una distancia corta sobre una criatura: acariciarla.
- **Comer**: néctar durante la incubación y cuenco después del nacimiento.
- **Jugar**: deja a la criatura entretenida durante una hora real; al terminar tendrá hambre.
- **Siesta**: deja a la criatura dormida durante una hora real.
- **Mirar**: muestra su estado, actividad actual y preferencia de cuidado sin revelar contadores internos.
- **Aseo**: selecciona una suciedad concreta.
- Burbuja con el retrato de Terry: conversación pendiente; el mismo retrato aparece en el cursor.
- Clic derecho: cancelar herramienta.

Terry necesita una caricia válida antes de dormir. El juego está pensado para permanecer abierto mientras se trabaja o estudia: las criaturas avisan cuando necesitan algo y conceden treinta minutos para responder.

## Flujo narrativo

La incubación combina dos tandas de néctar y cuatro tandas de mimos. Las grietas del 25 %, 50 % y 75 % están integradas en sprites completos del huevo.

Tras el nacimiento conviven Pipo, Mota y Terry. La primera petición aparece quince minutos después y, a partir de ahí, los ciclos ordinarios se separan aproximadamente una hora. Pipo prefiere comer y dormir; Mota pide jugar con mucha más frecuencia; Terry busca principalmente compañía. Después de cuatro cuidados favoritos y una jornada de ocho horas, Pipo adopta su aspecto más redondito.

El primer aviso desatendido hace que Terry hable por primera vez. A partir de ahí mantiene cinco conversaciones breves de apego: recuerda respuestas anteriores y, en la tercera, repite literalmente por qué dijo el jugador que volvería. El segundo descuido narrativo solo cuenta después de completar esta cadena y al menos otro ciclo de cuidado.

Pipo nunca desaparece delante del jugador. El cambio queda preparado hasta que la aplicación pierde el foco o la partida se abre de nuevo. Al regresar, Pipo ya no está, Mota y Terry aparecen dormidos y no aceptan acciones. Tras unos segundos Terry abre los ojos, muestra su retrato de conversación y comienza «Se fue» cuando el jugador decide hablarle. El hueco de Pipo puede inspeccionarse y conserva una marca fría donde dormía.

Las siguientes conversaciones aparecen cada dos ciclos de cuidado satisfactorios; no pueden acelerarse repitiendo siestas o pulsando una acción sin que haya una necesidad real.

Durante la siguiente etapa Terry pregunta por compartir, por echar de menos y finalmente: «¿Me querrías si hiciese una cosa mala?». Más tarde pregunta qué existe al otro lado de la pantalla. **Enseñarle tu lado** responde a esa pregunta y funciona como punto medio, no como desenlace.

Tras tres charlas adicionales desaparece Mota. Terry recuerda la respuesta del jugador, pide comida por encima del límite habitual y termina preguntando qué come el jugador y si puede abrirle.

## Datos

- `data/creatures/creatures.json`: personalidad, color y reglas de cada criatura.
- `data/phases/phases.json`: nueve fases narrativas y sus requisitos.
- `data/dialogues/dialogues.json`: charlas recurrentes y conversaciones principales.
- `data/requirements/post_dialogue.json`: versión documental de los requisitos posteriores a Pipo.
- `data/actions/actions.json`: etiquetas y símbolos de las acciones.

## Assets

- `assets/eggs/egg-stage-sprites.png`: cinco estados completos para cada huevo.
- `assets/creatures/creature-sprites.png`: poses principales.
- `assets/creatures/creature-reactions.png`: sueño y negativa.
- `assets/creatures/pipo-chubby.png`: evolución corporal de Pipo al final de la primera jornada.
- `assets/ui/action-icons.png`: iconos normalizados del HUD sin contaminación entre celdas.
- `assets/ui/reaction-symbols.png`: única hoja activa de expresiones.
- `assets/ui/tool-cursors.png`: cursores artísticos.
- `assets/ui/terry-talk.png`: retrato transparente usado para avisos y cursor de conversación.

Los arcos y líneas rojas del sistema visual anterior han sido retirados. Las reacciones de agradecimiento usan siempre el corazón.

## Guardado y revisión

La partida se guarda en `user://terry_the_egg_save.json`, incluyendo peticiones, límites de atención, bloques de juego o sueño, evolución corporal, respuestas, conversaciones pendientes, desapariciones y desenlace.

La versión para jugadores no incluye navegador narrativo, selector de hitos ni panel técnico. Todo el recorrido debe desbloquearse jugando y cuidando a las criaturas.
