# icpc-gpm-uaa-huronos

Instalación, configuración y soluciones de compatibilidad de [huronOS](https://huronos.org) para los equipos de la **Universidad Autónoma de Aguascalientes (UAA)** en el **ICPC Gran Premio de México**.

- 🏆 **Juez del concurso:** [MOJ](https://moj.naquadah.com.br) | [Ensaio](https://ensaio-times-2026.moj.naquadah.com.br/) | [Guía del competidor](https://moj.naquadah.com.br/contest/ajuda/competidor.html?lang=en)
- 💿 **ISO Base:** `huronOS-alpha-0.4-amd64.iso` (Debian 11 / Kernel Linux 6.0.15)
- 🏢 **Sede:** Laboratorios de Cómputo, Universidad Autónoma de Aguascalientes

---

## Estructura del Repositorio y Scripts Numerados

Los scripts están organizados y numerados cronológicamente según su orden de ejecución:

```text
icpc-gpm-uaa-huronos/
├── 01-install-huronos.sh               # [Paso 1] Instalación base en USB (incluye pasos 2 y 3 automáticamente)
├── 02-inject-custom-layer.sh           # [Paso 2] Inyección en 05-custom.hsl (Wallpaper, Driver fbdev, Mesa & CPH)
├── 02b-inject-vscode-extensions.sh     # [Auxiliar] Inyector independiente de extensiones VS Code (CPH & C++)
├── 03-configure-nvidia-boot.sh         # [Paso 3] Ajuste de bootloader para hardware 2024 y GPUs NVIDIA
├── 04-update-directives-wallpaper.sh   # [Utilidad] Calcula SHA256 de fondos y actualiza archivos .hdf
├── 05-test-huronos-vm.sh               # [Pruebas] Creación y prueba local en Máquina Virtual KVM / virt-manager
├── competitive-programming-helper-*.vsix # Paquete de extensión CPH para VS Code
├── huronos-wallpaper.png               # Wallpaper oficial personalizado para el concurso (1920×1080)
├── *.hdf                               # Archivos de directivas por concurso
├── .gitignore                          # Ignora ISOs, imágenes VM y archivos binarios vsix
├── AGENTS.md                           # Contexto técnico para asistentes IA
└── README.md                           # Documentación técnica completa
```

### Directivas de concurso

| Archivo | Concurso | Fecha y Horario | URL Directivas |
| --- | --- | --- | --- |
| [`icpc-gpm-2026-3rd-date.hdf`](./icpc-gpm-2026-3rd-date.hdf) | Gran Premio de México 2026 – 3ra Fecha | 29 Ago 2026, 11:00–16:00 CST | [GitHub Raw](https://raw.githubusercontent.com/CPC-GALLOS/icpc-gpm-uaa-huronos/main/icpc-gpm-2026-3rd-date.hdf) |

---

## Crónica Técnica: Hardware UAA 2024 vs huronOS 2022 (Kernel 6.0)

### El Contexto y Desafío
huronOS alpha 0.4 es una distribución en vivo basada en Debian 11 (Bullseye) con Linux Kernel **6.0.15**, empaquetada originalmente entre 2022 y 2023. Actualmente es un proyecto que **no cuenta con mantenedores activos ni desarrollo upstream continuo**.

Para el ciclo de competencias 2024–2026, los laboratorios de cómputo de la **Universidad Autónoma de Aguascalientes (UAA)** fueron renovados con computadoras Dell de última generación (procesadores **Intel Core 14th Gen / Arrow Lake** con gráficos integrados `8086:7d67` y/o tarjetas gráficas dedicadas **NVIDIA GeForce RTX serie Ada Lovelace**).

### El Problema Técnico Encontrado
1. **Falta de Drivers KMS:** El kernel 6.0.15 de huronOS carece de controladores *Kernel Mode Setting* (KMS) para hardware 2024 (el soporte para Intel Arrow Lake y GPUs NVIDIA modernas requiere kernels Linux >= 6.8 o el driver `xe`).
2. **Pantalla Negra en Arranque Estándar:** Al arrancar huronOS de forma predeterminada, el sistema intentaba inicializar controladores KMS inexistentes o incompatibles, resultando en congelamiento con pantalla negra tras el menú de arranque.
3. **Fallo de Xorg con `nomodeset`:** Al intentar la solución típica de arrancar con `nomodeset`, el servidor Xorg de huronOS (configurado con el driver estándar `modesetting`) colapsaba al no encontrar ningún dispositivo DRM/KMS funcional, impidiendo que el entorno gráfico Budgie Desktop iniciara.

### La Solución de Ingeniería Implementada
Para garantizar que huronOS funcione de manera 100% confiable y sin modificar el kernel base, se diseñó una solución en capas:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                   Escritorio Budgie / Codium / Apps                      │
└──────────────────────────────────────────────────────────────────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 │  Mesa LLVMpipe (Software Rendering)  │ (LIBGL_ALWAYS_SOFTWARE=1)
                 └───────────────────┬───────────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 │       Xorg fbdev Driver (/dev/fb0)    │ (xserver-xorg-video-fbdev)
                 └───────────────────┬───────────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 │       EFI Firmware Framebuffer        │ (efifb / VESA BIOS)
                 └───────────────────┬───────────────────┘
                                     │
┌──────────────────────────────────────────────────────────────────────────┐
│ Parámetros Kernel: modprobe.blacklist=i915,nouveau fbcon=nodefer        │
└──────────────────────────────────────────────────────────────────────────┘
```

1. **Driver `xserver-xorg-video-fbdev` en `05-custom.hsl`:**
   - Se extrajo el driver oficial de Debian `xserver-xorg-video-fbdev` y se inyectó en la capa personalizada `/usr/lib/xorg/modules/drivers/fbdev_drv.so`.
   - Se configuró `/etc/X11/xorg.conf.d/99-display.conf` para dirigir el servidor Xorg directamente al framebuffer del firmware UEFI (`/dev/fb0`).
2. **Aceleración por Software con Mesa LLVMpipe:**
   - Dado que el framebuffer EFI no provee aceleración 3D por hardware, se configuraron `/etc/X11/Xsession.d/99-huronos-software-rendering` con `LIBGL_ALWAYS_SOFTWARE=1` y `GALLIUM_DRIVER=llvmpipe`.
   - Esto permite que el entorno Budgie, Chromium y VS Code se rendericen a través de la CPU a 60 FPS estables.
3. **Ajuste de Parámetros del Kernel en Bootloader:**
   - Se descartó `nomodeset` para el modo gráfico (ya que bloquea la asignación del framebuffer) y se implementó `modprobe.blacklist=i915,nouveau fbcon=nodefer`.
   - Se removió el parámetro obsoleto `vga=normal`.
4. **Corrección de Menú Syslinux EFI de 64 bits:**
   - Se sustituyeron las dependencias de menú de 32 bits por el módulo nativo `/EFI/Boot/menu.c32` de 64 bits en `/EFI/Boot/syslinux.cfg`, eliminando bloqueos de memoria en firmwares UEFI modernos.

---

## Requisitos Previos

- Sistema Operativo: GNU/Linux (Fedora, Debian, Ubuntu, Arch Linux).
- Memoria USB de **16 GiB o superior** (será formateada por completo).
- La imagen ISO `huronOS-alpha-0.4-amd64.iso` en la raíz de este repositorio.

### Verificación de Checksums de la ISO

```bash
# MD5:    9ad2afe4980965c8b6b92fa00b8813d5
# SHA256: b9d530bc7e5b862de9e20c6ce1690ab90f993c6bfa7b44655234708f4e06b2e9
md5sum huronOS-alpha-0.4-amd64.iso
sha256sum huronOS-alpha-0.4-amd64.iso
```

### Instalación de Dependencias

```bash
# Debian / Ubuntu:
sudo apt install squashfs-tools parted psmisc e2fsprogs dosfstools perl-base

# Fedora:
sudo dnf install squashfs-tools parted psmisc e2fsprogs dosfstools perl

# Arch Linux:
sudo pacman -S squashfs-tools parted psmisc e2fsprogs dosfstools perl
```

---

## Guía de Instalación Paso a Paso

### Opción A: Instalación Automatizada Completa en USB

El script `01-install-huronos.sh` ejecuta la instalación base y encadena automáticamente los pasos 2 y 3 (inyección de extensiones, wallpaper y fixes de GPU):

```bash
bash 01-install-huronos.sh
```

El script solicitará:
1. **Contraseña de root:** *(Elige una o presiona Enter para usar `toor`)*
2. **URL de Directivas:** URL raw de GitHub del archivo `.hdf` correspondiente.
3. **IP del Servidor:** *(Dejar en blanco para DHCP)*
4. **Disco de destino:** Seleccionar la memoria USB correcta (ej. `/dev/sdb`).

---

### Opción B: Ejecución Manual o Personalización Modular

Si deseas aplicar cambios paso a paso en una memoria USB existente o partición montada:

#### Paso 1: Instalación Base
```bash
bash 01-install-huronos.sh
```

#### Paso 2: Inyección de Capa Personalizada (Wallpaper + Driver fbdev + VS Code Extensions)
```bash
# Auto-detecta partición con etiqueta HURONOS:
sudo bash 02-inject-custom-layer.sh

# O especificando partición y wallpaper:
sudo bash 02-inject-custom-layer.sh /dev/sdX1 huronos-wallpaper.png
```

#### Paso 2b: Inyección Específica de Extensiones de VS Code
```bash
sudo bash 02b-inject-vscode-extensions.sh /dev/sdX1
```

#### Paso 3: Configuración de Bootloader (Fixes UAA 2024 / NVIDIA)
```bash
sudo bash 03-configure-nvidia-boot.sh /dev/sdX1
```

#### Paso 4: Actualización de Hash de Wallpaper en Directivas `.hdf`
```bash
./04-update-directives-wallpaper.sh huronos-wallpaper.png icpc-gpm-2026-3rd-date.hdf
```

#### Paso 5: Pruebas en Máquina Virtual Local (KVM / virt-manager)
```bash
bash 05-test-huronos-vm.sh
```

---

## Extensiones de Visual Studio Code (C/C++, CPH, Python & Java)

Para optimizar el flujo de trabajo de los competidores durante el ICPC, huronOS incluye y activa las siguientes extensiones:

| Extensión | Identificador / Módulo | Funcionalidad |
| --- | --- | --- |
| **C/C++ Tools** (`ms-vscode.cpptools`) | `programming/vsc-cpptools` | Autocompletado IntelliSense, navegación de código, resaltado de sintaxis y formateo con `clang-format`. |
| **Competitive Programming Helper** (`DivyanshuAgrawal.competitive-programming-helper`) | `programming/vsc-cph` | Gestión de casos de prueba, ejecución rápida de soluciones, vista de diferencias (diff) y soporte multilingüe (C++, Java, Python, Kotlin). |
| **Microsoft Python** (`ms-python.python`) | `programming/vsc-python` | Soporte de autocompletado, linting y ejecución de scripts en Python 3 para desarrollo competitivo. |
| **Language Support for Java™ by Red Hat** (`redhat.java`) | `programming/vsc-java` | Soporte completo de lenguaje Java (Java 17/21), navegación y resolución de tipos para ICPC. |

### Integración en huronOS
1. **Directivas:** Se agregan `programming/vsc-cpptools`, `programming/vsc-cph`, `programming/vsc-python` y `programming/vsc-java` a `AvailableSoftware` en `icpc-gpm-2026-3rd-date.hdf`.
2. **Capa `05-custom.hsl`:** Todas las extensiones se pre-inyectan en `/opt/codium/contestant/extensions/` junto con sus descriptores en `ids/vsc-*.json`.
3. **Módulos HSM:** Se generan los módulos `vsc-cph.hsm`, `vsc-python.hsm` y `vsc-java.hsm` en `huronOS/software/programming/`.
4. **Carga Dinámica:** El lanzador `/usr/bin/codium` compila automáticamente `/opt/codium/contestant/extensions/extensions.json` combinando todos los descriptores en cada sesión.

---

## Instrucciones de Arranque en Máquinas de Concurso

1. Conecta la memoria USB en la computadora del laboratorio.
2. Si el equipo cuenta **únicamente con tarjeta NVIDIA dedicada**, conecta el monitor al puerto de la tarjeta gráfica (no a la tarjeta madre).
3. Enciende el equipo y presiona la tecla del menú de arranque (**F12** en Dell, **F11** en HP, **F8/Del** en Asus).
4. **Desactiva Secure Boot** en la configuración UEFI si está habilitado.
5. Selecciona la memoria USB para iniciar.
6. huronOS arrancará automáticamente en el escritorio del competidor tras 7 segundos.

---

## Pruebas de Desarrollo y Calidad (ShellCheck)

De acuerdo con las directrices de calidad del repositorio, todos los scripts deben verificarse con `shellcheck`:

```bash
shellcheck 01-install-huronos.sh 02-inject-custom-layer.sh 02b-inject-vscode-extensions.sh 03-configure-nvidia-boot.sh 04-update-directives-wallpaper.sh 05-test-huronos-vm.sh
```
*Garantía de calidad: 0 errores y 0 advertencias.*
