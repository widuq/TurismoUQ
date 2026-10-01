CREATE TABLE Municipio (
    id_municipio NUMBER(10) NOT NULL,
    nombre VARCHAR2(50) NOT NULL,
    codigo_postal VARCHAR2(10),
    
    CONSTRAINT pk_municipio PRIMARY KEY (id_municipio),
    CONSTRAINT uq_municipio_nombre UNIQUE (nombre)
);
COMMENT ON TABLE municipio IS
'Municipios del departamento del Quindío donde se encuentran los alojamientos turísticos.';

COMMENT ON COLUMN municipio.id_municipio IS
'Identificador único del municipio.';

COMMENT ON COLUMN municipio.nombre IS
'Nombre del municipio.';

COMMENT ON COLUMN municipio.codigo_postal IS
'Código postal del municipio.';


CREATE TABLE TipoAlojamiento (
    id_tipo_alojamiento NUMBER(10) NOT NULL,
    nombre VARCHAR2(50) NOT NULL,
    descripcion VARCHAR2 (200),
    
    CONSTRAINT pk_tipo_alojamiento PRIMARY KEY (id_tipo_alojamiento),
    CONSTRAINT uq_tipo_alojamiento_nombre UNIQUE (nombre)
);
COMMENT ON TABLE tipoalojamiento IS
'Catálogo de tipos de alojamiento turístico ofrecidos por TurismoUQ.';

COMMENT ON COLUMN tipoalojamiento.id_tipo_alojamiento IS
'Identificador único del tipo de alojamiento.';

COMMENT ON COLUMN tipoalojamiento.nombre IS
'Nombre del tipo de alojamiento, por ejemplo hotel, finca cafetera, glamping u hostal.';

COMMENT ON COLUMN tipoalojamiento.descripcion IS
'Descripción del tipo de alojamiento.';


CREATE TABLE Alojamiento (
    id_alojamiento NUMBER(10) NOT NULL,
    id_municipio NUMBER(10) NOT NULL,
    id_tipo_alojamiento NUMBER(10) NOT NULL,
    nombre VARCHAR2(50) NOT NULL,
    direccion VARCHAR2(150) NOT NULL,
    estrellas NUMBER(1) NOT NULL,
    correo VARCHAR2(50) NOT NULL,
    telefono VARCHAR2(20) NOT NULL,
    
    CONSTRAINT pk_alojamiento PRIMARY KEY (id_alojamiento),
    CONSTRAINT fk_alojamiento_municipio FOREIGN KEY (id_municipio) REFERENCES Municipio(id_municipio),
    CONSTRAINT fk_alojamiento_tipo FOREIGN KEY (id_tipo_alojamiento) REFERENCES TipoAlojamiento(id_tipo_alojamiento),
    CONSTRAINT ck_alojamiento_estrellas CHECK (estrellas BETWEEN 1 AND 5)
);
COMMENT ON TABLE alojamiento IS
'Alojamientos turísticos ofrecidos en los municipios del Quindío.';

COMMENT ON COLUMN alojamiento.id_alojamiento IS
'Identificador único del alojamiento.';

COMMENT ON COLUMN alojamiento.id_municipio IS
'Municipio al que pertenece el alojamiento.';

COMMENT ON COLUMN alojamiento.id_tipo_alojamiento IS
'Tipo de alojamiento del establecimiento.';

COMMENT ON COLUMN alojamiento.nombre IS
'Nombre comercial del alojamiento.';

COMMENT ON COLUMN alojamiento.direccion IS
'Dirección física del alojamiento.';

COMMENT ON COLUMN alojamiento.estrellas IS
'Calificación en estrellas autoasignada por el alojamiento, de 1 a 5.';

COMMENT ON COLUMN alojamiento.correo IS
'Correo electrónico de contacto del alojamiento.';

COMMENT ON COLUMN alojamiento.telefono IS
'Teléfono de contacto del alojamiento.';


CREATE TABLE Habitacion (
    id_habitacion NUMBER(10) NOT NULL,
    id_alojamiento NUMBER(10) NOT NULL,
    numero NUMBER(10) NOT NULL,
    capacidad_maxima NUMBER(3) NOT NULL,
    tipo VARCHAR2(50) NOT NULL,
    descripcion VARCHAR2(200),
    
    CONSTRAINT pk_habitacion PRIMARY KEY (id_habitacion),
    CONSTRAINT fk_habitacion_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento),
    CONSTRAINT uq_habitacion_numero UNIQUE (id_alojamiento, numero),
    CONSTRAINT ck_habitacion_capacidad CHECK (capacidad_maxima > 0),
    CONSTRAINT ck_habitacion_tipo CHECK (tipo IN ('SENCILLA', 'DOBLE', 'SUITE', 'CABAÑA'))
);
COMMENT ON TABLE habitacion IS
'Habitaciones ofrecidas por cada alojamiento turístico.';

COMMENT ON COLUMN habitacion.numero IS
'Número de la habitación dentro del alojamiento.';

COMMENT ON COLUMN habitacion.capacidad_maxima IS
'Cantidad máxima de huéspedes que puede alojar la habitación.';

COMMENT ON COLUMN habitacion.tipo IS
'Tipo de habitación: sencilla, doble, suite o cabaña.';

COMMENT ON COLUMN habitacion.descripcion IS
'Descripción de las características de la habitación.';


CREATE TABLE Temporada (
    id_temporada NUMBER(10) NOT NULL,
    nombre VARCHAR2(50) NOT NULL,
    nivel VARCHAR2(10) NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    anio NUMBER(4) NOT NULL,
    
    CONSTRAINT pk_temporada PRIMARY KEY (id_temporada),
    CONSTRAINT ck_temporada_nivel CHECK (nivel IN ('ALTA', 'MEDIA', 'BAJA')),
    CONSTRAINT ck_temporada_fechas CHECK (fecha_fin >= fecha_inicio),
    CONSTRAINT ck_temporada_anio CHECK (anio BETWEEN 2000 AND 2100)
);
COMMENT ON TABLE temporada IS
'Temporadas turísticas definidas para un periodo específico de un año.';

COMMENT ON COLUMN temporada.nombre IS
'Nombre de la temporada o periodo turístico.';

COMMENT ON COLUMN temporada.nivel IS
'Nivel de demanda de la temporada: ALTA, MEDIA o BAJA.';

COMMENT ON COLUMN temporada.fecha_inicio IS
'Fecha inicial de vigencia de la temporada.';

COMMENT ON COLUMN temporada.fecha_fin IS
'Fecha final de vigencia de la temporada.';

COMMENT ON COLUMN temporada.anio IS
'Año al que pertenece la temporada.';


CREATE TABLE Tarifa (
    id_tarifa NUMBER(10) NOT NULL,
    id_habitacion NUMBER(10) NOT NULL,
    id_temporada NUMBER(10) NOT NULL,
    precio_noche NUMBER(12,2) NOT NULL,
    
    CONSTRAINT pk_tarifa PRIMARY KEY (id_tarifa),
    CONSTRAINT fk_tarifa_temporada FOREIGN KEY (id_temporada) REFERENCES Temporada(id_temporada),
    CONSTRAINT fk_tarifa_habitacion FOREIGN KEY (id_habitacion) REFERENCES Habitacion(id_habitacion),
    CONSTRAINT uq_tarifa_habitacion_temporada UNIQUE (id_habitacion, id_temporada),
    CONSTRAINT ck_tarifa_precio CHECK (precio_noche > 0)
);
COMMENT ON TABLE tarifa IS
'Tarifas por noche de cada habitación según la temporada vigente.';

COMMENT ON COLUMN tarifa.precio_noche IS
'Precio por noche de la habitación durante la temporada asociada.';


CREATE TABLE Cliente (
    id_cliente NUMBER(10) NOT NULL,
    nombre_completo VARCHAR2(150) NOT NULL,
    tipo_documento VARCHAR2(20) NOT NULL,
    numero_documento VARCHAR2(30) NOT NULL,
    correo VARCHAR2(50) NOT NULL,
    telefono VARCHAR2(20) NOT NULL,
    ciudad_origen VARCHAR2(100) NOT NULL,
    fecha_registro DATE DEFAULT SYSDATE NOT NULL,
    
    CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
    CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT uq_cliente_correo UNIQUE (correo)
);
COMMENT ON TABLE cliente IS
'Clientes que realizan reservas de alojamientos turísticos.';

COMMENT ON COLUMN cliente.numero_documento IS
'Número del documento de identidad del cliente.';

COMMENT ON COLUMN cliente.ciudad_origen IS
'Ciudad de origen del cliente.';

COMMENT ON COLUMN cliente.fecha_registro IS
'Fecha en que el cliente se registra en la plataforma.';


CREATE TABLE Reserva (
    id_reserva NUMBER(10) NOT NULL,
    id_cliente NUMBER(10) NOT NULL,
    fecha_reserva DATE DEFAULT SYSDATE NOT NULL,
    fecha_checkin DATE NOT NULL,
    fecha_checkout DATE NOT NULL,
    estado VARCHAR2(20) NOT NULL,
    
    CONSTRAINT pk_reserva PRIMARY KEY (id_reserva),
    CONSTRAINT fk_reserva_cliente FOREIGN KEY (id_cliente) REFERENCES Cliente(id_cliente),
    CONSTRAINT ck_reserva_fechas CHECK (fecha_checkout > fecha_checkin),
    CONSTRAINT ck_reserva_estado CHECK (estado IN ('PENDIENTE', 'CONFIRMADA', 'CANCELADA', 'COMPLETADA'))
);
COMMENT ON TABLE reserva IS
'Reserva realizada por un cliente, que puede incluir una o varias habitaciones y servicios.';

COMMENT ON COLUMN reserva.fecha_reserva IS
'Fecha y hora en que se registra la reserva.';

COMMENT ON COLUMN reserva.fecha_checkin IS
'Fecha general de llegada de la reserva.';

COMMENT ON COLUMN reserva.fecha_checkout IS
'Fecha general de salida de la reserva.';

COMMENT ON COLUMN reserva.estado IS
'Estado de la reserva: PENDIENTE, CONFIRMADA, CANCELADA o COMPLETADA.';


CREATE TABLE ReservaHabitacion (
    id_reserva_habitacion NUMBER(10) NOT NULL,
    id_reserva NUMBER(10) NOT NULL,
    id_habitacion NUMBER(10) NOT NULL,
    fecha_checkin DATE NOT NULL,
    fecha_checkout DATE NOT NULL,
    cantidad_huespedes NUMBER(3) NOT NULL,
    
    CONSTRAINT pk_reserva_habitacion PRIMARY KEY (id_reserva_habitacion),
    CONSTRAINT fk_reserva_hab_reserva FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva),
    CONSTRAINT fk_reserva_hab_habitacion FOREIGN KEY (id_habitacion) REFERENCES Habitacion(id_habitacion),
    CONSTRAINT ck_reserva_hab_fechas CHECK (fecha_checkout > fecha_checkin),
    CONSTRAINT ck_reserva_hab_huespedes CHECK (cantidad_huespedes > 0)
);
COMMENT ON TABLE reservahabitacion IS
'Detalle de las habitaciones incluidas en una reserva. Permite que una reserva incluya varias habitaciones con fechas particulares.';

COMMENT ON COLUMN reservahabitacion.fecha_checkin IS
'Fecha de entrada específica de esta habitación.';

COMMENT ON COLUMN reservahabitacion.fecha_checkout IS
'Fecha de salida específica de esta habitación.';

COMMENT ON COLUMN reservahabitacion.cantidad_huespedes IS
'Cantidad de huéspedes asignados a esta habitación.';


CREATE TABLE Pago (
    id_pago NUMBER(10) NOT NULL,
    id_reserva NUMBER(10) NOT NULL,
    fecha_pago DATE DEFAULT SYSDATE NOT NULL,
    monto NUMBER(12,2) NOT NULL,
    metodo_pago VARCHAR2(30) NOT NULL,
    estado VARCHAR2(20) NOT NULL,
    
    CONSTRAINT pk_pago PRIMARY KEY (id_pago),
    CONSTRAINT fk_pago_reserva FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva),
    CONSTRAINT ck_pago_monto CHECK (monto > 0),
    CONSTRAINT ck_pago_metodo CHECK (metodo_pago IN ('TARJETA_CREDITO', 'TARJETA_DEBITO', 'PSE', 'TRANSFERENCIA', 'EFECTIVO')),
    CONSTRAINT ck_pago_estado CHECK (estado IN ('EXITOSO', 'FALLIDO', 'PENDIENTE', 'REEMBOLSADO'))
);
COMMENT ON TABLE pago IS
'Pagos y abonos realizados para cubrir el valor de una reserva.';

COMMENT ON COLUMN pago.monto IS
'Valor del pago o abono.';

COMMENT ON COLUMN pago.metodo_pago IS
'Método utilizado para realizar el pago.';

COMMENT ON COLUMN pago.estado IS
'Estado del pago: EXITOSO, FALLIDO, PENDIENTE o REEMBOLSADO.';


CREATE TABLE Servicio (
    id_servicio NUMBER(10) NOT NULL,
    id_alojamiento NUMBER(10) NOT NULL,
    nombre VARCHAR2(100) NOT NULL,
    descripcion VARCHAR2(200),
    precio NUMBER(12,2) NOT NULL,
    
    CONSTRAINT pk_servicio PRIMARY KEY (id_servicio),
    CONSTRAINT fk_servicio_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento),
    CONSTRAINT uq_servicio_alojamiento_nombre UNIQUE (id_alojamiento, nombre),
    CONSTRAINT ck_servicio_precio CHECK (precio > 0)
);
COMMENT ON TABLE servicio IS
'Servicios complementarios ofrecidos por un alojamiento turístico.';

COMMENT ON COLUMN servicio.nombre IS
'Nombre del servicio complementario.';

COMMENT ON COLUMN servicio.descripcion IS
'Descripción del servicio.';

COMMENT ON COLUMN servicio.precio IS
'Precio actual por unidad del servicio.';


CREATE TABLE ReservaServicio (
    id_reserva_servicio NUMBER(10) NOT NULL,
    id_reserva NUMBER(10) NOT NULL,
    id_servicio NUMBER(10) NOT NULL,
    cantidad NUMBER(5) NOT NULL,
    precio_unitario NUMBER(12,2) NOT NULL,
    
    CONSTRAINT pk_reserva_servicio PRIMARY KEY (id_reserva_servicio),
    CONSTRAINT fk_reserva_serv_reserva FOREIGN KEY (id_reserva) REFERENCES Reserva(id_reserva),
    CONSTRAINT fk_reserva_serv_servicio FOREIGN KEY (id_servicio) REFERENCES Servicio(id_servicio),
    CONSTRAINT uq_reserva_servicio UNIQUE (id_reserva, id_servicio),
    CONSTRAINT ck_reserva_serv_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_reserva_serv_precio CHECK (precio_unitario > 0)
);
COMMENT ON TABLE reservaservicio IS
'Servicios complementarios incluidos en una reserva y cantidad solicitada de cada servicio.';

COMMENT ON COLUMN reservaservicio.cantidad IS
'Cantidad de unidades del servicio solicitadas en la reserva.';

COMMENT ON COLUMN reservaservicio.precio_unitario IS
'Precio por unidad aplicado al momento de la reserva.';


CREATE TABLE Resena (
    id_resena NUMBER(10) NOT NULL,
    id_cliente NUMBER(10) NOT NULL,
    id_alojamiento NUMBER(10) NOT NULL,
    fecha DATE DEFAULT SYSDATE NOT NULL,
    calificacion NUMBER(1) NOT NULL,
    comentario VARCHAR2(500),
    
    CONSTRAINT pk_resena PRIMARY KEY (id_resena),
    CONSTRAINT fk_resena_cliente FOREIGN KEY (id_cliente) REFERENCES Cliente(id_cliente),
    CONSTRAINT fk_resena_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento),
    CONSTRAINT ck_resena_calificacion CHECK (calificacion BETWEEN 1 AND 5)
);
COMMENT ON TABLE resena IS
'Reseñas realizadas por clientes que hayan completado una estadía en un alojamiento.';

COMMENT ON COLUMN resena.calificacion IS
'Calificación otorgada al alojamiento, entre 1 y 5 estrellas.';

COMMENT ON COLUMN resena.comentario IS
'Comentario opcional realizado por el cliente.';


CREATE TABLE UsuarioSistema (
    id_usuario NUMBER(10) NOT NULL,
    id_alojamiento NUMBER(10),
    nombre VARCHAR2(100) NOT NULL,
    correo VARCHAR2(50) NOT NULL,
    contraseña VARCHAR2 (30) NOT NULL,
    rol VARCHAR2(20) NOT NULL,
    nombre_usuario VARCHAR2(50) NOT NULL,
    fecha_creacion DATE DEFAULT SYSDATE NOT NULL,
    
    CONSTRAINT pk_usuario_sistema PRIMARY KEY (id_usuario),
    CONSTRAINT fk_usuario_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento),
    CONSTRAINT uq_usuario_correo UNIQUE (correo),
    CONSTRAINT uq_usuario_nombre UNIQUE (nombre_usuario),
    CONSTRAINT ck_usuario_rol CHECK (rol IN ('ADMINISTRADOR', 'ENCARGADO')),
    CONSTRAINT ck_usuario_alojamiento_rol CHECK ((rol = 'ADMINISTRADOR' AND id_alojamiento IS NULL)
        OR (rol = 'ENCARGADO' AND id_alojamiento IS NOT NULL))
);
COMMENT ON TABLE usuariosistema IS
'Usuarios internos de TurismoUQ, incluyendo administradores y encargados de alojamientos.';

COMMENT ON COLUMN usuariosistema.rol IS
'Rol del usuario: ADMINISTRADOR o ENCARGADO.';

COMMENT ON COLUMN usuariosistema.nombre_usuario IS
'Nombre utilizado para iniciar sesión.';

COMMENT ON COLUMN usuariosistema.id_alojamiento IS
'Alojamiento administrado por el usuario cuando su rol es ENCARGADO.';