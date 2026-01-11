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
    save_timer = nil,
    last_activity = 0,
    last_force_save = 0,
    is_saving = false,
    blocking_autosave = false,
    SAVE_DELAY = 5,
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
    -- Aguarda 2 segundos para garantir que o livro carregou a estrutura
    logger.info("Sidekick: Reader pronto. Agendando checkSync.")
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
                        msg = string.format("Pg: %d/%d (%.1f%%)", 
                            doc_state.page or 0, 
                            doc_state.total_pages or 0,
                            (doc_state.percent or 0) * 100)
                    else
                        msg = "Erro ao ler estado"
                    end
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
                end
            }
        }
    }
end

function SideKickSync:getCurrentState()
    local page = nil
    local percent = nil
    local total_pages = nil
    local xpath = nil
    
    local ui = self.ui or (ReaderUI.instance and ReaderUI.instance.ui)
    if not ui then return nil end

    local doc = ui.document
    local view = ui.view

    -- TENTATIVA VIEW
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

    -- TENTATIVA FOOTER
    local footer = ui.footer
    if not footer and view and view.footer then 
        footer = view.footer 
    end

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

    -- TENTATIVA DOC
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
        -- xpath = xpath,
        file = file_path,
    }
end

function SideKickSync:scheduleSave()
    if not progress_ok then return end
    if self.blocking_autosave then return end

    self.last_activity = os.time()

    if self.save_timer then return end

    local function timer_callback()
        if self.blocking_autosave then
            self.save_timer = nil
            return
        end

        local now = os.time()
        local elapsed = now - self.last_activity
        
        if elapsed >= self.SAVE_DELAY then
            self.save_timer = nil
            self:executeSave(true)
        else
            local remaining = self.SAVE_DELAY - elapsed
            if remaining < 1 then remaining = 1 end
            self.save_timer = UIManager:scheduleIn(remaining, timer_callback)
        end
    end

    self.save_timer = UIManager:scheduleIn(self.SAVE_DELAY, timer_callback)
end

function SideKickSync:executeSave(is_background)
    if self.is_saving then return end
    if self.blocking_autosave then return end

    self.is_saving = true
    local state = self:getCurrentState()
    if state then
        progress.save_from_cache(state, is_background)
        if not is_background then
            UIManager:show(InfoMessage:new{ text = "Progresso Salvo!", timeout = 2 })
        end
    end
    self.is_saving = false
end

-- === EVENTOS ===
function SideKickSync:onPosUpdate() self:scheduleSave() end
function SideKickSync:onPageUpdate() self:scheduleSave() end
function SideKickSync:onCloseDocument() self:forceSave(true) end
function SideKickSync:onSuspend() self:forceSave(true) end
function SideKickSync:onQuit() self:forceSave(true) end

function SideKickSync:forceSave(silent)
    if self.save_timer then
        UIManager:unschedule(self.save_timer)
        self.save_timer = nil
    end
    local now = os.time()
    if self.last_force_save and (now - self.last_force_save) < 2 then return end
    self.last_force_save = now
    logger.info("Sidekick: Executando salvamento forçado.")
    self:executeSave(silent)
end

-- === LÓGICA DE SINCRONIZAÇÃO (USANDO BROADCAST) ===
function SideKickSync:checkSync()
    if not progress_ok then return end
    
    local state = self:getCurrentState()
    if not state then return end
    
    local fake_doc = { 
        file = state.file, 
        getVmPage = function() return state.page end 
    }
    
    local remote_data = progress.check_remote_progress(fake_doc)
    
    if remote_data then
        local r_page = tonumber(remote_data.page) or 0
        local l_page = tonumber(state.page) or 0
        
        -- Só avança se o remoto for estritamente maior
        if r_page <= l_page then return end

        logger.info("Sidekick: Avanço detectado (Remoto: " .. r_page .. " > Local: " .. l_page .. ")")

        -- Bloqueia autosave para evitar loops
        self.blocking_autosave = true
        if self.save_timer then
            UIManager:unschedule(self.save_timer)
            self.save_timer = nil
        end
        
        -- Feedback visual
        UIManager:show(InfoMessage:new{ text = "Sync: Indo para Pág " .. r_page, timeout = 2 })
            
        -- A SOLUÇÃO: broadcastEvent
        -- Não precisamos caçar a "ui" certa. O UIManager entrega pra quem interessar.
        UIManager:nextTick(function()
            logger.info("Sidekick: Broadcastindo evento GotoPage para", r_page)
            
            -- Envia para toda a aplicação. O ReaderPaging vai pegar isso.
            UIManager:broadcastEvent(Event:new("GotoPage", r_page))
            
            -- Libera a trava logo após o envio
            self.blocking_autosave = false
            self.last_activity = os.time()
        end)
    end
end

return SideKickSync