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
- [💾 Backups y Recuperación](#-backups-y-recuperación-híbrido)
    - [Estrategia Híbrida](#qué-se-respalda)
    - [🚨 Recuperación Total (Disaster Recovery)](#-recuperación-ante-desastre-servidor-nuevo)
    - [� Migración Rápida a Bitwarden](#cómo-usar-el-json-portable)
- [�📜 Referencia de Scripts](#-referencia-de-scripts)

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

### 🛡️ Medidas de Seguridad Automáticas
*   **Registros Cerrados por Defecto**: La variable `SIGNUPS_ALLOWED` está definida en `false` en el código. Esto evita que extraños se registren en tu servidor si encuentran tu URL.
*   **Gestión Temporal de Registros**:
    *   **Abrir (Para invitar)**: Pasa la variable al iniciar: `SIGNUPS_ALLOWED=true ./scripts/start.sh`.
    *   **Cerrar (Post-Registro)**: Simplemente reinicia el servidor normalmente:
        ```bash
        ./scripts/start.sh
        ```
        *Al no pasar la variable, volverá a su valor seguro (false), bloqueando nuevos registros inmediatamente.*

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
sudo apt update && sudo apt install -y age rclone curl git tar sqlite3

# Fedora / RHEL
sudo dnf install -y age rclone curl git tar sqlite3
```
*Tip: `sqlite3` es recomendado para realizar backups en caliente sin detener el servidor.*

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
> **⚠️ Importante (Restauración):** Si estás reinstalando o migrando servidor, debes restaurar tu identidad **ANTES** de ejecutar el instalador para evitar conflictos.
> ```bash
> mkdir -p ~/.age
> nano ~/.age/vaultwarden.key  # Pega tu clave privada original
> chmod 600 ~/.age/vaultwarden.key
> ```

### 3. Configurar Entorno Base
Edita el archivo `.env` generado con tus secretos básicos (aún no definas la URL si usarás Tailscale):
```bash
nano .env
```
| Variable | Descripción |
| :--- | :--- |
| `RCLONE_REMOTE` | Destino de rclone (Opcional por ahora) |
| `BW_PASSWORD` | Tu futura Master Password (para el backup JSON) |

---

## 🌐 4. Elegir Método de Despliegue

### 🔷 Opción A: Cloudflare Tunnel (Dominio Público)
1. Crea el túnel en Cloudflare Zero Trust y obtén el token.
2. En `.env`, define: `BW_HOST=https://tu-dominio.com` y `TUNNEL_TOKEN=...`.
3. Inicia (Habilitando registros para crear tu cuenta):
   ```bash
   SIGNUPS_ALLOWED=true ./scripts/start.sh
   ```
   ```
4. **Cerrar Registros**:
   Una vez creada tu cuenta, reinicia normal para bloquear intrusos:
   ```bash
   ./scripts/start.sh
   ```
### 🟣 Opción B: Tailscale (Red Privada)
1. Edita `docker-compose.yml`: Descomenta `ports: "8080:80"`.
2. Inicia el servidor (Permitiendo registro para crear tu cuenta):
   ```bash
   SIGNUPS_ALLOWED=true ./scripts/start.sh
   ```
3. Configura Tailscale para HTTPS:
   ```bash
   sudo tailscale serve --bg --https=443 localhost:8080
   sudo tailscale status # Copia la URL (https://xyz.ts.net)
   ```
5. **Finalizar y Cerrar Registros**:
   Actualiza tu `.env` con la URL obtenida (`BW_HOST=https://xyz.ts.net`) y reinicia para bloquear registros:
   ```bash
   ./scripts/start.sh
   ```

---

## 🚀 5. Finalización y Backups
1. Accede a tu nueva URL y crea tu cuenta.
2. Obtén tus API Keys (Ajustes -> Seguridad -> Claves API).
3. Configura los backups completos:
   ```bash
   ./scripts/manage_secrets.sh edit
   # Agrega BW_CLIENTID y BW_CLIENTSECRET
   ```
4. **Configurar Nube (Rclone)**:
   ```bash
   rclone config
   # 1. 'n' (New remote) -> Ponle nombre 'gdrive'
   # 2. 'drive' (Google Drive) -> Sigue los pasos para autorizar
   ```

5. **Definir Carpeta de Destino**:
   Indica en qué carpeta de la nube quieres guardar los backups (El script la creará si no existe):
   ```bash
   ./scripts/manage_secrets.sh edit
   # Formato: nombre_remote:Carpeta
   # Ejemplo: RCLONE_REMOTE=gdrive:Backups/Vaultwarden
   ```

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

### 🚨 Recuperación ante Desastre (Servidor Nuevo)

Si tu servidor original se perdió y estás configurando una **instancia nueva desde cero**, sigue estos pasos críticos en orden:

1.  **Clonar e Instalar Dependencias**:
    ```bash
    git clone https://github.com/TU_USUARIO/vaultwarden-proxmox.git /opt/vaultwarden
    cd /opt/vaultwarden
    # Instala age, docker, rclone, etc.
    ./scripts/install.sh
    ```

2.  **Restaurar Identidad Criptográfica**:
    Recupera tu llave maestra (que debiste guardar en un lugar seguro) y colócala en su sitio:
    ```bash
    mkdir -p ~/.age
    nano ~/.age/vaultwarden.key  # Pega tu clave privada aquí
    chmod 600 ~/.age/vaultwarden.key
    ```

3.  **Re-configurar Secretos**:
    El backup **NO** incluye tus credenciales de despliegue (`.env.age`) por seguridad. Debes regenerarlo o restaurarlo manualmente:
    ```bash
    ./scripts/manage_secrets.sh edit
    # Configura DOMAIN, TELEGRAM_TOKEN, RCLONE, etc.
    ```

4.  **Inicializar Servicios (Primer Arranque)**:
    Es necesario que Docker cree los contenedores y volúmenes antes de restaurar los datos.
    ```bash
    ./scripts/start.sh
    # Espera a que inicie y luego verifica que funciona
    ```

5.  **Descargar y Colocar el Backup**:
    El script necesita leer el archivo `.tar.gz.age` localmente. Traélo desde tu nube y colócalo en la raíz del proyecto (`/opt/vaultwarden`).

    *Opción A: Usando Rclone (Recomendado)*
    ```bash
    # Listar backups disponibles en la nube
    rclone lsl gdrive:Backups/Vault/
    
    # Descargar el archivo deseado a la carpeta actual
    rclone copy gdrive:Backups/Vault/vw_backup_YYYYMMDD_HHMMSS.tar.gz.age .
    ```

    *Opción B: Subida Manual (SFTP/SCP)*
    1.  Descarga el archivo desde tu Google Drive/S3 a tu computadora.
    2.  Súbelo al nuevo servidor usando SFTP (FileZilla) o SCP:
        ```bash
        scp backup.tar.gz.age usuario@tu-servidor:/opt/vaultwarden/
        ```

6.  **Ejecutar Restauración**:
    Ejecuta el script pasando el nombre del archivo descargado:
    ```bash
    ./scripts/restore.sh vw_backup_YYYYMMDD_HHMMSS.tar.gz.age
    ```
    *El script detendrá automáticamente el servidor, reemplazará la base de datos y adjuntos, y volverá a iniciarlo.*

### ¿Cómo usar el JSON Portable?
Si tu objetivo no es restaurar este servidor, sino realizar una **migración rápida a Bitwarden Cloud** (⚠️ **sin** archivos adjuntos ni configuraciones):

1.  Copia tu llave privada a la carpeta actual (si no la tienes a mano):
    ```bash
    cp ~/.age/vaultwarden.key .
    ```

2.  Descifra el backup manualmente:
    ```bash
    # Si tienes la key en la ruta por defecto:
    age -d -i ~/.age/vaultwarden.key -o backup.tar.gz backup.tar.gz.age
    
    # O si la acabas de copiar:
    age -d -i vaultwarden.key -o backup.tar.gz backup.tar.gz.age
    ```

3.  Descomprime:
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
