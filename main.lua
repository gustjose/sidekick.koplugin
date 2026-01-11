local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local ReaderUI = require("apps/reader/readerui")
local Dispatcher = require("dispatcher")
local _ = require("gettext")

local progress_ok, progress = pcall(require, "progress")

local SideKickSync = WidgetContainer:extend{
    name = "SideKickSync",
    is_doc_only = true,
    save_timer = nil,
    is_saving = false,
    SAVE_DELAY = 5, 
}

function SideKickSync:init()
    if not progress_ok then 
        logger.err("Sidekick: Falha ao carregar modulo progress")
        return 
    end

    if self.ui.menu then self.ui.menu:registerToMainMenu(self) end
    self:onDispatcherRegisterActions()

    self.ui:registerPostInitCallback(function()
        logger.info("Sidekick: UI completamente inicializada")
        UIManager:scheduleIn(1, function()
            self:checkSync()
        end)
    end)
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
                        msg = string.format("Página: %d/%d (%.1f%%)", 
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
    
    -- 1. Garante acesso à UI
    local ui = self.ui or (ReaderUI.instance and ReaderUI.instance.ui)
    if not ui then return nil end

    local doc = ui.document
    local view = ui.view

    -- 2. TENTATIVA VIEW (Método Visual Padrão)
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

    -- 3. TENTATIVA FOOTER (A Fonte da Verdade)
    -- Tenta encontrar o footer em ui.footer ou view.footer
    local footer = ui.footer
    if not footer and view and view.footer then 
        footer = view.footer 
    end

    if footer then
        -- a) Porcentagem exata
        if type(footer.percent_finished) == "number" then
            percent = footer.percent_finished
        elseif footer.progress_bar and type(footer.progress_bar.percentage) == "number" then
            percent = footer.progress_bar.percentage
        end

        -- b) Página atual e Total (Correção para Scroll Mode)
        if (not page or page <= 1) and type(footer.pageno) == "number" then
            page = footer.pageno
        end
        if (not total_pages or total_pages == 0) and type(footer.pages) == "number" then
            total_pages = footer.pages
        end
    end

    -- 4. TENTATIVA DOC (Backend - XPointer)
    if doc then
        local ok_x, res_x = pcall(function() return doc:getXPointer() end)
        if ok_x then xpath = res_x end
        
        -- Fallback: Se não temos página mas temos XPath
        if (not page or page <= 1) and xpath then
            local ok, res = pcall(function() return doc:getVmPage(xpath) end)
            if ok and type(res) == "number" then page = res end
        end
    end

    -- 5. CÁLCULOS FINAIS
    if not page then page = 1 end
    
    -- Recalcula percentual na mão se tivermos os números brutos e o footer falhou
    if (not percent or percent == 0) and page and total_pages and total_pages > 0 then
        percent = page / total_pages
    end

    -- Caminho do arquivo
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

function SideKickSync:scheduleSave()
    if not progress_ok then return end
    if self.save_timer then UIManager:unschedule(self.save_timer) end

    self.save_timer = UIManager:scheduleIn(self.SAVE_DELAY, function()
        self:executeSave(true)
        self.save_timer = nil
    end)
end

function SideKickSync:executeSave(is_background)
    if self.is_saving then return end
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

function SideKickSync:onReaderReady()
    UIManager:scheduleIn(2, function() self:checkSync() end)
end

function SideKickSync:onPosUpdate()
    self:scheduleSave()
end

function SideKickSync:onSuspend()
    self:forceSave(true)
end

function SideKickSync:forceSave(silent)
    if self.save_timer then
        UIManager:unschedule(self.save_timer)
        self.save_timer = nil
    end
    self:executeSave(silent)
end

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
        local ConfirmBox = require("ui/widget/confirmbox")
        local target_desc = remote_data.page
        if remote_data.xpath then target_desc = target_desc .. " (Preciso)" end

        local popup = ConfirmBox:new{
            text = "Sidekick: Progresso remoto detectado!\nIr para posição " .. target_desc .. "?",
            ok_text = "Sim",
            cancel_text = "Não",
            callback = function()
                local ui = ReaderUI.instance and ReaderUI.instance.ui
                if ui then 
                    if remote_data.xpath then
                        ui:handleEvent(require("ui/event"):new("GotoXPointer", remote_data.xpath))
                    else
                        ui:handleEvent(require("ui/event"):new("GotoPage", remote_data.page))
                    end
                end
            end
        }
        UIManager:show(popup)
    end
end

return SideKickSync