# Explicação Técnica - Como o Matcher Funciona

**Documento:** Guia de Entendimento do Produto para Pricing
**Objetivo:** Explicar o fluxo de operações e o racional de sizing da infraestrutura
**Data:** Janeiro 2026

---

## 1. Visão Geral: O que o Matcher faz?

O **Matcher** é uma engine de reconciliação financeira. Ele recebe transações de múltiplas fontes (banco, gateway de pagamento, ledger interno) e automaticamente encontra quais transações "casam" entre si.

### Exemplo Prático

Imagine que você tem:
- **Fonte A (Seu sistema - Midaz):** "Venda #123 de R$ 100,00 em 10/01"
- **Fonte B (Banco):** "Crédito de R$ 97,00 em 12/01" (com taxa de 3%)

O Matcher identifica que essas duas transações são a mesma operação, considerando:
- A diferença de valor (taxa do banco)
- A diferença de data (tempo de compensação)
- Regras configuradas pelo usuário

---

## 2. Fluxo Completo de Operações

### 2.1 Diagrama do Fluxo

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FLUXO DO MATCHER                                   │
└─────────────────────────────────────────────────────────────────────────────┘

    USUÁRIO                    MATCHER                         INFRAESTRUTURA
       │                          │                                   │
       │  1. Upload arquivo       │                                   │
       │  (CSV com transações)    │                                   │
       │─────────────────────────>│                                   │
       │                          │                                   │
       │                          │  2. Criar Job de Ingestion        │
       │                          │──────────────────────────────────>│ PostgreSQL
       │                          │                                   │  (INSERT job)
       │                          │                                   │
       │                          │  PARA CADA TRANSAÇÃO NO ARQUIVO:  │
       │                          │  ┌─────────────────────────────┐  │
       │                          │  │ 3. Verificar se é duplicata │  │
       │                          │  │────────────────────────────>│──│─> Redis
       │                          │  │                             │  │   (SETNX)
       │                          │  │                             │  │
       │                          │  │ 4. Verificar se já existe   │  │
       │                          │  │────────────────────────────>│──│─> PostgreSQL
       │                          │  │                             │  │   (SELECT EXISTS)
       │                          │  │                             │  │
       │                          │  │ 5. Salvar transação         │  │
       │                          │  │────────────────────────────>│──│─> PostgreSQL
       │                          │  │                             │  │   (INSERT)
       │                          │  └─────────────────────────────┘  │
       │                          │                                   │
       │                          │  6. Publicar evento "Pronto"      │
       │                          │──────────────────────────────────>│ RabbitMQ
       │                          │                                   │  (1 mensagem)
       │                          │                                   │
       │                          │  7. Worker recebe evento          │
       │                          │<──────────────────────────────────│ RabbitMQ
       │                          │                                   │
       │                          │  8. Executar Matching             │
       │                          │  ┌─────────────────────────────┐  │
       │                          │  │ Buscar transações unmatched │  │
       │                          │  │────────────────────────────>│──│─> PostgreSQL
       │                          │  │                             │  │   (SELECT)
       │                          │  │                             │  │
       │                          │  │ Aplicar regras de match     │  │
       │                          │  │ (em memória - CPU)          │  │
       │                          │  │                             │  │
       │                          │  │ Lock para evitar conflito   │  │
       │                          │  │────────────────────────────>│──│─> Redis
       │                          │  │                             │  │   (SETNX lock)
       │                          │  │                             │  │
       │                          │  │ Criar MatchGroup            │  │
       │                          │  │────────────────────────────>│──│─> PostgreSQL
       │                          │  │                             │  │   (INSERT)
       │                          │  │                             │  │
       │                          │  │ Criar MatchItems            │  │
       │                          │  │────────────────────────────>│──│─> PostgreSQL
       │                          │  │                             │  │   (INSERT)
       │                          │  │                             │  │
       │                          │  │ Atualizar status das txns   │  │
       │                          │  │────────────────────────────>│──│─> PostgreSQL
       │                          │  │                             │  │   (UPDATE)
       │                          │  │                             │  │
       │                          │  │ Liberar lock                │  │
       │                          │  │────────────────────────────>│──│─> Redis
       │                          │  │                             │  │   (DEL)
       │                          │  └─────────────────────────────┘  │
       │                          │                                   │
       │  9. Resultado disponível │                                   │
       │<─────────────────────────│                                   │
       │                          │                                   │
```

---

## 3. Detalhamento: O que acontece em cada etapa?

### 3.1 INGESTION (Ingestão de Dados)

Quando você faz upload de um arquivo CSV com 1.000 transações, o que acontece:

#### Passo 1: Criar Job
```
PostgreSQL: INSERT INTO ingestion_jobs (id, context_id, status, ...)
            VALUES ('uuid', 'ctx-uuid', 'PROCESSING', ...)
```
**Operações:** 1 INSERT no PostgreSQL

#### Passo 2: Para CADA transação no arquivo (1.000x):

**a) Verificar duplicata no Redis:**
```
Redis: SETNX matcher:dedupe:ctx-uuid:hash-da-transacao "1"
```
- Se retornar `1` (setou) → transação é nova
- Se retornar `0` (já existia) → é duplicata, pula

**Operações:** 1 operação Redis por transação

**b) Verificar se já existe no banco:**
```
PostgreSQL: SELECT EXISTS (
              SELECT 1 FROM transactions
              WHERE source_id = 'src-uuid' AND external_id = 'TXN-123'
            )
```
**Operações:** 1 SELECT no PostgreSQL por transação

**c) Salvar a transação:**
```
PostgreSQL: INSERT INTO transactions (id, amount, currency, date, ...)
            VALUES ('uuid', 100.00, 'BRL', '2026-01-10', ...)
```
**Operações:** 1 INSERT no PostgreSQL por transação

#### Passo 3: Publicar evento de conclusão
```
RabbitMQ: PUBLISH to exchange "matcher.events"
          routing_key "ingestion.completed"
          payload { job_id: 'uuid', transaction_count: 1000, ... }
```
**Operações:** 1 mensagem no RabbitMQ por JOB (não por transação!)

---

### 3.2 MATCHING (Reconciliação)

Quando o Worker recebe o evento de "ingestion completed", ele executa o matching:

#### Passo 1: Buscar transações não reconciliadas
```
PostgreSQL: SELECT * FROM transactions
            WHERE context_id = 'ctx-uuid'
            AND status = 'UNMATCHED'
            AND extraction_status = 'COMPLETE'
```
**Operações:** 1 SELECT (retorna muitas transações de uma vez)

#### Passo 2: Aplicar regras de matching (em memória)

O algoritmo compara as transações em memória:
```go
// Pseudocódigo do matching
for _, txnA := range transacoesDoMidaz {
    for _, txnB := range transacoesDoBanco {
        if matchExato(txnA, txnB) || matchComTolerancia(txnA, txnB) {
            candidatos = append(candidatos, Match{txnA, txnB, confianca})
        }
    }
}
```
**Operações:** CPU apenas, sem I/O de banco

#### Passo 3: Para cada MATCH encontrado:

**a) Adquirir lock distribuído (evitar conflito):**
```
Redis: SETNX matcher:lock:txn-uuid-A "worker-1" EX 30
Redis: SETNX matcher:lock:txn-uuid-B "worker-1" EX 30
```
**Operações:** 2 operações Redis por match

**b) Criar o MatchGroup:**
```
PostgreSQL: INSERT INTO match_groups (id, context_id, confidence, status, ...)
            VALUES ('mg-uuid', 'ctx-uuid', 95, 'CONFIRMED', ...)
```
**Operações:** 1 INSERT no PostgreSQL por match

**c) Criar os MatchItems (linkando as transações):**
```
PostgreSQL: INSERT INTO match_items (id, match_group_id, transaction_id, allocated_amount, ...)
            VALUES ('mi-uuid-1', 'mg-uuid', 'txn-uuid-A', 100.00, ...),
                   ('mi-uuid-2', 'mg-uuid', 'txn-uuid-B', 97.00, ...)
```
**Operações:** 1-2 INSERTs no PostgreSQL por match (depende de quantas txns no match)

**d) Atualizar status das transações:**
```
PostgreSQL: UPDATE transactions SET status = 'MATCHED' WHERE id IN ('txn-uuid-A', 'txn-uuid-B')
```
**Operações:** 1 UPDATE no PostgreSQL por match

**e) Liberar locks:**
```
Redis: DEL matcher:lock:txn-uuid-A
Redis: DEL matcher:lock:txn-uuid-B
```
**Operações:** 2 operações Redis por match

---

## 4. Resumo: Operações por Transação vs por Match

### 4.1 Tabela de Operações

| Fase | Componente | Operação | Frequência | Quantidade |
|------|------------|----------|------------|------------|
| **INGESTION** | Redis | SETNX (dedupe) | Por transação | 1 |
| **INGESTION** | PostgreSQL | SELECT EXISTS | Por transação | 1 |
| **INGESTION** | PostgreSQL | INSERT transaction | Por transação | 1 |
| **INGESTION** | RabbitMQ | PUBLISH evento | Por JOB | 1 |
| **MATCHING** | PostgreSQL | SELECT unmatched | Por JOB | 1 |
| **MATCHING** | Redis | SETNX + DEL (locks) | Por MATCH | 4 |
| **MATCHING** | PostgreSQL | INSERT match_group | Por MATCH | 1 |
| **MATCHING** | PostgreSQL | INSERT match_items | Por MATCH | 2 |
| **MATCHING** | PostgreSQL | UPDATE status | Por MATCH | 1 |

### 4.2 Exemplo Numérico

**Cenário:** Upload de arquivo com 1.000 transações, taxa de match de 80%

| Etapa | Cálculo | Total Operações |
|-------|---------|-----------------|
| Ingestion - Redis | 1.000 txns × 1 op | 1.000 ops Redis |
| Ingestion - PostgreSQL | 1.000 txns × 2 ops | 2.000 ops PostgreSQL |
| Ingestion - RabbitMQ | 1 job × 1 msg | 1 msg RabbitMQ |
| Matching - Redis | 800 matches × 4 ops | 3.200 ops Redis |
| Matching - PostgreSQL | 800 matches × 4 ops | 3.200 ops PostgreSQL |
| **TOTAL** | | **4.200 Redis, 5.200 PostgreSQL, 1 RabbitMQ** |

**Por transação processada:** ~4,2 ops Redis + ~5,2 ops PostgreSQL

---

## 5. Racional de Sizing: Por que escolhi cada instância?

### 5.1 PostgreSQL (Amazon RDS)

#### O que o PostgreSQL faz no Matcher:
- Armazena todas as transações
- Armazena configurações (contextos, regras, field maps)
- Armazena matches e exceptions
- Armazena audit log (compliance SOX)

#### Como dimensionar:

**Variáveis principais:**
1. **Queries por segundo (QPS)** - Capacidade de processamento
2. **Armazenamento (GB)** - Tamanho dos dados
3. **Memória (RAM)** - Cache de queries frequentes

**Cálculo para cada tier:**

| Tier | Transações/mês | Transações/dia | QPS estimado* | RAM necessária |
|------|----------------|----------------|---------------|----------------|
| Starter | 500K | ~17K | ~5 QPS | 4GB suficiente |
| Growth | 2M | ~67K | ~20 QPS | 8GB recomendado |
| Scale | 10M | ~333K | ~100 QPS | 16GB necessário |

*Assumindo processamento distribuído ao longo do dia

#### Escolha de instâncias:

**STARTER: db.t3.medium (2 vCPU, 4GB RAM)**

| Critério | Análise |
|----------|---------|
| CPU | 2 vCPU com burst suficiente para 5-10 QPS |
| RAM | 4GB permite cache de ~1GB para queries |
| Storage | 100GB gp3 = ~600K transações* |
| Preço | $80/mês - menor custo possível com performance aceitável |

*Estimativa: ~150 bytes/transação + indexes

**Por que NÃO db.t3.micro?**
- Apenas 1GB RAM - insuficiente para PostgreSQL com GORM
- CPU burst limitado - pode throttle em picos
- Risco de OOM (Out of Memory) com queries complexas

**Por que NÃO db.t3.small?**
- 2GB RAM - margem pequena para crescimento
- Diferença de custo para t3.medium é pequena (~$20/mês)

---

**GROWTH: db.t3.large (2 vCPU, 8GB RAM)**

| Critério | Análise |
|----------|---------|
| CPU | Mesmo 2 vCPU, mas com mais burst credits |
| RAM | 8GB permite cache maior, menos disk I/O |
| Storage | 250GB gp3 = ~1.5M transações |
| Preço | $160/mês |

**Por que 8GB de RAM?**
- 2M transações/mês = queries mais pesadas
- Joins entre transactions, match_groups, match_items
- Buffer pool maior = menos leituras de disco

---

**SCALE: db.r6g.large (2 vCPU, 16GB RAM) + Read Replica**

| Critério | Análise |
|----------|---------|
| CPU | Graviton (ARM) - melhor custo/performance |
| RAM | 16GB - cache significativo |
| Read Replica | Separa leitura de escrita |
| Storage | 500GB gp3 com IOPS provisionado |
| Preço | $560/mês (primary + replica) |

**Por que Read Replica?**
- 10M transações/mês gera ~100+ QPS
- Reporting e dashboard não devem impactar writes
- O PRD do Matcher menciona: "Database scales with Read Replicas"

---

### 5.2 Redis (Amazon ElastiCache)

#### O que o Redis faz no Matcher:
1. **Deduplicação** - Evita processar a mesma transação duas vezes
2. **Locking distribuído** - Evita que dois workers façam match da mesma transação

#### Como dimensionar:

**Variáveis principais:**
1. **Memória para keys** - Cada transação = 1 key de dedupe
2. **Operações por segundo** - SETNX, GET, DEL
3. **TTL das keys** - Por quanto tempo manter

**Cálculo de memória:**

```
Memória por key de dedupe:
- Key: "matcher:dedupe:ctx-uuid:hash" = ~80 bytes
- Value: "1" = ~8 bytes
- Overhead Redis: ~50 bytes
- Total: ~140 bytes/key

Para 500K transações/mês com TTL de 30 dias:
500K × 140 bytes = 70MB

Com margem de segurança (2x): 140MB
```

#### Escolha de instâncias:

**STARTER: cache.t3.small (2 vCPU, 1.5GB RAM)**

| Critério | Análise |
|----------|---------|
| Memória | 1.5GB >> 140MB necessário |
| Operações | Suporta ~25K ops/segundo |
| Preço | $25/mês |

**Por que NÃO cache.t3.micro?**
- Apenas 0.5GB RAM
- Risco de eviction se TTL das keys for longo
- Diferença de $8/mês não justifica o risco

---

**GROWTH: cache.t3.medium (2 vCPU, 3GB RAM)**

| Critério | Análise |
|----------|---------|
| Memória | 3GB para 2M transações |
| Operações | ~50K ops/segundo |
| Preço | $50/mês |

---

**SCALE: cache.r6g.large (2 vCPU, 13GB RAM)**

| Critério | Análise |
|----------|---------|
| Memória | 13GB para 10M+ transações |
| Operações | ~100K ops/segundo |
| Graviton | Melhor custo/performance |
| Preço | $150/mês |

**Por que upgrade significativo no Scale?**
- Locking distribuído com alto volume precisa de baixa latência
- Mais memória = menos evictions = menos falsos positivos de duplicata

---

### 5.3 RabbitMQ (Amazon MQ)

#### O que o RabbitMQ faz no Matcher:
1. **Desacoplar ingestion de matching** - Upload não espera matching terminar
2. **Eventos assíncronos** - Notificar quando processos completam

#### Insight importante: Volume BAIXO de mensagens

```
Análise do código (event_publisher.go):

- PublishIngestionCompleted() → 1 mensagem por JOB
- PublishIngestionFailed() → 1 mensagem por JOB falho

Se um JOB processa 1.000 transações:
- 500K transações/mês ÷ 1.000 txns/job = 500 jobs/mês
- 500 jobs/mês = ~17 mensagens/dia
```

**Conclusão:** RabbitMQ tem uso MUITO BAIXO no Matcher!

#### Escolha de instâncias:

**STARTER e GROWTH: mq.t3.micro (2 vCPU, 1GB RAM)**

| Critério | Análise |
|----------|---------|
| Capacidade | Suporta ~1.000 msg/segundo |
| Uso real | ~17-70 msg/dia (irrelevante) |
| Preço | $55/mês |

**Por que manter mq.t3.micro mesmo no Growth?**
- Volume de mensagens não justifica upgrade
- Bottleneck NUNCA será o RabbitMQ
- Custo fixo de managed service

---

**SCALE: mq.m5.large (2 vCPU, 8GB RAM)**

| Critério | Análise |
|----------|---------|
| Capacidade | Suporta clustering |
| HA | Alta disponibilidade para enterprise |
| Preço | $200/mês |

**Por que upgrade no Scale?**
- Não é por volume de mensagens
- É por **SLA e alta disponibilidade**
- Clientes Scale esperam 99.9%+ uptime
- mq.t3.micro não suporta cluster mode

---

## 6. Resumo Visual: Sizing por Tier

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TIER STARTER (R$ 3.995/mês)                          │
│                         500K transações/mês                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐       │
│   │   PostgreSQL     │   │      Redis       │   │    RabbitMQ      │       │
│   │   db.t3.medium   │   │  cache.t3.small  │   │   mq.t3.micro    │       │
│   │   2 vCPU, 4GB    │   │  2 vCPU, 1.5GB   │   │   2 vCPU, 1GB    │       │
│   │   100GB storage  │   │                  │   │   20GB storage   │       │
│   │   R$ 440/mês     │   │   R$ 125/mês     │   │   R$ 285/mês     │       │
│   └──────────────────┘   └──────────────────┘   └──────────────────┘       │
│                                                                              │
│   Compute: 3x Fargate (0.5 vCPU cada) = R$ 225/mês                          │
│   Outros: R$ 75/mês                                                          │
│   ─────────────────────────────────────────────                              │
│   TOTAL CUSTO: R$ 1.150/mês                                                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                         TIER GROWTH (R$ 9.995/mês)                           │
│                         2M transações/mês                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐       │
│   │   PostgreSQL     │   │      Redis       │   │    RabbitMQ      │       │
│   │   db.t3.large    │   │  cache.t3.medium │   │   mq.t3.micro    │       │
│   │   2 vCPU, 8GB    │   │  2 vCPU, 3GB     │   │   2 vCPU, 1GB    │       │
│   │   250GB storage  │   │                  │   │   50GB storage   │       │
│   │   R$ 925/mês     │   │   R$ 250/mês     │   │   R$ 295/mês     │       │
│   └──────────────────┘   └──────────────────┘   └──────────────────┘       │
│                                                                              │
│   Compute: 5x Fargate (1 vCPU cada) = R$ 810/mês                            │
│   Outros: R$ 225/mês                                                         │
│   ─────────────────────────────────────────────                              │
│   TOTAL CUSTO: R$ 2.505/mês                                                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                         TIER SCALE (R$ 24.995/mês)                           │
│                         10M transações/mês                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐       │
│   │   PostgreSQL     │   │      Redis       │   │    RabbitMQ      │       │
│   │   db.r6g.large   │   │  cache.r6g.large │   │   mq.m5.large    │       │
│   │   + Read Replica │   │  2 vCPU, 13GB    │   │   2 vCPU, 8GB    │       │
│   │   2x 16GB RAM    │   │                  │   │   HA Cluster     │       │
│   │   500GB storage  │   │                  │   │   100GB storage  │       │
│   │   R$ 3.150/mês   │   │   R$ 750/mês     │   │   R$ 1.040/mês   │       │
│   └──────────────────┘   └──────────────────┘   └──────────────────┘       │
│                                                                              │
│   Compute: 10x Fargate (2 vCPU cada) = R$ 3.060/mês                         │
│   Outros: R$ 400/mês                                                         │
│   ─────────────────────────────────────────────                              │
│   TOTAL CUSTO: R$ 8.400/mês                                                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Entendendo o "Custo por Match"

### 7.1 O que é um Match?

Um **Match** é quando o sistema encontra que duas (ou mais) transações representam a mesma operação financeira.

```
Exemplo de Match 1:1 (mais comum):

Transação A (Midaz):     Transação B (Banco):
├─ ID: TXN-001           ├─ ID: BANK-99887
├─ Valor: R$ 100,00      ├─ Valor: R$ 97,00
├─ Data: 10/01/2026      ├─ Data: 12/01/2026
└─ Ref: "Venda #123"     └─ Ref: "CRED TXN-001"

                    ↓ MATCH! ↓

MatchGroup:
├─ ID: MG-001
├─ Confiança: 95%
├─ Status: CONFIRMED
└─ MatchItems:
   ├─ Item 1: TXN-001, allocated: R$ 100,00
   └─ Item 2: BANK-99887, allocated: R$ 97,00
```

### 7.2 Operações por Match

| Operação | Componente | Por quê? |
|----------|------------|----------|
| SETNX lock txn A | Redis | Evitar que outro worker pegue a mesma transação |
| SETNX lock txn B | Redis | Idem |
| INSERT match_group | PostgreSQL | Registrar o match |
| INSERT match_item A | PostgreSQL | Linkar transação A ao match |
| INSERT match_item B | PostgreSQL | Linkar transação B ao match |
| UPDATE txn A status | PostgreSQL | Marcar como MATCHED |
| UPDATE txn B status | PostgreSQL | Marcar como MATCHED |
| DEL lock txn A | Redis | Liberar lock |
| DEL lock txn B | Redis | Liberar lock |
| **TOTAL** | | **4 Redis + 5 PostgreSQL = 9 operações** |

### 7.3 Custo por Match (estimativa)

**Usando ElastiCache provisionado (não Serverless):**
- Redis: Custo fixo por hora, não por operação
- PostgreSQL: Custo fixo por hora + IOPS se usar io1

**Se usássemos Serverless (para referência):**
```
ElastiCache Serverless: $0.0034/milhão ECPUs
Aurora Serverless: $0.20/milhão I/Os

Custo por match:
- Redis: 4 ops × $0.0000000034 = $0.0000000136
- PostgreSQL: 5 ops × $0.0000002 = $0.000001

Custo por match = ~$0.000001 = R$ 0,000005 por match
```

**Conclusão:** O custo VARIÁVEL por match é desprezível. O que importa é o custo FIXO da infraestrutura.

---

## 8. Por que a Metodologia "Standalone-First"?

### 8.1 O Problema

Se você cobra R$ 0,000005 por match, precisaria de **200 milhões de matches** para cobrir R$ 1.000 de custo fixo.

### 8.2 A Solução

Cobrar um **valor fixo mensal** que:
1. Cobre o custo da infraestrutura dedicada
2. Inclui um volume de transações
3. Tem margem de lucro embutida

### 8.3 Exemplo

```
Tier Starter:
├─ Custo fixo de infra: R$ 1.150/mês
├─ Volume incluso: 500K transações
├─ Preço: R$ 3.995/mês
├─ Margem: 71%
│
├─ Se cliente usa 500K txns: Margem = 71%
├─ Se cliente usa 100K txns: Margem = 71% (mesmo custo fixo)
└─ Se cliente usa 600K txns: Cobra overage de R$ 2,50/1K txns extras
```

---

## 9. Resumo Final

### O que você precisa saber para avaliar o pricing:

1. **PostgreSQL é o componente mais caro** - É onde estão os dados e as queries mais pesadas

2. **Redis tem uso moderado** - Deduplicação e locking, mas volume não é crítico

3. **RabbitMQ tem uso BAIXO** - 1 mensagem por JOB, não por transação

4. **Custo variável por match é desprezível** - O que importa é o custo fixo

5. **Margem vem do volume** - Quanto mais transações no plano, mais diluído o custo fixo

### Validação recomendada:

- [ ] Rodar infra real por 30 dias para validar custos
- [ ] Medir QPS real em ambiente de produção
- [ ] Ajustar sizing se uso for diferente do estimado

---

## Changelog

| Versão | Data | Alteração |
|--------|------|-----------|
| 1.0 | Jan 2026 | Versão inicial |

