local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local ReaderUI = require("apps/reader/readerui")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local _ = require("gettext")

local progress_ok, progress = pcall(require, "progress")

local SideKickSync = WidgetContainer:extend{
    name = "SideKickSync",
    is_doc_only = true,
    is_saving = false,
    blocking_autosave = false, -- Começa desbloqueado (safe default)
    time_next_sync = os.time(),
    delay = 5,
    last_local_interaction = 0,
}

function SideKickSync:init()
    if not progress_ok then 
        logger.err("Sidekick: Falha ao carregar modulo progress")
        return 
    end
    if self.ui.menu then self.ui.menu:registerToMainMenu(self) end
    self:onDispatcherRegisterActions()
    logger.info("Sidekick: Modulo inicializado.")
end

function SideKickSync:onReaderReady()
    logger.info("Sidekick: Reader pronto. Iniciando verificacao de Sync...")
    UIManager:scheduleIn(2, function() self:checkSync() end)
end

function SideKickSync:onDispatcherRegisterActions()
    Dispatcher:registerAction("sidekick_manual_save", {
        category = "none",
        event = "SideKickManualSave",
        title = _("SideKick: Forçar Salvamento"),
        text = _("Salva o progresso de leitura atual no arquivo sidekick."),
        separator = true,
        reader = true,
        callback = function() self:forceSave() end
    })
end

function SideKickSync:addToMainMenu(menu_items)
    menu_items.sidekick = {
        text = "SideKick Sync",
        sub_item_table = {
            {
                text = "Forçar Salvamento",
                callback = function() self:forceSave() end
            },
            {
                text = "Verificar Status",
                callback = function() 
                    local doc_state = self:getCurrentState()
                    local msg = ""
                    if doc_state then
                        msg = string.format("Local: Pg %d/%d (%.1f%%)", 
                            doc_state.page or 0, 
                            doc_state.total_pages or 0,
                            (doc_state.percent or 0) * 100)
                    else
                        msg = "Erro ao ler estado"
                    end
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                    self:checkSync() 
                end
            }
        }
    }
end

function SideKickSync:getCurrentState()
    local page = nil
    local percent = nil
    local total_pages = nil
    
    local ui = self.ui or (ReaderUI.instance and ReaderUI.instance.ui)
    if not ui then return nil end

    local doc = ui.document
    local view = ui.view

    if view then
        local props = {"current_page", "page_num", "page", "pageno"}
        for _, prop in ipairs(props) do
            if type(view[prop]) == "number" then
                page = view[prop]
                break
            end
        end
        if type(view.page_count) == "number" then total_pages = view.page_count end
    end

    local footer = ui.footer
    if not footer and view and view.footer then footer = view.footer end

    if footer then
        if type(footer.percent_finished) == "number" then
            percent = footer.percent_finished
        elseif footer.progress_bar and type(footer.progress_bar.percentage) == "number" then
            percent = footer.progress_bar.percentage
        end
        if (not page or page <= 1) and type(footer.pageno) == "number" then
            page = footer.pageno
        end
        if (not total_pages or total_pages == 0) and type(footer.pages) == "number" then
            total_pages = footer.pages
        end
    end

    local xpath = nil
    if doc then
        local ok_x, res_x = pcall(function() return doc:getXPointer() end)
        if ok_x then xpath = res_x end
        
        if (not page or page <= 1) and xpath then
            local ok, res = pcall(function() return doc:getVmPage(xpath) end)
            if ok and type(res) == "number" then page = res end
        end
    end

    if not page then page = 1 end
    if (not percent or percent == 0) and page and total_pages and total_pages > 0 then
        percent = page / total_pages
    end

    local file_path = nil
    if doc then file_path = doc.file end
    if not file_path and ReaderUI.instance and ReaderUI.instance.loaded_document then
        file_path = ReaderUI.instance.loaded_document
    end

    if not file_path then return nil end

    return {
        percent = percent or 0,
        page = page,
        total_pages = total_pages or 0,
        xpath = xpath,
        file = file_path,
    }
end

function SideKickSync:triggerAutoSave()
    if not progress_ok then return end
    
    -- Atualiza sempre que mexer para garantir que este dispositivo é o "dono" da vez
    self.last_local_interaction = os.time()

    if self.blocking_autosave then 
        -- logger.info("Sidekick: Save bloqueado (Sincronizando...)")
        return 
    end
    
    local agora = os.time()
    
    -- Lógica de Throttle: Só salva se passou o tempo do delay
    if self.time_next_sync < agora then
        self:executeSave(true)
        self.time_next_sync = agora + self.delay
        logger.info("Sidekick: Autosave - Salvo.")
    else
        -- logger.info("Sidekick: Autosave - Pulado (Throttle).")
    end
end

function SideKickSync:executeSave(is_background)
    if self.is_saving then return end
    if self.blocking_autosave then return end

    self.is_saving = true
    local state = self:getCurrentState()
    if state then
        local saved = progress.save_from_cache(state, is_background)
        if saved and not is_background then
            UIManager:show(InfoMessage:new{ text = "Progresso Salvo!", timeout = 1 })
        end
    end
    self.is_saving = false
end

-- === EVENTOS ===
function SideKickSync:onPosUpdate() self:triggerAutoSave() end
function SideKickSync:onPageUpdate() self:triggerAutoSave() end

-- Eventos críticos
function SideKickSync:onCloseDocument() self:forceSave(true) end
function SideKickSync:onSuspend() self:forceSave(true) end
function SideKickSync:onQuit() self:forceSave(true) end

function SideKickSync:forceSave(silent)
    logger.info("Sidekick: Executando salvamento forçado.")
    self:executeSave(silent)
end

-- === SINCRONIZAÇÃO ===
function SideKickSync:checkSync()
    if not progress_ok then return end
    
    local state = self:getCurrentState()
    if not state then return end
    
    local fake_doc = { 
        file = state.file, 
        getVmPage = function() return state.page end 
    }

    local remote_data, conflict_resolved = progress.check_remote_progress(fake_doc)
    
    if remote_data then
        local r_page = tonumber(remote_data.page) or 0
        local l_page = tonumber(state.page) or 0
        local r_timestamp = tonumber(remote_data.timestamp) or 0
        local r_percent = tonumber(remote_data.percent) or 0
        
        -- Adicionamos state.percent para log e comparação
        local l_percent = state.percent or 0

        logger.info(string.format("Sidekick: Check Sync (Resolvido: %s) - Remoto: %.2f%% (%d) vs Local: %.2f%% (%d)", 
            tostring(conflict_resolved), r_percent*100, r_timestamp, l_percent*100, self.last_local_interaction))

        -- CRITÉRIOS DE SINCRONIZAÇÃO ATUALIZADOS:
        -- 1. Timestamp remoto é mais novo que minha interação (Sync Padrão)
        -- 2. Conflito foi resolvido a favor do remoto (Sync de Correção)
        -- 3. [NOVO] Remoto tem progresso SUBSTANCIALMENTE maior (Furthest Read Wins)
        
        local is_newer = r_timestamp > self.last_local_interaction
        local is_ahead = r_percent > (l_percent + 0.001) -- Margem de 0.1% para evitar loops
        
        local should_sync = (is_newer or conflict_resolved or is_ahead)
        
        local diff_percent = math.abs(r_percent - l_percent)
        
        -- Verifica se vale a pena mover (diferença existe e sync foi aprovado)
        if should_sync and (diff_percent > 0.001) then
            
            self.blocking_autosave = true 
            
            -- [CÁLCULO DINÂMICO]
            local target_page = r_page 
            
            if r_percent > 0 and state.total_pages and state.total_pages > 0 then
                target_page = math.floor(state.total_pages * r_percent)
                if target_page < 1 then target_page = 1 end
                if target_page > state.total_pages then target_page = state.total_pages end
                
                logger.info(string.format("Sidekick: Avançando para Pg %d (%.2f%%) - Motivo: Ahead=%s, Newer=%s", target_page, r_percent*100, tostring(is_ahead), tostring(is_newer)))
            else
                logger.info("Sidekick: Usando número de página remoto direto.")
            end
            
            UIManager:show(InfoMessage:new{ text = "Sync: Indo para Pág " .. target_page, timeout = 2 })
            
            UIManager:nextTick(function()
                UIManager:broadcastEvent(Event:new("GotoPage", target_page))
                self.last_local_interaction = os.time() 
                UIManager:scheduleIn(3, function()
                    self.blocking_autosave = false
                end)
            end)
        else
            -- Se não sincronizou, mas o remoto era maior, significa que estamos "travados" por algum motivo?
            -- Com a lógica 'is_ahead', isso não deve mais acontecer.
            logger.info("Sidekick: Nada a fazer (Sincronizado ou Local é Maior).")
            self.blocking_autosave = false
        end
    else
        self.blocking_autosave = false
    end
end

return SideKickSync