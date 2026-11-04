# Radar VTC Valencia

Web app (PWA) para conductores VTC en Valencia: predice dónde va a haber salida masiva de gente de miércoles a domingo, de 16:00 a 04:00, y da consejos en tiempo real según tu posición.

Es un sitio estático: no tiene backend ni build. Vercel solo tiene que servir esta carpeta.

## Contenido

| Archivo | Para qué sirve |
| --- | --- |
| `index.html` | La app completa (HTML + CSS + JS + mapa de Valencia incrustado) |
| `manifest.webmanifest` | Permite instalarla en el móvil como una app |
| `sw.js` | Service worker: abre al instante y funciona sin cobertura |
| `icon-192.png`, `icon-512.png`, `apple-touch-icon.png` | Iconos |
| `vercel.json` | Cabeceras (permiso de GPS, caché del service worker) |

## Subirla a Vercel

### Opción A — desde la terminal (la más rápida)

```bash
cd C:\workspace\vtc\vercel
npx vercel login          # la primera vez
npx vercel                # crea el proyecto (acepta las preguntas por defecto)
npx vercel --prod         # publica en producción
```

- **Framework preset:** Other
- **Build command:** ninguno
- **Output directory:** `.` (la propia carpeta)

### Opción B — desde GitHub

1. Crea un repositorio, por ejemplo `radar-vtc`, y sube el contenido de esta carpeta.
2. En vercel.com → **Add New… → Project** → importa el repositorio.
3. Framework preset: **Other**. Sin comando de build. Deploy.

Cada `git push` publicará una versión nueva automáticamente.

## Instalarla en el móvil

1. Abre la URL de Vercel en el móvil.
2. **Android (Chrome):** menú ⋮ → *Instalar aplicación* / *Añadir a pantalla de inicio*.
   **iPhone (Safari):** botón Compartir → *Añadir a pantalla de inicio*.
3. Ábrela desde el icono. La primera vez:
   - Pulsa **Usar GPS** y acepta el permiso de ubicación.
   - Pulsa 🔔 para activar los avisos sonoros.

## Qué funciona fuera de Claude (y no dentro)

- **GPS automático** (dentro de Claude había que tocar el mapa).
- **Tiempo en directo** desde Open-Meteo, cada 15 min. Si está lloviendo o va a llover en la próxima hora y media, la app sube la demanda automáticamente.
- **Funciona sin cobertura**, usando lo último guardado.

## Limitaciones

- **Los avisos solo suenan con la app abierta en pantalla.** Para recibirlos con el móvil bloqueado hace falta un pequeño backend con Web Push (fase 2 del documento de diseño).
- **La agenda de eventos está escrita a mano** dentro de `index.html` (`BASE_EVENTS`, hasta el 15 de noviembre de 2026). Para añadir eventos sobre la marcha usa el botón **+** de la app. Para actualizar la agenda de forma permanente, edita `BASE_EVENTS` y vuelve a publicar.
- **Mapa base:** teselas de Esri World Dark Gray (© Esri, HERE, Garmin, © colaboradores de OpenStreetMap). Para uso comercial hay que contratar un servicio de mapas.
- **Tus datos se quedan en el móvil** (`localStorage`): instrucciones de la flota, eventos que añadas, posición marcada y registros de "Había trabajo / No había". Si borras los datos del navegador se pierden. Usa "Copiar mis registros" antes.

## Actualizar la app

Cuando tengas una versión nueva de `index.html`, sustitúyela en esta carpeta y vuelve a ejecutar `npx vercel --prod` (o haz `git push`). Para forzar que los móviles descarguen la versión nueva, sube el número de `CACHE` en `sw.js` (`radar-vtc-v1` → `radar-vtc-v2`).
