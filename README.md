# Gestiq para iPhone

Arquitectura de pagos prevista y criterios para App Review: [Arquitectura de pagos y reglas de Apple](docs/ARQUITECTURA_PAGOS_APPLE.md). Separa membresías digitales mediante IAP y adelantos de citas presenciales mediante Mercado Pago; es una propuesta pendiente de implementación.

App nativa en SwiftUI, iOS 17 o posterior, sin dependencias externas. Incluye login real, cuenta y administración de clientes y negocios.

Las pestañas **Clientes** y **Negocios** aparecen para cuentas con acceso a esas rutas según los permisos enviados por el backend. Incluyen búsqueda por nombre/correo/teléfono (también nombre del negocio), paginación de 10 registros y detalles con contacto, verificación, estado, actividad y citas recientes. Los negocios muestran políticas, horarios y vinculación guardada de Mercado Pago. Todo navega dentro de la app.

El administrador principal (`role.name=admin_master`) puede desactivar cuentas activas y reactivar cuentas desactivadas desde su detalle, con confirmación. El administrador interno tiene acceso de consulta. Las acciones usan los endpoints existentes y actualizan los datos después de la confirmación del servidor. Ante un fallo de conexión, comprueba el detalle antes de reintentar; la app no repite automáticamente una petición con resultado desconocido.

La pestaña **Inicio** muestra el dashboard administrativo para roles `admin_master` y `admin_intern` con acceso a `/dashboard`: cuentas y servicios actuales, citas del mes y negocios con más reservas. Permite seleccionar mes/año (2000–2099), actualizar y abrir detalles de negocios dentro de la app. El primer mes lo decide el backend según su zona horaria.

Para una cuenta de negocio (`customer`), **Mi negocio** permite crear o editar nombre, descripción, ubicación, foto de perfil, portada, horarios semanales y políticas de cancelación/reagenda. **Servicios** incluye búsqueda, paginación, creación y edición con fotos, duración, descuentos, retoques, anticipos y extras. Desde el detalle puedes archivar o publicar un servicio con confirmación. Los anticipos requieren la vinculación de Mercado Pago ya registrada en la cuenta. Las fotos se seleccionan con el selector nativo y se convierten a JPEG antes de enviarse; se admiten de 1 a 5 por servicio. El backend limita cada petición a 5 cambios de fotos y 30 entradas de extras; reemplazos grandes deben guardarse en grupos más pequeños. La vinculación de pagos aún no se realiza desde la app.

## Ejecutar

**Mi negocio** organiza sus controles en Perfil, Horarios y Políticas. Incluye botón Guardar permanente, campos etiquetados, agregar/editar horarios y eliminarlos con confirmación, anticipación editable directamente y guía para empresas. **Ver perfil público** carga los datos guardados y servicios dentro de la app. **Compartir negocio y QR** permite copiar o compartir el enlace y compartir/guardar el QR con el menú de iOS.

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

swiftc -module-cache-path /tmp/gestiq-swift-cache Gestiq/Auth/AuthClient.swift Gestiq/Auth/KeychainSessionStore.swift Gestiq/Auth/LoginModel.swift Gestiq/Admin/AdminModels.swift Gestiq/Admin/AdminDashboardModel.swift Tests/AdminChecks.swift -o /tmp/gestiq-admin-checks
/tmp/gestiq-admin-checks

swiftc -module-cache-path /tmp/gestiq-swift-cache Gestiq/Auth/AuthClient.swift Gestiq/Auth/KeychainSessionStore.swift Gestiq/Auth/LoginModel.swift Gestiq/Admin/AdminModels.swift Gestiq/Business/BusinessModels.swift Gestiq/Business/BusinessState.swift Tests/BusinessChecks.swift -o /tmp/gestiq-business-checks
/tmp/gestiq-business-checks
```

Con Xcode instalado:

```sh
xcodebuild -project Gestiq.xcodeproj -scheme Gestiq -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

El login reproduce la paleta, tarjeta y logo del frontend web. Usa Arial, la tipografía de respaldo del frontend, con tamaños adaptables. El login es la pantalla inicial y no contiene enlaces que abran la web. Registro, recuperación y confirmación de correo quedan fuera de esta entrega.

Compilación de simulador validada con Xcode 26.3 ubicado en `~/Downloads/Xcode.app`. Si `xcode-select` todavía apunta a Command Line Tools, antepone `DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"` al comando de compilación. La revisión visual en simulador queda pendiente.
