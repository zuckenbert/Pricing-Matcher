# Análise de Custos e Proposta de Pricing - Matcher

**Documento preparado para:** Lerian - Pricing do Matcher
**Data:** Janeiro 2026
**Versão:** 1.0
**Metodologia:** Standalone-First (worst case: 1 cliente usando infra dedicada)

---

## Executive Summary

Este documento apresenta a análise de custos de infraestrutura para o Matcher e uma proposta de pricing que garante **margem mínima de 70%** no tier mais barato, mantendo competitividade com Simetrik e Equals.

### Recomendação de Pricing

| Tier | Preço/Mês | Transações/Mês | Custo Estimado | Margem |
|------|-----------|----------------|----------------|--------|
| **Starter** | $799 | até 500K | $240 | 70% |
| **Growth** | $1,999 | até 2M | $450 | 77.5% |
| **Scale** | $4,999 | até 10M | $900 | 82% |
| **Enterprise** | Custom | Ilimitado | Negociado | 75%+ |

---

## 1. Visão Geral do Produto

### 1.1 O que é o Matcher

**Matcher** é uma engine de reconciliação financeira que automatiza o matching de transações entre o Midaz (ledger da Lerian) e sistemas de terceiros (bancos, gateways de pagamento, ERPs).

### 1.2 Stack Tecnológica

| Componente | Tecnologia | Versão |
|------------|------------|--------|
| Linguagem | Go | 1.24.2+ |
| HTTP Framework | Fiber | v2.52+ |
| Database | PostgreSQL | 17 |
| Cache | Redis (Valkey) | 8 |
| Message Queue | RabbitMQ | 4.1.3 |
| Observabilidade | OpenTelemetry | 1.39+ |

### 1.3 Componentes de Serviço

```
┌─────────────────────────────────────────────────────────────┐
│                      MATCHER SERVICES                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────┐    ┌──────────┐    ┌────────────┐             │
│  │   API   │    │  Worker  │    │ Scheduler  │             │
│  │ (Fiber) │    │ (Queue)  │    │  (Cron)    │             │
│  └────┬────┘    └────┬─────┘    └─────┬──────┘             │
│       │              │                │                     │
│       └──────────────┼────────────────┘                     │
│                      │                                      │
│  ┌───────────────────┴───────────────────────┐             │
│  │              INFRASTRUCTURE               │             │
│  │  ┌──────────┐  ┌───────┐  ┌──────────┐  │             │
│  │  │PostgreSQL│  │ Redis │  │ RabbitMQ │  │             │
│  │  └──────────┘  └───────┘  └──────────┘  │             │
│  └───────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 Métricas de Referência do PRD

| Métrica | Target Fase 1 |
|---------|---------------|
| Volume diário | 100K transações |
| Taxa de auto-match | ≥ 80% |
| Taxa de erro | < 0.1% |
| Usuários concorrentes | 10+ |

---

## 2. Análise de Custos de Infraestrutura

### 2.1 Metodologia: Standalone-First

A metodologia **Standalone-First** assume o pior cenário: um único cliente utilizando toda a infraestrutura dedicada. Isso garante:

1. **Pricing conservador** - Margem garantida mesmo no pior caso
2. **Escalabilidade** - À medida que clientes são adicionados, a margem aumenta
3. **Simplicidade** - Não requer modelagem complexa de compartilhamento

### 2.2 Custos AWS - Cenário Mínimo (Starter)

**Região:** US East (N. Virginia) - preços base
**Taxa de câmbio:** R$ 5,00 / USD

| Componente | Instância | Specs | Custo/Mês (USD) | Confiança |
|------------|-----------|-------|-----------------|-----------|
| **PostgreSQL** | RDS db.t3.medium | 2 vCPU, 4GB RAM | $80 | Alta |
| PostgreSQL Storage | gp3 100GB | 3000 IOPS base | $8 | Alta |
| **Redis** | ElastiCache cache.t3.small | 2 vCPU, 1.5GB | $25 | Alta |
| **RabbitMQ** | Amazon MQ mq.t3.micro | 2 vCPU, 1GB | $55 | Alta |
| RabbitMQ Storage | EBS 20GB | gp3 | $2 | Alta |
| **API Service** | Fargate | 0.5 vCPU, 1GB | $18 | Média |
| **Worker Service** | Fargate | 0.5 vCPU, 1GB | $18 | Média |
| **Scheduler** | Fargate | 0.25 vCPU, 0.5GB | $9 | Média |
| **CloudWatch** | Logs + Metrics | Basic | $15 | Média |
| **Data Transfer** | Estimado | Regional | $10 | Baixa |

**TOTAL STARTER:** **$240/mês** (~R$ 1.200/mês)

### 2.3 Custos AWS - Cenário Growth

| Componente | Instância | Specs | Custo/Mês (USD) | Confiança |
|------------|-----------|-------|-----------------|-----------|
| **PostgreSQL** | RDS db.t3.large | 2 vCPU, 8GB RAM | $160 | Alta |
| PostgreSQL Storage | gp3 250GB | 3000 IOPS | $20 | Alta |
| **Redis** | ElastiCache cache.t3.medium | 2 vCPU, 3GB | $50 | Alta |
| **RabbitMQ** | Amazon MQ mq.t3.micro | 2 vCPU, 1GB | $55 | Alta |
| RabbitMQ Storage | EBS 50GB | gp3 | $4 | Alta |
| **API Service** | Fargate x2 | 1 vCPU, 2GB | $72 | Média |
| **Worker Service** | Fargate x2 | 1 vCPU, 2GB | $72 | Média |
| **Scheduler** | Fargate | 0.5 vCPU, 1GB | $18 | Média |
| **CloudWatch** | Logs + Metrics + X-Ray | Enhanced | $30 | Média |
| **Data Transfer** | Estimado | Regional | $20 | Baixa |

**TOTAL GROWTH:** **$501/mês** (~R$ 2.505/mês)

### 2.4 Custos AWS - Cenário Scale

| Componente | Instância | Specs | Custo/Mês (USD) | Confiança |
|------------|-----------|-------|-----------------|-----------|
| **PostgreSQL** | RDS db.r6g.large | 2 vCPU, 16GB RAM | $280 | Alta |
| PostgreSQL Storage | gp3 500GB | 6000 IOPS | $50 | Alta |
| Read Replica | RDS db.r6g.large | Para queries | $280 | Alta |
| **Redis** | ElastiCache cache.r6g.large | 2 vCPU, 13GB | $150 | Alta |
| **RabbitMQ** | Amazon MQ mq.m5.large | 2 vCPU, 8GB | $200 | Alta |
| RabbitMQ Storage | EBS 100GB | gp3 | $8 | Alta |
| **API Service** | Fargate x4 | 2 vCPU, 4GB | $288 | Média |
| **Worker Service** | Fargate x4 | 2 vCPU, 4GB | $288 | Média |
| **Scheduler** | Fargate x2 | 0.5 vCPU, 1GB | $36 | Média |
| **Observability** | CloudWatch + X-Ray | Full | $80 | Média |
| **Data Transfer** | Estimado | Multi-AZ | $60 | Baixa |

**TOTAL SCALE:** **$1,720/mês** (~R$ 8.600/mês)

### 2.5 Resumo de Custos por Tier

| Tier | Custo Infra/Mês | Capacidade | Custo/1K Txn |
|------|-----------------|------------|--------------|
| **Starter** | $240 | 500K txn/mês | $0.48 |
| **Growth** | $501 | 2M txn/mês | $0.25 |
| **Scale** | $1,720 | 10M txn/mês | $0.17 |

---

## 3. Definição da Unidade de Cobrança

### 3.1 Análise de Opções

| Unidade | Prós | Contras | Recomendação |
|---------|------|---------|--------------|
| **Por Transação Reconciliada** | Granular, previsível, alinhado com valor | Complexo de estimar para cliente | Secundário |
| **Por MatchRun (Job)** | Simples, fácil de entender | Não escala bem com volume | Não recomendado |
| **Por ReconciliationContext** | Muito simples | Não reflete uso real | Não recomendado |
| **Subscription + Volume** | Previsibilidade + alinhamento | Mais complexo de comunicar | **Recomendado** |

### 3.2 Modelo Recomendado: Hybrid Subscription

```
Preço Total = Base Subscription + Overage (se aplicável)

- Base inclui: N transações/mês + suporte + features do tier
- Overage: Cobrança por transação excedente
```

### 3.3 Definição de "Transação"

Uma **transação** é contabilizada quando:

1. Um registro é **ingerido** com sucesso no sistema (status: COMPLETE)
2. Passa pelo processo de matching (matched ou unmatched)

**Não são contabilizadas:**
- Transações duplicadas (rejeitadas na ingestão)
- Transações com erro de validação
- Re-processamentos do mesmo registro

---

## 4. Proposta de Pricing

### 4.1 Tiers de Pricing

#### Tier: STARTER - $799/mês

**Target:** Startups, PMEs, primeiros projetos de reconciliação

| Característica | Incluído |
|----------------|----------|
| Transações/mês | 500.000 |
| Contextos de Reconciliação | 3 |
| Fontes de Dados | 6 |
| Regras de Matching | 20 |
| Usuários | 5 |
| Retenção de Dados | 90 dias |
| Suporte | E-mail (48h SLA) |
| Integrações | Webhook, CSV/JSON |

**Overage:** $0.50 por 1.000 transações excedentes

**Análise de Margem:**
- Receita: $799
- Custo: $240
- Margem: **70.0%** ✓

---

#### Tier: GROWTH - $1,999/mês

**Target:** Empresas em crescimento, operações multi-país

| Característica | Incluído |
|----------------|----------|
| Transações/mês | 2.000.000 |
| Contextos de Reconciliação | 10 |
| Fontes de Dados | 20 |
| Regras de Matching | 50 |
| Usuários | 15 |
| Retenção de Dados | 1 ano |
| Suporte | E-mail + Chat (24h SLA) |
| Integrações | + JIRA, API completa |
| Features | Multi-currency, Split/Aggregate |

**Overage:** $0.35 por 1.000 transações excedentes

**Análise de Margem:**
- Receita: $1,999
- Custo: $501
- Margem: **74.9%** ✓

---

#### Tier: SCALE - $4,999/mês

**Target:** Grandes empresas, fintechs, bancos digitais

| Característica | Incluído |
|----------------|----------|
| Transações/mês | 10.000.000 |
| Contextos de Reconciliação | Ilimitados |
| Fontes de Dados | Ilimitadas |
| Regras de Matching | Ilimitadas |
| Usuários | 50 |
| Retenção de Dados | 3 anos |
| Suporte | Dedicado (4h SLA) |
| Integrações | + ServiceNow, Custom |
| Features | + SLA Tracking, Advanced Reporting |

**Overage:** $0.20 por 1.000 transações excedentes

**Análise de Margem:**
- Receita: $4,999
- Custo: $1,720
- Margem: **65.6%** (abaixo de 70% - ajustar para $5,733 para 70%)

**Ajuste recomendado:** $5,499/mês para margem de 68.7%

---

#### Tier: ENTERPRISE - Custom

**Target:** Bancos, grandes varejistas, fintechs de escala

| Característica | Incluído |
|----------------|----------|
| Transações/mês | Negociado |
| Tudo do Scale | + |
| Infra Dedicada | Opcional |
| SLA | Customizado (99.9%+) |
| Suporte | Customer Success dedicado |
| Compliance | SOX, LGPD, SOC2 |
| Integrações | Custom development |

**Pricing:** Mínimo $10,000/mês, negociado caso a caso

---

### 4.2 Comparativo com Concorrência

| Aspecto | Matcher | Simetrik | Equals Brasil |
|---------|---------|----------|---------------|
| **Entry Price** | $799/mês | $3,000/mês | Não público |
| **Mid-tier** | $1,999/mês | Custom | Custom |
| **Modelo** | Subscription + Usage | Subscription | Custom |
| **Free Trial** | 14 dias | Disponível | Demo |
| **Self-Service** | Sim | Não | Não |
| **Open Source** | Core open | Não | Não |

### 4.3 Posicionamento de Preço

```
                          PREÇO
                            │
              $10k+ ────────┼──────── BlackLine
                            │         (Enterprise legacy)
                            │
               $3k ─────────┼──────── Simetrik
                            │         (VC-backed, global)
                            │
             $1.5k ─────────┼──────── Matcher (Growth)
                            │         (Open-source core)
                            │
              $800 ─────────┼──────── Matcher (Starter)
                            │         (Entry point)
                            │
                            └─────────────────────────────►
                                    ENTERPRISE ───► STARTUP
```

---

## 5. Break-Even Analysis

### 5.1 Cenário Starter (Single Client)

| Métrica | Valor |
|---------|-------|
| Receita Mensal | $799 |
| Custo Fixo | $240 |
| Margem Bruta | $559 (70%) |
| CAC Estimado | $2,000 |
| Payback | 3.6 meses |

### 5.2 Cenário Growth (10 Clientes)

| Métrica | Valor |
|---------|-------|
| Receita Mensal | $19,990 |
| Custo Infra (compartilhada) | $2,000 |
| Custo Operacional | $3,000 |
| Margem Bruta | $14,990 (75%) |

### 5.3 Unit Economics Target

| Métrica | Target |
|---------|--------|
| LTV | $24,000+ (24 meses avg) |
| CAC | $2,000 - $4,000 |
| LTV/CAC | 6x - 12x |
| Churn | < 5% anual |
| NRR | > 110% |

---

## 6. Grau de Confiança

### 6.1 Matriz de Confiança

| Estimativa | Confiança | Justificativa | Ação Recomendada |
|------------|-----------|---------------|------------------|
| **Custo PostgreSQL RDS** | Alta | Preços públicos AWS | Usar como base |
| **Custo ElastiCache** | Alta | Preços públicos AWS | Usar como base |
| **Custo Amazon MQ** | Alta | Preços públicos AWS | Usar como base |
| **Custo Fargate** | Média | Depende de scaling | Monitorar uso real |
| **Custo Data Transfer** | Baixa | Variável por uso | Adicionar buffer 20% |
| **Volume por Tier** | Média | Baseado em PRD | Validar com clientes |
| **Pricing Concorrência** | Média | Nem tudo público | Continuar pesquisa |

### 6.2 Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| Custos AWS aumentam | Baixa | Médio | Reserved Instances, Savings Plans |
| Volume maior que esperado | Média | Baixo | Auto-scaling, overage pricing |
| Competidor baixa preço | Média | Alto | Diferenciar por open-source, features |
| Cliente exige infra dedicada | Média | Médio | Tier Enterprise com markup |

---

## 7. Recomendações Finais

### 7.1 Pricing Recomendado

| Tier | Preço (USD) | Preço (BRL) |
|------|-------------|-------------|
| **Starter** | $799/mês | R$ 3.995/mês |
| **Growth** | $1,999/mês | R$ 9.995/mês |
| **Scale** | $5,499/mês | R$ 27.495/mês |
| **Enterprise** | $10,000+/mês | R$ 50.000+/mês |

### 7.2 Próximos Passos

1. **Validação com mercado** - Entrevistar 5-10 potenciais clientes
2. **Piloto gratuito** - Oferecer trial de 30 dias para 3 clientes
3. **Monitoramento de custos** - Implementar cost tracking detalhado
4. **Ajuste trimestral** - Revisar pricing a cada 3 meses

### 7.3 Métricas de Sucesso

| Métrica | Target Q1 | Target Q4 |
|---------|-----------|-----------|
| Clientes pagantes | 5 | 20 |
| MRR | $10,000 | $50,000 |
| Margem bruta | 70% | 75% |
| NPS | 40+ | 50+ |

---

## 8. Fontes

### Preços AWS
- [Amazon RDS PostgreSQL Pricing](https://aws.amazon.com/rds/postgresql/pricing/)
- [Amazon ElastiCache Pricing](https://aws.amazon.com/elasticache/pricing/)
- [Amazon MQ Pricing](https://aws.amazon.com/amazon-mq/pricing/)
- [AWS Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
- [AWS EBS Pricing](https://aws.amazon.com/ebs/pricing/)

### Análise Competitiva
- [Simetrik Official](https://simetrik.com/)
- [Equals Brasil](https://equals.com.br/en/)
- [BlackLine Pricing Analysis](https://www.numeric.io/blog/blackline-pricing)

### Ferramentas
- [AWS Pricing Calculator](https://calculator.aws/)
- [Vantage Instance Comparison](https://instances.vantage.sh/)

---

## Changelog

| Versão | Data | Alteração |
|--------|------|-----------|
| 1.0 | Jan 2026 | Versão inicial |

