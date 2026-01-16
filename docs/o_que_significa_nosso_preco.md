# O Que Significa o Preço que Calculamos

**Documento:** Entendendo as Limitações e Validade da Análise de Pricing
**Produtos:** Matcher e Flowker (Lerian)
**Data:** Janeiro 2026

---

## 1. Tipo de Preço que Calculamos

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                    É um PREÇO TETO (ceiling price)                          │
│                    baseado em INFRA DEDICADA                                │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   SIGNIFICA:                                                                 │
│   ──────────                                                                 │
│   "Se tivermos UM único cliente usando o produto sozinho,                   │
│    quanto custaria a infraestrutura DELE?"                                  │
│                                                                              │
│   É o cenário PIOR CASO (worst case).                                       │
│   Se o custo real for menor, a margem extra é BÔNUS.                        │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   NÃO SIGNIFICA:                                                             │
│   ───────────────                                                            │
│   ✗ NÃO é o máximo que a infra aguenta (não sabemos isso)                   │
│   ✗ NÃO é o mínimo (pode ser muito menos com cluster compartilhado)         │
│   ✗ NÃO é o custo REAL (nunca medimos em produção)                          │
│   ✗ NÃO é validado por teste de carga                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. O Que Sabemos vs O Que Não Sabemos

### 2.1 Alta Confiança (o que sabemos)

| Item | Confiança | Fonte |
|------|-----------|-------|
| Preços de tabela AWS | 100% | aws.amazon.com/pricing |
| Quais componentes usa (PostgreSQL, Redis, etc) | 100% | docker-compose.yml |
| Estrutura do código (operações por transação) | 95% | Código fonte analisado |
| Metodologia Standalone-First | 100% | Princípio de negócio |

### 2.2 Baixa Confiança (o que NÃO sabemos)

| Item | Confiança | Por quê? |
|------|-----------|----------|
| Se a infra aguenta o volume estimado | 60% | Sem teste de carga |
| Quantas operações REAIS por transação | 75% | GORM pode adicionar queries |
| Qual é o gargalo (CPU? DB? Memória?) | 50% | Sem profiling |
| Comportamento sob pico | 50% | Sem stress test |
| Custo em cluster compartilhado | 40% | Sem KubeCost |

---

## 3. Confiança Geral da Análise

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                    CONFIANÇA GERAL: 65% ±35%                                │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   O que isso significa na prática:                                          │
│                                                                              │
│   CENÁRIO PESSIMISTA (custo +35%):                                          │
│   ├─ Infra não aguenta o sizing que estimamos                               │
│   ├─ Precisamos de instâncias maiores                                       │
│   ├─ Custo Starter: R$ 1.150 → R$ 1.550                                    │
│   └─ Margem cai de 71% para 61% (ainda OK)                                 │
│                                                                              │
│   CENÁRIO OTIMISTA (custo -35%):                                            │
│   ├─ Infra aguenta mais do que estimamos                                    │
│   ├─ Podemos usar instâncias menores                                        │
│   ├─ Custo Starter: R$ 1.150 → R$ 750                                      │
│   └─ Margem sobe de 71% para 81%                                           │
│                                                                              │
│   CENÁRIO CLUSTER COMPARTILHADO:                                            │
│   ├─ Matcher roda junto com Midaz                                           │
│   ├─ Custo incremental muito menor                                          │
│   ├─ Custo Starter: R$ 1.150 → R$ 300-500                                  │
│   └─ Margem sobe para 85-90%                                               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Espectro de Preços Possíveis

```
                    ESPECTRO DE PREÇOS (Tier Starter)

   PREÇO MÍNIMO           O QUE CALCULAMOS           PREÇO MÁXIMO
   (cluster shared)       (standalone)               (se sizing errado)
        │                      │                           │
        ▼                      ▼                           ▼
   ─────●──────────────────────●───────────────────────────●─────────────
        │                      │                           │
   ~R$ 1.500/mês          R$ 3.995/mês               ~R$ 5.200/mês


   O QUE CADA PONTO SIGNIFICA:
   ───────────────────────────

   R$ 1.500/mês (MÍNIMO)
   └─ Se o Matcher rodar no mesmo cluster que o Midaz
      aproveitando infra já paga. Custo marginal apenas.

   R$ 3.995/mês (CALCULADO) ← NOSSO PREÇO
   └─ Se o cliente precisar de infra 100% dedicada.
      Isso é o que usamos como referência.

   R$ 5.200/mês (MÁXIMO)
   └─ Se nossas estimativas estiverem erradas
      e precisarmos de instâncias 35% maiores.
```

---

## 5. A Grande Pergunta: Até Quanto a Infra Aguenta?

### Resposta Honesta: NÃO SABEMOS

O que fizemos foi uma **estimativa teórica**:

```
1. Olhamos o código → contamos operações por transação
2. Olhamos specs da AWS → estimamos capacidade das instâncias
3. Multiplicamos → chegamos em um número de TPS

EXEMPLO (Tier Starter):
├─ db.t3.medium tem ~3.200 IOPS (spec AWS)
├─ Assumimos que 1 TPS = 11 operações de banco
├─ Logo: 3.200 IOPS ÷ 11 = ~290 TPS teórico máximo
├─ Com margem de segurança (70%): ~200 TPS
└─ Tier Starter tem 0.58 TPS pico → MUITO abaixo do limite teórico
```

### Por Que Isso Pode Estar Errado

| Fator | Impacto Potencial |
|-------|-------------------|
| GORM adiciona queries extras | +50-100% operações |
| Latência entre componentes | Reduz throughput real |
| CPU satura antes do banco | Gargalo inesperado |
| Contenção de locks no Redis | Reduz paralelismo |
| Queries de reporting/audit | +20-30% carga |

### O Que o Teste de Carga Responderia

1. **Throughput real**: Quantas transações/segundo REALMENTE aguenta
2. **Multiplicador TPS→QPS**: Quantas queries reais por transação
3. **Ponto de saturação**: Quando a infra começa a degradar
4. **Gargalo real**: O que quebra primeiro (CPU? Memória? I/O?)

---

## 6. Para Que Serve Esse Preço

### ✅ É SEGURO usar para:

| Uso | Por quê funciona |
|-----|------------------|
| Planejamento interno | Número conservador, não vai dar prejuízo |
| Conversas iniciais com clientes | "Na faixa de R$ 3-4K/mês" |
| Comparação com concorrentes | Ordem de magnitude correta |
| Definir tiers de volume | Proporções entre tiers fazem sentido |
| Garantir margem mínima | Mesmo no pior caso, não perde dinheiro |

### ❌ NÃO é seguro usar para:

| Uso | Por quê é arriscado |
|-----|---------------------|
| Fechar contratos de longo prazo | Custo real pode ser diferente |
| Publicar como preço oficial | Pode precisar ajustar depois |
| Prometer SLA de performance | Não validamos capacidade |
| Calcular ROI preciso | Margem real é incerta |

---

## 7. Comparativo: Flowker vs Matcher

| Aspecto | Flowker | Matcher |
|---------|---------|---------|
| Metodologia | Standalone-First | Standalone-First |
| Confiança geral | 65-75% | 65% ±35% |
| Tipo de preço | Teto (ceiling) | Teto (ceiling) |
| Teste de carga | Não | Não |
| KubeCost | Não | Não |
| Terraform produção | Não | Não |
| Análise de código | Sim | Sim |
| Preços AWS validados | Sim | Sim |

**Conclusão**: Ambas as análises têm o mesmo nível de maturidade e as mesmas limitações.

---

## 8. O Que Aumentaria Nossa Confiança

### De 65% para 85%+

```
┌─────────────────────────────────────────────────────────────────────────────┐
│   AÇÕES NECESSÁRIAS PARA VALIDAR O PRICING                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. TESTE DE CARGA (impacto: +15% confiança)                               │
│      └─ Responde: "Quanto a infra realmente aguenta?"                       │
│                                                                              │
│   2. KUBECOST 30 DIAS (impacto: +10% confiança)                             │
│      └─ Responde: "Quanto custa processar X transações?"                    │
│                                                                              │
│   3. VALIDAÇÃO DO TIME DE DEV (impacto: +5% confiança)                      │
│      └─ Responde: "O multiplicador TPS→QPS está correto?"                   │
│                                                                              │
│   4. PROFILING EM PRODUÇÃO (impacto: +5% confiança)                         │
│      └─ Responde: "Qual é o gargalo real?"                                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Recomendação de Uso

### Agora (sem validação)

```
✅ FAZER:
├─ Usar R$ 3.995 como referência interna
├─ Falar "na faixa de R$ 3-4K" com clientes
├─ Planejar com margem de 60-75%
└─ Priorizar teste de carga

❌ NÃO FAZER:
├─ Publicar preço como oficial
├─ Fechar contrato >12 meses sem cláusula de reajuste
├─ Prometer capacidade específica
└─ Assumir que o custo está 100% correto
```

### Depois do Teste de Carga

```
Com dados reais, poderemos:
├─ Confirmar ou ajustar os tiers
├─ Publicar preço oficial
├─ Fechar contratos de longo prazo
└─ Definir SLAs de capacidade
```

---

## 10. Resumo Executivo

| Pergunta | Resposta |
|----------|----------|
| **O preço faz sentido?** | Sim, como REFERÊNCIA e TETO |
| **É o custo real?** | Não, é uma estimativa |
| **Pode ser menor?** | Sim, até 35-50% menor com cluster compartilhado |
| **Pode ser maior?** | Sim, até 35% maior se sizing estiver errado |
| **Quando saberemos o valor real?** | Após teste de carga + KubeCost |
| **Posso usar agora?** | Sim, para planejamento e conversas iniciais |
| **Posso publicar?** | Não recomendado até validar |

---

**Conclusão**: O preço que calculamos é um **teto conservador** que garante que não perderemos dinheiro, mesmo no pior cenário. Mas para definir o preço final de go-to-market, precisamos validar com teste de carga e medição de custo real.

---

*Documento gerado em Janeiro 2026*
*Status: Análise preliminar - Aguardando validação técnica*
