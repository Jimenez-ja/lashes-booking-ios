# Gestiq para iPhone

App nativa en SwiftUI, iOS 17 o posterior, sin dependencias externas. Incluye login real por correo/contraseña y pantalla de cuenta con nombre, correo y cierre de sesión.

## Ejecutar

1. Instala Xcode y abre `Gestiq.xcodeproj`.
2. Selecciona el esquema `Gestiq` y un simulador iPhone; pulsa Run (⌘R).
3. Inicia sesión con una cuenta existente y correo verificado.

Para un iPhone físico, selecciona tu Team en **Signing & Capabilities** y ajusta el bundle identifier si es necesario.

`Config/App.xcconfig` contiene la URL pública de Railway (`/api`) y el origen `https://gestiq.app`. El backend exige este origen y `X-Gestiq-Session: 1`; la app envía ambos. La configuración usa `$()` para conservar las barras de las URLs en xcconfig. No se incluyen contraseñas ni credenciales.

La sesión se restaura al abrir la app mediante el backend. El refresh cookie se guarda en el llavero de iOS; el token de acceso y el perfil se mantienen en memoria. La app renueva el token cuando está próximo a caducar mientras está activa. Un fallo temporal ofrece reintentar sin borrar la sesión; una sesión revocada vuelve al login. Cerrar sesión requiere confirmación y revoca la sesión en el backend antes de borrar la copia local. Si falla la conexión, puedes reintentar. Esta entrega no incluye registro ni recuperación de contraseña.

## Validación

Pruebas del contrato de autenticación con respuestas simuladas, sin llamadas al backend:

```sh
mkdir -p /tmp/gestiq-swift-cache
swiftc -module-cache-path /tmp/gestiq-swift-cache Gestiq/Auth/AuthClient.swift Gestiq/Auth/KeychainSessionStore.swift Gestiq/Auth/LoginModel.swift Tests/AuthClientChecks.swift -o /tmp/gestiq-auth-checks
/tmp/gestiq-auth-checks
```

Con Xcode instalado:

```sh
xcodebuild -project Gestiq.xcodeproj -scheme Gestiq -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

El login reproduce la paleta, tarjeta y logo del frontend web. Usa Arial, la tipografía de respaldo del frontend, con tamaños adaptables. El login es la pantalla inicial y no contiene enlaces que abran la web. Registro, recuperación y confirmación de correo quedan fuera de esta entrega.

Compilación de simulador validada con Xcode 26.3 ubicado en `~/Downloads/Xcode.app`. Si `xcode-select` todavía apunta a Command Line Tools, antepone `DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"` al comando de compilación. La revisión visual en simulador queda pendiente.
