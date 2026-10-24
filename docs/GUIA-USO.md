# GNDeploy: guia rapida

1. Pulse Comenzar. Compruebe Ethernet o elija una red Wi-Fi e introduzca su contrasena. Con una imagen local puede continuar sin Internet.
2. En Windows, seleccione una imagen incluida y pulse Leer imagen; elija la edicion y pulse Usar edicion. Para descargar, el catalogo se carga al entrar en Windows; elija idioma y una fila. La carpeta Cache de la USB se propone automaticamente cuando se reconoce una sola USB GNDeploy con espacio suficiente.
3. En Drivers, elija un pack incluido y pulse Usar pack incluido, o seleccione una carpeta. Despues pulse Validar y usar carpeta para aplicarlo a la seleccion. Confirme que corresponde al modelo y a Windows. Puede continuar sin drivers adicionales.
4. En Autopilot, elija el perfil y pulse Usar perfil seleccionado, o Sin Autopilot. Revise la organizacion. El JSON por si solo no confirma el registro del equipo en la organizacion.
5. En Instalar, elija el disco por modelo y capacidad. Se muestran sus particiones actuales. Pulse Preparar instalacion y revise la lista. Si todo corresponde, marque la casilla y pulse Instalar Windows. Confirme el borrado en el ultimo aviso.

La instalacion elimina todos los archivos y particiones del disco elegido. No se elige automaticamente un destino. Si cambia la imagen, el disco, el perfil o los registros, debe volver a preparar la instalacion.

Al terminar puede guardar un informe y reiniciar. Retire la USB para arrancar desde el disco interno. La primera configuracion de Windows y el registro de Autopilot se verifican despues del reinicio.

## Agregar contenido

- Imagenes: GNDeploy\Images, archivos WIM o ESD.
- Drivers: GNDeploy\Drivers\Offline\NombreDelPack, archivos INF extraidos.
- Autopilot: GNDeploy\Autopilot\Profiles, archivos JSON.
- Herramientas portables: GNDeploy\Tools.

Pulse Herramientas > Actualizar contenido de USB despues de agregar archivos. No se ejecutan automaticamente herramientas nuevas. No extraiga instaladores OEM dentro de la carpeta de Windows ni use un pack de otra version.

## Si algo falla

Lea la accion sugerida, despliegue los detalles y guarde el informe. Una descarga puede reintentarse conservando los bloques completos; al terminar se comprueba su integridad. Un fallo de instalacion requiere revisar los registros antes de volver a borrar el disco.

Windows 7 no admite Autopilot. Para el T420 consulte tambien GUIA-T420-UEFI.md. La descarga automatica de la evaluacion IoT LTSC queda temporalmente bloqueada hasta resolver la discrepancia entre el archivo recibido y el hash esperado; puede importar su propio medio verificado.


## Centro de utilidades

En Herramientas, seleccione una consulta y pulse Consultar:
- Unidades y espacio libre: capacidad, sistema de archivos y espacio disponible.
- Dispositivos con problemas: codigos de error e identificadores de hardware publicados por CIM. Sin resultados no garantiza que todos los dispositivos esten detectados.
- Configuracion de red: IP, puerta de enlace, DNS y DHCP.
- Exportar diagnostico completo: guarda inventario y registros de red en una carpeta nueva del destino elegido.

Verificar SHA-256 calcula la huella de un archivo WIM, ESD, ISO u otro archivo. Si dispone de una huella del proveedor, peguela para comparar. Sin una referencia solo se calcula la huella; esto no acredita el origen ni valida la firma digital. Guardar resultado exporta el texto visible.

Cargar driver INF permite cargar un driver extraido en la sesion actual de WinPE/WinRE, por ejemplo para red o almacenamiento. Confirme el archivo antes de cargarlo. No agrega el driver automaticamente al Windows que se instalara: para eso use Drivers > Validar y usar carpeta. Despues de cargarlo, actualice hardware o vuelva a buscar Wi-Fi. Se bloquea durante operaciones y en modo de pruebas.

Salir permite volver al asistente, reiniciar o apagar; las acciones de energia requieren confirmacion. No cierre herramientas mientras esten copiando archivos.
