# Aeródromos da Região Norte (ANAC) — Projeto final

Banco PostgreSQL normalizado até a **3ª Forma Normal (3FN)**, gerado exclusivamente a partir do CSV fornecido para o trabalho. Mantive os nomes das quatro entregas na raiz do repositório original.

## Arquivos

1. `trabalho_aerodromo.sql` — DDL: 13 tabelas, chaves, relacionamentos, `NOT NULL`, `UNIQUE`, `CHECK` e índices.
2. `carga_aerodromo.sql` — **INSERTs SQL completos**, sem Python, `COPY` ou caminho local; carrega os 809 aeródromos e todas as tabelas, com verificação final.
3. `anac_aerodromos_norte.csv` — arquivo original **inalterado**.
4. `README.md` — decisões, conferência e mapeamento das 34 colunas.

## Execução no pgAdmin (PostgreSQL)

Crie um banco **vazio**, por exemplo `aerodromos_norte`. No Query Tool dele, execute **primeiro** todo o `trabalho_aerodromo.sql`. Depois execute **todo** o `carga_aerodromo.sql`. A carga termina com uma tabela de conferência: os 13 resultados devem ser `OK`. O script contém `BEGIN/COMMIT` e interrompe a carga em caso de contagem divergente.

**Não é necessário importar o CSV:** todos os dados estão nos `INSERT` do segundo arquivo.

## Critérios de modelagem

- **Identificadores:** `aerodromo_id` e `pista_id` conservam exatamente os IDs da ANAC. Todas as chaves restantes seguem `nome_da_tabela_id`, com a sigla UF natural usada como `estado_id`. Em relacionamentos N:N, a chave primária é composta das respectivas FKs; não existem IDs artificiais desnecessários.
- **Localização:** `municipio` serve ao local do aeródromo e ao município servido, por meio de `municipio_id` e `municipio_servido_id`. `estado` contém somente as **7 siglas presentes no CSV**, sem adicionar nomes completos não fornecidos.
- **Pistas:** `pista` é entidade própria, comportando futuras múltiplas pistas por aeródromo. Aeródromos sem pista ficam sem registro na tabela `pista`, não com dados fictícios.
- **Campos multivalorados:** `operacao_diurna`, `operacao_noturna` e `operacao_internacional` são decompostos em linhas atômicas com tabelas de domínio. A notação técnica PCN com `/` é mantida intacta, por não ser uma lista de valores de voo.
- **RBAC:** `aerodromo_rbac` contém somente os 71 aeródromos classificados; `perfil_operacional_id` é `NULL` em 16 deles, como na fonte. Nenhuma informação ausente é completada artificialmente.
- **Descrições:** nomes, situação, tipo de uso, superfícies, tipos e restrições são armazenados em **MAIÚSCULAS, SEM ACENTOS**; campos técnicos (CIAD/OACI/PCN), números, booleanos, datas e URLs conservam os valores de origem. O caso `D´Oeste` foi padronizado para `D'OESTE`, preservando o sinal de separação de palavras. As 9 grafias de restrição viram 8 textos únicos porque duas só diferem pela caixa da palavra `Exceto`; os 19 vínculos com aeródromos permanecem.
- **Sem invenções:** 3 `tipo_uso` ausentes continuam `NULL`; 333 `codigo_oaci` ausentes continuam `NULL`; os 156 sem pista não recebem pista; a data de ano 3032 do CSV é mantida, sem corrigir por hipótese.

**Fidelidade de grafia:** a opção por maiúsculas sem acentos necessariamente elimina diferenças ortográficas literais *dentro das tabelas normalizadas*. O CSV original, incluído sem modificação, preserva todos os textos, datas, pontuação e grafias para auditoria. Nenhuma identidade de aeródromo, informação técnica ou associação é removida por essa padronização.

## Contagens esperadas

| Tabela | Registros |
|---|---:|
| `estado` | 7 |
| `municipio` | 242 |
| `superficie_pista` | 9 |
| `tipo_operacao` | 3 |
| `perfil_operacional` | 3 |
| `categoria_operacao` | 3 |
| `restricao` | 8 |
| `aerodromo` | 809 |
| `pista` | 653 |
| `aerodromo_operacao` | 1163 |
| `aerodromo_rbac` | 71 |
| `aerodromo_categoria_operacao` | 13 |
| `aerodromo_restricao` | 19 |

## Exemplos de SELECT para a apresentação

```sql
-- Aeródromos do Pará, em ordem de município e nome:
SELECT a.nome, a.ciad, m.nome AS municipio, a.situacao
FROM aerodromo AS a
JOIN municipio AS m USING (municipio_id)
WHERE m.estado_id = 'PA'
ORDER BY m.nome, a.nome;

-- Aeródromos sem código OACI:
SELECT nome, ciad FROM aerodromo
WHERE codigo_oaci IS NULL
ORDER BY nome;

-- Quantidade de aeródromos por situação:
SELECT situacao, COUNT(*) AS quantidade
FROM aerodromo GROUP BY situacao
ORDER BY quantidade DESC;
```

## Rastreamento das 34 colunas do CSV

| Campo original | Destino no modelo |
|---|---|
| `id_aerodromo` | `aerodromo.aerodromo_id` |
| `ciad` | `aerodromo.ciad` |
| `codigo_oaci` | `aerodromo.codigo_oaci` |
| `tipo_uso` | `aerodromo.tipo_uso` |
| `nome` | `aerodromo.nome` |
| `municipio` | `municipio.nome (aerodromo.municipio_id)` |
| `uf` | `municipio.estado_id (aerodromo.municipio_id)` |
| `municipio_servido` | `municipio.nome (aerodromo.municipio_servido_id)` |
| `uf_servido` | `municipio.estado_id (aerodromo.municipio_servido_id)` |
| `latitude` | `aerodromo.latitude` |
| `longitude` | `aerodromo.longitude` |
| `altitude_m` | `aerodromo.altitude_m` |
| `operacao_diurna` | `aerodromo_operacao + tipo_operacao [DIURNO]` |
| `operacao_noturna` | `aerodromo_operacao + tipo_operacao [NOTURNO]` |
| `pista1_id` | `pista.pista_id` |
| `pista1_designacao` | `pista.designacao` |
| `pista1_comprimento_m` | `pista.comprimento_m` |
| `pista1_largura_m` | `pista.largura_m` |
| `pista1_resistencia_kg` | `pista.resistencia_kg` |
| `pista1_resistencia_mpa` | `pista.resistencia_mpa` |
| `pista1_resistencia_pcn` | `pista.resistencia_pcn` |
| `pista1_superficie` | `superficie_pista.descricao (pista.superficie_pista_id)` |
| `pista1_luzes_eixo` | `pista.luzes_eixo` |
| `pista1_luzes_borda` | `pista.luzes_borda` |
| `situacao` | `aerodromo.situacao` |
| `classe_rbac153` | `aerodromo_rbac.classe_rbac153` |
| `perfil_operacional_rbac153` | `perfil_operacional.descricao (aerodromo_rbac.perfil_operacional_id)` |
| `classe_rbac107` | `aerodromo_rbac.classe_rbac107` |
| `operacao_internacional` | `aerodromo_categoria_operacao + categoria_operacao` |
| `certificacao_operacional` | `aerodromo.certificacao_operacional` |
| `validade_cadastro` | `aerodromo.validade_cadastro` |
| `link_portaria_cadastro` | `aerodromo.link_portaria_cadastro` |
| `restricao` | `aerodromo_restricao + restricao` |
| `amazonia_legal` | `aerodromo.amazonia_legal` |

## Equipe

- Pedro Andrade Gonçalves de Souza
- Júlia Labad Jatene
- Luan Piedade de Oliveira
- João Paulo Oliveira Rodrigues

## Nota de verificação

Os scripts foram conferidos programaticamente contra o CSV: contagens, chaves, vínculos, nulos, valores numéricos e reconstrução dos 34 atributos. A execução real no PostgreSQL deve ser confirmada no pgAdmin pela equipe, após rodar os dois scripts na ordem acima.
