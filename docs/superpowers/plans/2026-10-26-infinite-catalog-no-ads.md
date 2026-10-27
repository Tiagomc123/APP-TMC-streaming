# Catálogo contínuo sem publicidade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paginar o catálogo TMDB automaticamente durante a rolagem e remover a publicidade intersticial própria do TMC.

**Architecture:** O repositório TMDB retorna itens e metadados da página. Cada grade e a tela de busca controlam seu próprio cursor, adicionam resultados sem duplicatas e param em `total_pages`. O caminho de reprodução vai direto ao resolvedor sem criar uma tela de anúncio.

**Tech Stack:** Flutter, Dart, HTTP do TMDB via Supabase Edge Function.

**Spec:** `docs/superpowers/specs/2026-10-26-infinite-catalog-no-ads-design.md`

## Global Constraints

- Preservar as abas atuais, favoritos locais e o fluxo de detalhes/reprodução.
- Usar o parâmetro de página suportado pela API TMDB e encerrar na página máxima retornada.
- Remover o intersticial interno, sem remover o filtro de streams de publicidade.

## Review Focus

- Rolagem curta em Android TV deve continuar buscando até a grade ficar rolável ou acabar o catálogo.
- Requisições simultâneas de paginação não podem duplicar itens.
- Trocar filme/série ou consulta na busca invalida respostas antigas.
- Tendências mistas devem manter IDs e telas de detalhes de séries como séries.
- Lista local e favoritos não devem disparar paginação remota.

---

### Task 1: Paginação do repositório TMDB

**Files:**
- Modify: `lib/data/repositories/tmdb_repository.dart`
- Create or update the page result type in the same file.

- [x] Adicionar tipo de resultado com itens, página atual e total de páginas.
- [x] Passar `page` em tendências, populares, busca de filmes e busca de séries.
- [x] Manter filtros mistos de tendências e limite de páginas reportado pelo TMDB.

### Task 2: Rolagem infinita por aba e busca

**Files:**
- Modify: `lib/ui/screens/home_screen.dart`
- Modify: `lib/ui/screens/search_screen.dart`
- Modify: `lib/data/models/media_item.dart`

- [x] Fazer as grades incrementarem páginas perto do fim da rolagem, com carregamento e deduplicação.
- [x] Fazer busca paginar e ignorar respostas antigas após consulta ou tipo alterado.
- [x] Preservar `media_type` para classificar séries em tendências.

### Task 3: Remover publicidade própria

**Files:**
- Modify: `lib/main.dart`, `lib/core/app_config.dart`, `lib/ui/screens/home_screen.dart`, `lib/ui/screens/search_screen.dart`, `lib/ui/screens/details_screen.dart`, `android/app/src/main/AndroidManifest.xml`
- Delete: `lib/services/ads/ad_gate_service.dart`, `lib/ui/screens/ad_gate_screen.dart`

- [x] Remover dependências, parâmetros, chamada pre-play, configuração de frequência e tela de anúncio.
- [x] Remover o App ID de teste do AdMob do Manifest.
- [x] Confirmar análise estática e ausência de referências ativas ao intersticial.
