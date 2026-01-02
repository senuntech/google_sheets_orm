import 'package:example/create_categoria.dart';
import 'package:example/create_produto.dart';
import 'package:flutter/material.dart';
import 'package:google_sheets_orm/orm.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;

void main() => runApp(
  MaterialApp(
    home: SheetsPoc(),
    routes: {
      '/create-produto': (context) => CreateProduto(),
      '/create-categoria': (context) => CreateCategoria(),
    },
  ),
);

class SheetsPoc extends StatefulWidget {
  @override
  _SheetsPocState createState() => _SheetsPocState();
}

class _SheetsPocState extends State<SheetsPoc> {
  final GoogleSignIn googleSignIn = GoogleSignIn(
    scopes: [sheets.SheetsApi.spreadsheetsScope, drive.DriveApi.driveScope],
  );
  GoogleSignInAccount? _currentUser;

  @override
  void initState() {
    super.initState();
    googleSignIn.onCurrentUserChanged.listen((account) {
      setState(() => _currentUser = account);
    });
  }

  Future<void> _handleSignIn() async {
    try {
      await googleSignIn.signIn();
      await setupDatabase();
    } catch (error) {
      print('Erro no login: $error');
    }
  }

  Future<void> setupDatabase() async {
    final gsheets = GoogleSheetsDatabase();
    var httpClient = (await googleSignIn.authenticatedClient())!;

    final minhaEstrutura = {
      "Produtos": [
        "id",
        "nome",
        "preco",
        "id_categoria",
        "nome_da_categoria",
        "teste",
      ],
      "Categorias": ["id", "nome_categoria", "id_produto", "nome"],
    };

    await gsheets.initialize(
      httpClient: httpClient,
      fileName: "Minha Base",
      structure: minhaEstrutura,
      foreignKeys: [
        ForeignKey(
          sourceTable: "Produtos",
          sourceKeyColumn: "id_categoria",
          sourceTargetColumn: "nome_da_categoria",
          lookupTable: "Categorias",
          lookupKeyColumn: "id",
          lookupResultColumn: "nome_categoria",
        ),
        ForeignKey(
          sourceTable: "Categorias",
          sourceKeyColumn: "id_produto",
          sourceTargetColumn: "nome",
          lookupTable: "Produtos",
          lookupKeyColumn: "id",
          lookupResultColumn: "teste",
        ),
      ],
    );

    print("Pronto para usar a planilha: ${gsheets.spreadsheetId}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Google Sheets PoC")),
      body: Center(
        child: _currentUser == null
            ? ElevatedButton(
                onPressed: _handleSignIn,
                child: Text("Logar com Google"),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Olá, ${_currentUser!.displayName}"),
                  SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/create-categoria');
                    },
                    child: Text("Adicionar Categoria"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/create-produto');
                    },
                    child: Text("Adicionar Produto"),
                  ),
                ],
              ),
      ),
    );
  }
}
