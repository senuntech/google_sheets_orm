### 📊 Google Sheets ORM
##### Este package transforma o Google Sheets em um banco de dados dinâmico para aplicações Flutter, permitindo operações de CRUD utilizando Mapas (JSON), com gerenciamento automático de IDs, criação de abas, relacionamentos (Foreign Keys), Fórmulas e Proteção de Células.


### 🛠️ 1. Configuração do Ambiente (Google Cloud)
Antes de codar, você precisa configurar seu projeto no Google Cloud Console:

Habilitar APIs: Ative a **Google Sheets API** e a **Google Drive API**.

Configurar Escopos: Garanta que seu login solicite os seguintes escopos:
`https://www.googleapis.com/auth/spreadsheets`
`https://www.googleapis.com/auth/drive.file`

### 🚀 2. Instalação
Adicione as dependências no seu `pubspec.yaml`:
```yaml
dependencies:
  google_sheets_orm: ^1.4.0
  googleapis: ^13.2.0
  google_sign_in: ^6.2.1
  extension_google_sign_in_as_googleapis_auth: ^2.0.12
```

### 🏗️ 3. Inicialização da Base de Dados
O `GoogleSheetsDatabase` é um Singleton. Você deve inicializá-lo uma única vez (geralmente após o login ou no splash screen). Este processo busca o arquivo no Drive ou o cria automaticamente se não existir.

```dart
import 'package:google_sheets_orm/orm.dart';

final db = GoogleSheetsDatabase();

// Obtenha o cliente autenticado (Exemplo via GoogleSignIn)
final googleUser = await GoogleSignIn(scopes: [
  'https://www.googleapis.com/auth/spreadsheets',
  'https://www.googleapis.com/auth/drive.file',
]).signIn();

final httpClient = (await googleUser?.authenticatedClient())!;

// Configura o nome do arquivo, estrutura de abas/colunas, foreign keys e fórmulas
await db.initialize(
  httpClient: httpClient,
  fileName: "Minha_Base_Dados_App",
  structure: {
    "Clientes": ["id", "nome"],
    "Debitos": ["id", "id_cliente", "valor", "nome_cliente"],
  },
  foreignKeys: [
    ForeignKey(
      sourceTable: 'Debitos',
      sourceKeyColumn: 'id_cliente',
      sourceTargetColumn: 'nome_cliente',
      lookupTable: 'Clientes',
      lookupKeyColumn: 'id',
      lookupResultColumn: 'nome',
      onDeleteCascade: true, // Habilita a exclusão em cascata automática
    ),
  ],
  formulas: [
    Formula(
      sheet: 'Debitos',
      range: 'E:E',
      formula: '=C2*1.1', // Fórmula de exemplo para aplicar na coluna inteira
      isProtected: true, // Protege a coluna contra edição manual
    )
  ]
);
```


### 📝 4. Operações CRUD (SheetORM)
Com a base inicializada, você pode realizar operações em qualquer aba definida na estrutura.

**Acessando o Repositório**
```dart
final db = GoogleSheetsDatabase();
SheetORM get repo => db.repo("Debitos");
```

#### Criar Registro (Insert / InsertAll)
O campo `id` é gerado e retornado automaticamente (Auto-incremento).
```dart
// Inserir um único registro
int novoId = await repo.insert({
  "id_cliente": "1",
  "valor": 4500.00,
});

// Inserir múltiplos registros de uma vez
List<int> ids = await repo.insertAll([
  {"id_cliente": "1", "valor": 100},
  {"id_cliente": "2", "valor": 200},
]);
```

#### Ler Dados (Find / FindAll / FindById)
Retorna uma `List<Map<String, dynamic>>`, facilitando a conversão para Models/Entidades.
```dart
final todos = await repo.findAll();

// Busca específica (Ex: WHERE id_cliente = '1')
final meusDebitos = await repo.find(column: "id_cliente", value: "1");

// Busca por ID
final debito = await repo.findById(10);
```

#### Atualizar Registro (Update)
Atualiza as colunas enviadas no mapa, localizando o registro na planilha pelo `id`. Colunas controladas por Foreign Keys são ignoradas na atualização para não quebrar fórmulas.
```dart
await repo.updateWhereId("10", {
  "valor": 4200.00, 
});
```

#### Deletar Registro (Delete / DeleteWhere)
Remove as linhas fisicamente da planilha. Com suporte nativo a Exclusão em Cascata!
```dart
// Deletar linha específica por ID
await repo.delete("10");

// Deletar utilizando Query básica
await repo.deleteWhere("valor>1000"); 
```

### 🔗 5. Recursos Avançados

#### 1. Foreign Keys e Relacionamentos
O ORM gerencia relacionamentos usando a classe `ForeignKey`. Ele injeta automaticamente fórmulas (`ARRAYFORMULA` + `PROCX/XLOOKUP`) no Sheets para popular dados relacionados (ex: buscar o nome do cliente no débito de forma reativa).

#### 2. Exclusão em Cascata (ON DELETE CASCADE)
Se você ativar `onDeleteCascade: true` em uma `ForeignKey`, deletar um registro pai (Ex: `Clientes`) irá buscar e deletar todos os registros dependentes (Ex: `Debitos` daquele cliente) de forma recursiva. O ORM consolida todas as deleções de todas as abas utilizando uma única requisição (`BatchUpdate`) altamente otimizada na API do Google Sheets.

#### 3. Proteção Automática de Colunas
Por padrão, as colunas alvo de `ForeignKey` e `Formula` são configuradas no Google Sheets com regras de proteção de intervalo (`Protected Range`). O ORM solicita à API que exiba um aviso caso um usuário tente editar manualmente essas colunas calculadas na interface web do Planilhas.


### 📂 6. Arquitetura do Sistema

| Componente  | Função|
| ------------- |:-------------:|
| GoogleSheetsDatabase | Singleton que armazena a conexão e orquestra a criação de Foreign Keys, Fórmulas, Proteções e Deleção em Cascata Atômica. |
| SheetORM | Classe que representa um repositório e executa as operações na aba (Insert, Update, Delete, Find). |
| Auto-Increment | Lógica interna que procura a coluna 'id' para gerar iterativamente o próximo número de forma automática. |
