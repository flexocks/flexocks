#!/bin/bash

check_installed() {
    local cmd=$1
    local check_paths=(/usr/local/bin /usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin)
    for path in "${check_paths[@]}"; do
        if [[ -x "$path/$cmd" ]]; then
            echo "$path/$cmd"
            return 0
        fi
    done
    return 1
}

add_to_path() {
    local path_to_add=$1

    # Detecta el shell del usuario
    local shell_profile
    if [[ "$SHELL" == "/bin/zsh" ]]; then
        shell_profile="$HOME/.zshrc"
    else
        shell_profile="$HOME/.bash_profile"
    fi

    echo "Añadiendo $path_to_add al $shell_profile..."
    echo "export PATH=\"$path_to_add:\$PATH\"" >> "$shell_profile"
}

brew_path=$(check_installed brew)
if [[ $? -ne 0 ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ $? -ne 0 ]]; then
        echo "Ocurrió un error al instalar Homebrew. Finalizando..."
        exit 1
    fi

    brew_path=$(check_installed brew)
    if [[ $? -ne 0 ]]; then
        echo "No se pudo encontrar Homebrew después de la instalación. Finalizando..."
        exit 1
    fi
else
    echo "Homebrew ya está instalado en $brew_path. Saltando su instalación..."

    if [[ ! "$PATH" =~ "$(dirname "$brew_path")" ]]; then
        add_to_path "$(dirname "$brew_path")"
    fi
fi

check_installed autossh
if [[ $? -ne 0 ]]; then
    echo "autossh no está presente. Instalando..."
    "$brew_path" install autossh
else
    echo "autossh ya está instalado. Saltando su instalación..."
fi

check_installed expect
if [[ $? -ne 0 ]]; then
    echo "expect no está presente. Instalando..."
    "$brew_path" install expect
else
    echo "expect ya está instalado. Saltando su instalación..."
fi

osascript -e 'tell application "Terminal" to close first window without saving'
