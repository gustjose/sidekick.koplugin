local logger = require("logger")
local json = require("json")
local docsettings = require("frontend/docsettings")
local lfs = require("libs/libkoreader-lfs")

local Progress = {
    extension = ".sidekick.json" 
}

function Progress.get_sidekick_path(doc_file)
    if not doc_file then return nil end
    
    local sdr_dir = docsettings:getSidecarDir(doc_file)
    if not sdr_dir then 
        logger.warn("Sidekick: SDR dir nao encontrado para", doc_file)
        return nil 
    end
    
    lfs.mkdir(sdr_dir)

    local filename = doc_file:match("([^/]+)$") or "unknown"
    local full_path = sdr_dir .. "/" .. filename .. Progress.extension
    
    return full_path
end

function Progress.read_json(path)
    local f, err = io.open(path, "r")
    if not f then 
        if err and not err:find("No such file") then
            logger.warn("Sidekick: Falha ao abrir arquivo: ", err)
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
    
    logger.warn("Sidekick: JSON corrompido ou inválido.")
    return nil
end

function Progress.save_from_cache(state, background)
    if not state or not state.file then return false end

    local filepath = Progress.get_sidekick_path(state.file)
    if not filepath then return false end

    local data = {
        percent = state.percent,
        page = state.page,
        total_pages = state.total_pages,
        xpath = state.xpath,
        timestamp = os.time(),
        device = "KOReader",
        file_path = state.file
    }

    -- [ALTERADO] Proteção baseada em PROGRESSO, não em timestamp.
    -- Só impede o save se o arquivo no disco tiver um progresso MAIOR que o atual.
    -- Se o arquivo no disco for apenas "mais novo" (data errada) mas tiver menos progresso, nós sobrescrevemos.
    local existing_data = Progress.read_json(filepath)
    if existing_data and existing_data.percent and existing_data.percent > (data.percent + 0.0001) then
        logger.warn(string.format("Sidekick: Ignorando save. Disco tem mais progresso (%.2f%% vs %.2f%%).", existing_data.percent*100, data.percent*100))
        return false
    end

    local status, json_str = pcall(json.encode, data)
    if not status then return false end

    local f, err = io.open(filepath, "w")
    if not f then
        logger.err("Sidekick: Erro de escrita em ", filepath, ": ", err)
        return false
    end

    f:write(json_str)
    f:close()

    if not background then
        logger.info("Sidekick: Salvo com sucesso. Pg:", data.page)
    end
    
    return true
end

function Progress.resolve_conflicts(main_filepath)
    local dir = main_filepath:match("^(.*)/")
    local filename = main_filepath:match("([^/]+)$")

    local any_resolution = false
    
    local base_name = filename:sub(1, -string.len(Progress.extension) - 1)
    
    for file in lfs.dir(dir) do
        if file:find(base_name, 1, true) and file:find("sync%-conflict") and file:match("%.json$") then
            
            local conflict_path = dir .. "/" .. file
            logger.info("Sidekick: Conflito detectado -> ", file)
            
            local main_data = Progress.read_json(main_filepath)
            local conflict_data = Progress.read_json(conflict_path)
            
            if not conflict_data or not conflict_data.percent then
                logger.warn("Sidekick: Arquivo de conflito inválido. Deletando.")
                os.remove(conflict_path)
            else
                local main_pct = (main_data and main_data.percent) or 0
                local conf_pct = conflict_data.percent or 0
                
                local should_replace = false
                
                -- [ALTERADO] Lógica Pura de Progresso
                -- O conflito só vence se tiver ESTRITAMENTE mais progresso.
                -- Empates (mesmo com timestamp mais novo) são descartados para manter a estabilidade.
                if conf_pct > (main_pct + 0.0001) then
                    logger.info(string.format("Sidekick: Conflito VENCE (%.2f%% > %.2f%%).", conf_pct*100, main_pct*100))
                    should_replace = true
                else
                    logger.info(string.format("Sidekick: Conflito PERDE ou EMPATA (%.2f%% vs %.2f%%). Deletando.", conf_pct*100, main_pct*100))
                end

                if should_replace then
                    os.remove(main_filepath) 
                    local success, err = os.rename(conflict_path, main_filepath)
                    if not success then
                        logger.err("Sidekick: Falha ao renomear conflito: ", err)
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