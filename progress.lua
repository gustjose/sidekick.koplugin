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
    
    -- Garante que o diretório existe
    lfs.mkdir(sdr_dir)

    local filename = doc_file:match("([^/]+)$") or "unknown"
    local full_path = sdr_dir .. "/" .. filename .. Progress.extension
    
    -- [DEBUG LOG] Mostra onde está tentando salvar/ler
    -- logger.info("Sidekick: Path do arquivo JSON -> ", full_path)
    return full_path
end

function Progress.read_json(path)
    local f, err = io.open(path, "r")
    if not f then 
        -- Só avisa se for erro real, não se for apenas arquivo inexistente (comum em livro novo)
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

    -- Lê o atual para evitar sobrescrever dados mais novos (conflito básico)
    local existing_data = Progress.read_json(filepath)
    if existing_data and existing_data.timestamp and existing_data.timestamp > data.timestamp then
        logger.warn("Sidekick: Ignorando save. Arquivo no disco é mais recente.")
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

function Progress.check_remote_progress(document)
    if not document or not document.file then return nil end
    
    local filepath = Progress.get_sidekick_path(document.file)
    local data = Progress.read_json(filepath)
    
    -- [CORREÇÃO] Retorna os dados SEMPRE que encontrar o arquivo válido.
    -- Removemos a verificação "if data.page ~= current_page".
    -- O main.lua que vai decidir se precisa syncar ou não.
    if data and data.page then
        return data
    end
    
    return nil
end

return Progress