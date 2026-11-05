-- Painel de teste dev (client: Ctrl+X, só em dev mode). Trava no server: devTestPanel no config.lua.
-- Flags mudam o GRUPO em memória (jeito Canary): valem pra todo o grupo e voltam ao
-- groups.xml quando o server reinicia. Flags lidas só no login ficam fora da lista.
local OPCODE = 213

-- Só flags lidas na hora da ação.
local FLAGS = {
	{"CannotPickupItem", PlayerFlag_CannotPickupItem},
	{"NotGenerateLoot", PlayerFlag_NotGenerateLoot},
	{"CannotUseCombat", PlayerFlag_CannotUseCombat},
	{"CannotAttackMonster", PlayerFlag_CannotAttackMonster},
	{"CannotAttackPlayer", PlayerFlag_CannotAttackPlayer},
	{"CannotBeAttacked", PlayerFlag_CannotBeAttacked},
	{"IgnoredByMonsters", PlayerFlag_IgnoredByMonsters},
	{"NotGainExperience", PlayerFlag_NotGainExperience},
	{"NotGainInFight", PlayerFlag_NotGainInFight},
	{"HasNoExhaustion", PlayerFlag_HasNoExhaustion},
	{"HasInfiniteMana", PlayerFlag_HasInfiniteMana},
	{"IgnoreSpellCheck", PlayerFlag_IgnoreSpellCheck},
	{"HasInfiniteCapacity", PlayerFlag_HasInfiniteCapacity},
}

-- Dicas geradas de docs/ingame-commands.md (fonte dos textos). Comando sem dica mostra só a palavra.
local HINTS = {
	["/goto"] = "<nome> - Teleporta você até a criatura/jogador.",
	["/c"] = "<nome> - Puxa a criatura/jogador até você.",
	["/t"] = "Vai pro templo da sua cidade (e zera a instância).",
	["/town"] = "<nome ou id da cidade> - Vai pro templo da cidade.",
	["/a"] = "<n> - Anda n tiles na direção em que você olha.",
	["/up"] = "Sobe um andar.",
	["/down"] = "Desce um andar.",
	["/pos"] = "[x,y,z] ou [{x=..., y=..., z=...}] - Sem parâmetro mostra sua posição; com coordenadas (e access) teleporta.",
	["!pos"] = "[x,y,z] ou [{x=..., y=..., z=...}] - Sem parâmetro mostra sua posição; com coordenadas (e access) teleporta.",
	["/kick"] = "<jogador> - Desconecta o jogador (não funciona em quem tem access).",
	["/addtutor"] = "<jogador> - Promove conta normal a tutor (jogador online).",
	["/removetutor"] = "<jogador> - Rebaixa tutor a normal.",
	["/info"] = "<jogador> - Mostra nome, access, level, magic level, velocidade, posição, IP e outros chars no mesmo IP.",
	["/promote"] = "<jogador> - Dá a promoção da vocação (online ou offline).",
	["/addpremium"] = "<jogador>[, dias] - Adiciona dias de premium (padrão 30); funciona offline.",
	["/addaddon"] = "<jogador>, <outfitId\\ - access",
	["/addmount"] = "<jogador>, <mountId\\ - access",
	["!kills"] = "Mostra suas mortes injustificadas/skull (é comando de jogador, apesar da pasta).",
	["/b"] = "<mensagem> - Broadcast pra todos os jogadores.",
	["/clean"] = "Limpa os itens soltos do mapa.",
	["/raid"] = "<nome da raid> - Força uma raid (data/raids/).",
	["/battlepass"] = "status \\ - reset <jogador> \\",
	["/summon"] = "<monstro> - Cria o monstro como seu summon.",
	["/testsummon"] = "<monstro>[, qtd] - Cria qtd monstros (1-500, padrão 1).",
	["/stresssummon"] = "<monstro>[, qtd][, raio][, tentativas] - Espalha monstros em área (qtd 1-500 padrão 50, raio 1-30 padrão 8, tentativas 1-100 padrão 20).",
	["/x"] = "<id do efeito> - Dispara um *distance effect* (projétil) em volta de você.",
	["/z"] = "<id do efeito> - Magic effect na sua posição.",
	["/y"] = "<texto> <cor> - Texto animado (uma palavra + código de cor).",
	["/looktype"] = "<lookType> - Troca a sua aparência.",
	["/r"] = "[qtd] - Remove a criatura/item do tile à sua frente (qtd pra pilhas; não remove chão).",
	["/condition"] = "root\\ - agony\\",
	["/i"] = "<nome ou id>[, qtd][, subtipo] - Cria item na sua mochila (subtipo = cargas/fluido de não-empilháveis).",
	["/attr"] = "<atributo>, <valor>[, extra] - Seta atributo na coisa à sua frente. Item: qualquer atributo de item (aid, uid, description, text, ...) ou custom, <chave>, <valor>. Criatura: health, addSummon, event.",
	["/check"] = "[uid] ou [uid=N] - Inspeciona o item à frente ou pelo unique id.",
	["/owner"] = "[jogador\\ - access + tipo 6",
	["/forgeitem"] = "<nome ou id>[, tier N\\ - cN]",
	["/imbuementitem"] = "<nome ou id>, <grupo>, <imbuement>[, <grupo>, <imbuement>...] - Cria item já imbuído. Ex.: /imbuementitem underworld rod, vampirism, powerful vampirism. Requer imbuementSystemEnabled = true.",
	["/addexperience"] = "<jogador>, <qtd> - Adiciona (ou remove, se negativo) experiência.",
	["/addskill"] = "<jogador>, <skill>[, qtd] - Sobe skill: club, sword, axe, dist..., shield..., fish..., fist..., m... (magic), level/l.../e....",
	["/coins"] = "add\\ - access + tipo 6",
	["/add"] = "tibiacoins, <jogador>, <qtd> - Atalho pra adicionar Tibia Coins.",
	["/storage"] = "<jogador>, <chave>[, valor] - Lê (sem valor) ou grava storage.",
	["/proficiency"] = "<experiência>[, itemId] - Dá experiência de proficiência à arma equipada (ou ao itemId).",
	["/bestiarykills"] = "[jogador,] <monstro ou raceId>, <kills> - Soma kills no bestiary. Requer bestiarySystemEnabled = true.",
	["/mccheck"] = "Lista jogadores com mais de um char por IP (multiclient).",
	["/hireling"] = "[nome][, sexo] - Cria uma lâmpada de hireling na Store Inbox. Requer o sistema de hireling ligado.",
	["/clearhirelingstats"] = "[jogador] - Zera skills/outfits de hireling (seu ou do jogador).",
	["/ban"] = "<jogador>[, motivo] - Bane a conta por 7 dias (fixo no script).",
	["/ipban"] = "<jogador> - Bane o IP por 7 dias e derruba o jogador.",
	["/unban"] = "<jogador> - Remove ban de conta e de IP.",
	["/reload"] = "all \\ - chat \\",
	["/shutdown"] = "[minutos] - Sem parâmetro: desliga já. Com minutos: avisa a cada minuto e desliga.",
	["/closeserver"] = "[shutdown] - Fecha o server pra login (com shutdown, desliga).",
	["/openserver"] = "Reabre pra login.",
	["/time"] = "[set sunrise\\ - sunset\\",
	["/m"] = "<monstro> - Cria monstro selvagem à sua frente.",
	["/s"] = "<npc> - Cria NPC.",
	["/cliport"] = "Liga/desliga o modo \"clicou no mapa, teleportou\".",
	["/gotoinfluenced"] = "[fiendish] - Vai até o monstro influenced (ou fiendish) mais próximo.",
	["/ghost"] = "Fica invisível/visível.",
	["/hide"] = "Esconde/mostra a sua barra de vida pros outros.",
	["/chameleon"] = "<nome ou id do item> - Se disfarça de item.",
	["/spy"] = "<jogador> - Vê a tela do jogador.",
	["/unspy"] = "Para de espionar.",
	["/spyinv"] = "<jogador> - Vê o inventário/mochila do jogador.",
	["/resetplayer"] = "<jogador> - resetsystem/02_talkaction_reset.lua",
	["/echo"] = "status \\ - spawn [monstro] \\",
	["/bossdiff"] = "[dificuldade] - network/boss_difficulty.lua",
	["/wheelaug"] = "<nome da magia> - network/wheel/wheel.lua",
	["!wheelaug"] = "<nome da magia> - network/wheel/wheel.lua",
	["/forge"] = "info \\ - sliver",
	["!forge"] = "info \\ - sliver",
	["/dupe"] = "start \\ - info \\",
	["/stress_db"] = "start \\ - diag \\",
	["/net"] = "create \\ - pool \\",
	["/stress_reactor"] = "Stress do reactor (resultado no console).",
	["/spstress"] = "[loops] (padrão 500) - Stress de smart pointers.",
	["/spregisterstress"] = "[qtd] (padrão 25) - Registra talkactions temporárias em massa.",
	["/spconditionstress"] = "[loops] (padrão 10000) - Stress de conditions.",
	["/spawnstressdemon"] = "[qtd] (1-25) - Cria demônios de stress.",
	["/testcreatureicon"] = "<categoria 0\\ - access + tipo 6",
	["/clearcreatureicon"] = "Limpa os ícones.",
	["/testrotten"] = "[count] - Ícone Rotten Charge.",
	["/testforge"] = "[4\\ - access + tipo 6",
	["!commands"] = "",
	["/commands"] = "",
	["!online"] = "",
	["/online"] = "",
	["!serverinfo"] = "",
	["!uptime"] = "",
	["!spawnrate"] = "",
	["!deathlist"] = "<jogador> - ",
	["!frags"] = "",
	["!rank"] = "<tipo>[, vocação] - ",
	["!promotion"] = "",
	["!bless"] = "",
	["/bless"] = "",
	["!buypremium"] = "",
	["!buy"] = "gold pouch - ",
	["!changesex"] = "",
	["!reset"] = "",
	["!resetinfo"] = "",
	["!reward"] = "exercise - ",
	["!dailyexercise"] = "",
	["!storeinbox"] = "",
	["!sinbox"] = "",
	["!inbox"] = "",
	["!quickloot"] = "on\\ - Liga/desliga o quick loot.",
	["/autoloot"] = "list \\ - off \\",
	["!autoloot"] = "list \\ - off \\",
	["!chain"] = "on\\ - Sistema de chain.",
	["!cleave"] = "on\\ - Sistema de cleave.",
	["!emotespells"] = "on\\ - Magias faladas como emote.",
	["/expcolor"] = "white\\ - green\\",
	["/healthdisplay"] = "[real\\ - Vida em número ou %. /healthreal e /healthpercent são atalhos.",
	["!harmony"] = "",
	["/findinfluenced"] = "",
	["!findinfluenced"] = "",
	["!token"] = "on \\ - set <token> (sem parâmetro mostra o status)",
	["!cast"] = "on \\ - password <senha> \\",
	["!buyhouse"] = "",
	["!buygh"] = "",
	["!sellhouse"] = "<jogador> - ",
	["!leavehouse"] = "",
	["!houseguest"] = "add\\ - list",
	["!protecthouse"] = "[on\\ - Proteção da casa (sem parâmetro mostra o status).",
	["!unwrap"] = "",
	["/createguild"] = "<nome> (aceita \"nome com espaço\") - ",
	["/disbandguild"] = "",
	["/guildinvite"] = "<jogador> - ",
	["!guild"] = "accept \\ - Responde convite.",
	["/guildleave"] = "",
	["/guildkick"] = "<jogador> - ",
	["/guildpromote"] = "<jogador> - ",
	["/guilddemote"] = "<jogador> - ",
	["/transferleadership"] = "<jogador> - ",
	["/gc"] = "<mensagem> - ",
	["/guildbc"] = "<mensagem> - ",
	["/balance"] = "[donate <qtd> \\ - Saldo da guild.",
	["/war"] = "invite,<guild>,<fraglimit>[,dinheiro,tempo] \\ - reject,<guild> \\",
}

-- addString converte UTF-8 -> latin1 e manda vazio se a conversão falhar:
-- texto só com caracteres latin1, e o corte dos pedaços nunca no meio de um caractere.
local function send(player, data)
	local buffer = json.encode(data)
	local size = 8000
	if #buffer <= size then
		player:sendExtendedOpcode(OPCODE, buffer)
		return
	end

	local first = 1
	while first <= #buffer do
		local last = math.min(first + size - 1, #buffer)
		while last < #buffer and buffer:byte(last + 1) >= 0x80 and buffer:byte(last + 1) < 0xC0 do
			last = last - 1
		end
		local prefix = first == 1 and "S" or (last == #buffer and "E" or "P")
		player:sendExtendedOpcode(OPCODE, prefix .. buffer:sub(first, last))
		first = last + 1
	end
end

local function sendState(player)
	local flags = {}
	for _, flag in ipairs(FLAGS) do
		flags[#flags + 1] = {name = flag[1], on = player:hasGroupFlag(flag[2])}
	end

	-- Todos os comandos, com o que o core exige (src/talkaction.cpp): o client filtra por cargo.
	local commands = {}
	for _, talk in ipairs(Game.getTalkActions()) do
		local words = talk:getWords()
		commands[#commands + 1] = {
			words = words,
			hint = HINTS[words:lower()] or "",
			access = talk:access(),
			accountType = talk:accountType()
		}
	end
	table.sort(commands, function(a, b) return a.words < b.words end)

	send(player, {
		group = player:getGroup():getName(),
		ghost = player:isInGhostMode(),
		flags = flags,
		commands = commands
	})
end

local function setQuests(player, complete)
	for _, quest in pairs(Game.getQuests()) do
		player:setStorageValue(quest.storageId, complete and quest.storageValue or -1)
		for _, mission in pairs(quest.missions) do
			player:setStorageValue(mission.storageId, complete and mission.endValue or -1)
		end
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, complete and "[Dev] Quests completas." or "[Dev] Quests zeradas.")
end

local actions = {
	state = function(player) end,
	flag = function(player, data)
		for _, flag in ipairs(FLAGS) do
			if flag[1] == data.name then
				if data.on then
					player:setGroupFlag(flag[2])
				else
					player:removeGroupFlag(flag[2])
				end
			end
		end
	end,
	ghost = function(player) player:setGhostMode(not player:isInGhostMode()) end,
	quests = function(player, data) setQuests(player, data.complete) end,
}

local devPanel = CreatureEvent("DevPanelOpcode")

function devPanel.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end

	if not configManager.getBoolean(configKeys.DEV_TEST_PANEL) then
		logWarning(string.format("[DevPanel] recusado (devTestPanel = false): %s", player:getName()))
		return
	end

	local ok, data = pcall(json.decode, buffer)
	local action = ok and type(data) == "table" and actions[data.action]
	if not action then
		return
	end

	action(player, data)
	sendState(player)
end

devPanel:register()

local devPanelLogin = CreatureEvent("DevPanelLogin")

function devPanelLogin.onLogin(player)
	player:registerEvent("DevPanelOpcode")
	return true
end

devPanelLogin:register()
