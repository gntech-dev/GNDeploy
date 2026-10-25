# GNDeploy

Modulo PowerShell independiente para preparar medios WinPE/WinRE y desplegar Windows con interfaz grafica, red, drivers OEM y perfiles Autopilot JSON. Licencia **GPL-3.0-only**.

**Estado experimental.** La interfaz de referencia r12 paso 29 comprobaciones en Hyper-V sin instalar Windows. Wi-Fi/trackpad fisicos en X1 Nano, Proxmox y Windows 7 UEFI en T420 requieren validacion. El empaquetado del modulo tiene pruebas independientes; no convierte esas pruebas en una instalacion completa.

## Descargar e instalar

En Windows PowerShell 5.1 x64, descargue `Install-GNDeploy.ps1` de una release de este repositorio, revise el archivo y ejecutelo:

```powershell
$install = & .\Install-GNDeploy.ps1 -Repository gntech-dev/GNDeploy -Tag v0.2.1
Import-Module $install.ModulePath
Get-GNDeployVersion
Start-GNDeploy -Preview
```

El instalador usa `%LOCALAPPDATA%\GNDeploy\Modules`, verifica SHA-256 y conserva versiones separadas. No escribe en OneDrive, no modifica el perfil PowerShell y no instala ADK automaticamente. En otra sesion importe el `ModulePath` que devolvio la instalacion.

Tambien puede instalar un ZIP descargado manualmente usando su hash publicado:

```powershell
$install = & .\Install-GNDeploy.ps1 -PackagePath .\GNDeploy-0.2.1.zip -ExpectedSha256 '<SHA256 de SHA256SUMS.txt>'
Import-Module $install.ModulePath
```

Un checksum publicado junto al ZIP detecta corrupcion; no sustituye una firma digital independiente. No se recomienda ejecutar contenido remoto directamente con `Invoke-Expression`.

## Crear un medio

```powershell
New-GNDeployWorkspace
# En Windows PowerShell como administrador:
Install-GNDeployDependency
New-GNDeployISO -Base WinPE
# Para WLAN, aporte un winre.wim compatible con el build del ADK:
New-GNDeployISO -Base WinRE -WinREPath C:\Sources\winre.wim
```

La ISO se construye en el equipo del operador. Este proyecto no redistribuye imagenes de Windows, ADK, fuentes de Windows ni paquetes OEM. Agregue sus medios, drivers y perfiles localmente. La construccion WinRE necesita una fuente de la misma familia de build que el ADK.

## Comandos principales

- `Start-GNDeploy`: interfaz; `-Preview` en Windows completo, despliegue real solo en WinPE/WinRE.
- `New-GNDeployWorkspace`: carpetas y catalogos locales.
- `Install-GNDeployDependency`: instalacion firmada de ADK/WinPE, requiere administrador.
- `New-GNDeployISO`: construccion local del arranque.
- `New-GNDeployUSB`: USB identificada por numero, serie y capacidad; admite `-WhatIf`.
- `Export-GNDeployWinRE`: extraer WinRE de un medio propio.
- `New-GNDeployWindowsImage`: mantenimiento offline con receta JSON; requiere validacion del resultado.
- `Get-GNWindowsCatalog`, `Get-GNOemDriverPack`, `Get-GNHardwareStatus`, `Test-GNFileIntegrity`: motor y diagnostico.

La instalacion de Windows borra el disco elegido tras revisar y confirmar. Un perfil Autopilot JSON no registra ni asigna por si solo el equipo en el tenant.

Documentacion: [Instalacion y desarrollo](docs/USAGE.md), [Guia de uso](docs/GUIA-USO.md), [Windows 7 UEFI](docs/T420-UEFI.md), [Historial](CHANGELOG.md).

## Desarrollo

```powershell
Get-ChildItem .\tests\Test-*.ps1 | ForEach-Object { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName; if ($LASTEXITCODE) { throw $_.Name } }
.\scripts\Build-Distribution.ps1 -OutputRoot C:\GNDeploy-Releases\0.2.1
```

Las releases distribuyen el modulo ZIP y `SHA256SUMS.txt`. Las pruebas CI no instalan Windows ni modifican discos fisicos. No hay publicacion en PowerShell Gallery todavia: `Install-Module GNDeploy` no se presenta como un metodo disponible.

