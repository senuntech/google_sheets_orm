### 📊 Google Sheets ORM
##### Este package transforma o Google Sheets em um banco de dados dinâmico para aplicações Flutter, permitindo operações de CRUD (Create, Read, Update, Delete) utilizando Mapas (JSON), com gerenciamento automático de IDs e criação de tabelas.


### 🛠️ 1. Configuração do Ambiente (Google Cloud)
Antes de codar, você precisa configurar seu projeto no Google Cloud Console:

Habilitar APIs: Ative a Google Sheets API e a Google Drive API.

Configurar Escopos: Garanta que seu login solicite os seguintes escopos:

https://www.googleapis.com/auth/spreadsheets

https://www.googleapis.com/auth/drive.file

### 🚀 2. Instalação
Adicione as dependências no seu pubspec.yaml:
```
dependencies:
  google_sheets_orm: # Caminho para o seu package
  googleapis: ^13.0.0
  google_sign_in: ^6.2.1
  extension_google_sign_in_as_googleapis_auth: ^2.0.0
```

### 🏗️ 3. Inicialização da Base de Dados
O GoogleSheetsDatabase é um Singleton. Você deve inicializá-lo uma única vez (geralmente após o login ou no splash screen). Este processo busca o arquivo no Drive ou o cria automaticamente se não existir.

```dart
final db = GoogleSheetsDatabase();

// Obtenha o cliente autenticado (Exemplo via GoogleSignIn)
final googleUser = await GoogleSignIn(scopes: [
  'https://www.googleapis.com/auth/spreadsheets',
  'https://www.googleapis.com/auth/drive.file',
]).signIn();

final httpClient = (await googleUser?.authenticatedClient())!;

// Configura o nome do arquivo e a estrutura de abas/colunas
await db.initialize(
  httpClient: httpClient,
  fileName: "Minha_Base_Dados_App",
  structure: {
    "Produtos": ["id", "descricao", "valor", "estoque"],
    "Categorias": ["id", "nome_categoria"],
  },
);
```


### 📝 4. Operações CRUD (SheetORM)
Com a base inicializada, você pode realizar operações em qualquer aba definida na estrutura.

Acessando o Repositório
Dentro de sua StatefulWidget ou Controller, crie um acesso rápido ao ORM:

```dart
final db = GoogleSheetsDatabase();
SheetORM get repo => db.repo("Produtos");
```

##### Criar Registro (Create)
O campo id é gerado automaticamente (Auto-incremento).

```dart
await repo.create({
  "descricao": "Notebook Gamer",
  "valor": 4500.00,
  "estoque": 10,
});
```

#### Ler Todos os Dados (Find All)
Retorna uma List<Map<String, dynamic>>, facilitando o uso em ListViews.

```dart
final produtos = await repo.findAll();
print(produtos[0]['descricao']); // Saída: Notebook Gamer
```

#### Atualizar Registro (Update)
Atualiza apenas as colunas enviadas no mapa, localizando o registro pelo id.

```dart
await repo.updateWhereId("1", {
  "valor": 4200.00, // Preço promocional
});
```

#### Deletar Registro (Delete)
Remove a linha fisicamente da planilha.
```dart
await repo.delete(1);
```

### 📂 5. Arquitetura do Sistema

| Componente  | Função|
| ------------- |:-------------:|
| GoogleSheetsDatabase      | Singleton que armazena a conexão (api) e o ID da planilha. Resolve o GID das abas. |
| SheetORM      | Classe responsável pela lógica de negócio. Converte linhas (Lists) em objetos amigáveis (Maps). |
| Auto-Increment     |Lógica interna que lê a coluna 'id' e gera o próximo número inteiro.|


### 💡 Dicas de Uso

- Tipagem: Embora o Sheets armazene texto, o ORM usa USER_ENTERED, permitindo que o Google Sheets reconheça datas e números automaticamente.

- Performance: O método updateWhereId foi otimizado para atualizar a linha inteira de uma vez, reduzindo o consumo da cota da API.

- Relacionamentos: Para simular chaves estrangeiras, basta salvar o id da categoria dentro da coluna id_categoria do produto.
