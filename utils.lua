local logger = require("logger")
local ltn12 = require("ltn12")
local json = require("json")
local NetworkMgr = require("ui/network/manager")
local device = require("device")

-- Tenta carregar bibliotecas de rede
local http = require("socket.http")
local has_ssl, https = pcall(require, "ssl.https") 

local Utils = {}

function Utils.logInfo(...) logger.info("Sidekick:", ...) end
function Utils.logWarn(...) logger.warn("Sidekick:", ...) end
function Utils.logErr(...)  logger.err("Sidekick:", ...) end

-- === Carregamento do settings.json Local ===

local function get_plugin_path()
    local path = debug.getinfo(1).source:match("@?(.*[\\/])")
    return path or ""
end

function Utils.load_config()
    local path = get_plugin_path() .. "settings.json"
    local f = io.open(path, "r")
    
    local config = {
        url = "http://127.0.0.1:8384",
        api_key = "",
        folder_id = "default"
    }

    if not f then
        Utils.logWarn("Arquivo settings.json nao encontrado em:", path)
        return config
    end

    local content = f:read("*a")
    f:close()

    if content then
        local ok, data = pcall(json.decode, content)
        if ok and type(data) == "table" then
            Utils.logInfo("Configurações carregadas de settings.json")
            return data
        else
            Utils.logErr("Erro ao decodificar settings.json")
        end
    end

    return config
end

function Utils.triggerSyncthing(specific_path)
    if not device.isAndroid and not NetworkMgr:isWifiOn() then
        Utils.logInfo("Wi-Fi desligado (E-ink). Ignorando trigger do Syncthing.")
        return
    end

    local config = Utils.load_config()
    
    local url = config.url
    local api_key = config.api_key
    local folder_id = config.folder_id

    if not api_key or api_key == "" or api_key == "COLE_SUA_API_KEY_AQUI" then 
        Utils.logWarn("API Key invalida. Edite o arquivo settings.json na pasta do plugin.")
        return 
    end

    url = url:gsub("/+$", "")

    local full_url = string.format("%s/rest/db/scan?folder=%s", url, folder_id)
    if specific_path then
        local clean_path = specific_path:gsub(" ", "%%20")
        full_url = full_url .. "&sub=" .. clean_path
    end

    Utils.logInfo("Enviando requisicao para Syncthing...")

    local response_body = {}
    local res, code, headers, status
    
    if full_url:find("^https") then
        if not has_ssl then
            Utils.logErr("ERRO: URL é HTTPS mas biblioteca ssl.https nao carregou.")
            return
        end
        
        res, code, headers, status = https.request{
            url = full_url,
            method = "POST",
            headers = {
                ["X-API-Key"] = api_key,
                ["Content-Length"] = "0"
            },
            source = ltn12.source.string(""),
            sink = ltn12.sink.table(response_body),
            protocol = "any",
            options = {"all"},
            verify = "none" 
        }
    else
        res, code, headers, status = http.request{
            url = full_url,
            method = "POST",
            headers = {
                ["X-API-Key"] = api_key,
                ["Content-Length"] = "0"
            },
            sink = ltn12.sink.table(response_body)
        }
    end

    if code == 200 then
        Utils.logInfo("Syncthing respondeu: OK (Scan iniciado)")
    else
        Utils.logWarn("Syncthing falhou. Codigo HTTP:", code, "Erro:", status or res)
    end
end

return Utils