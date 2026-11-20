-- Ejecutar en el portal: SQL database > Query editor (SQL authentication).
-- Usuario y password: az keyvault secret show --vault-name <kv> -n db-user / db-password --query value -o tsv
-- Carabayllo 5: 2 torres / 120 dptos. El resto son valores de ejemplo: reemplazalos por los reales.
IF OBJECT_ID('dbo.proyectos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.proyectos (
        codigo        VARCHAR(10)   NOT NULL PRIMARY KEY,
        nombre        NVARCHAR(100) NOT NULL,
        empresa       NVARCHAR(100) NOT NULL,
        torres        INT           NULL,
        departamentos INT           NULL,
        estado        NVARCHAR(30)  NULL
    );
END;

MERGE dbo.proyectos AS t
USING (VALUES
    ('P001', N'Sunny Park',   N'Constructora Padova', 1, 80,  N'En obra'),
    ('P002', N'Carabayllo 5', N'Padova SAC',          2, 120, N'Preventa'),
    ('P003', N'Litoral 900',  N'Mirano',              1, 60,  N'Entregado')
) AS s (codigo, nombre, empresa, torres, departamentos, estado)
ON t.codigo = s.codigo
WHEN NOT MATCHED THEN
    INSERT (codigo, nombre, empresa, torres, departamentos, estado)
    VALUES (s.codigo, s.nombre, s.empresa, s.torres, s.departamentos, s.estado);

SELECT * FROM dbo.proyectos ORDER BY codigo;
