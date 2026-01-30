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
- [💾 Backups y Recuperación](#-backups-y-recuperación)
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
sudo apt update && sudo apt install -y age rclone curl git

# Fedora / RHEL
sudo dnf install -y age rclone curl git
```

### 3. Bitwarden CLI (Para Backups)
El script de backup usa el CLI oficial. Requiere Node.js:
```bash
# Instalar BW CLI (Versión 2024.x requerida por compatibilidad)
npm install -g @bitwarden/cli@2024.1.0

# Verificar
bw --version
```

### 4. Solución de Problemas (Troubleshooting)

**Error: `userDecryptionOptions is missing` durante el backup**
Este es un error conocido con las versiones recientes de Bitwarden CLI (>2024.12) al conectar con Vaultwarden.
*   **Solución:** Asegúrate de instalar la versión **2024.1.0** como se indica arriba.
*   Alternativa: Cambia el algoritmo KDF en la web de Vaultwarden (Ajustes -> Seguridad) para regenerar las opciones de cifrado.

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
*   **Usuarios Nuevos:** El script generará una nueva identidad AGE y te ofrecerá crear un `.env` limpio.
*   **Propietarios (Restore):** El script te alertará si falta tu llave maestra. Deberás restaurarla en `~/.age/vaultwarden.key` antes de continuar.

### 3. Configurar Entorno
```bash
# Si eres usuario nuevo, edita el .env generado:
nano .env
```

| Variable | Descripción | Ejemplo |
| :--- | :--- | :--- |
| `BW_HOST` | URL donde estará tu Vault | `https://vault.midominio.com` |
| `BW_PASSWORD` | Password de tu cuenta de Vault | `UnaPassMuyFuerte` |
| `RCLONE_REMOTE` | Destino de rclone | `gdrive:/Backups/Vault` |
| `TELEGRAM_TOKEN` | Token de tu bot | `123456:ABC-DEF...` |

---

## 🌐 Opciones de Despliegue

Elige la que mejor se adapte a tu infraestructura:

| Opción | Nivel | Pros | Contras |
| :--- | :---: | :--- | :--- |
| **Cloudflare Tunnel** | ⭐⭐⭐ | Sin abrir puertos, SSL auto, super seguro. | Requiere dominio propio. |
| **Tailscale** | ⭐⭐ | Red privada VPN, muy fácil. | HTTPS manual/complejo. |
| **Directo / LProxy** | ⭐ | Control total, hosting local. | Debes abrir puertos (80/443). |

### 🔷 Opción A: Cloudflare Tunnel (Recomendada)
1. Ve a [Cloudflare Zero Trust](https://one.dash.cloudflare.com/).
2. Networks -> Tunnels -> Create a Tunnel.
3. Copia el **Tunnel Token** en tu `docker-compose.yml`.
4. Configura el hostname: `vault.tudominio.com` -> `http://vaultwarden:80`.

### 🟣 Opción B: Tailscale (VPN Privada)
Ideal si quieres acceso seguro sin exponer nada a internet público. **Vaultwarden requiere HTTPS**, y Tailscale lo hace fácil.

1.  **Preparar Docker**:
    *   Edita `docker-compose.yml`.
    *   **Descomenta** la sección `ports` para exponer el puerto 8080.
    *   **Comenta o borra** el bloque del servicio `cloudflared` (no lo necesitas).
    *   Reinicia: `./scripts/start.sh`.

2.  **Configurar Tailscale**:
    ```bash
    # Instalar (si no lo tienes)
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale up

    # Habilitar HTTPS y proxy reverso automático (Magic!)
    sudo tailscale cert
    sudo tailscale serve --bg --https=443 localhost:8080
    ```

3.  **Acceso**:
    *   Tu Vault estará disponible en: `https://nombre-maquina.tu-tailnet.ts.net`
    *   Puedes ver la URL exacta con `tailscale status`.

---

## 🔐 Gestión de Secretos (AGE)

Este proyecto no guarda passwords en texto plano. Usamos `.env.age` el cual está cifrado.

### Flujo para Usuarios Nuevos
1. El instalador generará tu identidad en `~/.age/vaultwarden.key`.
2. Crea tu `.env` con tus secretos.
3. **Cifra tus secretos:** `./scripts/manage_secrets.sh encrypt`.
4. Borra el archivo `.env` original (el script te lo ofrecerá).

### Flujo de Trabajo Diario
*   **Editar**: `./scripts/manage_secrets.sh edit` (Abre un editor temporal y re-cifra al salir).
*   **Ver**: `./scripts/manage_secrets.sh view`.
*   **Backup de Clave**: Ejecuta `./scripts/manage_secrets.sh show-key` y guarda el resultado en un gestor externo (Ej: Bitwarden Cloud personal). **SIN ESTA CLAVE NO PODRÁS RECUPERAR TUS BACKUPS NI TU CONFIGURACIÓN.**

---

## 💾 Backups y Recuperación

### El Script de Backup (`backup.sh`)
*   Ejecuta `bw export` de forma aislada.
*   Cifra el JSON resultante con tu clave pública AGE.
*   Sube el archivo a la nube configurada en Rclone.
*   Envía notificación a Telegram.

### Recuperación tras desastre
Si tu servidor muere, sigue estos pasos en uno nuevo:
1. Instala dependencias (`age`, `rclone`).
2. Restaura tu clave privada en `~/.age/vaultwarden.key`.
3. Descarga el backup: `rclone copy gdrive:Backup/Vault/vw_backup_... .`.
4. Descifra: `age -d -i ~/.age/vaultwarden.key -o vault.json vw_backup_...age`.
5. Importa el JSON en tu nueva instancia.

---

## 📜 Referencia de Scripts

| Script | Acción | UX |
| :--- | :--- | :--- |
| `install.sh` | Configuración inicial | Asistente interactivo. |
| `start.sh` | Lanzador seguro | Levanta Docker y borra rastro de secretos. |
| `backup.sh` | Ejecuta backup | Pantalla de estado y logs detallados. |
| `manage_secrets.sh`| Toolset de AGE | Manejo completo de llaves y cifrado. |

---

## 🤝 Contribuciones y Open Source

Este proyecto es 100% Open Source bajo licencia MIT. Si encuentras un bug o tienes una mejora:
1. Haz un **Fork**.
2. Crea una rama `feat/tu-mejora`.
3. Envía un **Pull Request**.

---

## 🛡️ FAQ

**¿Es seguro guardar el backup en Google Drive?**
Sí, el backup se cifra localmente con **AGE** antes de salir del servidor. Ni Google ni nadie sin tu clave privada puede ver el contenido.

**¿Puedo usarlo sin dominio?**
Sí, usa la opción de **Tailscale** o accede por IP local, pero ten en cuenta que las extensiones de navegador suelen requerir HTTPS para funcionar correctamente.

---
<p align="center">Creado con ❤️ por <a href="https://github.com/herwingx">herwingx</a></p>
