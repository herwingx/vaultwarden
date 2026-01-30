# 🚀 Vaultwarden Self-Hosted: La Guía Definitiva

> **Protege tu soberanía digital** — La solución definitiva para auto-hospedar tu gestor de contraseñas con backups automáticos, cifrados y listos para producción.

<p align="center">
  <img src="https://raw.githubusercontent.com/herwingx/vaultwarden-proxmox/main/preview.png" alt="Vaultwarden Preview" width="800" style="border-radius: 10px; box-shadow: 0 10px 30px rgba(0,0,0,0.5);"/>
</p>

[![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![Vaultwarden](https://img.shields.io/badge/Vaultwarden-175DDC?style=for-the-badge&logo=bitwarden&logoColor=white)](https://github.com/dani-garcia/vaultwarden)
[![AGE](https://img.shields.io/badge/AGE_Encryption-2D3748?style=for-the-badge&logo=gnuprivacyguard&logoColor=white)](https://age-encryption.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

---

## 📑 Tabla de Contenidos
- [✨ Características](#-características)
- [💎 Beneficios Premium](#-beneficios-premium)
- [🛠️ Requisitos Previos (Paso a Paso)](#️-requisitos-previos-paso-a-paso)
- [🚀 Instalación Rápida](#-instalación-rápida)
- [🌐 Opciones de Despliegue](#-opciones-de-despliegue)
- [🔐 Gestión de Secretos (AGE)](#-gestión-de-secretos-age)
- [💾 Backups y Recuperación (Híbrido)](#-backups-y-recuperación-híbrido)
- [📜 Referencia de Scripts](#-referencia-de-scripts)

---

## ✨ Características

| Funcionalidad | Descripción |
| :--- | :--- |
| 🐳 **Docker Native** | Despliegue orquestado con Docker Compose. |
| 🔐 **Cifrado Militar** | Secretos y backups protegidos con **AGE** (Identity Files). |
| ☁️ **Multi-Cloud Backup** | Integración con **rclone** (Drive, S3, Dropbox, etc.). |
| 📱 **Notificaciones** | Alertas instantáneas vía Telegram Bot API. |
| ⏰ **Zero-Touch Ops** | Cronjob inteligente para backups sin intervención del usuario. |
| 🌐 **Acceso Universal** | Guías para Cloudflare Tunnel, Tailscale y Proxy Inverso. |

---

## 💎 Beneficios Premium GRATIS

Vaultwarden habilita **todas las funciones premium de Bitwarden** sin costo alguno:

1. 🔐 **TOTP Interno**: Genera códigos de 2FA directamente en la app.
2. 🛡️ **Hardware Security**: Soporte para YubiKey, FIDO2 y WebAuthn.
3. 🏢 **Organizaciones Ilimitadas**: Comparte passwords de forma segura con familia o equipo.
4. 📊 **Reportes de Auditoría**: Detecta leaks de contraseñas y debilidades.
5. 📎 **Adjuntos Cifrados**: Sube documentos directamente a tu bóveda.

---

## 🛠️ Requisitos Previos (Paso a Paso)

Antes de clonar, asegúrate de tener las herramientas base instaladas. Elige tu distribución:

### 1. Docker y Docker Compose
```bash
# Ubuntu / Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Verificar
docker compose version
```

### 2. Herramientas de Cifrado y Backup
```bash
# Ubuntu / Debian
sudo apt update && sudo apt install -y age rclone curl git tar

# Fedora / RHEL
sudo dnf install -y age rclone curl git tar
```

### 3. Bitwarden CLI (Opcional pero Recomendado)
Si deseas que tus backups incluyan un JSON portable compatible con Bitwarden Cloud:
```bash
# Instalar BW CLI (v2024.1.0 recomendada)
npm install -g @bitwarden/cli@2024.1.0

# Verificar
bw --version
```
*Si tienes problemas con `userDecryptionOptions is missing`, usa esta versión específica.*

---

## 🚀 Instalación Rápida

### 1. Clonar el repositorio
Recomendamos usar una ruta estándar como `/opt/vaultwarden`:
```bash
sudo git clone https://github.com/TU_USUARIO/vaultwarden-proxmox.git /opt/vaultwarden
cd /opt/vaultwarden
sudo chown -R $USER:$USER .
```

### 2. Ejecutar Asistente de Configuración
Nuestro script inteligente detectará si eres un usuario nuevo o si estás restaurando un backup:
```bash
chmod +x scripts/*.sh
./scripts/install.sh
```

### 3. Configurar Entorno
```bash
# Si eres usuario nuevo, edita el .env generado:
nano .env
```

| Variable | Descripción | Ejemplo |
| :--- | :--- | :--- |
| `BW_HOST` | URL donde estará tu Vault | `https://vault.midominio.com` |
| `BW_PASSWORD` | Password de tu cuenta de Vault | `UnaPassMuyFuerte` (Para JSON Export) |
| `RCLONE_REMOTE` | Destino de rclone | `gdrive:/Backups/Vault` |
| `TELEGRAM_TOKEN` | Token de tu bot | `123456:ABC-DEF...` |

---

## 🌐 Opciones de Despliegue

### 🔷 Opción A: Cloudflare Tunnel (Recomendada)
1. Ve a [Cloudflare Zero Trust](https://one.dash.cloudflare.com/).
2. Networks -> Tunnels -> Create a Tunnel.
3. Copia el **Tunnel Token** en tu `docker-compose.yml`.
4. Configura el hostname: `vault.tudominio.com` -> `http://vaultwarden:80`.

### 🟣 Opción B: Tailscale (VPN Privada)
1. Descomenta `ports: "8080:80"` en `docker-compose.yml`.
2. Habilita HTTPS mágico: `tailscale serve --bg --https=443 localhost:8080`.

---

## 🔐 Gestión de Secretos (AGE)

Este proyecto no guarda passwords en texto plano. Usamos `.env.age` el cual está cifrado.

*   **Editar Secrets**: `./scripts/manage_secrets.sh edit`
*   **Ver Clave Maestra**: `./scripts/manage_secrets.sh show-key`
    *   ⚠️ **GUARDA ESTA CLAVE**: Sin ella, tus backups son basura digital irrecuperable.

---

## 💾 Backups y Recuperación (Híbrido)

Implementamos una estrategia de **Backup Híbrido** para máxima seguridad y flexibilidad.

### ¿Qué se respalda?
Cada backup genera un archivo cifrado (`.tar.gz.age`) que contiene **DOS** niveles de seguridad:

1.  📀 **System Backup (Copia Fiel)**:
    *   `db.sqlite3`: La base de datos cruda.
    *   `attachments/`: Tus fotos, PDFs y archivos adjuntos.
    *   `config.json`: Configuraciones de tu servidor.
    *   `rsa_key*`: Tus identidad criptográfica.
    *   *Uso:* Restaurar tu servidor exactamente como estaba.

2.  📄 **JSON Export (Portabilidad)**:
    *   `vault_export.json`: Un archivo estándar de Bitwarden.
    *   *Uso:* Importar tus contraseñas en Bitwarden Cloud u otro gestor si decides migrar.

### Cómo Restaurar (Script Guiado)

Hemos creado un script que automatiza todo el proceso de recuperación de desastres:

```bash
# 1. Trae tu archivo de backup (ej. desde Google Drive con rclone)
rclone copy gdrive:Backup/Vault/vw_backup_timestamp.tar.gz.age .

# 2. Ejecuta el restaurador
./scripts/restore.sh vw_backup_timestamp.tar.gz.age
```

**El script hará lo siguiente:**
1.  Descifrará el archivo usando tu clave AGE.
2.  Detendrá el contenedor de forma segura.
3.  **Hará un backup de tu carpeta `data` actual** (por si algo sale mal).
4.  Reemplazará la base de datos y adjuntos.
5.  Reiniciará el servidor.

### ¿Cómo usar el JSON Portable?
Si tu objetivo no es restaurar este servidor, sino **extraer tus datos** para irte a otro lado:

1.  Descifra el backup manualmente:
    ```bash
    age -d -i ~/.age/vaultwarden.key -o backup.tar.gz backup.tar.gz.age
    ```
2.  Descomprime:
    ```bash
    tar -xzf backup.tar.gz
    ```
3.  Encontrarás el archivo `vault_export.json`. Este archivo se puede importar en la web de Bitwarden (Herramientas -> Importar).
    *   ⚠️ **Advertencia:** Este JSON **NO** contiene tus archivos adjuntos ni configuraciones de servidor.

---

## 📜 Referencia de Scripts

| Script | Acción | UX |
| :--- | :--- | :--- |
| `install.sh` | Configuración inicial | Asistente interactivo. |
| `start.sh` | Lanzador seguro | Levanta Docker y borra rastro de secretos. |
| `backup.sh` | Backup Híbrido | Genera SQLite + JSON, cifra y sube a nube. |
| `restore.sh` | Restauración | Recuperación guiada y segura desde backup. |
| `manage_secrets.sh`| Toolset de AGE | Manejo completo de llaves y cifrado. |

---

## 🤝 Contribuciones y Open Source

Este proyecto es 100% Open Source bajo licencia MIT.

---
<p align="center">Creado con ❤️ por <a href="https://github.com/herwingx">herwingx</a></p>
