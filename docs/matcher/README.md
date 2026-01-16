# Pricing Analysis - Matcher (Lerian)

**Data:** Janeiro 2026
**Produto:** Matcher - Engine de Reconciliação Financeira
**Repositório do Produto:** github.com/lerianstudio/matcher

---

## Documentos Disponíveis

### 1. Proposta de Pricing (Principal)
- **[proposta_pricing_matcher_BRL.md](proposta_pricing_matcher_BRL.md)** - Proposta completa de pricing em Reais
- **[proposta_pricing_matcher_BRL.pdf](proposta_pricing_matcher_BRL.pdf)** - Versão PDF

Conteúdo:
- Tiers: Starter (R$ 3.995), Growth (R$ 9.995), Scale (R$ 24.995), Enterprise
- Análise de custos detalhada com níveis de confiança
- Metodologia Standalone-First
- Racional de cada premissa

### 2. Explicação Técnica
- **[explicacao_tecnica_matcher.md](explicacao_tecnica_matcher.md)** - Como o Matcher funciona
- **[explicacao_tecnica_matcher.pdf](explicacao_tecnica_matcher.pdf)** - Versão PDF

Conteúdo:
- Fluxo completo de operações (diagrama)
- Operações por transação e por match
- Racional de sizing por componente (PostgreSQL, Redis, RabbitMQ)
- Relação TPS → QPS → Infraestrutura
- Comparação de custos Midaz vs Matcher

### 3. Documento de Validação (para time de Dev)
- **[validacao_tps_qps_matcher.md](validacao_tps_qps_matcher.md)** - Perguntas para validação
- **[validacao_tps_qps_matcher.pdf](validacao_tps_qps_matcher.pdf)** - Versão PDF

Conteúdo:
- Fórmula proposta: 1 TPS ≈ 11 QPS
- 11 perguntas para o time de desenvolvimento validar
- Tabela para preenchimento de valores reais

### 4. Limitações e Próximos Passos
- **[limitacoes_e_proximos_passos.md](limitacoes_e_proximos_passos.md)** - O que falta validar
- **[limitacoes_e_proximos_passos.pdf](limitacoes_e_proximos_passos.pdf)** - Versão PDF

Conteúdo:
- O que sabemos vs o que estimamos vs o que não sabemos
- O que o teste de carga vai responder
- Standalone vs Cluster compartilhado
- Roadmap de validação (KubeCost, teste de carga)

### 5. Análise Competitiva
- **[analise_competitiva_matcher.md](analise_competitiva_matcher.md)** - Simetrik e Equals

### 6. Documento Completo (versão inicial)
- **[pricing_matcher_completo.md](pricing_matcher_completo.md)** - Análise completa em USD
- **[pricing_matcher_completo.pdf](pricing_matcher_completo.pdf)** - Versão PDF

---

## Resumo dos Tiers

| Tier | Preço/mês | Transações/mês | Custo Estimado | Margem |
|------|-----------|----------------|----------------|--------|
| **Starter** | R$ 3.995 | 500K | R$ 1.150 | 71% |
| **Growth** | R$ 9.995 | 2M | R$ 2.505 | 75% |
| **Scale** | R$ 24.995 | 10M | R$ 8.400 | 66% |
| **Enterprise** | Custom | Custom | Custom | 75%+ |

---

## Fórmulas Chave

```
TPS_médio = Transações_mês ÷ 2.592.000
TPS_pico = TPS_médio × 3
QPS_infra = TPS_pico × 11
Custo_base ≈ R$ 500 + (TPS_pico × R$ 450)
```

---

## Status

- ✅ Análise de código completa
- ✅ Estimativa de custos AWS
- ✅ Proposta de tiers
- ⏳ Aguardando validação do time de dev (documento enviado)
- ⏳ Aguardando teste de carga
- ⏳ Aguardando medição via KubeCost

---

## Próximos Passos

1. **Imediato:** Enviar `validacao_tps_qps_matcher.pdf` para o time de dev
2. **Curto prazo:** Planejar teste de carga
3. **Médio prazo:** Configurar KubeCost para medição de custo real
4. **Longo prazo:** Refinar pricing com dados reais
