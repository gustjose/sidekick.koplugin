local logger = require("logger")
local ltn12 = require("ltn12")

-- Tenta carregar bibliotecas de rede
local http = require("socket.http")
local has_ssl, https = pcall(require, "ssl.https") -- LuaSec para HTTPS

local Utils = {}

-- === CONFIGURAÇÕES ===
-- IMPORTANTE: Mudei para HTTPS para evitar o erro 307
local SYNC_URL = "https://127.0.0.1:8384" 
local SYNC_API_KEY = "J3ewiacqu5idyf76Lq2fvJp5rUU6RKEG"
local SYNC_FOLDER_ID = "gwfho-uld6e"

function Utils.logInfo(...) logger.info("Sidekick:", ...) end
function Utils.logWarn(...) logger.warn("Sidekick:", ...) end
function Utils.logErr(...)  logger.err("Sidekick:", ...) end

function Utils.triggerSyncthing(specific_path)
    if not SYNC_API_KEY or SYNC_API_KEY == "" then return end

    local full_url = string.format("%s/rest/db/scan?folder=%s", SYNC_URL, SYNC_FOLDER_ID)
    if specific_path then
        local clean_path = specific_path:gsub(" ", "%%20")
        full_url = full_url .. "&sub=" .. clean_path
    end

    Utils.logInfo("Enviando requisicao para Syncthing...")

    local response_body = {}
    local res, code, headers, status
    
    -- Detecta se é HTTPS e se temos a biblioteca
    if full_url:find("^https") then
        if not has_ssl then
            Utils.logErr("ERRO: URL é HTTPS mas biblioteca ssl.https nao carregou.")
            return
        end
        
        -- Configuração especial para HTTPS (Ignora certificado auto-assinado)
        res, code, headers, status = https.request{
            url = full_url,
            method = "POST",
            headers = {
                ["X-API-Key"] = SYNC_API_KEY,
                ["Content-Length"] = "0"
            },
            source = ltn12.source.string(""),
            sink = ltn12.sink.table(response_body),
            
            -- CRUCIAL: Ignora validação de certificado (necessário para localhost/android)
            protocol = "any",
            options = {"all"},
            verify = "none" 
        }
    else
        -- Fallback para HTTP simples
        res, code, headers, status = http.request{
            url = full_url,
            method = "POST",
            headers = {
                ["X-API-Key"] = SYNC_API_KEY,
                ["Content-Length"] = "0"
            },
            sink = ltn12.sink.table(response_body)
        }
    end

    if code == 200 then
        Utils.logInfo("Syncthing respondeu: OK (Scan iniciado)")
    else
        -- Se der 307 novamente, o log nos avisará
        Utils.logWarn("Syncthing falhou. Codigo HTTP:", code, "Erro/Status:", status or res)
    end
end

return Utils