local json = require("json")
local docsettings = require("frontend/docsettings")
local lfs = require("libs/libkoreader-lfs")
local utils = require("utils")
local device = require("device") 

local Progress = {
    extension = ".sidekick.json" 
}

--- Obtém um ID único para o dispositivo atual
function Progress.get_device_id()
    -- Tenta usar o serial, id ou modelo para garantir unicidade
    return device.serial or device.id or device.model or "unknown_device"
end

--- Gera o caminho completo para o arquivo de progresso
function Progress.get_sidekick_path(doc_file)
    if not doc_file then return nil end
    
    local sdr_dir = docsettings:getSidecarDir(doc_file)
    if not sdr_dir then 
        utils.logWarn("SDR dir não encontrado para", doc_file)
        return nil 
    end
    
    lfs.mkdir(sdr_dir)

    local filename = doc_file:match("([^/]+)$") or "unknown"
    return sdr_dir .. "/" .. filename .. Progress.extension
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

--- Salva o estado do dispositivo ATUAL, incrementando a revisão global.
function Progress.save_from_cache(state, background)
    if not state or not state.file then return false end

    local filepath = Progress.get_sidekick_path(state.file)
    if not filepath then return false end

    -- 1. Ler dados existentes de todos os dispositivos
    local all_data = Progress.read_json(filepath) or {}
    
    -- 2. Descobrir qual é a maior revisão GLOBAL atual (de qualquer dispositivo)
    local max_global_rev = 0
    for _, entry in pairs(all_data) do
        if entry.revision and entry.revision > max_global_rev then
            max_global_rev = entry.revision
        end
    end

    -- 3. Preparar o payload do MEU dispositivo
    -- A minha nova revisão deve ser maior que TUDO o que existe no arquivo agora
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

    -- 4. Gravar no disco
    local status, json_str = pcall(json.encode, all_data)
    if not status then return false end

    local f, err = io.open(filepath, "w")
    if not f then
        utils.logErr("Erro de escrita em", filepath, ":", err)
        return false
    end

    f:write(json_str)
    f:close()

    if not background then
        utils.logInfo(string.format("Salvo: %s (Rev %d)", my_id, my_new_rev))
    end
    
    -- Retorna a nova revisão para atualizar a memória local
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

return Progress