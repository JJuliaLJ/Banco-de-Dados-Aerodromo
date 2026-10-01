CREATE TABLE aerodromos(
id_aerodromo INT PRIMARY KEY,
ciad VARCHAR NOT NULL,
codigo_oaci VARCHAR NOT NULL,
tipo_uso VARCHAR NOT NULL CHECK(tipo_uso IN("Público", "Privado")),
nome VARCHAR NOT NULL,
municipio VARCHAR NOT NULL,
uf VARCHAR NOT NULL,
);

CREATE TABLE pistas(
id_pista INT PRIMARY KEY,
deisgnacao NOT NULL,
pista_largura_m NUMERIC NOT NULL,
pista_resistencia_kg NUMERIC NOT NULL, 
pista_resistencia_mpa NUMERIC NOT NULL, 
pista_resistencia_pcn VARCHAR NOT NULL,
pista_superficie VARCHAR NOT NULL CHECK (pista_superficie IN())
pista1_luzes_eixo boolean
pista1_luzes_borda: boolean

);