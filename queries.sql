-- 1) Mostrar usuarios (nombre, apellido, dni) que a lo largo del mes en curso
-- hicieron más de 10 viajes/alquileres partiendo siempre y únicamente de la misma estación.

SELECT u.nombre, u.apellido, u.dni
FROM Usuario u
JOIN Viaje v ON u.id_usuario = v.id_usuario
WHERE MONTH(v.tiempo_inicio) = MONTH(CURRENT_DATE())
  AND YEAR(v.tiempo_inicio) = YEAR(CURRENT_DATE())
GROUP BY u.id_usuario, v.estacion_origen
HAVING COUNT(*) > 10
   AND COUNT(DISTINCT v.estacion_origen) = 1;


-- 2) Mostrar bicicletas que han pasado por TODAS las estaciones
-- sea como origen o destino del viaje.

SELECT b.id_bicicleta
FROM Bicicleta b
JOIN Viaje v ON b.id_bicicleta = v.id_bicicleta
JOIN Estacion e
    ON e.id_estacion IN (v.estacion_origen, v.estacion_destino)
GROUP BY b.id_bicicleta
HAVING COUNT(DISTINCT e.id_estacion) =
(
    SELECT COUNT(*)
    FROM Estacion
);


-- 3) Mostrar todos los viajes del año en curso que involucran bicicletas nuevas
-- (sin viajes anteriores) y usuarios con más de 15 alquileres realizados.

SELECT v.*
FROM Viaje v
JOIN Bicicleta b ON v.id_bicicleta = b.id_bicicleta
JOIN Usuario u ON v.id_usuario = u.id_usuario
WHERE YEAR(v.tiempo_inicio) = YEAR(CURRENT_DATE())
  AND NOT EXISTS
(
    SELECT 1
    FROM Viaje
    WHERE Viaje.id_bicicleta = b.id_bicicleta
      AND Viaje.tiempo_inicio < v.tiempo_inicio
)
AND
(
    SELECT COUNT(*)
    FROM Viaje
    WHERE Viaje.id_usuario = u.id_usuario
) > 15;