-- Definición de tablas
CREATE TABLE Usuario (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,                        
    nombre VARCHAR(45) NOT NULL,                                      
    apellido VARCHAR(45) NOT NULL,                                    
    dni VARCHAR(10) NOT NULL UNIQUE,                                  
    email VARCHAR(255) NOT NULL UNIQUE,                               
    hashed_password VARCHAR(255) NOT NULL,                            
    telefono VARCHAR(20),                                            
    fecha_registro DATETIME DEFAULT CURRENT_TIMESTAMP                 
);

CREATE TABLE Estacion (
    id_estacion INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    capacidad INT NOT NULL,
    bicicletas_disponibles INT NOT NULL DEFAULT 0 CHECK (bicicletas_disponibles <= capacidad)
);

CREATE TABLE Bicicleta (
    id_bicicleta INT AUTO_INCREMENT PRIMARY KEY,
    estado ENUM('disponible', 'en_reparacion', 'en_viaje') NOT NULL DEFAULT 'disponible',
    id_estacion INT DEFAULT NULL,
    CONSTRAINT fk_bicicleta_estacion FOREIGN KEY (id_estacion) REFERENCES Estacion (id_estacion) ON DELETE SET NULL,
    CHECK (
        estado = 'disponible' AND id_estacion IS NOT NULL OR 
        estado = 'en_viaje' AND id_estacion IS NULL
    )
);

CREATE TABLE Viaje (
    id_viaje INT AUTO_INCREMENT PRIMARY KEY,
    id_bicicleta INT NOT NULL,
    id_usuario INT NOT NULL, 
    estacion_origen INT NOT NULL,
    estacion_destino INT DEFAULT NULL,
    tiempo_inicio DATETIME NOT NULL,
    tiempo_fin DATETIME DEFAULT NULL,
    CONSTRAINT fk_viaje_bicicleta FOREIGN KEY (id_bicicleta) REFERENCES Bicicleta (id_bicicleta),
    CONSTRAINT fk_viaje_usuario FOREIGN KEY (id_usuario) REFERENCES Usuario (id_usuario),
    CONSTRAINT fk_viaje_estacion_origen FOREIGN KEY (estacion_origen) REFERENCES Estacion (id_estacion),
    CONSTRAINT fk_viaje_estacion_destino FOREIGN KEY (estacion_destino) REFERENCES Estacion (id_estacion)
);

CREATE TABLE Pago (
    id_pago INT AUTO_INCREMENT PRIMARY KEY,                          
    id_usuario INT NOT NULL,                                          
    monto DECIMAL(10, 2) NOT NULL,                                    
    fecha_pago DATETIME NOT NULL,                                     
    metodo ENUM('tarjeta', 'efectivo', 'transferencia') NOT NULL,     
    estado ENUM('pendiente', 'completado', 'fallido') NOT NULL,       
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario)           
);

-- Restricciones y permisos
REVOKE INSERT, UPDATE, DELETE ON Viaje FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON Bicicleta FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON Estacion FROM PUBLIC;

-- Triggers 
DELIMITER $$

CREATE TRIGGER actualizar_bicicletas_disponibles_insert
AFTER INSERT ON Bicicleta
FOR EACH ROW
BEGIN
    IF NEW.estado = 'disponible' THEN
        UPDATE Estacion
        SET bicicletas_disponibles = bicicletas_disponibles + 1
        WHERE id_estacion = NEW.id_estacion;
    END IF;
END $$

CREATE TRIGGER actualizar_bicicletas_disponibles_delete
AFTER DELETE ON Bicicleta
FOR EACH ROW
BEGIN
    IF OLD.estado = 'disponible' THEN
        UPDATE Estacion
        SET bicicletas_disponibles = bicicletas_disponibles - 1
        WHERE id_estacion = OLD.id_estacion;
    END IF;
END $$

CREATE TRIGGER validar_bicicleta_en_viaje
BEFORE INSERT ON Viaje
FOR EACH ROW
BEGIN
    DECLARE estado_actual VARCHAR(20);
    DECLARE estacion_actual INT;

    SELECT estado, id_estacion INTO estado_actual, estacion_actual
    FROM Bicicleta
    WHERE id_bicicleta = NEW.id_bicicleta;

    IF estado_actual != 'disponible' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La bicicleta debe estar disponible.';
    END IF;

    IF estacion_actual != NEW.estacion_origen THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La bicicleta no está en la estación de origen.';
    END IF;

    UPDATE Bicicleta
    SET estado = 'en_viaje', id_estacion = NULL
    WHERE id_bicicleta = NEW.id_bicicleta;
END $$

-- Procedimientos almacenados 
DELIMITER $$

CREATE PROCEDURE registrar_viaje (
    IN p_id_bicicleta INT,
    IN p_id_usuario INT, 
    IN p_estacion_origen INT,
    IN p_tiempo_inicio DATETIME
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error al registrar el viaje.';
    END;

    START TRANSACTION;

    DECLARE estado_actual VARCHAR(20);
    DECLARE estacion_actual INT;

    SELECT estado, id_estacion INTO estado_actual, estacion_actual
    FROM Bicicleta
    WHERE id_bicicleta = p_id_bicicleta;

    IF estado_actual != 'disponible' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La bicicleta debe estar disponible.';
    END IF;

    IF estacion_actual != p_estacion_origen THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La bicicleta no está en la estación de origen.';
    END IF;

    UPDATE Bicicleta
    SET estado = 'en_viaje', id_estacion = NULL
    WHERE id_bicicleta = p_id_bicicleta;

    INSERT INTO Viaje (id_bicicleta, id_usuario, estacion_origen, tiempo_inicio)
    VALUES (p_id_bicicleta, p_id_usuario, p_estacion_origen, p_tiempo_inicio);

    COMMIT;
END $$

CREATE PROCEDURE registrar_retorno (
    IN p_id_viaje INT,
    IN p_id_estacion_destino INT,
    IN p_hora_fin DATETIME
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error al registrar el retorno.';
    END;

    START TRANSACTION;

    DECLARE espacio_disponible INT;

    SELECT capacidad - bicicletas_disponibles INTO espacio_disponible
    FROM Estacion
    WHERE id_estacion = p_id_estacion_destino;

    IF espacio_disponible <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La estación está llena.';
    END IF;

    UPDATE Viaje
    SET estacion_destino = p_id_estacion_destino, tiempo_fin = p_hora_fin
    WHERE id_viaje = p_id_viaje;

    UPDATE Bicicleta
    SET estado = 'disponible', id_estacion = p_id_estacion_destino
    WHERE id_bicicleta = (SELECT id_bicicleta FROM Viaje WHERE id_viaje = p_id_viaje);

    COMMIT;
END $$
DELIMITER ;


-- Permisos finales
GRANT EXECUTE ON PROCEDURE registrar_viaje TO usuario_aplicacion;
GRANT EXECUTE ON PROCEDURE registrar_retorno TO usuario_aplicacion;
GRANT ALL PRIVILEGES ON Viaje TO root;
GRANT ALL PRIVILEGES ON Bicicleta TO root;
GRANT ALL PRIVILEGES ON Estacion TO root;

-- Datos iniciales 
INSERT INTO Estacion (nombre, capacidad) VALUES ('Estacion A', 10), ('Estacion B', 8), ('Estacion C', 5);

INSERT INTO Bicicleta (estado, id_estacion) VALUES ('disponible', 1), ('disponible', 2), ('disponible', 3), ('en_reparacion', NULL), ('disponible', 1);

-- Carga inicial de viajes 
CALL registrar_viaje(1, 1, 1, '2024-11-01 08:00:00');
CALL registrar_viaje(2, 2, 2, '2024-11-01 09:00:00');
CALL registrar_viaje(3, 3, 3, '2024-11-01 10:00:00');

-- Vistas 
CREATE VIEW estaciones_mas_utilizadas AS
SELECT estacion_origen, COUNT(*) AS total_viajes
FROM Viaje
GROUP BY estacion_origen
ORDER BY total_viajes DESC
LIMIT 3;

CREATE VIEW bicicletas_mas_utilizadas AS
SELECT id_bicicleta, COUNT(*) AS total_usos
FROM Viaje
WHERE tiempo_inicio >= CURDATE() - INTERVAL 30 DAY
GROUP BY id_bicicleta
ORDER BY total_usos DESC;

CREATE VIEW viajes_largos AS
SELECT id_viaje, id_bicicleta, estacion_origen, estacion_destino,
       TIMESTAMPDIFF(MINUTE, tiempo_inicio, tiempo_fin) AS duracion
FROM Viaje
WHERE TIMESTAMPDIFF(MINUTE, tiempo_inicio, tiempo_fin) > 30;
