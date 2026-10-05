-- =============================================================================
-- Aerodromos da Regiao Norte (ANAC) - Consultas de exemplo
-- PostgreSQL
--
-- Equipe:
--   - Pedro Andrade Gonçalves de Souza
--   - Julia Labad Jatene
--   - Luan Piedade de Oliveira
--   - Jõao Paulo Oliveira Rodrigues
--
-- Este arquivo nao faz parte da carga. Serve de estudo para a apresentacao:
-- cobre os padroes de JOIN que qualquer pergunta sobre este banco vai exigir.
--
-- Os cinco padroes que resolvem praticamente qualquer pergunta:
--   1. aerodromo -> municipio -> estado           (localizacao)
--   2. aerodromo -> pista -> superficie_pista     (caracteristicas da pista)
--   3. aerodromo -> aerodromo_operacao -> tipo_operacao   (regras de voo)
--   4. aerodromo -> aerodromo_rbac -> perfil_operacional  (regulatorio)
--   5. aerodromo -> aerodromo_restricao -> restricao      (restricoes)
--
-- Regra de bolso: se a pergunta fala de UF, municipio, pista, operacao,
-- classe RBAC ou restricao, e JOIN. Se fala de nome, CIAD, OACI, situacao,
-- coordenada, altitude ou validade, esta tudo em 'aerodromo', sem JOIN.
--
-- Atencao: use LEFT JOIN para pista, aerodromo_rbac e aerodromo_restricao.
-- 156 aerodromos nao tem pista, 738 nao tem classificacao regulatoria e 790
-- nao tem restricao; com INNER JOIN eles desaparecem silenciosamente do
-- resultado e a contagem sai errada.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Quantos aerodromos por UF, separados por tipo de uso
--    Padrao: localizacao + agregacao com filtro condicional
-- -----------------------------------------------------------------------------
SELECT e.nome AS estado,
       count(*)                                           AS total,
       count(*) FILTER (WHERE a.tipo_uso = 'Público')     AS publicos,
       count(*) FILTER (WHERE a.tipo_uso = 'Privado')     AS privados,
       count(*) FILTER (WHERE a.tipo_uso IS NULL)         AS sem_informacao
FROM aerodromo a
JOIN municipio m ON m.id_municipio = a.id_municipio
JOIN estado    e ON e.sigla        = m.uf
GROUP BY e.nome
ORDER BY total DESC;


-- -----------------------------------------------------------------------------
-- 2. A pista mais longa de cada UF
--    Padrao: DISTINCT ON do PostgreSQL resolve "o maior de cada grupo" sem
--    subconsulta correlacionada
-- -----------------------------------------------------------------------------
SELECT DISTINCT ON (m.uf)
       m.uf,
       a.nome          AS aerodromo,
       m.nome          AS municipio,
       p.designacao,
       p.comprimento_m,
       s.descricao     AS superficie
FROM pista p
JOIN aerodromo        a ON a.id_aerodromo  = p.id_aerodromo
JOIN municipio        m ON m.id_municipio  = a.id_municipio
JOIN superficie_pista s ON s.id_superficie = p.id_superficie
ORDER BY m.uf, p.comprimento_m DESC;


-- -----------------------------------------------------------------------------
-- 3. Aerodromos que operam IFR a noite
--    Padrao: filtro na tabela de relacionamento de coluna multivalorada
-- -----------------------------------------------------------------------------
SELECT a.ciad, a.codigo_oaci, a.nome, m.nome AS municipio, m.uf
FROM aerodromo a
JOIN aerodromo_operacao ao ON ao.id_aerodromo     = a.id_aerodromo
JOIN tipo_operacao      t  ON t.id_tipo_operacao  = ao.id_tipo_operacao
JOIN municipio          m  ON m.id_municipio      = a.id_municipio
WHERE ao.periodo = 'Noturno'
  AND t.sigla    = 'IFR'
ORDER BY m.uf, a.nome;


-- -----------------------------------------------------------------------------
-- 4. Aerodromos homologados para IFR tanto de dia quanto de noite
--    Padrao: exigir duas linhas distintas da mesma tabela de relacionamento.
--    GROUP BY + HAVING count = 2 e mais legivel que dois EXISTS.
-- -----------------------------------------------------------------------------
SELECT a.ciad, a.nome, m.nome AS municipio, m.uf
FROM aerodromo a
JOIN aerodromo_operacao ao ON ao.id_aerodromo    = a.id_aerodromo
JOIN tipo_operacao      t  ON t.id_tipo_operacao = ao.id_tipo_operacao
JOIN municipio          m  ON m.id_municipio     = a.id_municipio
WHERE t.sigla = 'IFR'
GROUP BY a.id_aerodromo, a.ciad, a.nome, m.nome, m.uf
HAVING count(DISTINCT ao.periodo) = 2
ORDER BY m.uf, a.nome;


-- -----------------------------------------------------------------------------
-- 5. Municipios servidos por mais de um aerodromo
--    Padrao: usa a SEGUNDA chave estrangeira de localizacao
-- -----------------------------------------------------------------------------
SELECT m.nome AS municipio_servido,
       m.uf,
       count(*)                      AS qtd_aerodromos,
       string_agg(a.nome, ', ' ORDER BY a.nome) AS aerodromos
FROM aerodromo a
JOIN municipio m ON m.id_municipio = a.id_municipio_servido
GROUP BY m.id_municipio, m.nome, m.uf
HAVING count(*) > 1
ORDER BY qtd_aerodromos DESC, m.nome;


-- -----------------------------------------------------------------------------
-- 6. Aerodromos que atendem um municipio diferente daquele onde estao
--    Padrao: dois JOIN na MESMA tabela, com aliases distintos. E a consulta
--    que prova por que a modelagem usa uma tabela de municipio so.
-- -----------------------------------------------------------------------------
SELECT a.ciad,
       a.nome                       AS aerodromo,
       loc.nome || ' / ' || loc.uf  AS localizado_em,
       srv.nome || ' / ' || srv.uf  AS serve_a
FROM aerodromo a
JOIN municipio loc ON loc.id_municipio = a.id_municipio
JOIN municipio srv ON srv.id_municipio = a.id_municipio_servido
WHERE a.id_municipio <> a.id_municipio_servido
ORDER BY loc.uf, a.nome;


-- -----------------------------------------------------------------------------
-- 7. Cadastros vencidos e a vencer nos proximos 12 meses
--    Padrao: aritmetica de data, tudo na tabela central
-- -----------------------------------------------------------------------------
SELECT a.ciad, a.nome, m.nome AS municipio, m.uf,
       a.situacao,
       a.validade_cadastro,
       a.validade_cadastro - CURRENT_DATE AS dias_restantes,
       CASE WHEN a.validade_cadastro < CURRENT_DATE THEN 'VENCIDO'
            ELSE 'A VENCER' END           AS status
FROM aerodromo a
JOIN municipio m ON m.id_municipio = a.id_municipio
WHERE a.validade_cadastro < CURRENT_DATE + INTERVAL '12 months'
ORDER BY a.validade_cadastro;


-- -----------------------------------------------------------------------------
-- 8. Aerodromos interditados ou restritos, com o texto da restricao
--    Padrao: LEFT JOIN em relacionamento opcional
-- -----------------------------------------------------------------------------
SELECT a.ciad, a.nome, m.nome AS municipio, m.uf,
       a.situacao,
       r.descricao AS restricao
FROM aerodromo a
JOIN      municipio           m  ON m.id_municipio = a.id_municipio
LEFT JOIN aerodromo_restricao ar ON ar.id_aerodromo = a.id_aerodromo
LEFT JOIN restricao           r  ON r.id_restricao  = ar.id_restricao
WHERE a.situacao = 'Interditado'
   OR r.id_restricao IS NOT NULL
ORDER BY a.situacao, m.uf, a.nome;


-- -----------------------------------------------------------------------------
-- 9. Perfil das pistas por tipo de superficie
--    Padrao: agregacao sobre a tabela de dominio
-- -----------------------------------------------------------------------------
SELECT s.descricao                        AS superficie,
       count(*)                           AS qtd_pistas,
       round(avg(p.comprimento_m))        AS comprimento_medio_m,
       min(p.comprimento_m)               AS menor_m,
       max(p.comprimento_m)               AS maior_m,
       round(avg(p.largura_m), 1)         AS largura_media_m
FROM pista p
JOIN superficie_pista s ON s.id_superficie = p.id_superficie
GROUP BY s.descricao
ORDER BY qtd_pistas DESC;


-- -----------------------------------------------------------------------------
-- 10. Aerodromos sem pista cadastrada
--     Padrao: LEFT JOIN + IS NULL para achar ausencia. 156 registros.
-- -----------------------------------------------------------------------------
SELECT a.ciad, a.nome, m.nome AS municipio, m.uf, a.situacao, a.tipo_uso
FROM aerodromo a
JOIN      municipio m ON m.id_municipio = a.id_municipio
LEFT JOIN pista     p ON p.id_aerodromo = a.id_aerodromo
WHERE p.id_pista IS NULL
ORDER BY m.uf, a.nome;


-- -----------------------------------------------------------------------------
-- 11. Classificacao regulatoria completa dos aerodromos classificados
--     Padrao: percorre as quatro tabelas do bloco regulatorio de uma vez,
--     incluindo a coluna multivalorada de categorias
-- -----------------------------------------------------------------------------
SELECT a.ciad, a.codigo_oaci, a.nome, m.nome AS municipio, m.uf,
       rb.classe_rbac153,
       rb.classe_rbac107,
       pf.descricao AS perfil_operacional,
       string_agg(co.descricao, ' | ' ORDER BY co.descricao) AS categorias_operacao
FROM aerodromo_rbac rb
JOIN      aerodromo                    a  ON a.id_aerodromo  = rb.id_aerodromo
JOIN      municipio                    m  ON m.id_municipio  = a.id_municipio
LEFT JOIN perfil_operacional           pf ON pf.id_perfil    = rb.id_perfil
LEFT JOIN aerodromo_categoria_operacao ac ON ac.id_aerodromo = rb.id_aerodromo
LEFT JOIN categoria_operacao           co ON co.id_categoria = ac.id_categoria
GROUP BY a.ciad, a.codigo_oaci, a.nome, m.nome, m.uf,
         rb.classe_rbac153, rb.classe_rbac107, pf.descricao
ORDER BY rb.classe_rbac153, m.uf, a.nome;


-- -----------------------------------------------------------------------------
-- 12. Pistas aptas a aviacao comercial: asfalto ou concreto, 1500 m ou mais,
--     com iluminacao de borda, em aerodromo publico
--     Padrao: filtro composto sobre aerodromo + pista + superficie
-- -----------------------------------------------------------------------------
SELECT a.ciad, a.codigo_oaci, a.nome, m.nome AS municipio, m.uf,
       p.designacao, p.comprimento_m, p.largura_m,
       s.descricao AS superficie,
       p.resistencia_pcn
FROM aerodromo a
JOIN municipio        m ON m.id_municipio  = a.id_municipio
JOIN pista            p ON p.id_aerodromo  = a.id_aerodromo
JOIN superficie_pista s ON s.id_superficie = p.id_superficie
WHERE a.tipo_uso      = 'Público'
  AND s.descricao     IN ('Asfalto', 'Concreto')
  AND p.comprimento_m >= 1500
  AND p.luzes_borda   IS TRUE
ORDER BY p.comprimento_m DESC;


-- -----------------------------------------------------------------------------
-- 13. Os cinco aerodromos mais altos de cada UF
--     Padrao: window function RANK com particao por UF
-- -----------------------------------------------------------------------------
SELECT uf, posicao, nome, municipio, altitude_m
FROM (
    SELECT m.uf,
           a.nome,
           m.nome AS municipio,
           a.altitude_m,
           rank() OVER (PARTITION BY m.uf ORDER BY a.altitude_m DESC) AS posicao
    FROM aerodromo a
    JOIN municipio m ON m.id_municipio = a.id_municipio
    WHERE a.altitude_m IS NOT NULL
) AS r
WHERE posicao <= 5
ORDER BY uf, posicao;


-- -----------------------------------------------------------------------------
-- 14. Como a resistencia da pista foi informada
--     Padrao: evidencia a restricao CHECK de exclusividade entre as duas
--     notacoes de resistencia
-- -----------------------------------------------------------------------------
SELECT CASE WHEN p.resistencia_pcn IS NOT NULL THEN 'PCN (notacao OACI)'
            ELSE 'Peso em kg + pressao em MPa' END AS forma_de_informar,
       count(*)                                    AS qtd_pistas,
       round(avg(p.comprimento_m))                 AS comprimento_medio_m
FROM pista p
GROUP BY forma_de_informar
ORDER BY qtd_pistas DESC;


-- -----------------------------------------------------------------------------
-- 15. Panorama por UF cruzando pista, operacao e regulatorio
--     Padrao: varias subconsultas agregadas sem multiplicar linhas.
--     Agregar direto sobre tres JOIN de uma vez contaria cada aerodromo mais
--     de uma vez (uma por linha de operacao); por isso cada metrica vem de uma
--     subconsulta propria.
-- -----------------------------------------------------------------------------
SELECT e.sigla AS uf,
       e.nome  AS estado,
       count(DISTINCT a.id_aerodromo)                                  AS aerodromos,
       count(DISTINCT p.id_pista)                                      AS pistas,
       count(DISTINCT rb.id_aerodromo)                                 AS classificados_rbac,
       count(DISTINCT ao.id_aerodromo) FILTER (WHERE t.sigla = 'IFR')  AS operam_ifr,
       count(DISTINCT a.id_aerodromo)  FILTER (WHERE a.amazonia_legal) AS na_amazonia_legal
FROM estado e
JOIN      municipio          m  ON m.uf             = e.sigla
JOIN      aerodromo          a  ON a.id_municipio   = m.id_municipio
LEFT JOIN pista              p  ON p.id_aerodromo   = a.id_aerodromo
LEFT JOIN aerodromo_rbac     rb ON rb.id_aerodromo  = a.id_aerodromo
LEFT JOIN aerodromo_operacao ao ON ao.id_aerodromo  = a.id_aerodromo
LEFT JOIN tipo_operacao      t  ON t.id_tipo_operacao = ao.id_tipo_operacao
GROUP BY e.sigla, e.nome
ORDER BY aerodromos DESC;
