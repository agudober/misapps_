# Mis cuentas (Supabase)

1. En Supabase → SQL Editor, ejecuta `supabase/schema.sql`.
2. Authentication → Sign In / Providers → Email: desactiva "Allow new users to sign up".
3. Authentication → Users → Add user (marca "Auto Confirm User") para ti y para tu pareja.
4. Project Settings → API: copia la Project URL y la clave anon/publishable en `supabase-config.js`.
5. Sube el contenido de esta carpeta a GitHub y activa Settings → Pages (rama main, carpeta /root).
6. Si ya tenías el proyecto creado con el esquema anterior, ejecuta ademas `supabase/migracion-invitaciones.sql` (SQL Editor → Run, una sola vez). Añade invitaciones, correo interno y cuentas de solo lectura. Si empiezas de cero, `schema.sql` ya lo incluye.


Actualización visual: paleta verde billete como color principal y botón «Volver al inicio» en todas las pantallas, enlazado a la página principal situada en la carpeta superior. Se ha actualizado la versión de caché del Service Worker para aplicar los cambios.
