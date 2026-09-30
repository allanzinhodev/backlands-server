# Comandos in-game (talkactions)

Referência de todos os comandos digitáveis no chat do jogo, levantada direto dos
scripts em 2026-09-29. Fonte da verdade: os próprios scripts (`TalkAction(...)`)
em [`data/scripts/`](../data/scripts/) — ao criar/alterar um comando, atualize
esta página.

No jogo, **`/commands`** (ou `!commands`) lista os comandos que a sua conta pode
usar.

## Como funciona a permissão

O core (`src/talkaction.cpp`) checa duas coisas antes de rodar o script:

| Checagem | Setada no script por | Passa quando |
|----------|----------------------|--------------|
| **access** | `talkaction:access(true)` | o **grupo** do personagem tem `access="1"` em [`data/XML/groups.xml`](../data/XML/groups.xml) (grupos 4 gamemaster, 5 community manager, 6 god) |
| **accountType** | `talkaction:accountType(N)` | o **tipo da conta** (`accounts.type`) é `>= N` |

Tipos de conta (`src/enums.h`): `1` normal · `2` tutor · `3` senior tutor ·
`4` gamemaster · `5` community manager · `6` god.

Ou seja: para ter **todos** os comandos é preciso **grupo 6** no personagem
(`players.group_id`) **e** **tipo 6** na conta (`accounts.type`). Mudou o tipo da
conta no banco → relogar.

Alguns scripts ainda fazem checagens próprias dentro do `onSay`
(`getGroup():getAccess()`, `getAccountType()`, `getGroup():getId()`) — anotadas
na coluna *Nível* quando relevantes.

Legenda da coluna **Nível**:

- **access** = só `access(true)` (qualquer GM/CM/god);
- **access + tipo N** = `access(true)` e `accountType(N)`;
- **tipo N** = só `accountType(N)`, sem `access(true)`;
- **interno** = sem restrição no core, o script checa por conta própria;
- **livre** = qualquer jogador.

Parâmetros: `<obrigatório>`, `[opcional]`, `a|b` = uma das opções. O separador
entre a palavra e os parâmetros é sempre um **espaço**; dentro dos parâmetros a
maioria usa **vírgula**.

---

## GM — `data/scripts/talkactions/gm/`

### Navegação

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/goto` | `<nome>` | access | Teleporta você até a criatura/jogador. |
| `/c` | `<nome>` | access | Puxa a criatura/jogador até você. |
| `/t` | — | access | Vai pro templo da sua cidade (e zera a instância). |
| `/town` | `<nome ou id da cidade>` | access | Vai pro templo da cidade. |
| `/a` | `<n>` | access | Anda `n` tiles na direção em que você olha. |
| `/up` | — | access | Sobe um andar. |
| `/down` | — | access | Desce um andar. |
| `/pos`, `!pos` | `[x,y,z]` ou `[{x=…, y=…, z=…}]` | livre (teleporte só com access) | Sem parâmetro mostra sua posição; com coordenadas (e access) teleporta. |

### Moderação

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/kick` | `<jogador>` | access | Desconecta o jogador (não funciona em quem tem access). |
| `/addtutor` | `<jogador>` | access + tipo 3 | Promove conta normal a tutor (jogador online). |
| `/removetutor` | `<jogador>` | access + tipo 3 | Rebaixa tutor a normal. |

### Jogador

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/info` | `<jogador>` | access | Mostra nome, access, level, magic level, velocidade, posição, IP e outros chars no mesmo IP. |
| `/promote` | `<jogador>` | access + tipo 4 | Dá a promoção da vocação (online ou offline). |
| `/addpremium` | `<jogador>[, dias]` | interno (access) | Adiciona dias de premium (padrão 30); funciona offline. |
| `/addaddon` | `<jogador>, <outfitId\|all>[, addon 0-3]` | access | Dá outfit/addon (id do `outfits.xml`). |
| `/addmount` | `<jogador>, <mountId\|all>` | access | Dá montaria (id do `mounts.xml`); o jogador precisa relogar. |
| `!kills` | — | livre | Mostra suas mortes injustificadas/skull (é comando de jogador, apesar da pasta). |

### Servidor / eventos

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/B` | `<mensagem>` | access | Broadcast pra todos os jogadores. |
| `/clean` | — | interno (access) | Limpa os itens soltos do mapa. |
| `/raid` | `<nome da raid>` | access + tipo 4 | Força uma raid (`data/raids/`). |
| `/battlepass` | `status \| newseason \| reset <jogador> \| sync <jogador> \| unlockshop <jogador> \| shopcoins\|coins <jogador> <qtd> \| test [jogador] [pontos]` | access | Administra o Battle Pass. Requer `battlePassSystemEnabled = true`. |

### Spawn

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/summon` | `<monstro>` | access | Cria o monstro como **seu** summon. |
| `/testsummon` | `<monstro>[, qtd]` | access | Cria `qtd` monstros (1–500, padrão 1). |
| `/stresssummon` | `<monstro>[, qtd][, raio][, tentativas]` | access | Espalha monstros em área (qtd 1–500 padrão 50, raio 1–30 padrão 8, tentativas 1–100 padrão 20). |

### Visual / ferramentas

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/x` | `<id do efeito>` | access | Dispara um *distance effect* (projétil) em volta de você. |
| `/z` | `<id do efeito>` | access | Magic effect na sua posição. |
| `/y` | `<texto> <cor>` | access | Texto animado (uma palavra + código de cor). |
| `/looktype` | `<lookType>` | access | Troca a sua aparência. |
| `/r` | `[qtd]` | access | Remove a criatura/item do tile à sua frente (`qtd` pra pilhas; não remove chão). |
| `/condition` | `root\|fear\|agony\|bleed[, segundos][, jogador]` | **livre** ⚠️ | Aplica a condição em você ou no jogador (padrão 10 s). Ver *Pontos a investigar*. |

---

## God — `data/scripts/talkactions/god/`

### Itens

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/i` | `<nome ou id>[, qtd][, subtipo]` | access + tipo 6 | Cria item na sua mochila (subtipo = cargas/fluido de não-empilháveis). |
| `/attr` | `<atributo>, <valor>[, extra]` | access + tipo 6 | Seta atributo na coisa à sua frente. Item: qualquer atributo de item (`aid`, `uid`, `description`, `text`, …) ou `custom, <chave>, <valor>`. Criatura: `health`, `addSummon`, `event`. |
| `/check` | `[uid]` ou `[uid=N]` | access + tipo 6 | Inspeciona o item à frente ou pelo unique id. |
| `/owner` | `[jogador\|none]` | access + tipo 6 | Dono da casa em que você está (`none`/vazio remove). |
| `/forgeitem` | `<nome ou id>[, tier N\|tN][, classification N\|cN]` | access + tipo 6 | Cria item com tier/classificação da forja. |
| `/imbuementitem` | `<nome ou id>, <grupo>, <imbuement>[, <grupo>, <imbuement>…]` | access + tipo 6 | Cria item já imbuído. Ex.: `/imbuementitem underworld rod, vampirism, powerful vampirism`. Requer `imbuementSystemEnabled = true`. |

### Jogador

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/addexperience` | `<jogador>, <qtd>` | access + tipo 6 | Adiciona (ou remove, se negativo) experiência. |
| `/addskill` | `<jogador>, <skill>[, qtd]` | access + tipo 6 | Sobe skill: `club`, `sword`, `axe`, `dist…`, `shield…`, `fish…`, `fist…`, `m…` (magic), `level`/`l…`/`e…`. |
| `/coins` | `add\|remove, <jogador>, <qtd>` | access + tipo 6 | Adiciona/remove Tibia Coins. |
| `/add` | `tibiacoins, <jogador>, <qtd>` | access + tipo 6 | Atalho pra adicionar Tibia Coins. |
| `/storage` | `<jogador>, <chave>[, valor]` | interno (access) | Lê (sem valor) ou grava storage. |
| `/proficiency` | `<experiência>[, itemId]` | interno (access) | Dá experiência de proficiência à arma equipada (ou ao `itemId`). |
| `/bestiarykills` | `[jogador,] <monstro ou raceId>, <kills>` | access + tipo 6 | Soma kills no bestiary. Requer `bestiarySystemEnabled = true`. |
| `/mccheck` | — | access + tipo 6 | Lista jogadores com mais de um char por IP (multiclient). |
| `/hireling` | `[nome][, sexo]` | access | Cria uma lâmpada de hireling na Store Inbox. Requer o sistema de hireling ligado. |
| `/clearhirelingstats` | `[jogador]` | access | Zera skills/outfits de hireling (seu ou do jogador). |

### Moderação

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/ban` | `<jogador>[, motivo]` | access + tipo 6 | Bane a **conta** por 7 dias (fixo no script). |
| `/ipban` | `<jogador>` | access + tipo 6 | Bane o IP por 7 dias e derruba o jogador. |
| `/unban` | `<jogador>` | access + tipo 6 | Remove ban de conta e de IP. |

### Servidor

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/reload` | `all \| actions \| chat \| config \| creaturescripts \| events \| global \| libs \| globalevents \| items \| monsters \| mounts \| movements \| npcs \| outfits \| raids \| scripts \| spells \| talkactions \| weapons` | access + tipo 6 | Recarrega o tipo (aceita singular/plural). Requer `reloadCommandEnabled = true`. |
| `/shutdown` | `[minutos]` | access + tipo 6 | Sem parâmetro: desliga já. Com minutos: avisa a cada minuto e desliga. |
| `/closeserver` | `[shutdown]` | access + tipo 6 | Fecha o server pra login (com `shutdown`, desliga). |
| `/openserver` | — | access + tipo 6 | Reabre pra login. |
| `/time` | `[set sunrise\|day\|sunset\|night\|<minutos>]` | access + tipo 6 | Mostra ou muda a hora do mundo. |

### Spawn / navegação / visual / espionagem

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/m` | `<monstro>` | access + tipo 6 | Cria monstro selvagem à sua frente. |
| `/s` | `<npc>` | access + tipo 6 | Cria NPC. |
| `/cliport` | — | access + tipo 6 | Liga/desliga o modo "clicou no mapa, teleportou". |
| `/gotoinfluenced` | `[fiendish]` | access + tipo 6 | Vai até o monstro influenced (ou fiendish) mais próximo. |
| `/ghost` | — | access + tipo 6 | Fica invisível/visível. |
| `/hide` | — | access + tipo 6 | Esconde/mostra a sua barra de vida pros outros. |
| `/chameleon` | `<nome ou id do item>` | access + tipo 6 | Se disfarça de item. |
| `/spy` | `<jogador>` | access + tipo 6 | Vê a tela do jogador. |
| `/unspy` | — | access + tipo 6 | Para de espionar. |
| `/spyinv` | `<jogador>` | access + tipo 6 | Vê o inventário/mochila do jogador. |

---

## Comandos de GM/god fora de `talkactions/`

| Comando | Parâmetros | Nível | Arquivo | O que faz |
|---------|-----------|-------|---------|-----------|
| `/resetplayer` | `<jogador>` | access + tipo 4 | `resetsystem/02_talkaction_reset.lua` | Força reset do jogador. |
| `/echo` | `status \| cleanup \| spawn [monstro] \| visualwarden\|visualleader\|visualempowered\|visualminion [monstro]` | access + tipo 6 | `echo/echo_debug.lua` | Debug do Echo Raid (sem monstro usa o alvo atacado). Requer `echoRaidSystemEnabled` + bestiary. |
| `/bossdiff` | `[dificuldade]` | access + tipo 6 | `network/boss_difficulty.lua` | Abre a janela de dificuldade de boss (diagnóstico). |
| `/wheelaug`, `!wheelaug` | `<nome da magia>` | tipo 6 + interno (access) | `network/wheel/wheel.lua` | Relatório de augments da Wheel pra uma magia. |
| `/forge`, `!forge` | `info \| dust \| sliver` | livre | `actions/systems/forge.lua` | Informações/conversões da forja. |

## Testes e stress (não usar em produção)

| Comando | Parâmetros | Nível | O que faz |
|---------|-----------|-------|-----------|
| `/dupe` | `start \| 1-8 \| info \| clean` | access + tipo 6 | Fases de teste de dupe de itens (save threadado). |
| `/stress_db` | `start \| 1-11 \| diag \| info \| clean` | access + tipo 6 | Stress do banco (tabela isolada `stress_pr69`). |
| `/net` | `create \| gc \| pool \| leak \| send \| concurrent \| bigdata \| reset \| exhaust \| fragment \| refcount \| all\|start` (+ args por vírgula) | tipo 6 + interno (access) | Stress de `NetworkMessage`. |
| `/stress_reactor` | — | tipo 6 + interno (access) | Stress do reactor (resultado no console). |
| `/spstress` | `[loops]` (padrão 500) | interno (tipo 4) | Stress de smart pointers. |
| `/spregisterstress` | `[qtd]` (padrão 25) | interno (tipo 4) | Registra talkactions temporárias em massa. |
| `/spconditionstress` | `[loops]` (padrão 10000) | interno (tipo 4) | Stress de conditions. |
| `/spawnstressdemon` | `[qtd]` (1–25) | interno (tipo 4) | Cria demônios de stress. |
| `/testcreatureicon` | `<categoria 0\|1>, <iconId>, <count>` | access + tipo 6 | Seta ícone de criatura em você. |
| `/clearcreatureicon` | — | access + tipo 6 | Limpa os ícones. |
| `/testrotten` | `[count]` | access + tipo 6 | Ícone Rotten Charge. |
| `/testforge` | `[4\|5]` | access + tipo 6 | Ícone Influenced (4) / Fiendish (5). |

---

## Jogador — `data/scripts/talkactions/player/` (e outros)

| Comando | Parâmetros | O que faz |
|---------|-----------|-----------|
| `!commands`, `/commands` | — | Lista os comandos disponíveis pra você. |
| `!online`, `/online` | — | Jogadores online. |
| `!serverinfo` | — | Rates e infos do servidor. |
| `!uptime` | — | Tempo desde o boot. |
| `!spawnrate` | — | Rate de spawn atual. |
| `!deathlist` | `<jogador>` | Últimas mortes do jogador. |
| `!frags` | — | Seus frags. |
| `!rank` | `<tipo>[, vocação]` | Top: `level`, `magic`, `bank`, `fist`, `club`, `sword`, `axe`, `distance`, `shielding`, `fishing`, `frags`; vocação `sorcerer`, `druid`, `paladin`, `knight`, `ms`, `ed`, `rp`, `ek`, `em`, `none`. |
| `!promotion` | — | Compra a promoção. |
| `!bless`, `/bless` | — | Compra as bênçãos. |
| `!buypremium` | — | Compra premium com gold. |
| `!buy` | `gold pouch` | Compra o gold pouch. |
| `!changesex` | — | Troca o sexo do personagem. |
| `!reset` / `!resetinfo` | — | Sistema de reset / informações do seu reset. |
| `!reward` | `exercise` | Pega a arma de exercício de recompensa. |
| `!dailyexercise` | — | Recompensa diária de exercício. |
| `!storeinbox`, `!sinbox`, `!inbox` | — | Abre a Store Inbox. |
| `!quickloot` | `on\|off` | Liga/desliga o quick loot. |
| `/autoloot`, `!autoloot` | `list \| on \| off \| clear \| gold` (sem parâmetro mostra o status) | Autoloot. |
| `!chain` | `on\|off` | Sistema de chain. |
| `!cleave` | `on\|off` | Sistema de cleave. |
| `!emotespells` | `on\|off` | Magias faladas como emote. |
| `/expcolor` | `white\|red\|green\|blue\|orange\|yellow\|pink\|purple\|teal\|gold` | Cor do texto de experiência. |
| `/healthdisplay` | `[real\|percent]` (sem parâmetro alterna) | Vida em número ou %. `/healthreal` e `/healthpercent` são atalhos. |
| `!harmony` | — | Informação de harmony (monk). |
| `/findinfluenced`, `!findinfluenced` | — | Direção do monstro influenced mais próximo. |
| `!token` | `on \| off <token> \| set <token>` (sem parâmetro mostra o status) | Token de segurança da conta. |
| `!cast` | `on \| off \| password <senha> \| passwordoff \| list\|show \| kick <nome>` | Transmissão (cast) do seu jogo. |
| **Casas** | | |
| `!buyhouse` | — | Compra a casa à sua frente. |
| `!buygh` | — | Compra guildhall. |
| `!sellhouse` | `<jogador>` | Vende a casa pro jogador. |
| `!leavehouse` | — | Abandona a casa. |
| `!houseguest` | `add\|remove <jogador> \| list` | Convidados da casa. |
| `!protecthouse` | `[on\|off]` | Proteção da casa (sem parâmetro mostra o status). |
| `!unwrap` | — | Desembala o item de decoração. |
| **Guild** | | |
| `/createguild` | `<nome>` (aceita `"nome com espaço"`) | Cria guild. |
| `/disbandguild` | — | Desfaz a sua guild. |
| `/guildinvite` | `<jogador>` | Convida. |
| `!guild` | `accept \| decline` | Responde convite. |
| `/guildleave` | — | Sai da guild. |
| `/guildkick` | `<jogador>` | Expulsa. |
| `/guildpromote` / `/guilddemote` | `<jogador>` | Sobe/desce rank. |
| `/transferleadership` | `<jogador>` | Passa a liderança. |
| `/gc` | `<mensagem>` | Chat da guild. |
| `/guildbc` | `<mensagem>` | Broadcast pra guild. |
| `/balance` | `[donate <qtd> \| pick <qtd>]` | Saldo da guild. |
| `/war` | `invite,<guild>,<fraglimit>[,dinheiro,tempo] \| accept,<guild> \| reject,<guild> \| end,<guild> \| cancel,<guild>` | Guerra de guilds. |

---

## Pontos a investigar

Achados do levantamento de 2026-09-29, ainda não corrigidos:

1. **`/condition` sem nenhuma permissão** (`gm/condition.lua`): não tem
   `access(true)`, `accountType` nem checagem interna. Qualquer jogador pode
   aplicar root/fear/agony/bleed em qualquer jogador online. **Brecha de
   segurança** — adicionar `access(true)` (e talvez `accountType`).
2. **Comandos de staff sem `access(true)` aparecem pra jogador no
   `/commands`**: `/addpremium`, `/clean`, `/storage`, `/proficiency`,
   `/spstress`, `/spregisterstress`, `/spconditionstress`, `/spawnstressdemon`,
   `/net`, `/stress_reactor`, `/wheelaug`. Estão protegidos por checagem interna,
   mas o `/commands` usa `talkaction:access()` pra separar a lista e mostra
   esses como comando comum. Padronizar com `access(true)` + `accountType`.
3. **Critérios misturados**: a pasta (`gm/` × `god/`) não define o nível. Uns
   usam só `access(true)`, outros `accountType(4)`, outros `accountType(6)`,
   outros `getAccountType() >= GAMEMASTER` interno e `/time set` checa
   `getGroup():getId() < 3`. Definir a regra (ex.: `gm/` = `accountType(4)`,
   `god/` = `accountType(6)`, sempre com `access(true)`).
4. **`!kills` está em `gm/`** mas é comando de jogador — mover pra `player/`.
5. **`/ban` e `/ipban` com duração fixa de 7 dias** e sem aceitar duração por
   parâmetro. `/ban` falha **em silêncio** quando o jogador não existe ou já
   está banido; `/ipban` e `/unban` também não avisam quando o jogador não
   existe.
6. **`/summon` (GM) × `/m` (god)**: fazem quase a mesma coisa (monstro como
   summon × selvagem) com níveis diferentes — conferir se é intencional.
7. **Sistemas desligados no `config.lua` de dev** deixam comandos sem efeito:
   `battlePassSystemEnabled`, `imbuementSystemEnabled`, `bestiarySystemEnabled`
   (→ `/bestiarykills`, `/echo`), `echoRaidSystemEnabled`,
   `forgeSystemEnabled`, `wheelSystemEnabled`; a chave do hireling nem aparece
   no `config.lua` de dev (conferir o default em `src/configmanager.cpp`).
8. **Scripts de stress/teste carregados sempre** (`talkactions/stress/`,
   `god/stress/`, `test_creature_icons.lua`, `/stresssummon`, `/testsummon`):
   avaliar desligar em produção (prefixo `#` no nome do arquivo desabilita o
   script).
9. **Conta compartilhada**: na conta de dev `teste`, o tipo da conta vale pra
   todos os personagens. `Teste Knight` (grupo 1) fica barrado nos comandos com
   `access(true)`, mas passaria nos que só checam `accountType` sem checagem
   interna — hoje nenhum, mas vale ter uma conta só pra staff.
10. **Mensagens em inglês** nos comandos; o projeto é em português — decidir se
    traduz.
