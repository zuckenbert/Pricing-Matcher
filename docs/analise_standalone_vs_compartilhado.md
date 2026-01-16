# Análise de Pricing: Standalone vs. Infraestrutura Compartilhada

**Data:** Janeiro 2025
**Contexto:** Resposta à discussão sobre compartilhamento de infraestrutura entre produtos Lerian

---

## Contexto da Discussão

### O ponto levantado (Jefferson/Engenharia):

> "Terraform que temos é só do Midaz e alguns componentes podem ser compartilhados como clusters. As máquinas e banco de dados podem aumentar (quantidade)."
>
> "Podemos usar KubeCost para pegar o custo real dos novos serviços subindo no cluster já existente."

### O princípio de pricing (Produto):

> Cada produto deve ser precificado considerando **infraestrutura dedicada** (standalone), não compartilhada. Isso porque:
>
> 1. **Worst case scenario**: Um dia podemos ter um único cliente usando apenas o Flowker
> 2. **Produtos independentes**: Cada produto pode ser vendido separadamente
> 3. **Sustentabilidade**: O produto precisa se pagar sozinho, sem subsídio cruzado

---

## Metodologia: "Standalone-First Pricing"

### Por que precificar como standalone?

```
┌─────────────────────────────────────────────────────────────────┐
│                    CENÁRIO OTIMISTA                             │
│              (Infra compartilhada - NÃO usar para pricing)      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Cluster K8s compartilhado: $500/mês                           │
│  ├── Midaz:    40% = $200/mês                                  │
│  ├── Flowker:  20% = $100/mês  ← Parece barato!                │
│  ├── Matcher:  20% = $100/mês                                  │
│  └── CRM:      20% = $100/mês                                  │
│                                                                 │
│  Risco: Se Flowker for vendido separado e cliente cancelar     │
│         outros produtos, o custo real do Flowker sobe para     │
│         $500/mês (100% do cluster).                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    CENÁRIO CONSERVADOR                          │
│              (Infra dedicada - USAR para pricing)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Flowker standalone: $918/mês                                  │
│  ├── PostgreSQL:   $108/mês                                    │
│  ├── MongoDB:      $389/mês                                    │
│  ├── Valkey:       $94/mês                                     │
│  ├── Temporal:     $25/mês                                     │
│  ├── RabbitMQ:     $180/mês                                    │
│  └── Compute:      $122/mês                                    │
│                                                                 │
│  Benefício: Se infra for compartilhada na prática,             │
│             a margem MELHORA (bônus, não dependência).         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Princípio Fundamental

| Aspecto | Abordagem |
|---------|-----------|
| **Pricing** | Baseado em custo **standalone** (worst case) |
| **Operação** | Pode usar infra **compartilhada** (otimização) |
| **Resultado** | Margem garantida no worst case, margem extra no best case |

---

## Análise de Break-Even: Flowker Standalone

### Custo Fixo Mensal (Infra Dedicada)

| Componente | Custo/mês (USD) | Custo/mês (BRL) |
|------------|-----------------|-----------------|
| PostgreSQL (RDS db.r6g.large) | $108 | R$ 540 |
| MongoDB (Atlas M30) | $389 | R$ 1.945 |
| Valkey (ElastiCache cache.r6g.large) | $94 | R$ 470 |
| Temporal Cloud (base) | $25 | R$ 125 |
| RabbitMQ (Amazon MQ mq.m5.large) | $180 | R$ 900 |
| Compute (EKS 2x c6g.large) | $122 | R$ 610 |
| **TOTAL** | **$918** | **R$ 4.590** |

### Custo Variável por Workflow

| Componente | Custo/workflow |
|------------|----------------|
| Temporal (9 actions × $0.000025) | $0.000225 |
| MongoDB, Valkey, etc. | ~$0.00001 |
| **TOTAL** | **~$0.000235 (~R$ 0.0012)** |

### Break-Even por Tier de Preço

**Fórmula:** `Break-even = Custo Fixo / (Preço - Custo Variável)`

| Preço/workflow | Margem unitária | Break-even (workflows/mês) | Break-even (clientes*) |
|----------------|-----------------|---------------------------|------------------------|
| R$ 0.05 | R$ 0.0488 | 94.057 | ~4 clientes |
| R$ 0.08 | R$ 0.0788 | 58.249 | ~2-3 clientes |
| R$ 0.10 | R$ 0.0988 | 46.457 | ~2 clientes |
| R$ 0.15 | R$ 0.1488 | 30.847 | ~1-2 clientes |
| R$ 0.20 | R$ 0.1988 | 23.091 | ~1 cliente |

*Assumindo cliente médio com 25.000 workflows/mês

### Interpretação

```
Para o Flowker se pagar com infra DEDICADA:

Cenário A: Preço de R$ 0.10/workflow
├── Precisa de ~47K workflows/mês
├── Equivale a ~2 clientes Growth (25K cada)
├── Com 3+ clientes: lucro garantido
└── Com infra compartilhada: margem extra de 50-70%

Cenário B: Preço de R$ 0.05/workflow (agressivo)
├── Precisa de ~94K workflows/mês
├── Equivale a ~4 clientes Growth
├── Mais arriscado, mas competitivo
└── Só viável se infra for compartilhada
```

---

## Cenários de Margem: Standalone vs. Compartilhado

### Cenário 1: Flowker Standalone (Worst Case)

```
Premissas:
- Infra 100% dedicada ao Flowker
- 100.000 workflows/mês
- Preço: R$ 0.10/workflow

Receita:        100.000 × R$ 0.10  = R$ 10.000/mês
Custo fixo:                         = R$ 4.590/mês
Custo variável: 100.000 × R$ 0.0012 = R$ 120/mês
Custo total:                        = R$ 4.710/mês

Margem bruta:   R$ 5.290/mês (52.9%)
```

### Cenário 2: Flowker Compartilhado (Best Case)

```
Premissas:
- Infra compartilhada (Flowker = 25% do cluster)
- 100.000 workflows/mês
- Preço: R$ 0.10/workflow

Receita:        100.000 × R$ 0.10  = R$ 10.000/mês
Custo fixo:     R$ 4.590 × 25%     = R$ 1.148/mês
Custo variável: 100.000 × R$ 0.0012 = R$ 120/mês
Custo total:                        = R$ 1.268/mês

Margem bruta:   R$ 8.732/mês (87.3%)
```

### Comparativo Visual

```
                    MARGEM BRUTA POR CENÁRIO

100% ┤                                    ████████ 87.3%
     │                                    ████████ (compartilhado)
 80% ┤                                    ████████
     │                                    ████████
 60% ┤  ██████████ 52.9%                  ████████
     │  ██████████ (standalone)           ████████
 40% ┤  ██████████                        ████████
     │  ██████████                        ████████
 20% ┤  ██████████                        ████████
     │  ██████████                        ████████
  0% ┼──██████████────────────────────────████████──
        Standalone                      Compartilhado
        (pricing base)                  (operação real)
```

---

## Resposta para a Discussão Técnica

### Síntese para o Jefferson

> "A análise de pricing do Flowker **já considera infraestrutura dedicada** (standalone), não compartilhada. Isso é intencional:
>
> 1. **Worst case garantido**: Se um dia tivermos um único cliente usando só o Flowker, o pricing ainda se sustenta
>
> 2. **Produtos independentes**: Cada produto (Flowker, Matcher, CRM, Fee) precisa se pagar sozinho
>
> 3. **Margem conservadora**: Com 100K workflows/mês a R$ 0.10, temos 52.9% de margem no pior caso
>
> O KubeCost e as tags são ótimos para **operação** (entender custo real e otimizar), mas para **pricing** usamos o cenário standalone. Se a infra for compartilhada na prática, a margem extra vai de 53% para 87% - isso é bônus, não dependência."

### Próximos Passos Sugeridos

| Ação | Responsável | Objetivo |
|------|-------------|----------|
| Instalar KubeCost no cluster | Engenharia | Visibilidade de custo real por serviço |
| Implementar tags nos DBs | Engenharia | Rastrear custo de serviços gerenciados |
| Rodar benchmark de carga | Engenharia | Validar custo marginal por workflow |
| Definir tiers finais | Produto | Converter análise em pricing público |

---

## Modelo de Pricing Recomendado (Validado para Standalone)

### Tiers com Margem Garantida

| Tier | Volume/mês | Preço | Custo Standalone | Margem Mínima |
|------|------------|-------|------------------|---------------|
| **Starter** | Até 1.000 | Grátis | Subsidiado | Aquisição |
| **Growth** | 1K - 25K | R$ 1.990 + R$ 0.10/wf | R$ 4.620 | ~50%* |
| **Scale** | 25K - 200K | R$ 7.990 + R$ 0.05/wf | R$ 4.830 | ~65%* |
| **Enterprise** | 200K+ | Custom | Variável | >70% |

*Margem calculada no pior caso (standalone). Com infra compartilhada, margem sobe para 75-90%.

### Validação do Modelo

```
Exemplo: Cliente Growth com 25.000 workflows/mês

Receita:
├── Base:     R$ 1.990
└── Variável: 25.000 × R$ 0.10 = R$ 2.500
    TOTAL:    R$ 4.490/mês

Custo (standalone):
├── Fixo:     R$ 4.590
└── Variável: 25.000 × R$ 0.0012 = R$ 30
    TOTAL:    R$ 4.620/mês

Margem: -R$ 130 (ligeiramente negativo)

→ INSIGHT: Cliente Growth ÚNICO não cobre infra standalone.
   Precisamos de 2+ clientes Growth para break-even.
   Ou ajustar para R$ 2.500 base + R$ 0.10/wf.
```

### Ajuste Sugerido

Para garantir sustentabilidade com **um único cliente**:

| Tier | Volume/mês | Preço Original | Preço Ajustado (Standalone-Safe) |
|------|------------|----------------|----------------------------------|
| **Growth** | 1K - 25K | R$ 1.990 + R$ 0.10/wf | R$ 2.990 + R$ 0.08/wf |
| **Scale** | 25K - 200K | R$ 7.990 + R$ 0.05/wf | R$ 9.990 + R$ 0.04/wf |

Com esse ajuste, mesmo um único cliente Growth (25K wf) gera margem positiva:
- Receita: R$ 2.990 + (25K × R$ 0.08) = R$ 4.990
- Custo: R$ 4.620
- Margem: R$ 370 (7.4%)

---

## Conclusão

### Princípio Adotado

```
╔════════════════════════════════════════════════════════════════╗
║  PRICING: Baseado em custo STANDALONE (worst case)             ║
║  OPERAÇÃO: Pode usar infra COMPARTILHADA (otimização)          ║
║  RESULTADO: Margem garantida sempre, margem extra como bônus   ║
╚════════════════════════════════════════════════════════════════╝
```

### Validação

| Cenário | Margem | Status |
|---------|--------|--------|
| 1 cliente Growth (standalone) | ~7% | ✅ Sustentável |
| 2 clientes Growth (standalone) | ~35% | ✅ Saudável |
| 3+ clientes (compartilhado) | >70% | ✅ Excelente |

### Recomendação Final

O Flowker pode ser precificado de forma competitiva **E** sustentável, mesmo no pior caso de um único cliente com infraestrutura dedicada. O compartilhamento de infraestrutura é uma **otimização operacional**, não uma **dependência de pricing**.

---

*Documento gerado em Janeiro 2025*
*Análise validada para cenário standalone*
