import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:google_sheets_orm/orm.dart';

class CreateCategoria extends StatefulWidget {
  const CreateCategoria({super.key});

  @override
  State<CreateCategoria> createState() => _CreateCategoriaState();
}

class _CreateCategoriaState extends State<CreateCategoria> {
  final db = GoogleSheetsDatabase();
  SheetORM get repo => db.repo("Categorias");
  SheetORM get repoProd => db.repo("Produtos");

  Future<void> _addCategoria() async {
    // Exemplo: Criando categoria via diálogo ou input
    await repo.create({
      "nome_categoria": "Nova Categoria ${DateTime.now().second}",
    });
    setState(() {}); // Atualiza a lista
  }

  Future<void> _delete(String id) async {
    await repo.delete(id);
    setState(() {});
  }

  Future<void> _update(String id, String nomeAtual) async {
    await repo.updateWhereId(id, {"nome_categoria": "$nomeAtual (Editado)"});
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: repo.findAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Erro: ${snapshot.error}"));
          }

          final categorias = snapshot.data ?? [];

          if (categorias.isEmpty) {
            return const Center(child: Text("Nenhuma categoria encontrada."));
          }

          return ListView.builder(
            itemCount: categorias.length,
            itemBuilder: (context, index) {
              final cat = categorias[index];
              final id = cat['id'].toString();
              final nome = cat['nome_categoria'] ?? "Sem nome";

              return ListTile(
                leading: CircleAvatar(child: Text(id)),
                title: Text(nome),
                onTap: () => _update(id, nome),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => _delete(id),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: .min,
        children: [
          FloatingActionButton(
            heroTag: null,
            onPressed: () async {
              final test = await repoProd.find(column: "id", value: 7);
              log(test.toString());
            },
            child: const Icon(Icons.search),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _addCategoria,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
