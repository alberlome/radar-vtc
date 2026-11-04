-- Radar VTC Valencia - Esquema MVP (PostgreSQL 16 + PostGIS + h3)
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS h3;          -- opcional en Supabase: h3-pg
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- similitud de títulos para deduplicar

CREATE TYPE categoria_evento AS ENUM ('deportes','conciertos','transporte','ocio_nocturno','ciudad');
CREATE TYPE tipo_evento AS ENUM (
  'futbol','baloncesto','otro_deporte',
  'concierto_arena','concierto_sala','discoteca',
  'llegada_tren','llegada_vuelo','evento_ciudad');
CREATE TYPE estado_evento AS ENUM ('programado','en_curso','finalizado','cancelado','aplazado');
CREATE TYPE nivel_demanda AS ENUM ('verde','amarillo','rojo','critico');

-- Lugares fijos
CREATE TABLE recintos (
  id              serial PRIMARY KEY,
  nombre          text NOT NULL UNIQUE,
  tipo            text NOT NULL,                 -- estadio, arena, sala, discoteca, estacion, aeropuerto
  aforo           integer,
  ubicacion       geography(Point,4326) NOT NULL,
  punto_recogida  geography(Point,4326),         -- donde conviene esperar, no la puerta
  zona            text,
  notas_conductor text,                          -- consejos: cortes de tráfico, salidas
  activo          boolean NOT NULL DEFAULT true
);

-- Tabla central normalizada
CREATE TABLE eventos (
  id                          bigserial PRIMARY KEY,
  recinto_id                  integer REFERENCES recintos(id),
  tipo_evento                 tipo_evento NOT NULL,
  categoria                   categoria_evento NOT NULL,
  titulo                      text NOT NULL,
  fecha                       date NOT NULL,
  hora_inicio                 timestamptz NOT NULL,
  hora_fin                    timestamptz NOT NULL,
  hora_fin_estimada           boolean NOT NULL DEFAULT true,
  noche_operativa             date NOT NULL,     -- noche de 16:00 a 04:00 a la que pertenece
  ubicacion_lat_lng           geography(Point,4326) NOT NULL,
  asistencia_estimada         integer,
  coeficiente_impacto_demanda numeric(4,2) CHECK (coeficiente_impacto_demanda BETWEEN 0 AND 10),
  estado                      estado_evento NOT NULL DEFAULT 'programado',
  fuente                      text NOT NULL,
  fuente_id                   text,
  datos_extra                 jsonb NOT NULL DEFAULT '{}',
  creado_en                   timestamptz NOT NULL DEFAULT now(),
  actualizado_en              timestamptz NOT NULL DEFAULT now(),
  UNIQUE (fuente, fuente_id)
);
CREATE INDEX eventos_noche_idx  ON eventos (noche_operativa, hora_fin);
CREATE INDEX eventos_geo_idx    ON eventos USING gist (ubicacion_lat_lng);
CREATE INDEX eventos_titulo_trgm ON eventos USING gin (titulo gin_trgm_ops);

-- Trenes y vuelos (con retraso en vivo)
CREATE TABLE llegadas_transporte (
  id                 bigserial PRIMARY KEY,
  evento_id          bigint REFERENCES eventos(id) ON DELETE CASCADE,
  modo               text NOT NULL CHECK (modo IN ('tren','vuelo')),
  operador           text,                       -- Renfe, Iryo, Ouigo, Ryanair...
  numero             text NOT NULL,
  origen             text,
  terminal_estacion  text NOT NULL,              -- Joaquín Sorolla, Estació del Nord, VLC T1
  llegada_programada timestamptz NOT NULL,
  llegada_estimada   timestamptz,
  plazas_estimadas   integer,
  estado             text,
  actualizado_en     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (modo, numero, llegada_programada)
);
CREATE INDEX llegadas_hora_idx ON llegadas_transporte (coalesce(llegada_estimada, llegada_programada));

-- Ventanas de demanda que se pintan en el mapa
CREATE TABLE ventanas_demanda (
  id         bigserial PRIMARY KEY,
  evento_id  bigint NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
  inicio     timestamptz NOT NULL,
  pico       timestamptz NOT NULL,
  fin        timestamptz NOT NULL,
  intensidad numeric(5,2) NOT NULL,
  nivel      nivel_demanda NOT NULL
);
CREATE INDEX ventanas_tiempo_idx ON ventanas_demanda (inicio, fin);

-- Agregado por celda H3 (res. 8) y franja de 15 min
CREATE TABLE demanda_celda (
  h3_index      text NOT NULL,
  franja_inicio timestamptz NOT NULL,
  intensidad    numeric(5,2) NOT NULL,
  nivel         nivel_demanda NOT NULL,
  eventos_ids   bigint[] NOT NULL,
  PRIMARY KEY (h3_index, franja_inicio)
);
CREATE INDEX demanda_franja_idx ON demanda_celda (franja_inicio);

-- Datos crudos de cada scraper/API
CREATE TABLE raw_ingestas (
  id           bigserial PRIMARY KEY,
  fuente       text NOT NULL,
  capturado_en timestamptz NOT NULL DEFAULT now(),
  payload      jsonb NOT NULL,
  hash         text NOT NULL,
  UNIQUE (fuente, hash)
);

-- Usuarios y notificaciones
CREATE TABLE usuarios (
  id        uuid PRIMARY KEY,                    -- = auth.users.id en Supabase
  alias     text,
  creado_en timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE preferencias (
  usuario_id    uuid PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
  categorias    categoria_evento[] NOT NULL DEFAULT '{deportes,conciertos,transporte,ocio_nocturno}',
  umbral_alerta nivel_demanda NOT NULL DEFAULT 'rojo',
  zona_base     geography(Point,4326),
  en_servicio   boolean NOT NULL DEFAULT false
);
CREATE TABLE suscripciones_push (
  id         bigserial PRIMARY KEY,
  usuario_id uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  endpoint   text NOT NULL UNIQUE,
  p256dh     text NOT NULL,
  auth       text NOT NULL,
  creado_en  timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE feedback_ventanas (
  id          bigserial PRIMARY KEY,
  usuario_id  uuid REFERENCES usuarios(id) ON DELETE SET NULL,
  ventana_id  bigint REFERENCES ventanas_demanda(id) ON DELETE CASCADE,
  habia_trabajo boolean NOT NULL,
  creado_en   timestamptz NOT NULL DEFAULT now()
);

-- Noche operativa: de 16:00 a 04:00 (hora de Madrid)
CREATE OR REPLACE FUNCTION noche_operativa(ts timestamptz) RETURNS date
LANGUAGE sql IMMUTABLE AS $$
  SELECT ((ts AT TIME ZONE 'Europe/Madrid') - interval '4 hours')::date
$$;

-- Ventana de interés: miércoles (3) a domingo (0)
CREATE OR REPLACE FUNCTION en_ventana_operativa(ts timestamptz) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT extract(dow FROM noche_operativa(ts)) IN (3,4,5,6,0)
     AND ((ts AT TIME ZONE 'Europe/Madrid')::time >= time '16:00'
       OR (ts AT TIME ZONE 'Europe/Madrid')::time <  time '04:00')
$$;
