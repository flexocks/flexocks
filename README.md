# Flexocks (una app que vale para poco y sólo empleará su autor)

**Flexocks** es una herramienta diseñada para facilitar la navegación segura y privada a través de Firefox en macOS. Desarrollada con Swift y scripts de shell, esta aplicación establece una conexión SSH con un host remoto, que actúa como un proxy SOCKS, permitiéndote navegar a través de ese host.

> Si sabes lanzar un comando ssh y no te da pereza hacerlo y dejar el terminal abierto, esta app te la puedes ahorrar.

## Instalación y Uso

- **Instala**: Mueve el fichero `Flexocks.app` al directorio `Applications` o `Aplicaciones` (depende del idioma de instalación).
  
- **Configura**: Edita los datos de conexión de tu host (nombre o ip, un puerto local cualquiera disponible, el puerto remoto por el que escucha ssh tu servidor, usuario y contraseña).
  
- **Navega**: Reinicia Firefox. Si todo ha salido bien la pantalla de inicio mostrará que navegas desde la ubicación de tu servidor remoto.

## Características

- **Verificación Continua**: Cada vez que inicies Flexocks, la aplicación verifica automáticamente si las herramientas `expect` y `autossh` están presentes en el sistema. Si en alguna ocasión no las detecta, procederá con su instalación. Por ello, la aplicación puede tardar un poco más en iniciar en su primera ejecución.

- **Navegación Proxy a través de SSH**: Una vez que las herramientas requeridas están en su lugar, Flexocks crea una conexión SSH segura a un host remoto que actúa como un proxy SOCKS. Esto prepara el terreno para que utilices Firefox y navegues a través de ese host, garantizando una navegación desde esa ubicación sin pasar por proxy corporativo o para saltarse restricciones de país.

- **Gestión Automática del Proxy de Firefox**: Flexocks modifica automáticamente la configuración del proxy de Firefox cuando te conectas y restablece dicha configuración a "none" al desconectar. Hay que reiniciar Firefox después de conectar o desconectar para asegurar que el navegador actualiza y aplica la nueva configuración.

- **Recomendaciones**: Si accedes a un host a través de internet vas a necesitar que el router redirija el tráfico de un puerto de acceso remoto al puerto de ssh, el 22 generalmente. Considera utilizar un servicio de DDNS (Dynamic Domain Name System) para poder acceder al host siempre con el mismo nombre, evitando así la necesidad de editar la dirección IP constantemente en la configuración. 

  Si quieres hacer un test con tu propio Mac:
  1. En las preferencias del sistema => Compartir / Sharing => activa “Remote Login”/“Inicio de sesión remoto”
  2. Configura Flexocks con estos valores en el formulario: `localhost+12345+22+tu_usuario+tu_contraseña`

## Requisitos

- macOS (13.5 o superior mientras no le busque remedio).
- Firefox instalado.
- Otorgar permisos a la aplicación de manipulación de otras apps (modifica las políticas de Firefox).

## Disclaimer

Lo normal es que esté llena de fallos porque programar entretiene, desarrollar es un asco y la arquitectura final está muy lejos de lo que me habría gustado. Hasta para algo tan simple como ejecutar una conexión ssh hay que pisar demasiados charcos. 

La versión actual habría que limpiarla un poco aún (mejor gestión del fichero de log, gestión de errores, pruebas en diferentes versiones de MacOS y Firefox,…)
