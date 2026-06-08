local json = require("json")
local docsettings = require("frontend/docsettings")
local lfs = require("libs/libkoreader-lfs")
local utils = require("utils")
local device = require("device")
local DataStorage = require("datastorage")
local util = require("util")

local Progress = {
    extension = ".sidekick.json" 
}

--- Obtém um ID único para o dispositivo atual
function Progress.get_device_id()
    -- Tenta usar o serial, id ou modelo para garantir unicidade
    return device.serial or device.id or device.model or "unknown_device"
end

local docsettings = require("frontend/docsettings")

--- Função nativa de hash (djb2) para evitar dependência de bibliotecas criptográficas externas.
local function simple_hash(str)
    local hash = 5381
    for i = 1, #str do
        hash = (hash * 33) + string.byte(str, i)
        hash = hash % 4294967296
    end
    return string.format("%x", hash)
end

--- Obtém o caminho centralizado para o arquivo de progresso de um e-book.
-- @param doc_file string O caminho absoluto do arquivo do e-book.
-- @return string|nil O caminho do arquivo de sincronização ou nil em caso de falha.
function Progress.get_sidekick_path(doc_file)
    utils.logInfo("get_sidekick_path: Iniciando para " .. tostring(doc_file))
    if not doc_file or type(doc_file) ~= "string" then
        utils.logErr("get_sidekick_path: doc_file invalido")
        return nil
    end

    local book_dir = doc_file:match("^(.*)/")
    if not book_dir then
        utils.logErr("get_sidekick_path: Nao foi possivel obter o diretorio do livro.")
        return nil
    end

    local sync_dir = book_dir .. "/.sidekick_sync"
    local mode = lfs.attributes(sync_dir, "mode")
    if not mode then
        local success, err = lfs.mkdir(sync_dir)
        if not success then
            utils.logErr("get_sidekick_path: Nao foi possivel criar o diretorio de sincronizacao: " .. tostring(err))
            return nil
        end
        utils.logInfo("get_sidekick_path: Diretorio .sidekick_sync criado em " .. sync_dir)
    elseif mode ~= "directory" then
        utils.logErr("get_sidekick_path: O caminho do diretorio de sincronizacao existe mas nao e um diretorio.")
        return nil
    end

    local filename = doc_file:match("([^/]+)$") or "unknown"
    local file_hash = simple_hash(doc_file)
    
    local sync_filename = filename .. "_" .. file_hash .. Progress.extension
    local final_path = sync_dir .. "/" .. sync_filename
    utils.logInfo("get_sidekick_path: Caminho final: " .. tostring(final_path))

    return final_path
end

--- Lê o JSON completo (tabela de dispositivos)
function Progress.read_json(path)
    local f, err = io.open(path, "r")
    if not f then 
        if err and not err:find("No such file") then
            utils.logWarn("Falha ao abrir arquivo:", err)
        end
        return nil 
    end
    
    local content = f:read("*a")
    f:close()
    
    if not content or content == "" then return nil end
    
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then
        return data
    end
    
    utils.logWarn("JSON corrompido ou inválido.")
    return nil
end

--- Analisa os dados de TODOS os dispositivos e retorna o estado mais avançado (Vencedor)
-- Critério: Maior Revision > Maior Porcentagem > Timestamp
function Progress.get_best_candidate(all_data)
    if not all_data then return nil end
    
    local best_entry = nil
    
    for dev_id, entry in pairs(all_data) do
        if type(entry) == "table" and entry.revision then
            if not best_entry then
                best_entry = entry
            else
                -- 1. Critério Soberano: Revision
                if entry.revision > best_entry.revision then
                    best_entry = entry
                
                -- 2. Empate de Revision: Maior Porcentagem ganha
                elseif entry.revision == best_entry.revision then
                    local p1 = entry.percent or 0
                    local p2 = best_entry.percent or 0
                    if p1 > (p2 + 0.0001) then
                        best_entry = entry
                    end
                end
            end
        end
    end
    
    return best_entry
end

--- NOVO: Obtém especificamente os dados salvos por ESTE dispositivo
function Progress.get_my_data(document)
    if not document or not document.file then return nil end
    
    local filepath = Progress.get_sidekick_path(document.file)
    local all_data = Progress.read_json(filepath)
    
    if not all_data then return nil end
    
    local my_id = Progress.get_device_id()
    return all_data[my_id]
end

--- Grava uma tabela de dados em um arquivo no formato JSON.
-- @param path string O caminho do arquivo onde o JSON será salvo.
-- @param data table A tabela de dados a ser codificada em JSON.
-- @return boolean Retorna verdadeiro se a gravação foi bem-sucedida, ou falso caso contrário.
function Progress.save_json(path, data)
    if not path or type(path) ~= "string" or not data or type(data) ~= "table" then
        return false
    end

    local status, json_str = pcall(json.encode, data)
    if not status then
        utils.logErr("Nao foi possivel codificar os dados em JSON.")
        return false
    end

    local f, err = io.open(path, "w")
    if not f then
        utils.logErr("Erro ao abrir arquivo para escrita em " .. path .. ": " .. tostring(err))
        return false
    end

    local write_status, write_err = f:write(json_str)
    f:close()

    if not write_status then
        utils.logErr("Erro ao escrever dados no arquivo " .. path .. ": " .. tostring(write_err))
        return false
    end

    return true
end

--- Salva o estado do dispositivo atual, incrementando a revisão global e adicionando metadados.
-- @param state table Tabela contendo as informações de estado de leitura do e-book.
-- @param background boolean Flag indicando se a operação é em segundo plano (evita logs).
-- @return boolean, number|nil Retorna verdadeiro e a nova revisão se for bem-sucedido, ou falso em caso de falha.
function Progress.save_from_cache(state, background)
    if not state or not state.file then
        return false
    end

    local filepath = Progress.get_sidekick_path(state.file)
    if not filepath then
        return false
    end

    local all_data = Progress.read_json(filepath) or {}
    local max_global_rev = 0
    for _, entry in pairs(all_data) do
        if entry.revision and entry.revision > max_global_rev then
            max_global_rev = entry.revision
        end
    end

    local my_new_rev = max_global_rev + 1
    local my_id = Progress.get_device_id()

    all_data[my_id] = {
        revision = my_new_rev,
        percent = state.percent,
        page = state.page,
        xpath = state.xpath,
        timestamp = os.time(),
        device_model = device.model
    }

    all_data._meta = {
        original_file = state.file
    }

    local saved = Progress.save_json(filepath, all_data)
    if not saved then
        return false
    end

    if not background then
        utils.logInfo(string.format("Salvo: %s (Rev %d)", my_id, my_new_rev))
    end

    return true, my_new_rev
end

--- Resolve conflitos comparando qual arquivo contém o candidato "Vencedor"
function Progress.resolve_conflicts(main_filepath)
    local dir = main_filepath:match("^(.*)/")
    local filename = main_filepath:match("([^/]+)$")
    local any_resolution = false
    local base_name = filename:sub(1, -string.len(Progress.extension) - 1)
    
    for file in lfs.dir(dir) do
        if file:find(base_name, 1, true) and file:find("sync%-conflict") and file:match("%.json$") then
            
            local conflict_path = dir .. "/" .. file
            utils.logInfo("Conflito detectado ->", file)
            
            local main_data = Progress.read_json(main_filepath)
            local conflict_data = Progress.read_json(conflict_path)
            
            -- Compara o "Melhor Candidato" de cada arquivo
            local best_main = Progress.get_best_candidate(main_data)
            local best_conf = Progress.get_best_candidate(conflict_data)
            
            local should_replace = false
            
            if not best_main and best_conf then
                should_replace = true
            elseif best_main and best_conf then
                -- Se o arquivo de conflito tiver uma revisão MAIOR que o principal, ele ganha
                if best_conf.revision > best_main.revision then
                    utils.logInfo(string.format("Conflito VENCE por Revision (%d > %d).", best_conf.revision, best_main.revision))
                    should_replace = true
                -- Empate de revisão: Porcentagem
                elseif best_conf.revision == best_main.revision and (best_conf.percent or 0) > (best_main.percent or 0) then
                    should_replace = true
                end
            end

            if should_replace then
                os.remove(main_filepath) 
                local success, err = os.rename(conflict_path, main_filepath)
                if not success then utils.logErr("Erro ao renomear conflito:", err) end
                any_resolution = true
            else
                utils.logInfo("Conflito PERDE. Deletando.")
                os.remove(conflict_path)
            end
        end
    end
    return any_resolution
end

--- Verifica o progresso remoto
-- @return Table|nil: O "Melhor Candidato" (page, percent, revision) ou nil.
function Progress.check_remote_progress(document)
    if not document or not document.file then return nil end
    
    local filepath = Progress.get_sidekick_path(document.file)
    local was_resolved = Progress.resolve_conflicts(filepath)
    local all_data = Progress.read_json(filepath)
    
    local best = Progress.get_best_candidate(all_data)
    
    if best then
        return best, was_resolved
    end
    
    return nil, was_resolved
end

--- Realiza a migração sob demanda (lazy migration) de um arquivo de progresso antigo para o formato centralizado.
-- @param doc_file string O caminho absoluto do arquivo do e-book.
-- @return boolean Retorna verdadeiro se a migração ocorreu com sucesso, ou falso caso contrário.
function Progress.migrate_old_sync(doc_file)
    if not doc_file or type(doc_file) ~= "string" then
        return false
    end

    local old_filepath = doc_file .. Progress.extension
    local mode = lfs.attributes(old_filepath, "mode")
    
    if not mode then
        local sdr_dir = docsettings:getSidecarDir(doc_file)
        if sdr_dir then
            local filename = doc_file:match("([^/]+)$") or "unknown"
            local sdr_filepath = sdr_dir .. "/" .. filename .. Progress.extension
            if lfs.attributes(sdr_filepath, "mode") then
                old_filepath = sdr_filepath
                mode = "file"
            end
        end
    end

    if not mode then
        utils.logInfo("migrate_old_sync: Nenhum arquivo antigo encontrado para " .. doc_file)
        return false
    end

    local data = Progress.read_json(old_filepath)
    if not data then
        utils.logWarn("Nao foi possivel ler os dados antigos de: " .. old_filepath)
        return false
    end

    data._meta = {
        original_file = doc_file
    }

    local new_filepath = Progress.get_sidekick_path(doc_file)
    if not new_filepath then
        utils.logErr("Nao foi possivel obter o novo caminho de sincronizacao para: " .. doc_file)
        return false
    end

    local saved = Progress.save_json(new_filepath, data)
    if saved then
        local removed, err = os.remove(old_filepath)
        if not removed then
            utils.logErr("Nao foi possivel remover o arquivo antigo " .. old_filepath .. ": " .. tostring(err))
        end
        utils.logInfo("Migracao concluida para o livro " .. doc_file)
        return true
    end

    return false
end

--- Remove arquivos de sincronização órfãos cujos e-books originais foram deletados.
-- @param doc_file string O caminho absoluto de um e-book para inferir o diretório raiz da limpeza.
-- @return boolean Retorna verdadeiro se a limpeza foi concluída com sucesso, ou falso caso contrário.
function Progress.cleanup_orphans(doc_file)
    if not doc_file or type(doc_file) ~= "string" then
        return false
    end

    local book_dir = doc_file:match("^(.*)/")
    if not book_dir then
        utils.logErr("cleanup_orphans: Nao foi possivel obter o diretorio do livro.")
        return false
    end

    local sync_dir = book_dir .. "/.sidekick_sync"
    local mode = lfs.attributes(sync_dir, "mode")
    if not mode or mode ~= "directory" then
        return false
    end

    for filename in lfs.dir(sync_dir) do
        if filename ~= "." and filename ~= ".." and filename:match("%.json$") then
            local filepath = sync_dir .. "/" .. filename
            local data = Progress.read_json(filepath)

            if data and data._meta and data._meta.original_file then
                local orig_file = data._meta.original_file
                local exists = lfs.attributes(orig_file, "mode")

                if not exists then
                    local success, err = os.remove(filepath)
                    if not success then
                        utils.logErr("Nao foi possivel remover o arquivo orfao " .. filepath .. ": " .. tostring(err))
                    else
                        utils.logInfo("Removido arquivo de sincronizacao orfao: " .. filepath)
                    end
                end
            end
        end
    end

    return true
end

return Progress