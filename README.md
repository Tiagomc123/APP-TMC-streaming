# TMC — Agregador de Streaming

Aplicativo Flutter para descobrir filmes e séries, organizar uma lista pessoal e reproduzir vídeos e canais ao vivo. O projeto combina metadados do TMDB com fontes de reprodução externas configuradas no aplicativo.

> A disponibilidade do catálogo, dos players externos e dos canais ao vivo depende de serviços de terceiros, da conexão e da região. O TMC não hospeda nem fornece os vídeos.

## Recursos

- Catálogo de filmes e séries com tendências, populares, mais bem avaliados e categorias.
- Busca de títulos, detalhes, temporadas, episódios, recomendações e trailers.
- Reprodução em WebView ou player de vídeo, com tentativa de selecionar fontes disponíveis e qualidade HLS quando a transmissão oferece variantes.
- Controles de reprodução, retomada do ponto assistido e lista “Continuar assistindo”.
- Favoritos e histórico/progresso vinculados a perfis locais.
- Cadastro e login locais no dispositivo; backup e reimportação de dados pela interface do app.
- Canais ao vivo predefinidos e possibilidade de adicionar links `.m3u8` próprios.
- Interface adaptada para Android e Android TV, incluindo navegação por controle remoto.
- Script PowerShell para atualizar o app e preservar a chave TMDB já configurada na cópia local.

## Tecnologias

- Flutter e Dart
- TMDB API para catálogo e metadados
- `http`, `video_player` e `webview_flutter`
- `shared_preferences` e `path_provider` para preferências e persistência local
- `google_fonts` para tipografia

## Requisitos

- Flutter SDK compatível com Dart `^3.13.2` (veja `environment` em `pubspec.yaml`).
- Android Studio/SDK para compilar e executar no Android ou Android TV.
- Uma chave de API do TMDB para carregar catálogo, imagens e detalhes.

Confira a instalação do Flutter com:

```bash
flutter doctor
```

## Configuração

1. Clone o repositório e entre na pasta do projeto:

   ```bash
   git clone https://github.com/Tiagomc123/APP-TMC-streaming.git
   cd APP-TMC-streaming
   ```

2. Obtenha uma chave de API no [TMDB](https://www.themoviedb.org/settings/api).

3. O aplicativo usa o proxy `tmdb-proxy` do Supabase para consultar o TMDB. A chave privada da API do TMDB fica somente no secret `TMDB_API_KEY` do Supabase; ela não deve ser adicionada ao Flutter nem ao GitHub. O app envia apenas a chave pública `sb_publishable_` no cabeçalho `apikey`.

4. Baixe as dependências:

   ```bash
   flutter pub get
   ```

## Executar

Listar dispositivos disponíveis:

```bash
flutter devices
```

Executar em um dispositivo Android conectado ou emulador:

```bash
flutter run
```

Executar no navegador (se o alvo Web estiver habilitado no seu ambiente Flutter):

```bash
flutter run -d chrome
```

## Compilar

APK de instalação Android:

```bash
flutter build apk --release
```

App Bundle para publicação Android:

```bash
flutter build appbundle --release
```

Build Web:

```bash
flutter build web --release
```

Os diretórios `ios/`, `macos/`, `linux/` e `windows/` contêm scaffolds Flutter. A disponibilidade de cada recurso, especialmente reprodução de vídeo e WebView, pode variar por plataforma; o foco principal do projeto é Android/Android TV.

## Atualizador PowerShell

O repositório contém `atualizar.ps1`, que aplica a versão incluída no próprio script, garante algumas dependências/configurações e executa `flutter pub get` e `flutter analyze`.

No PowerShell, a partir da raiz do projeto:

```powershell
powershell -ExecutionPolicy Bypass -File .\atualizar.ps1
```

O script cria `lib/main.dart.bak` antes de substituir o arquivo e tenta preservar uma chave TMDB já configurada em `lib/main.dart`. Revise as alterações geradas antes de fazer commit.

## Verificações

Analisar o código Dart:

```bash
flutter analyze
```

Executar os testes automatizados:

```bash
flutter test
```

## Estrutura do projeto

```text
lib/main.dart                 Código principal do app
assets/                       Ícones e recursos gráficos
android/                      Projeto Android e configuração Android TV
ios/                          Projeto iOS
macos/                        Projeto macOS
linux/                        Projeto Linux
windows/                      Projeto Windows
web/                          Arquivos do alvo Web
test/                          Testes Flutter
atualizar.ps1                 Script PowerShell de atualização
pubspec.yaml                  Dependências e configuração Flutter
```

## Dados e privacidade

Perfis, favoritos, progresso e preferências são armazenados localmente no dispositivo/navegador. O cadastro local não é uma conta remota e não sincroniza automaticamente entre dispositivos. O backup descrito pelo app é local; guarde uma cópia do arquivo de backup em local seguro se precisar transferi-la ou restaurá-la depois.

A chave TMDB deve ser configurada pelo desenvolvedor. Evite publicar chaves e outros segredos em repositórios ou capturas de tela.

## Créditos

- [TMDB](https://www.themoviedb.org/) fornece metadados e imagens. Este produto usa a API do TMDB, mas não é endossado nem certificado pelo TMDB.
- Flutter e os pacotes listados em `pubspec.yaml` são projetos de seus respectivos mantenedores.
