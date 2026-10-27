# Editar fontes externas

O app lê as fontes habilitadas da tabela `public.tmc_sources` pelo Edge Function
`tmc-sources`. A tabela é privada para o app; edite pelo Supabase Dashboard,
com sua conta de administrador.

## Adicionar ou remover um domínio de um provedor existente

No Dashboard, abra **Table Editor → public.tmc_sources**. Cada linha é um
provedor e `urls` é a lista de endereços HTTPS que ele tentará em sequência.
Edite essa lista para incluir ou excluir um domínio. Desmarque `enabled` para
desligar o provedor sem apagar a configuração.

Os domínios do arquivo antigo foram importados. Os quatro IDs que o app já
consegue resolver e estão ativos são `superflix_api`, `warezcdn`, `embedcine`
e `pontofinal`. Os outros provedores do arquivo também ficaram salvos, mas
desativados até receberem um adaptador de reprodução no app.

Há dez linhas vazias (`custom_01` a `custom_10`) reservadas para você cadastrar
futuras fontes. Ao preencher uma delas, ela continuará sem efeito no app até
que exista um adaptador compatível e o ID seja ligado a esse adaptador.

Também é possível editar no SQL Editor:

```sql
update public.tmc_sources
set urls = array['https://dominio-atual.com', 'https://novo-espelho.com']
where id = 'embedcine';

update public.tmc_sources
set enabled = false
where id = 'pontofinal';
```

Para remover definitivamente um provedor da lista, exclua a linha. Para apenas
retirar um espelho, salve a lista `urls` sem aquele endereço. O app atualiza o
cache remoto em até cinco minutos; reabra os detalhes ou aguarde a próxima
resolução para carregar a configuração.

Cada provedor tem um formato de página/API próprio. Um novo domínio que use o
formato de um dos quatro IDs pode ser adicionado à lista sem recompilar o app.
Um site com protocolo diferente precisa de um adaptador no código do provedor.

Os trailers são independentes: seus IDs e metadados vêm exclusivamente da API
de vídeos do TMDB, e o player os reproduz pelo YouTube.
