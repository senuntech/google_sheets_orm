import 'package:flutter/material.dart';
import 'package:google_sheets_orm/orm.dart';

class CreateProduto extends StatefulWidget {
  const CreateProduto({super.key});

  @override
  State<CreateProduto> createState() => _CreateProdutoState();
}

class _CreateProdutoState extends State<CreateProduto> {
  final db = GoogleSheetsDatabase();
  SheetORM get repo => db.repo("Produtos");

  Future<void> addProduto() async {
    await repo.insert({
      "nome": "Produto Novo",
      "preco": 25.00,
      "id_categoria": 1,
      "updated_at": DateTime.now().toIso8601String(),
    });
    setState(() {});
  }

  Future<void> insertAll() async {
    final list = List.generate(
      100,
      (index) => {
        "nome": "Produto Novo",
        "preco": 25.00,
        "id_categoria": 10,
        "updated_at": DateTime.now().toIso8601String(),
      },
    );

    await repo.insertAll(list);

    setState(() {});
  }

  Future<void> deleteWhere(String query) async {
    await repo.deleteWhere(query);
    setState(() {});
  }

  Future<void> update(String id) async {
    await repo.updateWhereId(id, {
      "nome": "Alterado via Singleton",
      "updated_at": DateTime.now().toIso8601String(),
    });
    setState(() {});
  }

  Future<void> delete(String id) async {
    await repo.delete(id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CRUD via Singleton')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: repo.findAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final list = snapshot.data ?? [];

          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              final id = item['id'].toString();

              return ListTile(
                title: Text("${item['id']} - ${item['nome']}"),
                subtitle: Text("${item['preco']}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => delete(id),
                ),
                onTap: () => update(id),
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
            onPressed: () => deleteWhere("id_categoria=10"),
            child: const Icon(Icons.delete),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            heroTag: null,
            onPressed: insertAll,
            child: const Icon(Icons.add_circle_rounded),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            heroTag: null,
            onPressed: addProduto,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
