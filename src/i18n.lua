--- Módulo simples de Internacionalização (i18n) para KOReader
-- Evita a complexidade do sistema de compilação gettext (.po/.mo)
-- Usa o idioma atual do dispositivo para retornar traduções estáticas.

local I18n = {}

-- Dicionário contendo as traduções. 
-- A chave é o texto base em Inglês e o valor é a tradução em Português.
local dict_pt = {
    ["SideKick Sync"] = "Sincronização SideKick",
    ["Force Save"] = "Forçar Salvamento",
    ["Check Status"] = "Verificar Status",
    ["Sidekick Settings"] = "Configurações do Sidekick",
    ["Signal Syncthing"] = "Sinalizar para Syncthing",
    ["Cancel"] = "Cancelar",
    ["Save"] = "Salvar",
    ["Saved successfully!"] = "Salvo com sucesso!",
    ["Error saving!"] = "Erro ao salvar!",
    ["Syncing..."] = "Sincronizando...",
    ["Syncing: Page "] = "Sincronizando: Página ",
    ["Edit "] = "Editar ",
    ["Sidekick: Force Save"] = "SideKick: Forçar Salvamento",
    ["Saves current reading progress to the sidekick file."] = "Salva o progresso de leitura atual no arquivo sidekick.",
    ["Sidekick - Progress Sync"] = "Sidekick - Sincronizador de Progresso",
    ["Generates local progress files for Syncthing."] = "Gera arquivos de progresso locais para sincronização via Syncthing."
}

--- Função que tenta ler o idioma atual configurado no KOReader de forma defensiva.
-- @return string O código do idioma (ex: "pt_BR", "en_US") ou "en" como fallback.
local function getCurrentLanguage()
    -- G_reader_settings é a variável global do KOReader que armazena configurações
    if G_reader_settings and type(G_reader_settings.readSetting) == "function" then
        local lang = G_reader_settings:readSetting("language")
        if lang and type(lang) == "string" then
            return lang
        end
    end
    return "en" -- Fallback para inglês se não for possível determinar
end

--- Cache do idioma para não ler a configuração global em cada chamada de tradução
local current_lang = getCurrentLanguage()

--- Função principal de tradução que substitui o gettext.
-- Se o idioma atual for português e a chave existir no dicionário, retorna o valor.
-- Caso contrário, retorna a string original em inglês.
-- @param text string A string original em Inglês.
-- @return string A string traduzida ou a original.
function I18n.getText(text)
    if not text or type(text) ~= "string" then return text end

    -- Verifica se o idioma começa com "pt" (pega pt_BR e pt_PT)
    if current_lang:sub(1, 2) == "pt" then
        local translation = dict_pt[text]
        if translation then
            return translation
        end
    end

    -- Fallback: idioma não é PT ou a tradução não existe no dicionário
    return text
end

-- Configura o metatable para permitir chamar o módulo como uma função diretamente.
-- Assim podemos fazer `local _ = require("i18n")` e usar `_("Texto")`.
setmetatable(I18n, {
    __call = function(self, text)
        return self.getText(text)
    end
})

return I18n
