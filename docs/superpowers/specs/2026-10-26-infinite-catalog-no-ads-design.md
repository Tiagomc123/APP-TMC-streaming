# Catálogo contínuo sem publicidade

## Intenção

Manter as abas atuais e carregar páginas adicionais do TMDB conforme o usuário rola Início, Filmes, Séries ou os resultados da busca. Remover o intersticial de publicidade próprio do TMC, inclusive antes da reprodução.

## Abordagem

Manter feeds separados por aba e usar a paginação `page` e `total_pages` do TMDB. O feed Início continua misturando filmes e séries, classificando cada item pelo `media_type`; Filmes, Séries e Busca mantêm seus filtros próprios. A tela de publicidade, o gatilho de reprodução, os parâmetros e o identificador de teste do AdMob serão removidos.

Um feed único substituiria as abas existentes e mudaria a organização pedida; paginação apenas nos feeds atuais deixaria a busca inconsistente. A abordagem escolhida mantém a navegação atual e cobre todos os catálogos remotos.

## Limites e chamadas

- Favoritos e biblioteca continuam locais e não paginam pelo TMDB.
- O carregamento adicional começa perto do fim da grade e deduplica itens por chave.
- Cada aba mantém seu próprio estado de paginação.
- O scanner continua filtrando URLs de anúncios para não tratá-las como streams de vídeo.
- Nenhuma alteração remota ao Supabase é necessária para paginação; o proxy atual já aceita `page` e responde com dados.
