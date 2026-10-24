# ThinkPad T420: Windows 7 x64 mediante UEFI

1. Enciende el T420 y entra en ThinkPad Setup con **F1**.
2. En **Startup > UEFI/Legacy Boot**, selecciona **UEFI Only** y guarda con **F10**.
3. Arranca la Kingston mediante **F12**.
4. En GNDeploy, abre **Windows**, selecciona `Windows-7-SP1-x64.wim`, pulsa **Leer imagen**, elige la edición y pulsa **Usar edición**.
5. En **Drivers**, puedes seleccionar el pack incluido `Lenovo-T420-Win7-x64-Network`. Pulsa **Validar y usar carpeta** antes de continuar. Contiene Ethernet Intel 82579LM y Wi-Fi Intel compatible con los dispositivos indicados en los README de Lenovo; no es un pack completo de chipset, gráficos y periféricos.
6. En **Autopilot**, deja **Sin Autopilot**: Windows 7 no lo admite.
7. En **Instalar**, selecciona el disco interno y revisa el plan. Debe indicar **UEFI**. La instalación borra el disco seleccionado y crea particiones GPT.
8. Pulsa **Preparar instalacion**, revisa el modelo y la capacidad, marca la casilla de borrado y pulsa **Instalar Windows en el disco seleccionado**. Confirma el borrado en el aviso final. Cuando termine, retira la USB y arranca desde el disco interno o Windows Boot Manager.

Windows 7 requiere Secure Boot desactivado si el firmware dispone de esa función. GNDeploy no modifica las opciones de firmware.

Se comprobaron el particionado GPT, la aplicación de la imagen y los archivos EFI/BCD. El arranque final UEFI en el T420 está pendiente de prueba física. Hyper-V Gen2 no es un destino admitido para Windows 7; la prueba BIOS anterior llegó al asistente inicial en Hyper-V Gen1.

La USB incluye Explorer++, 7-Zip, editor de texto y vista de procesos. Puedes agregar ejecutables portables x64 en `GNDeploy\Tools` y pulsar **Actualizar lista**.

Puedes agregar imágenes WIM/ESD en `GNDeploy\Images`, drivers extraídos en `GNDeploy\Drivers\Offline` y perfiles JSON para Windows compatible en `GNDeploy\Autopilot\Profiles`.

Referencia: [Lenovo BIOS/UEFI Deployment Guide](https://docs.lenovocdrt.com/ref/bios/bios_guide/).


