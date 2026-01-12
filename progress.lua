local json = require("json")
local docsettings = require("frontend/docsettings")
local lfs = require("libs/libkoreader-lfs")
local utils = require("utils")

local Progress = {
    extension = ".sidekick.json" 
}

--- Gera o caminho completo para o arquivo de progresso (.sidekick.json) no diretório sdr.
-- @param doc_file String: Caminho absoluto do arquivo do documento.
-- @return String|nil: Caminho completo do json ou nil em caso de erro.
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

--- Lê e decodifica o arquivo JSON de progresso.
-- @param path String: Caminho do arquivo.
-- @return Table|nil: Tabela com os dados ou nil se falhar.
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

--- Salva o estado atual no arquivo JSON, respeitando a lógica de maior progresso.
-- Apenas salva se o progresso atual for maior ou igual ao do disco, ou se não houver arquivo.
-- @param state Table: Tabela contendo percent, page, etc.
-- @param background Boolean: Se verdadeiro, suprime mensagens de sucesso na UI (logs mantidos).
-- @return Boolean: True se salvou com sucesso, False caso contrário.
function Progress.save_from_cache(state, background)
    if not state or not state.file then return false end

    local filepath = Progress.get_sidekick_path(state.file)
    if not filepath then return false end

    -- Dados estritamente necessários para a sincronização
    local data = {
        percent = state.percent,
        page = state.page,
        timestamp = os.time()
    }

    local existing_data = Progress.read_json(filepath)
    
    -- Lógica de proteção: Disco tem mais progresso > Abortar save
    if existing_data and existing_data.percent and existing_data.percent > (data.percent + 0.0001) then
        utils.logWarn(string.format("Ignorando save. Disco tem mais progresso (%.2f%% vs %.2f%%).", existing_data.percent*100, data.percent*100))
        return false
    end

    local status, json_str = pcall(json.encode, data)
    if not status then return false end

    local f, err = io.open(filepath, "w")
    if not f then
        utils.logErr("Erro de escrita em", filepath, ":", err)
        return false
    end

    f:write(json_str)
    f:close()

    if not background then
        utils.logInfo("Salvo com sucesso. Pg:", data.page)
    end
    
    return true
end

--- Verifica e resolve conflitos de sincronização (arquivos sync-conflict gerados pelo Syncthing).
-- Mantém o arquivo (principal ou conflito) que tiver estritamente maior progresso.
-- @param main_filepath String: Caminho do arquivo JSON principal.
-- @return Boolean: True se houve alguma resolução de conflito, False caso contrário.
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
            
            if not conflict_data or not conflict_data.percent then
                utils.logWarn("Arquivo de conflito inválido. Deletando.")
                os.remove(conflict_path)
            else
                local main_pct = (main_data and main_data.percent) or 0
                local conf_pct = conflict_data.percent or 0
                local should_replace = false
                
                if conf_pct > (main_pct + 0.0001) then
                    utils.logInfo(string.format("Conflito VENCE (%.2f%% > %.2f%%).", conf_pct*100, main_pct*100))
                    should_replace = true
                else
                    utils.logInfo(string.format("Conflito PERDE ou EMPATA (%.2f%% vs %.2f%%). Deletando.", conf_pct*100, main_pct*100))
                end

                if should_replace then
                    os.remove(main_filepath) 
                    local success, err = os.rename(conflict_path, main_filepath)
                    if not success then
                        utils.logErr("Falha ao renomear conflito:", err)
                    end
                    any_resolution = true
                else
                    os.remove(conflict_path)
                end
            end
        end
    end
    return any_resolution
end

--- Verifica o progresso remoto lendo o arquivo JSON e resolvendo conflitos prévios.
-- @param document Table: Objeto documento contendo o caminho do arquivo.
-- @return Table|nil: Dados remotos (page, percent, timestamp) ou nil.
-- @return Boolean: Indica se houve resolução de conflito nesta verificação.
function Progress.check_remote_progress(document)
    if not document or not document.file then return nil end
    
    local filepath = Progress.get_sidekick_path(document.file)
    local was_resolved = Progress.resolve_conflicts(filepath)
    local data = Progress.read_json(filepath)
    
    if data and data.page then
        return data, was_resolved
    end
    
    return nil
end

return Progress