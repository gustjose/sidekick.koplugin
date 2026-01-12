local logger = require("logger")

local Utils = {}

--- Envia uma mensagem de informação para o log do sistema com prefixo padrão.
-- @param ... Mensagens a serem concatenadas e logadas.
function Utils.logInfo(...)
    logger.info("Sidekick:", ...)
end

--- Envia uma mensagem de aviso para o log do sistema.
-- @param ... Mensagens a serem concatenadas e logadas.
function Utils.logWarn(...)
    logger.warn("Sidekick:", ...)
end

--- Envia uma mensagem de erro para o log do sistema.
-- @param ... Mensagens a serem concatenadas e logadas.
function Utils.logErr(...)
    logger.err("Sidekick:", ...)
end

return Utils