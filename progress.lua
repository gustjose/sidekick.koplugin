local logger = require("logger")
local json = require("json")
local docsettings = require("frontend/docsettings")
local lfs = require("libs/libkoreader-lfs")

local Progress = {
    extension = ".sidekick.json" 
}

-- [FIX] Usa a API nativa para pegar a pasta de metadados (.sdr)
function Progress.get_sidekick_path(doc_file)
    if not doc_file then return nil end
    
    local sdr_dir = docsettings:getSidecarDir(doc_file)
    if not sdr_dir then 
        logger.warn("Sidekick: SDR dir nao encontrado para", doc_file)
        return nil 
    end
    
    -- Garante que o diretório existe
    lfs.mkdir(sdr_dir)

    local filename = doc_file:match("([^/]+)$") or "unknown"
    return sdr_dir .. "/" .. filename .. Progress.extension
end

-- [FIX] Leitura segura inspirada no utils.lua do AnnotationSync
function Progress.read_json(path)
    local f = io.open(path, "r")
    if not f then return nil end
    
    local content = f:read("*a")
    f:close()
    
    if not content or content == "" then return nil end
    
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

function Progress.save_from_cache(state, background)
    if not state or not state.file then 
        logger.warn("Sidekick: Estado invalido para salvar")
        return false 
    end

    local filepath = Progress.get_sidekick_path(state.file)
    if not filepath then return false end

    -- Prepara os dados
    local data = {
        percent = state.percent,
        page = state.page,
        total_pages = state.total_pages,  -- [FIX] Adicionado total_pages
        xpath = state.xpath,
        timestamp = os.time(), -- Importante para resolução de conflitos
        device = "KOReader",
        file_path = state.file
    }

    -- [FIX] Verifica se o arquivo no disco é mais recente antes de salvar (Conflito simples)
    local existing_data = Progress.read_json(filepath)
    if existing_data and existing_data.timestamp and existing_data.timestamp > data.timestamp then
        logger.warn("Sidekick: Tentativa de sobrescrever progresso mais recente. Abortando.")
        return false
    end

    local status, json_str = pcall(json.encode, data)
    if not status then
        logger.err("Sidekick: Erro ao gerar JSON: ", json_str)
        return false
    end

    local f, err = io.open(filepath, "w")
    if not f then
        logger.err("Sidekick: Permissao negada ou erro de disco: ", filepath, err)
        return false
    end

    f:write(json_str)
    f:close()

    if not background then
        logger.info("Sidekick: Arquivo gravado com sucesso em: ", filepath)
        logger.info("Sidekick: Dados salvos - Página ", data.page, " de ", data.total_pages, 
                   " (", math.floor((data.percent or 0) * 100), "%)")
    end
    
    return true
end

function Progress.check_remote_progress(document)
    if not document or not document.file then return end
    
    local filepath = Progress.get_sidekick_path(document.file)
    local data = Progress.read_json(filepath)
    
    if data and data.page then
        local current_page = document:getVmPage()
        
        -- Só avisa se a página for diferente E o timestamp do arquivo for razoavelmente recente/válido
        -- (Isso é útil se você usa Syncthing: o arquivo mudou no disco externamente)
        if data.page ~= current_page then
             -- Retorna os dados para o main.lua decidir se mostra o popup
            return data
        end
    end
    return nil
end

return Progress