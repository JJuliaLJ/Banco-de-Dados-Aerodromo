-- =============================================================================
-- Aerodromos da Regiao Norte (ANAC) - Script de criacao (DDL)
-- PostgreSQL
--
-- Fonte: anac_aerodromos_norte.csv (809 aerodromos, 34 colunas)
--
-- Equipe:
--   - Pedro Andrade Gonçalves de Souza
--   - Julia Labad Jatene
--   - Luan Piedade de Oliveira
--   - Jõao Paulo Oliveira Rodrigues
--
-- Modelo normalizado ate a 3a Forma Normal. Nenhuma informacao do CSV e
-- descartada: cada coluna da planilha original esta mapeada em exatamente um
-- atributo ou em uma tabela de relacionamento, conforme os comentarios
-- COMMENT ON de rastreabilidade ao final de cada bloco.
--
-- Ordem de execucao: este script primeiro, depois o script de carga.
-- =============================================================================

-- Execucao idempotente: permite reprocessar o script sem recriar o banco.
DROP TABLE IF EXISTS aerodromo_restricao          CASCADE;
DROP TABLE IF EXISTS aerodromo_categoria_operacao CASCADE;
DROP TABLE IF EXISTS aerodromo_rbac               CASCADE;
DROP TABLE IF EXISTS aerodromo_operacao           CASCADE;
DROP TABLE IF EXISTS pista                        CASCADE;
DROP TABLE IF EXISTS aerodromo                    CASCADE;
DROP TABLE IF EXISTS restricao                    CASCADE;
DROP TABLE IF EXISTS categoria_operacao           CASCADE;
DROP TABLE IF EXISTS perfil_operacional           CASCADE;
DROP TABLE IF EXISTS tipo_operacao                CASCADE;
DROP TABLE IF EXISTS superficie_pista             CASCADE;
DROP TABLE IF EXISTS municipio                    CASCADE;
DROP TABLE IF EXISTS estado                       CASCADE;


-- =============================================================================
-- 1. LOCALIZACAO
-- =============================================================================

-- O CSV traz dois pares de localizacao: (municipio, uf) = onde o aerodromo
-- esta fisicamente, e (municipio_servido, uf_servido) = qual municipio ele
-- atende. Os 71 municipios servidos sao todos subconjunto dos 242 municipios
-- de localizacao, portanto uma unica tabela 'municipio' atende aos dois papeis
-- e evita duplicacao: a distincao de papel fica nas duas chaves estrangeiras
-- da tabela 'aerodromo', nao em duas tabelas separadas.

CREATE TABLE estado (
    sigla   CHAR(2)     NOT NULL,
    nome    VARCHAR(30) NOT NULL,

    CONSTRAINT pk_estado         PRIMARY KEY (sigla),
    CONSTRAINT uq_estado_nome    UNIQUE (nome),
    CONSTRAINT ck_estado_sigla   CHECK (sigla ~ '^[A-Z]{2}$')
);

COMMENT ON TABLE  estado IS 'Unidades federativas da Regiao Norte. Dominio das colunas uf e uf_servido do CSV.';
COMMENT ON COLUMN estado.sigla IS 'Origem: colunas uf / uf_servido.';


CREATE TABLE municipio (
    id_municipio SERIAL      NOT NULL,
    nome         VARCHAR(60) NOT NULL,
    uf           CHAR(2)     NOT NULL,

    CONSTRAINT pk_municipio      PRIMARY KEY (id_municipio),
    CONSTRAINT fk_municipio_uf   FOREIGN KEY (uf) REFERENCES estado (sigla)
                                 ON UPDATE CASCADE ON DELETE RESTRICT,
    -- Chave natural. Nenhum nome de municipio se repete entre UFs diferentes
    -- neste recorte, mas o par (nome, uf) e a identificacao correta e o
    -- UNIQUE garante que a carga nao insira o mesmo municipio duas vezes.
    CONSTRAINT uq_municipio_nome_uf UNIQUE (nome, uf),
    CONSTRAINT ck_municipio_nome    CHECK (btrim(nome) <> '')
);

CREATE INDEX ix_municipio_uf ON municipio (uf);

COMMENT ON TABLE  municipio IS 'Municipios da Regiao Norte, usados tanto como local do aerodromo quanto como municipio servido.';
COMMENT ON COLUMN municipio.nome IS 'Origem: colunas municipio / municipio_servido. Gravado em caixa alta sem acento padronizado pela carga, pois o CSV grafa o mesmo municipio em caixa alta na coluna de localizacao e capitalizado na coluna de municipio servido.';


-- =============================================================================
-- 2. TABELAS DE DOMINIO
-- =============================================================================
-- Valores de texto que se repetem em muitas linhas do CSV foram extraidos para
-- tabelas proprias. Isso elimina a dependencia transitiva (o texto descritivo
-- passa a depender da chave da tabela de dominio, nao da chave do aerodromo ou
-- da pista) e e o que leva o modelo a 3FN. Codigos curtos e autoexplicativos
-- (classe_rbac153, classe_rbac107) ficaram como CHECK, pois nao carregam
-- atributo descritivo proprio que justifique uma tabela.

CREATE TABLE superficie_pista (
    id_superficie SERIAL      NOT NULL,
    descricao     VARCHAR(20) NOT NULL,

    CONSTRAINT pk_superficie_pista PRIMARY KEY (id_superficie),
    CONSTRAINT uq_superficie_desc  UNIQUE (descricao)
);

COMMENT ON TABLE superficie_pista IS 'Tipos de superficie de pista (9 valores distintos). Origem: coluna pista1_superficie.';


CREATE TABLE tipo_operacao (
    id_tipo_operacao SERIAL      NOT NULL,
    sigla            VARCHAR(15) NOT NULL,

    CONSTRAINT pk_tipo_operacao PRIMARY KEY (id_tipo_operacao),
    CONSTRAINT uq_tipo_operacao UNIQUE (sigla)
);

COMMENT ON TABLE tipo_operacao IS 'Regras de voo: VFR, IFR e Sem Operacao. Origem: valores atomicos extraidos de operacao_diurna e operacao_noturna.';


CREATE TABLE perfil_operacional (
    id_perfil SERIAL      NOT NULL,
    descricao VARCHAR(30) NOT NULL,

    CONSTRAINT pk_perfil_operacional PRIMARY KEY (id_perfil),
    CONSTRAINT uq_perfil_operacional UNIQUE (descricao)
);

COMMENT ON TABLE perfil_operacional IS 'Perfil operacional RBAC 153 (3 valores distintos). Origem: coluna perfil_operacional_rbac153.';


CREATE TABLE categoria_operacao (
    id_categoria SERIAL       NOT NULL,
    descricao    VARCHAR(100) NOT NULL,

    CONSTRAINT pk_categoria_operacao PRIMARY KEY (id_categoria),
    CONSTRAINT uq_categoria_operacao UNIQUE (descricao)
);

COMMENT ON TABLE categoria_operacao IS 'Categorias de operacao autorizada. Origem: coluna operacao_internacional do CSV, que apesar do nome nao guarda um booleano, mas de uma a duas categorias de operacao separadas por " / " (ex.: "Publico Taxi Aereo e Aviacao Geral (RNS)").';


CREATE TABLE restricao (
    id_restricao SERIAL NOT NULL,
    descricao    TEXT   NOT NULL,

    CONSTRAINT pk_restricao PRIMARY KEY (id_restricao),
    CONSTRAINT uq_restricao UNIQUE (descricao),
    CONSTRAINT ck_restricao_desc CHECK (btrim(descricao) <> '')
);

COMMENT ON TABLE restricao IS 'Textos de restricao operacional. 19 aerodromos possuem restricao, mas apenas 9 textos distintos: extrair para tabela propria evita repetir o mesmo texto longo em varias linhas. Origem: coluna restricao.';


-- =============================================================================
-- 3. ENTIDADE CENTRAL
-- =============================================================================

CREATE TABLE aerodromo (
    -- Identificador proprio da ANAC, preservado do CSV (nao e SERIAL para que
    -- as chaves do banco correspondam exatamente as da planilha de origem).
    id_aerodromo             INTEGER       NOT NULL,
    ciad                     CHAR(6)       NOT NULL,
    codigo_oaci              CHAR(4)       NULL,
    nome                     VARCHAR(100)  NOT NULL,
    -- 3 dos 809 registros nao informam tipo de uso, por isso a coluna admite
    -- NULL; o CHECK restringe os valores efetivamente preenchidos.
    tipo_uso                 VARCHAR(10)   NULL,
    id_municipio             INTEGER       NOT NULL,
    -- Apenas 77 aerodromos declaram municipio servido: relacionamento opcional.
    id_municipio_servido     INTEGER       NULL,
    latitude                 NUMERIC(9,6)  NOT NULL,
    longitude                NUMERIC(9,6)  NOT NULL,
    altitude_m               NUMERIC(6,1)  NULL,
    situacao                 VARCHAR(15)   NOT NULL,
    certificacao_operacional BOOLEAN       NOT NULL,
    amazonia_legal           BOOLEAN       NOT NULL,
    validade_cadastro        DATE          NULL,
    link_portaria_cadastro   VARCHAR(255)  NULL,

    CONSTRAINT pk_aerodromo      PRIMARY KEY (id_aerodromo),
    CONSTRAINT uq_aerodromo_ciad UNIQUE (ciad),
    -- 476 dos 809 aerodromos possuem codigo OACI e todos sao distintos.
    -- UNIQUE no PostgreSQL nao bloqueia multiplos NULL, o que e exatamente o
    -- comportamento desejado para os 333 aerodromos sem codigo.
    CONSTRAINT uq_aerodromo_oaci UNIQUE (codigo_oaci),

    CONSTRAINT fk_aerodromo_municipio
        FOREIGN KEY (id_municipio) REFERENCES municipio (id_municipio)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_aerodromo_municipio_servido
        FOREIGN KEY (id_municipio_servido) REFERENCES municipio (id_municipio)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT ck_aerodromo_ciad      CHECK (ciad ~ '^[A-Z]{2}[0-9]{4}$'),
    CONSTRAINT ck_aerodromo_oaci      CHECK (codigo_oaci ~ '^[A-Z0-9]{4}$'),
    CONSTRAINT ck_aerodromo_nome      CHECK (btrim(nome) <> ''),
    CONSTRAINT ck_aerodromo_tipo_uso  CHECK (tipo_uso IN ('Público', 'Privado')),
    CONSTRAINT ck_aerodromo_situacao  CHECK (situacao IN ('Cadastrado', 'Autorizado', 'Interditado')),
    CONSTRAINT ck_aerodromo_latitude  CHECK (latitude  BETWEEN -90  AND 90),
    CONSTRAINT ck_aerodromo_longitude CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_aerodromo_altitude  CHECK (altitude_m >= 0),
    CONSTRAINT ck_aerodromo_validade  CHECK (validade_cadastro >= DATE '2000-01-01'),
    CONSTRAINT ck_aerodromo_link      CHECK (link_portaria_cadastro ~ '^https?://')
);

CREATE INDEX ix_aerodromo_municipio         ON aerodromo (id_municipio);
CREATE INDEX ix_aerodromo_municipio_servido ON aerodromo (id_municipio_servido);
CREATE INDEX ix_aerodromo_situacao          ON aerodromo (situacao);
CREATE INDEX ix_aerodromo_tipo_uso          ON aerodromo (tipo_uso);
CREATE INDEX ix_aerodromo_nome              ON aerodromo (nome);
CREATE INDEX ix_aerodromo_validade          ON aerodromo (validade_cadastro);

COMMENT ON TABLE  aerodromo IS 'Entidade central: um registro por aerodromo cadastrado (809 no total).';
COMMENT ON COLUMN aerodromo.id_aerodromo IS 'Origem: coluna id_aerodromo.';
COMMENT ON COLUMN aerodromo.id_municipio IS 'Origem: colunas municipio + uf (municipio onde o aerodromo esta localizado).';
COMMENT ON COLUMN aerodromo.id_municipio_servido IS 'Origem: colunas municipio_servido + uf_servido (municipio atendido pelo aerodromo).';
COMMENT ON COLUMN aerodromo.validade_cadastro IS 'Origem: coluna validade_cadastro. Atributo monovalorado do proprio aerodromo, dependente apenas da chave primaria, por isso permanece nesta tabela e nao em uma tabela de cadastro separada.';


-- =============================================================================
-- 4. PISTA
-- =============================================================================
-- As colunas pista1_* descrevem uma entidade distinta do aerodromo e por isso
-- formam uma tabela propria. Neste recorte cada aerodromo tem no maximo uma
-- pista e 156 dos 809 nao tem nenhuma, mas o relacionamento e modelado como
-- 1:N (a chave primaria e a pista, e nao o aerodromo), de modo que um segundo
-- registro de pista para o mesmo aerodromo nao exige alteracao de estrutura.

CREATE TABLE pista (
    -- Identificador proprio da pista no cadastro da ANAC, preservado do CSV.
    id_pista        INTEGER      NOT NULL,
    id_aerodromo    INTEGER      NOT NULL,
    designacao      VARCHAR(7)   NOT NULL,
    comprimento_m   NUMERIC(6,1) NOT NULL,
    largura_m       NUMERIC(4,1) NOT NULL,
    id_superficie   INTEGER      NOT NULL,
    -- A resistencia e informada de duas formas mutuamente exclusivas no CSV:
    -- 530 pistas trazem o par (kg, MPa) e 123 trazem a notacao PCN.
    resistencia_kg  NUMERIC(7,1) NULL,
    resistencia_mpa NUMERIC(5,2) NULL,
    resistencia_pcn VARCHAR(15)  NULL,
    luzes_eixo      BOOLEAN      NULL,
    luzes_borda     BOOLEAN      NULL,

    CONSTRAINT pk_pista PRIMARY KEY (id_pista),
    CONSTRAINT fk_pista_aerodromo
        FOREIGN KEY (id_aerodromo) REFERENCES aerodromo (id_aerodromo)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_pista_superficie
        FOREIGN KEY (id_superficie) REFERENCES superficie_pista (id_superficie)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    -- Permite varias pistas por aerodromo, mas nunca a mesma designacao
    -- repetida no mesmo aerodromo.
    CONSTRAINT uq_pista_aerodromo_designacao UNIQUE (id_aerodromo, designacao),

    CONSTRAINT ck_pista_designacao  CHECK (designacao ~ '^[0-9]{2}/[0-9]{2}$'),
    CONSTRAINT ck_pista_comprimento CHECK (comprimento_m > 0),
    CONSTRAINT ck_pista_largura     CHECK (largura_m > 0),
    CONSTRAINT ck_pista_resist_kg   CHECK (resistencia_kg  > 0),
    CONSTRAINT ck_pista_resist_mpa  CHECK (resistencia_mpa > 0),
    -- Garante a exclusividade observada nos dados: ou o par (kg, MPa), ou PCN,
    -- e exatamente uma das duas formas sempre esta presente.
    CONSTRAINT ck_pista_resistencia CHECK (
        (resistencia_kg IS NOT NULL AND resistencia_mpa IS NOT NULL AND resistencia_pcn IS     NULL)
     OR (resistencia_kg IS     NULL AND resistencia_mpa IS     NULL AND resistencia_pcn IS NOT NULL)
    )
);

CREATE INDEX ix_pista_aerodromo   ON pista (id_aerodromo);
CREATE INDEX ix_pista_superficie  ON pista (id_superficie);
CREATE INDEX ix_pista_comprimento ON pista (comprimento_m);

COMMENT ON TABLE  pista IS 'Pistas de pouso e decolagem (653 registros). Origem: colunas pista1_* do CSV.';
COMMENT ON COLUMN pista.designacao IS 'Origem: coluna pista1_designacao. Formato cabeceira/cabeceira oposta, ex.: 06/24.';
COMMENT ON COLUMN pista.resistencia_pcn IS 'Origem: coluna pista1_resistencia_pcn. Codigo PCN composto (ex.: 78/F/D/X/T) mantido integro por ser identificador tecnico padronizado da OACI, nao uma lista de valores independentes.';


-- =============================================================================
-- 5. OPERACAO POR PERIODO  (coluna multivalorada)
-- =============================================================================
-- operacao_diurna e operacao_noturna guardam ate dois valores na mesma celula,
-- separados por " / " (ex.: "VFR / IFR"). Celula multivalorada viola a 1FN,
-- logo os valores sao decompostos em uma linha por par (periodo, regra de voo).
-- Uma unica tabela de relacionamento atende as duas colunas, com o periodo
-- como parte da chave primaria.

CREATE TABLE aerodromo_operacao (
    id_aerodromo     INTEGER     NOT NULL,
    periodo          VARCHAR(7)  NOT NULL,
    id_tipo_operacao INTEGER     NOT NULL,

    CONSTRAINT pk_aerodromo_operacao PRIMARY KEY (id_aerodromo, periodo, id_tipo_operacao),
    CONSTRAINT fk_aerodromo_operacao_aerodromo
        FOREIGN KEY (id_aerodromo) REFERENCES aerodromo (id_aerodromo)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_aerodromo_operacao_tipo
        FOREIGN KEY (id_tipo_operacao) REFERENCES tipo_operacao (id_tipo_operacao)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_aerodromo_operacao_periodo CHECK (periodo IN ('Diurno', 'Noturno'))
);

CREATE INDEX ix_aerodromo_operacao_tipo    ON aerodromo_operacao (id_tipo_operacao);
CREATE INDEX ix_aerodromo_operacao_periodo ON aerodromo_operacao (periodo);

COMMENT ON TABLE  aerodromo_operacao IS 'Regras de voo autorizadas por periodo. Origem: colunas multivaloradas operacao_diurna e operacao_noturna, decompostas em valores atomicos.';
COMMENT ON COLUMN aerodromo_operacao.periodo IS 'Diurno = coluna operacao_diurna; Noturno = coluna operacao_noturna.';


-- =============================================================================
-- 6. CLASSIFICACAO REGULATORIA
-- =============================================================================
-- classe_rbac153, perfil_operacional_rbac153, classe_rbac107 e
-- operacao_internacional estao preenchidas em apenas 71 dos 809 aerodromos, e
-- sempre em conjunto. Mante-las em 'aerodromo' deixaria 738 linhas com quatro
-- colunas nulas; em tabela 1:1 opcional existem somente os 71 registros que
-- de fato possuem classificacao.

CREATE TABLE aerodromo_rbac (
    id_aerodromo   INTEGER  NOT NULL,
    classe_rbac153 SMALLINT NOT NULL,
    classe_rbac107 CHAR(4)  NOT NULL,
    -- 55 dos 71 classificados informam perfil operacional.
    id_perfil      INTEGER  NULL,

    CONSTRAINT pk_aerodromo_rbac PRIMARY KEY (id_aerodromo),
    CONSTRAINT fk_aerodromo_rbac_aerodromo
        FOREIGN KEY (id_aerodromo) REFERENCES aerodromo (id_aerodromo)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_aerodromo_rbac_perfil
        FOREIGN KEY (id_perfil) REFERENCES perfil_operacional (id_perfil)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT ck_aerodromo_rbac153 CHECK (classe_rbac153 IN (1, 2, 3)),
    CONSTRAINT ck_aerodromo_rbac107 CHECK (classe_rbac107 IN ('AP-0', 'AP-1', 'AP-2'))
);

CREATE INDEX ix_aerodromo_rbac_perfil ON aerodromo_rbac (id_perfil);
CREATE INDEX ix_aerodromo_rbac_153    ON aerodromo_rbac (classe_rbac153);

COMMENT ON TABLE aerodromo_rbac IS 'Classificacao regulatoria RBAC 153 e RBAC 107 (71 registros). Relacionamento 1:1 opcional com aerodromo.';


-- Segunda coluna multivalorada: operacao_internacional pode trazer duas
-- categorias separadas por " / ". A chave estrangeira aponta para
-- aerodromo_rbac, e nao para aerodromo, porque nos dados toda categoria de
-- operacao pertence a um aerodromo que possui classificacao regulatoria.
CREATE TABLE aerodromo_categoria_operacao (
    id_aerodromo INTEGER NOT NULL,
    id_categoria INTEGER NOT NULL,

    CONSTRAINT pk_aerodromo_categoria PRIMARY KEY (id_aerodromo, id_categoria),
    CONSTRAINT fk_aerodromo_categoria_rbac
        FOREIGN KEY (id_aerodromo) REFERENCES aerodromo_rbac (id_aerodromo)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_aerodromo_categoria_categoria
        FOREIGN KEY (id_categoria) REFERENCES categoria_operacao (id_categoria)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE INDEX ix_aerodromo_categoria_categoria ON aerodromo_categoria_operacao (id_categoria);

COMMENT ON TABLE aerodromo_categoria_operacao IS 'Categorias de operacao autorizadas por aerodromo. Origem: coluna multivalorada operacao_internacional, decomposta pelo separador " / ".';


-- =============================================================================
-- 7. RESTRICOES OPERACIONAIS
-- =============================================================================
-- Relacionamento N:N com a tabela de dominio 'restricao'. Nos dados atuais
-- cada aerodromo restrito tem um unico texto de restricao, mas alguns textos
-- agregam mais de uma proibicao na mesma celula; a tabela de relacionamento
-- permite registrar restricoes adicionais sem alterar a estrutura.

CREATE TABLE aerodromo_restricao (
    id_aerodromo INTEGER NOT NULL,
    id_restricao INTEGER NOT NULL,

    CONSTRAINT pk_aerodromo_restricao PRIMARY KEY (id_aerodromo, id_restricao),
    CONSTRAINT fk_aerodromo_restricao_aerodromo
        FOREIGN KEY (id_aerodromo) REFERENCES aerodromo (id_aerodromo)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_aerodromo_restricao_restricao
        FOREIGN KEY (id_restricao) REFERENCES restricao (id_restricao)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE INDEX ix_aerodromo_restricao_restricao ON aerodromo_restricao (id_restricao);

COMMENT ON TABLE aerodromo_restricao IS 'Restricoes operacionais vigentes por aerodromo (19 registros). Origem: coluna restricao.';
