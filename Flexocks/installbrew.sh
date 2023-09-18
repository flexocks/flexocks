#!/bin/bash

PASSWORD="$1"  # Recoge la contraseña del primer argumento

echo "$PASSWORD" | sudo -S true

if [ $? -ne 0 ]; then
    echo "Error: la contraseña es incorrecta."
    exit 1
fi

echo "$PASSWORD" | sudo -S /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo "export PATH=/opt/homebrew/bin:$PATH" >> ~/.bash_profile
source ~/.bash_profile

exit 0

