CREATE TABLE municipios(
id_municipio INT PRIMARY KEY,
nome VARCHAR NOT NULL,
uf CHAR(2) NOT NULL
);


CREATE TABLE aerodromos(
id_aerodromo INT PRIMARY KEY,
ciad VARCHAR NOT NULL,
codigo_oaci VARCHAR NOT NULL,
tipo_uso VARCHAR NOT NULL CHECK(tipo_uso IN("Público", "Privado")),
nome VARCHAR NOT NULL,
municipio_localizado VARCHAR NOT NULL,
municipio_servido VARCHAR NOT NULL,
id_pista INT NOT NULL,
FOREIGN KEY (id_pista) REFERENCES aerodromos(id_pistas),
FOREIGN KEY (municipio_localizado) REFERENCES municipios(id_municipio),
FOREIGN KEY (municipio_servido) REFERENCES municipios(id_municipio)
);

CREATE TABLE pistas(
id_pista INT PRIMARY KEY,
deisgnacao NOT NULL,
pista_largura_m NUMERIC NOT NULL,
pista_resistencia_kg NUMERIC NOT NULL, 
pista_resistencia_mpa NUMERIC NOT NULL, 
pista_resistencia_pcn VARCHAR NOT NULL,
pista_superficie VARCHAR NOT NULL,
pista1_luzes_eixo BOOLEAN NOT NULL,
pista1_luzes_borda BOOLEAN NOT NULL
FOREIGN KEY (id_aerodromo) REFERENCES aerodromos(id_aerodromos)
);

CREATE TABLE cadastro(
id_aerodromo INT NOT NULL,
situacao VARCHAR NOT NULL CHECK(situacao IN("Autorizado", "Cadastrado", "Interditado")),
validade_cadastro DATE NOT NULL,
link_portaria_cadastro NOT NULL,
FOREIGN KEY (id_aerodromo) REFERENCES aerodromos(id_aerodromos)
);