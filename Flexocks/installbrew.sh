#!/bin/bash

check_installed() {
    local cmd=$1
    local check_paths=(/usr/local/bin /usr/bin /bin /usr/sbin /sbin)
    for path in "${check_paths[@]}"; do
        if [[ -x "$path/$cmd" ]]; then
            return 0
        fi
    done
    return 1
}

# Instalar Homebrew si no está presente
check_installed brew
if [[ $? -ne 0 ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Si la instalación de Homebrew falla, terminamos el script
    if [[ $? -ne 0 ]]; then
        echo "Ocurrió un error al instalar Homebrew. Finalizando..."
        exit 1
    fi

    # Actualizamos Homebrew para asegurarnos de que tengamos las fórmulas más recientes
    brew update
else
    echo "Homebrew ya está instalado. Saltando su instalación..."
fi

# Comprobar e instalar autossh si no está presente
check_installed autossh
if [[ $? -ne 0 ]]; then
    echo "autossh no está presente. Instalando..."
    brew install autossh
else
    echo "autossh ya está instalado. Saltando su instalación..."
fi

# Comprobar e instalar expect si no está presente
check_installed expect
if [[ $? -ne 0 ]]; then
    echo "expect no está presente. Instalando..."
    brew install expect
else
    echo "expect ya está instalado. Saltando su instalación..."
fi
