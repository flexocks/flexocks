#!/bin/bash

#!/bin/bash

# Ejecutamos directamente la instalación de Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo "export PATH=/opt/homebrew/bin:$PATH" >> ~/.bash_profile
source ~/.bash_profile

exit 0

