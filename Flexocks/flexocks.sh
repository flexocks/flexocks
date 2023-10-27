#!/bin/bash

resources_path="$(dirname "$0")"
script_expect="${resources_path}/flexocks.expect"
APP_SUPPORT_DIR="/Users/$(whoami)/Library/Application Support/Flexocks"
[ -d "$APP_SUPPORT_DIR" ] || mkdir -p "$APP_SUPPORT_DIR"
LOG_FILE="$APP_SUPPORT_DIR/flexocks.log"
HTML_FILE_PATH="${resources_path}/flexocks.html"

if [ -d "/Applications" ]; then
    BASE_DIR="/Applications"
elif [ -d "/Aplicaciones" ]; then
    BASE_DIR="/Aplicaciones"
else
    echo "Ni Applications ni Aplicaciones existen."
    exit 1
fi

DIST_DIR="${BASE_DIR}/Firefox.app/Contents/Resources/distribution"
POLICIES_FILE="$DIST_DIR/policies.json"

action="$1"
shift

while [[ $# -gt 1 ]]; do
    key="$1"
    case $key in
        -h|--host)
        host="$2"
        shift
        ;;
        -l|--puertoLocal)
        puertoLocal="$2"
        shift
        ;;
        -r|--puertoRemoto)
        puertoRemoto="$2"
        shift
        ;;
        -o|--extrassh)
        extrassh="$2"
        shift
        ;;
        -u|--usuario)
        usuario="$2"
        shift
        ;;
        -c|--contrasena)
        contrasena="$2"
        shift
        ;;
    esac
    shift
done

if [ "$action" == "start" ]; then
    [ -d "$DIST_DIR" ] || mkdir -p "$DIST_DIR"

    # Modificar el archivo HTML para incluir la ruta del archivo de registro
    sed -i "" "s|%%LOG_FILE_PATH%%|$LOG_FILE|g" "$HTML_FILE_PATH"

    # Copiar el archivo HTML al directorio de distribución
    cp "${resources_path}/flexocks.html" "$DIST_DIR/"

    cat > "$POLICIES_FILE" <<EOL
{
  "policies": {
    "Proxy": {
      "Mode": "manual",
      "SOCKSProxy": "127.0.0.1:$puertoLocal",
      "SOCKSVersion": 5,
      "UseProxyForDNS": true
    },
    "Homepage": {
      "URL": "file://${DIST_DIR}/flexocks.html",
      "Locked": true,
      "StartPage": "homepage-locked"
    }
  }
}
EOL

    echo "Fichero policies.json de Firefox: " >> "$LOG_FILE"
    cat $POLICIES_FILE >> "$LOG_FILE"

    if nc -z -v -G 2 "$host" "$puertoRemoto" 2>&1 | tee -a "$LOG_FILE" | grep succeeded > /dev/null; then
        if pgrep -f "autossh.*$host.*$puertoRemoto" > /dev/null; then
            result=$(curl -x 127.0.0.1:$puertoLocal http://www.google.es 2>&1)
            if echo "$result" | grep -q "Failed to connect"; then
                echo "El proceso de conexión está en ejecución pero aún no hay conectividad"
            else
                echo "Conexión SSH ya establecida. No se vuelve a ejecutar"
            fi
        else
            nohup "$script_expect" "$host" "$puertoLocal" "$puertoRemoto" "$extrassh" "$usuario" "$contrasena" >> "$LOG_FILE" 2>&1 &
            echo "Conexión SSH en ejecución."
            echo "Archivo de políticas de Firefox generado con éxito para SOCKS 5 Proxy."
        fi
    else
        echo "El servidor $host no está disponible. No se puede establecer la conexión SSH."
        echo "El servidor $host no está disponible. No se puede establecer la conexión SSH." >> "$LOG_FILE" 2>&1 &
    fi

elif [ "$action" == "stop" ]; then
    cp "${resources_path}/flexocks_off.html" "$DIST_DIR/flexocks.html"
    if [ -f "$POLICIES_FILE" ]; then
        cat > "$POLICIES_FILE" <<EOL
{
  "policies": {
    "Proxy": {
      "Mode": "none"
    }
  }
}
EOL
        echo "El modo del proxy en el archivo de políticas de Firefox ha sido configurado a 'none'."
    else
        echo "El archivo policies.json no existe."
    fi

    process_id=$(ps aux | grep "autossh" | grep "$host" | grep "$puertoRemoto" | grep "$puertoLocal" | grep -v grep | awk '{print $2}')
    if [ -n "$process_id" ]; then
        kill "$process_id"
        echo "Conexión SSH desconectada."
    else
        echo "No se encontró ninguna conexión SSH en ejecución."
    fi

elif [ "$action" == "status" ]; then
    process_id=$(ps aux | grep "autossh" | grep "$host" | grep "$puertoLocal" | grep "$puertoRemoto" | grep -v grep | awk '{print $2}')
    if [ -n "$process_id" ]; then
        result=$(curl -x 127.0.0.1:$puertoLocal http://www.google.es 2>&1)
        if echo "$result" | grep -q "Failed to connect"; then
            echo "2"
        else
            echo "0"
        fi
    else
        echo "1"
    fi
else
    echo "Uso: $0 {start|stop|status}"
fi
