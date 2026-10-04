# Arquitectura de Pagos y Reglas de Apple - App de Citas/Salones de Belleza

Estado: propuesta de arquitectura para la implementación y preparación de App Review. Guardar este documento no implementa los pagos ni garantiza la aprobación. Las precisiones de la sección 3 deben aplicarse al desarrollar los flujos y redactar las notas para Apple.

## 1. Modelo de Negocio y Flujos Financieros

La plataforma maneja dos flujos de dinero completamente separados:

* **Flujo B2B (Suscripción/Membresía de la plataforma):**
  * Cobro de membresías o cuotas recurrentes a los salones de belleza/proveedores.
  * **Pasarela propuesta originalmente:** Se procesa directamente hacia la cuenta de la empresa utilizando **Apple Pay / In-App Purchase** (cumpliendo con las normas de Apple para servicios de software/SaaS digitales).
  * **Precisión para implementar:** Para vender dentro de iOS una membresía que desbloquee funciones digitales, la opción base será **In-App Purchase mediante StoreKit**, con suscripciones configuradas en App Store Connect. Apple Pay no es equivalente ni sustituye a IAP. La liquidación de estas ventas se realiza mediante Apple según los acuerdos aplicables.
* **Flujo C2C / Marketplace (Adelantos para citas):**
  * El cliente final paga un depósito/adelanto para asegurar su cita con el salón de belleza.
  * **Pasarela:** Se usa **Mercado Pago** configurado bajo un esquema de *split de pagos / marketplace* para que el dinero caiga **directamente a la cuenta de Mercado Pago del salón**. La empresa dueña de la plataforma **no toca ni retiene** esos fondos.
  * Esta separación es un requisito del diseño propuesto. Debe verificarse en la configuración y liquidación real de Mercado Pago; este documento no acredita que el backend ya implemente split ni que su configuración actual cumpla ese requisito. Si la plataforma no recibe parte del adelanto, no debe configurarse una comisión que le transfiera parte de esos fondos.

## 2. Cumplimiento de Políticas de la App Store (Apple)

* **Pagos de citas presenciales:** Al tratarse de un servicio del mundo real, consumido en un establecimiento físico, el adelanto entre el cliente y el salón se cobra mediante un método distinto de In-App Purchase, conforme a la regla 3.1.3(e).
* **Estrategia de integración de Mercado Pago:**
  * La decisión del proyecto es realizar el adelanto mediante un **flujo web seguro de Checkout Pro**, presentado dentro de la app cuando sea compatible con el proveedor o mediante navegador y retorno a la app.
  * El objetivo es usar el checkout alojado del proveedor para el pago de la cita. **Apple no exige WebView o navegador como condición general para permitir un procesador externo en servicios presenciales.** Esta elección de integración no debe presentarse como una obligación de Apple ni como un mecanismo para eludir la revisión.
  * Un webhook notifica al backend del resultado del pago. El backend verifica el evento con Mercado Pago, lo procesa de manera idempotente y comprueba propietario, cita, importe, moneda y estado antes de aplicar la transición correspondiente.
  * La app consulta el backend al regresar del checkout y actualiza el estado de la cita. Una redirección de éxito por sí sola no confirma el pago. Los resultados pendientes, rechazados o que requieren revisión deben conservar su estado correcto; **“Cita confirmada”** solo se muestra cuando el backend confirme que corresponde.

## 3. Precisiones verificadas y criterios de implementación

Fuente oficial consultada el 4 de octubre de 2026: [App Review Guidelines de Apple](https://developer.apple.com/app-store/review/guidelines/).

* **3.1.1 y 3.1.2:** La venta dentro de la app de funciones digitales y suscripciones se rige por IAP y sus reglas. Apple Pay es otro medio de pago.
* **3.1.3(e):** Para bienes físicos y servicios consumidos fuera de la app, Apple exige métodos distintos de IAP. Mercado Pago se propone para los adelantos de citas presenciales.
* **3.1.3(c) y 3.1.3(f):** Hay excepciones específicas para servicios empresariales y aplicaciones complementarias gratuitas. El nombre “B2B” por sí solo no acredita que una excepción aplique. La arquitectura base propuesta usa IAP para la membresía digital vendida dentro de iOS.
* Las reglas de compras externas pueden variar por storefront y acuerdos aplicables. El checkout de citas no debe utilizarse para vender la membresía digital de la plataforma.

### Separación técnica prevista

* **Membresía:** StoreKit → verificación de transacción en backend → permisos de la plataforma. Gestionar renovaciones, restauración, caducidad y revocaciones.
* **Adelanto:** Checkout Pro del salón → webhook verificado por backend → estado del pago y de la cita → actualización en iOS. Mantener reembolsos y conciliación asociados al salón correspondiente.
* Separar identificadores, registros de transacciones y permisos de ambos flujos. El pago de una cita no activa una suscripción de software.

### Preparación para revisión

Las notas de App Review deben explicar qué compra cada flujo, que las citas son presenciales y quién recibe el adelanto. Proporcionar acceso de prueba y un backend disponible para revisar la app. La documentación debe describir el comportamiento efectivamente implementado; la decisión final corresponde a App Review.
