# icpc-gpm-uaa-huronos

Configuración e instalación de [huronOS](https://huronos.org) para el equipo de la **Universidad Autónoma de Aguascalientes** en el **Gran Premio de México 2026 – Tercera Fecha**.

- 📅 **Fecha:** 29 de agosto de 2026, 11:00 – 16:00 hrs (CST, UTC-6)
- 🏆 **Juez:** [boca.icpcmexico.org](https://boca.icpcmexico.org)
- 💿 **ISO:** huronOS alpha 0.4 amd64

---

## Contenido del repo

```
icpc-gpm-uaa-huronos/
├── install-huronos.sh          # Script de instalación automatizada
├── icpc-gpm-2026-3rd-date.hdf  # Archivo de directivas para el concurso
├── .gitignore                   # Ignora la ISO (colócala manualmente)
├── AGENTS.md                    # Contexto para IA
└── README.md                    # Este archivo
```

---

## Requisitos

- GNU/Linux (Fedora, Ubuntu, Debian, Arch)
- USB de **16 GiB o más** (se borrará completamente)
- La ISO de huronOS alpha 0.4 colocada en este directorio:

  ```
  huronOS-alpha-0.4-amd64.iso
  ```

  Descárgala desde [mirrors.huronos.org](https://mirrors.huronos.org/huronOS/alpha/huronOS-alpha-0.4-amd64.iso)  
  y **verifica los checksums** antes de instalar:

  | Hash   | Valor |
  |--------|-------|
  | MD5    | `9ad2afe4980965c8b6b92fa00b8813d5` |
  | SHA256 | `b9d530bc7e5b862de9e20c6ce1690ab90f993c6bfa7b44655234708f4e06b2e9` |

  ```bash
  md5sum huronOS-alpha-0.4-amd64.iso
  sha256sum huronOS-alpha-0.4-amd64.iso
  ```

---

## Instalación

```bash
bash install-huronos.sh
```

El script realiza automáticamente:

1. Instala dependencias del sistema
2. Enmascara udisks2 para evitar interferencia del automontador
3. Monta la ISO
4. Ejecuta `install.sh` de huronOS (interactivo — selecciona tu USB)
5. Ejecuta `sync` dos veces para garantizar escritura completa al disco
6. Desmonta y limpia

### Valores para el instalador

| Prompt | Valor |
|--------|-------|
| Root password | *(el que elijas)* |
| Directives URL | `https://gist.github.com/ArielParra/60c5cd5c47fa44228b2429bf09dd38e3/raw/ce9ea83e80d36cd469b2c2e741ccbe089ebeaade/icpc-gpm-2026-3rd-date.hdf` |
| IP of sync server | *(dejar en blanco)* |
| IP / Mask / Gateway | *(dejar en blanco — DHCP)* |
| Target disk | Selecciona tu USB (ej. `/dev/sdb`) |

> ⚠️ **El USB se borrará completamente.** Verifica que seleccionas el disco correcto.

---

## Directivas del concurso

El archivo [`icpc-gpm-2026-3rd-date.hdf`](./icpc-gpm-2026-3rd-date.hdf) configura:

| Modo | Firewall | USB | Software |
|------|----------|-----|----------|
| **Always** (fuera del concurso) | Todo abierto | Permitido | Todos los lenguajes e IDEs |
| **Contest** (11:00–16:00) | Solo BOCA + ICPC Mexico | Bloqueado | Todos los lenguajes e IDEs |

**Bookmarks en el navegador:** BOCA Contest · ICPC Mexico  
**Zona horaria:** America/Mexico_City (UTC-6, CST)  
**Teclado por defecto:** latam

---

## Directivas hosteadas

El archivo de directivas está disponible en GitHub Gist:  
`https://gist.github.com/ArielParra/60c5cd5c47fa44228b2429bf09dd38e3/raw/ce9ea83e80d36cd469b2c2e741ccbe089ebeaade/icpc-gpm-2026-3rd-date.hdf`

---

## Boot

1. Conecta el USB e inicia el equipo
2. Entra al menú de boot (F12 / F2 / Del)
3. **Desactiva Secure Boot** si usas UEFI
4. Selecciona el USB para arrancar
5. huronOS arranca automáticamente al escritorio del concursante
