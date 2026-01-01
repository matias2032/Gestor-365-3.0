 Gestão Bar POS

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)

O **Gestão Bar POS** é um sistema de Ponto de Venda (Point of Sale) moderno e intuitivo, desenvolvido com Flutter. Foi desenhado para facilitar o dia a dia de bares e pequenos estabelecimentos, permitindo o controlo total de pedidos, stock e faturação.

Funcionalidades Principais

- Gestão de Inventário: Registo completo de produtos com imagens, categorias e controlo automático de stock.
-  Sistema de Pedidos: Fluxo otimizado para abertura, acompanhamento e finalização de pedidos.
-  Dashboard: Visualização clara das métricas do negócio e resumo de vendas.
-  Gestão de Utilizadores: Sistema de autenticação com diferentes níveis de acesso e gestão de perfis.
-  Sincronização Cloud: Integração com Supabase para sincronização de dados em tempo real.
-  Relatórios PDF: Geração de documentos e faturas em formato PDF.
-  Modo Escuro/Claro: Interface adaptável com suporte a temas.
- 🪵 Logs do Sistema: Histórico de atividades para auditoria e segurança.

 Tecnologias Utilizadas

- Flutter & Dart: Framework principal para desenvolvimento cross-platform.
- Supabase: Backend-as-a-Service para base de dados e autenticação.
- Provider: Gestão de estado e temas.
- PDF: Geração de ficheiros PDF dinâmicos.

 Estrutura do Projeto

```text
lib/
 ├── models/       # Modelos de dados (Produto, Pedido, Utilizador...)
 ├── screens/      # Interfaces do utilizador (UI)
 ├── services/     # Lógica de negócio e integrações (Base de dados, PDF, Sync)
 ├── theme/        # Definições de cores e estilos
 └── widgets/      # Componentes reutilizáveis
