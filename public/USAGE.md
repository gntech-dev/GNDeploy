# Instalacion, construccion y contribuciones

## Requisitos

Windows x64 y Windows PowerShell 5.1. La GUI usa Windows Forms y un proceso STA. La construccion de medios requiere administrador, ADK Deployment Tools y WinPE Add-on. WinRE para Wi-Fi lo aporta el operador; debe coincidir con la familia de build del ADK.

## Entorno limpio y funcionamiento offline

Descargue el ZIP de modulo, SHA256SUMS.txt e Install-GNDeploy.ps1 desde una release. Conserve el hash. Use el modo `-PackagePath` y `-ExpectedSha256` para instalar sin red. El paquete contiene codigo y catalogos; no incluye Windows ni drivers.

```powershell
$install = & .\Install-GNDeploy.ps1 -PackagePath .\GNDeploy-0.2.0.zip -ExpectedSha256 '<hash publicado>'
Import-Module $install.ModulePath
$workspace = New-GNDeployWorkspace -Path C:\GNDeploy
Get-Command -Module GNDeploy
Start-GNDeploy -Preview
```

Para abrir el asistente real dentro de WinPE/WinRE, use `Start-GNDeploy` sin Preview. La importacion del modulo no inicia una instalacion ni selecciona disco.

## Crear USB

Obtenga primero numero, serie y tamano exacto de la USB:

```powershell
Get-Disk | Where-Object BusType -eq USB | Format-Table Number,FriendlyName,SerialNumber,Size
# Sustituya cada valor por la identidad comprobada de SU USB:
New-GNDeployUSB -DiskNumber 2 -ExpectedSerial 'SERIE-DE-SU-USB' -ExpectedSize 64000000000 -ISO C:\Medios\GNDeploy.iso -WhatIf
```

Revise el plan y repita sin `-WhatIf` solo para crear la USB. El creador conserva la comprobacion de identidad y solicita confirmacion de la operacion destructiva. No hay una serie de USB predeterminada. El modo de arranque predeterminado es UEFI; `Dual` es una opcion de creacion de medio y no garantiza soporte de cada Windows en BIOS.

## Construir imagenes y extraer WinRE

```powershell
Export-GNDeployWinRE -ImagePath C:\Images\install.wim -Index 1 -Root C:\GNDeploy
New-GNDeployWindowsImage -RecipePath .\config\recipe.example.json -Root C:\GNDeploy
```

La receta de ejemplo debe adaptarse a su imagen. Los paquetes requieren hashes y los drivers deben estar extraidos. Esta funcion de mantenimiento no afirma validacion completa de cada receta.

## Publicacion y CI

El repositorio contiene una seleccion explicita de fuentes. No deben agregarse logs del laboratorio, perfiles reales, secretos, imagenes Windows ni binarios de terceros. Build-Distribution genera una carpeta Repository publicable y un ZIP instalable a partir de una lista permitida.

CI ejecuta las pruebas en Windows PowerShell 5.1 y genera artefactos. Un tag `v0.2.0` debe coincidir con ModuleVersion 0.2.0. El workflow de release crea una prerelease publica con ZIP, checksums e instalador; no publica ISO ni ejecuta pruebas destructivas.

Para proponer cambios, abra un issue o pull request con el problema, comportamiento esperado y comprobaciones realizadas. No adjunte contrasenas, perfiles reales ni identificadores privados del tenant. El codigo aportado se distribuye bajo GPL-3.0-only.
