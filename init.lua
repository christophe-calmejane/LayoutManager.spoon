local obj = {}
obj.__index = obj

-- Spoon metadata
obj.name = "LayoutManager"
obj.version = "1.0"
obj.author = "Christophe Calmejane"
obj.homepage = "https://github.com/christophe-calmejane/LayoutManager.spoon"
obj.license = "MIT"
obj.layouts = {}
obj.layoutsFilePath = os.getenv("HOME") .. "/.hammerspoon/Spoons/LayoutManager.spoon/layouts.lua"
obj.layoutData = {}
obj.mainWindow = nil
obj.newLayoutWindow = nil
obj.menubar = nil
obj.lastAction = 0

-- Storage mode constants
obj.STORAGE_MODE_SCREEN_RELATIVE = "screen-relative"
obj.STORAGE_MODE_GLOBAL_COORDINATES = "global-coordinates"

-- Snapshot current layout (legacy function for clipboard)
function obj:snapshotLayout()
  local layout = self:snapshotCurrentLayout(self.STORAGE_MODE_SCREEN_RELATIVE)
  hs.pasteboard.setContents(hs.inspect(layout))
end

-- Apply layout
function obj:applyLayout(layoutDef)
  -- Determine storage mode - check for global coordinates or default to screen-relative
  local storageMode = self.STORAGE_MODE_SCREEN_RELATIVE
  if layoutDef.storageMode then
    storageMode = layoutDef.storageMode
  elseif layoutDef.layout and #layoutDef.layout > 0 and layoutDef.layout[1].globalX then
    storageMode = self.STORAGE_MODE_GLOBAL_COORDINATES
  end

  for _, winDef in ipairs(layoutDef.layout) do
    local app = hs.application.get(winDef.app)
    if app then
      local matchedWindow = hs.fnutils.find(app:allWindows(), function(win)
        return win:title() == winDef.title
      end) or app:mainWindow()

      if matchedWindow then
        if storageMode == self.STORAGE_MODE_GLOBAL_COORDINATES then
          -- Use global coordinates
          if winDef.globalX and winDef.globalY and winDef.globalW and winDef.globalH then
            matchedWindow:setFrame({
              x = winDef.globalX,
              y = winDef.globalY,
              w = winDef.globalW,
              h = winDef.globalH
            })
          end
        else
          -- Use screen-relative coordinates (backward compatibility)
          local screen = hs.screen.find(winDef.screen)
          if screen and winDef.relX and winDef.relY and winDef.relW and winDef.relH then
            local screenFrame = screen:frame()
            matchedWindow:setFrame({
              x = screenFrame.x + winDef.relX * screenFrame.w,
              y = screenFrame.y + winDef.relY * screenFrame.h,
              w = winDef.relW * screenFrame.w,
              h = winDef.relH * screenFrame.h
            })
          end
        end
      end
    end
  end

  local modeText = storageMode == self.STORAGE_MODE_GLOBAL_COORDINATES and " (Global)" or " (Screen-Relative)"
  hs.alert.show("Layout \"" .. layoutDef.name .. "\"" .. modeText .. " applied")
end

-- Save layouts to file
function obj:saveLayoutsToFile()
  local file = io.open(self.layoutsFilePath, "w")
  if file then
    file:write("return " .. hs.inspect(self.layoutData))
    file:close()
    return true
  else
    hs.alert.show("Failed to save layouts.lua")
    return false
  end
end

-- Load layouts from file
function obj:loadLayouts()
  local ok, layouts = pcall(dofile, self.layoutsFilePath)

  if not ok then
    self.layoutData = {} -- Initialize empty if loading fails
    return
  end

  self.layoutData = layouts or {}
  self.layouts = {}

  for _, layoutDef in ipairs(self.layoutData) do
    self.layouts[layoutDef.name] = layoutDef.layout

    if layoutDef.shortcut then
      hs.hotkey.bind(layoutDef.shortcut.mods, layoutDef.shortcut.key, function()
        self:applyLayout(layoutDef)
      end)
    end
  end

  -- Update menubar menu with new layouts
  self:updateMenubarMenu()
end

-- UI Helper functions
function obj:refreshMainUI()
  if self.mainWindow then
    -- Stop the timer before deleting the window
    if self.checkTimer then
      self.checkTimer:stop()
      self.checkTimer = nil
    end

    self.mainWindow:delete()
    self.mainWindow = nil
    self:showLayoutManagerUI()
  end
end

function obj:removeLayout(layoutName)
  -- Show confirmation dialog
  local choice = hs.dialog.blockAlert("Confirm Remove",
    "Are you sure you want to remove the layout '" .. layoutName .. "'?",
    "Remove", "Cancel")

  if choice == "Remove" then
    for i, layout in ipairs(self.layoutData) do
      if layout.name == layoutName then
        table.remove(self.layoutData, i)
        break
      end
    end

    self:saveLayoutsToFile()
    self:loadLayouts() -- Reload to update hotkeys and menubar
    self:refreshMainUI()
    hs.alert.show("Layout '" .. layoutName .. "' removed")
  end
end

function obj:updateLayout(layoutName)
  for i, layout in ipairs(self.layoutData) do
    if layout.name == layoutName then
      -- Preserve the storage mode when updating
      local storageMode = layout.storageMode or self.STORAGE_MODE_SCREEN_RELATIVE
      local currentLayout = self:snapshotCurrentLayout(storageMode)
      layout.layout = currentLayout
      break
    end
  end

  self:saveLayoutsToFile()
  self:loadLayouts() -- Reload layouts and update menubar
  hs.alert.show("Layout '" .. layoutName .. "' updated")
end

function obj:snapshotCurrentLayout(storageMode)
  -- Default to screen-relative mode for backward compatibility
  storageMode = storageMode or self.STORAGE_MODE_SCREEN_RELATIVE

  local layout = {}
  local windows = hs.window.allWindows()

  for _, win in ipairs(windows) do
    local app = win:application():name()
    local title = win:title()
    local frame = win:frame()
    local screen = win:screen()
    local screenFrame = screen:frame()

    local windowData = {
      app = app,
      title = title,
    }

    if storageMode == self.STORAGE_MODE_GLOBAL_COORDINATES then
      -- Store absolute coordinates
      windowData.globalX = frame.x
      windowData.globalY = frame.y
      windowData.globalW = frame.w
      windowData.globalH = frame.h
    else
      -- Store screen-relative coordinates (backward compatibility)
      windowData.relX = (frame.x - screenFrame.x) / screenFrame.w
      windowData.relY = (frame.y - screenFrame.y) / screenFrame.h
      windowData.relW = frame.w / screenFrame.w
      windowData.relH = frame.h / screenFrame.h
      windowData.screen = screen:id()
    end

    table.insert(layout, windowData)
  end

  return layout
end

-- Show main layout manager UI
function obj:showLayoutManagerUI()
  -- If window already exists, just bring it to front instead of recreating
  if self.mainWindow then
    self.mainWindow:show()
    return
  end

  local tableData = {}
  for _, layout in ipairs(self.layoutData) do
    local shortcutText = "None"
    if layout.shortcut and layout.shortcut.mods and layout.shortcut.key then
      shortcutText = table.concat(layout.shortcut.mods, "+") .. "+" .. layout.shortcut.key
    end

    -- Determine storage mode display text
    local modeText = "Screen-Relative"
    if layout.storageMode == self.STORAGE_MODE_GLOBAL_COORDINATES then
      modeText = "Global"
    elseif layout.layout and #layout.layout > 0 and layout.layout[1].globalX then
      modeText = "Global"
    end

    table.insert(tableData, {
      name = layout.name,
      shortcut = shortcutText,
      mode = modeText,
      remove = "Remove",
      update = "Update"
    })
  end

  self.mainWindow = hs.webview.new({ x = 100, y = 100, w = 600, h = 400 })
      :windowTitle("Layout Manager")
      :closeOnEscape(true)
      :allowTextEntry(true)
      :allowNewWindows(false)
      :allowGestures(false)
      :windowStyle(hs.webview.windowMasks.titled | hs.webview.windowMasks.closable |
        hs.webview.windowMasks.miniaturizable | hs.webview.windowMasks.resizable)
      :show()

  -- Set up message handlers - try different callback methods for compatibility
  if self.mainWindow.navigationCallback then
    self.mainWindow:navigationCallback(function(action, webview, details)
      if details and details.url then
        if (action == "willNavigate" or action == "didStartProvisionalNavigation") and details and details.url then
          local url = details.url

          if url:match("closeWindow") then
            self.mainWindow:delete()
            self.mainWindow = nil
            return false -- prevent navigation
          elseif url:match("removeLayout/(.+)") then
            local layoutName = url:match("removeLayout/(.+)")
            self:removeLayout(layoutName)
            return false -- prevent navigation
          elseif url:match("updateLayout/(.+)") then
            local layoutName = url:match("updateLayout/(.+)")
            self:updateLayout(layoutName)
            return false -- prevent navigation
          elseif url:match("createNewLayout") then
            self:showNewLayoutUI()
            return false -- prevent navigation
          end
        end
      end
      return true
    end)
  elseif self.mainWindow.windowCallback then
    self.mainWindow:windowCallback(function(action, webview, details)
      if action == "closing" then
        self.mainWindow = nil
        return true
      elseif action == "navigation" and details and details.url then
        local url = details.url

        if url:match("removeLayout/(.+)") then
          local layoutName = url:match("removeLayout/(.+)")
          self:removeLayout(layoutName)
          return false -- prevent navigation
        elseif url:match("updateLayout/(.+)") then
          local layoutName = url:match("updateLayout/(.+)")
          self:updateLayout(layoutName)
          return false -- prevent navigation
        elseif url:match("createNewLayout") then
          self:showNewLayoutUI()
          return false -- prevent navigation
        elseif url:match("closeWindow") then
          self.mainWindow:delete()
          self.mainWindow = nil
          return false -- prevent navigation
        end
      end
      return true
    end)
  end                 -- Set up a timer to check for JavaScript flags as a fallback
  self.lastAction = 0 -- Track last action time for debouncing
  self.checkTimer = hs.timer.doEvery(0.3, function()
    if self.mainWindow then
      -- Check for title changes
      local title = self.mainWindow:title()
      if title then
        local currentTime = hs.timer.secondsSinceEpoch()
        -- Debounce: only process if enough time has passed since last action
        if currentTime - self.lastAction < 1.0 then
          return
        end

        if title:match("CLOSE_REQUESTED") then
          self.lastAction = currentTime
          self.mainWindow:delete()
          self.mainWindow = nil
          if self.checkTimer then
            self.checkTimer:stop()
            self.checkTimer = nil
          end
          return
        elseif title:match("APPLY_LAYOUT:(.+)") then
          local layoutName = title:match("APPLY_LAYOUT:(.+)")
          self.lastAction = currentTime
          -- Reset title immediately to prevent repeated triggers
          self.mainWindow:evaluateJavaScript("document.title = 'Layout Manager';")
          -- Find and apply the layout
          for _, layout in ipairs(self.layoutData) do
            if layout.name == layoutName then
              self:applyLayout(layout)
              break
            end
          end
          return
        elseif title:match("REMOVE_LAYOUT:(.+)") then
          local layoutName = title:match("REMOVE_LAYOUT:(.+)")
          self.lastAction = currentTime
          -- Reset title immediately to prevent repeated triggers
          self.mainWindow:evaluateJavaScript("document.title = 'Layout Manager';")
          self:removeLayout(layoutName)
          return
        elseif title:match("UPDATE_LAYOUT:(.+)") then
          local layoutName = title:match("UPDATE_LAYOUT:(.+)")
          self.lastAction = currentTime
          -- Reset title immediately to prevent repeated triggers
          self.mainWindow:evaluateJavaScript("document.title = 'Layout Manager';")
          self:updateLayout(layoutName)
          return
        elseif title:match("CREATE_NEW_LAYOUT") then
          self.lastAction = currentTime
          -- Reset title immediately to prevent repeated triggers
          self.mainWindow:evaluateJavaScript("document.title = 'Layout Manager';")
          self:showNewLayoutUI()
          return
        end
      end
    end
  end)

  -- Also update the HTML to use navigation instead of messageHandlers
  local updatedHtml = [[
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          margin: 20px;
          /* Disable context menu */
          -webkit-user-select: none;
          -webkit-touch-callout: none;
          -webkit-context-menu: none;
        }
        /* Disable context menu on all elements */
        * {
          -webkit-user-select: none;
          -webkit-touch-callout: none;
          -webkit-context-menu: none;
        }
        table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
        th, td { padding: 8px; text-align: left; border: 1px solid #ddd; }
        th { background-color: #f5f5f5; }
        button { padding: 5px 10px; margin: 2px; cursor: pointer; }
        .apply-btn { background-color: #2196F3; color: white; border: none; border-radius: 3px; }
        .remove-btn { background-color: #ff4444; color: white; border: none; border-radius: 3px; }
        .update-btn { background-color: #4CAF50; color: white; border: none; border-radius: 3px; }
        .new-btn { background-color: #2196F3; color: white; border: none; border-radius: 3px; padding: 10px 20px; }
        .close-btn { background-color: #666; color: white; border: none; border-radius: 3px; padding: 10px 20px; float: right; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
      </style>
    </head>
    <body>
      <div class="header">
        <h2>Layout Manager</h2>
        <button class="close-btn" onclick="closeWindow()">Close</button>
      </div>
      <table id="layoutTable">
        <thead>
          <tr>
            <th>Name</th>
            <th>Shortcut</th>
            <th>Mode</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody id="tableBody">
        </tbody>
      </table>
      <button class="new-btn" onclick="createNewLayout()">Create New Layout</button>

      <script>
        function updateTable(data) {
          console.log('updateTable called with:', data);
          const tbody = document.getElementById('tableBody');
          tbody.innerHTML = '';

          data.forEach(function(layout, index) {
            const row = tbody.insertRow();
            row.insertCell(0).textContent = layout.name;
            row.insertCell(1).textContent = layout.shortcut;
            row.insertCell(2).textContent = layout.mode;

            const actionCell = row.insertCell(3);
            actionCell.innerHTML =
              '<button class="apply-btn" onclick="applyLayout(\'' + layout.name + '\')">Apply</button>' +
              '<button class="update-btn" onclick="updateLayout(\'' + layout.name + '\')">Update</button>' +
              '<button class="remove-btn" onclick="removeLayout(\'' + layout.name + '\')">Remove</button>';
          });
        }

        function applyLayout(name) {
          console.log('Apply layout clicked: ' + name);
          document.title = 'APPLY_LAYOUT:' + name;
        }

        function removeLayout(name) {
          console.log('Remove layout clicked: ' + name);
          document.title = 'REMOVE_LAYOUT:' + name;
        }

        function updateLayout(name) {
          console.log('Update layout clicked: ' + name);
          document.title = 'UPDATE_LAYOUT:' + name;
        }

        function createNewLayout() {
          console.log('Create new layout clicked');
          document.title = 'CREATE_NEW_LAYOUT';
        }

        function closeWindow() {
          console.log('Close button clicked');
          document.title = 'CLOSE_REQUESTED';
        }

        // Initialize table data when page loads
        window.addEventListener('DOMContentLoaded', function() {
          updateTable(]] .. hs.json.encode(tableData) .. [[);
        });

        // Disable context menu completely
        document.addEventListener('contextmenu', function(e) {
          e.preventDefault();
          return false;
        });

        // Disable F5 and Ctrl+R refresh
        document.addEventListener('keydown', function(e) {
          if (e.key === 'F5' || (e.ctrlKey && e.key === 'r')) {
            e.preventDefault();
            return false;
          }
        });

        // Check if table is empty on focus and regenerate if needed
        window.addEventListener('focus', function() {
          const tbody = document.getElementById('tableBody');
          if (!tbody || tbody.children.length === 0) {
            updateTable(]] .. hs.json.encode(tableData) .. [[);
          }
        });
      </script>
    </body>
    </html>
  ]]

  self.mainWindow:html(updatedHtml)
end

-- Show new layout creation UI
function obj:showNewLayoutUI()
  if self.newLayoutWindow then
    self.newLayoutWindow:delete()
  end

  self.newLayoutWindow = hs.webview.new({ x = 150, y = 150, w = 400, h = 250 })
      :windowTitle("Create New Layout")
      :closeOnEscape(true)
      :allowTextEntry(true)
      :allowNewWindows(false)
      :windowStyle(hs.webview.windowMasks.titled | hs.webview.windowMasks.closable |
        hs.webview.windowMasks.miniaturizable | hs.webview.windowMasks.resizable)
      :show()

  -- Set up the HTML for new layout window
  local newLayoutHtml = [[
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 20px; }
          input { width: 100%; padding: 8px; margin: 5px 0; border: 1px solid #ddd; border-radius: 3px; }
          select { width: 100%; padding: 8px; margin: 5px 0; border: 1px solid #ddd; border-radius: 3px; }
          button { padding: 8px 16px; margin: 5px; cursor: pointer; border: none; border-radius: 3px; }
          .create-btn { background-color: #4CAF50; color: white; }
          .cancel-btn { background-color: #f44336; color: white; }
          .snapshot-btn { background-color: #2196F3; color: white; }
          .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
          .close-btn { background-color: #666; color: white; border: none; border-radius: 3px; padding: 8px 16px; float: right; }
          .storage-mode-info { font-size: 12px; color: #666; margin-top: 5px; }
        </style>
      </head>
      <body>
        <div class="header">
          <h3>Create New Layout</h3>
          <button class="close-btn" onclick="cancelNewLayout()">Close</button>
        </div>

        <label>Layout Name:</label>
        <input type="text" id="layoutName" placeholder="Enter layout name">

        <label>Storage Mode:</label>
        <select id="storageMode" onchange="updateStorageModeInfo()">
          <option value="screen-relative">Screen-Relative (Legacy)</option>
          <option value="global-coordinates" selected>Global Coordinates (Recommended)</option>
        </select>
        <div id="storageModeInfo" class="storage-mode-info">
          Stores window positions relative to their screen. May break when screen setup changes.
        </div>

        <label>Shortcut (optional - format: cmd+alt+ctrl):</label>
        <input type="text" id="shortcutMods" placeholder="cmd+alt+ctrl (leave empty for no shortcut)" value="">

        <label>Shortcut Key (optional):</label>
        <input type="text" id="shortcutKey" placeholder="Enter key (e.g., L) or leave empty" maxlength="1">

        <br><br>
        <button class="snapshot-btn" onclick="createLayout()">Take Snapshot & Create</button>

        <script>
          function updateStorageModeInfo() {
            const mode = document.getElementById('storageMode').value;
            const info = document.getElementById('storageModeInfo');

            if (mode === 'global-coordinates') {
              info.textContent = 'Stores absolute screen coordinates. More reliable when moving between different screen setups.';
            } else {
              info.textContent = 'Stores window positions relative to their screen. May break when screen setup changes.';
            }
          }

          function createLayout() {
            console.log('Create layout clicked');
            const name = document.getElementById('layoutName').value;
            const mods = document.getElementById('shortcutMods').value;
            const key = document.getElementById('shortcutKey').value;
            const storageMode = document.getElementById('storageMode').value;

            if (!name) {
              alert('Please enter a layout name');
              return;
            }

            // Include storage mode in the message
            document.title = 'CREATE_LAYOUT:' + name + ':' + (mods || '') + ':' + (key || '') + ':' + storageMode;
          }

          function cancelNewLayout() {
            console.log('Cancel clicked');
            document.title = 'CANCEL_NEW_LAYOUT';
          }

          // Initialize storage mode info
          updateStorageModeInfo();
        </script>
      </body>
      </html>
    ]]

  self.newLayoutWindow:html(newLayoutHtml)

  -- Set up window callback for new layout window
  if not self.newLayoutCheckTimer then
    self.newLayoutCheckTimer = hs.timer.doEvery(0.3, function()
      if self.newLayoutWindow then
        local title = self.newLayoutWindow:title()
        if title then
          local currentTime = hs.timer.secondsSinceEpoch()
          if self.lastAction and currentTime - self.lastAction < 1.0 then
            return
          end

          if title:match("CANCEL_NEW_LAYOUT") then
            self.lastAction = currentTime
            self.newLayoutWindow:delete()
            self.newLayoutWindow = nil
            if self.newLayoutCheckTimer then
              self.newLayoutCheckTimer:stop()
              self.newLayoutCheckTimer = nil
            end
          elseif title:match("CREATE_LAYOUT:(.+)") then
            local params = title:match("CREATE_LAYOUT:(.+)")
            local name, mods, key, storageMode = params:match("([^:]*):([^:]*):([^:]*):([^:]*)")
            if name and name ~= "" then
              self.lastAction = currentTime

              local modList = {}
              -- Only process mods if they exist and are not empty
              if mods and mods ~= "" then
                for mod in mods:gmatch("[^,]+") do
                  table.insert(modList, mod:match("^%s*(.-)%s*$"))
                end
              end

              -- Only pass key if it's not empty
              local finalKey = (key and key ~= "") and key or nil
              local finalMods = (#modList > 0) and modList or nil

              -- Default to screen-relative if storage mode is empty
              local finalStorageMode = (storageMode and storageMode ~= "") and storageMode or
                  self.STORAGE_MODE_SCREEN_RELATIVE

              self:createNewLayout(name, finalMods, finalKey, finalStorageMode)

              self.newLayoutWindow:delete()
              self.newLayoutWindow = nil
              if self.newLayoutCheckTimer then
                self.newLayoutCheckTimer:stop()
                self.newLayoutCheckTimer = nil
              end
            end
          end
        end
      end
    end)
  end
end

-- Create new layout with snapshot
function obj:createNewLayout(name, mods, key, storageMode)
  storageMode = storageMode or self.STORAGE_MODE_SCREEN_RELATIVE
  local layout = self:snapshotCurrentLayout(storageMode)

  local newLayout = {
    name = name,
    layout = layout,
    storageMode = storageMode
  }

  -- Only add shortcut if both mods and key are provided
  if mods and mods ~= "" and key and key ~= "" then
    newLayout.shortcut = {
      mods = mods,
      key = key
    }
  end

  table.insert(self.layoutData, newLayout)
  self:saveLayoutsToFile()
  self:loadLayouts()   -- Reload to update hotkeys and menubar
  self:refreshMainUI() -- Refresh the UI to show the new layout

  local modeText = storageMode == self.STORAGE_MODE_GLOBAL_COORDINATES and " (Global)" or " (Screen-Relative)"
  hs.alert.show("Layout '" .. name .. "'" .. modeText .. " created")
end

-- Setup menubar
function obj:setupMenubar()
  if self.menubar then
    self.menubar:delete()
  end

  -- Create a menu bar item for Layout Manager
  self.menubar = hs.menubar.new()
  if self.menubar then
    self.menubar:setTitle("📐")
    self.menubar:setTooltip("Layout Manager")
    self:updateMenubarMenu()
  end
end

-- Update menubar menu with current layouts
function obj:updateMenubarMenu()
  if not self.menubar then
    return
  end

  local menu = {
    {
      title = "Open Layout Manager",
      fn = function()
        self:showLayoutManagerUI()
      end
    }
  }

  -- Add separator if there are layouts
  if #self.layoutData > 0 then
    table.insert(menu, { title = "-" }) -- Separator

    -- Add each layout as a menu item
    for _, layout in ipairs(self.layoutData) do
      local shortcutText = ""
      if layout.shortcut and layout.shortcut.mods and layout.shortcut.key then
        shortcutText = " (" .. table.concat(layout.shortcut.mods, "+") .. "+" .. layout.shortcut.key .. ")"
      end

      table.insert(menu, {
        title = layout.name .. shortcutText,
        fn = function()
          self:applyLayout(layout)
        end
      })
    end
  end

  self.menubar:setMenu(menu)
end

-- Initialize the spoon
function obj:init()
  -- Start by loading layouts and setting up everything
  self:loadLayouts()
  self:setupMenubar()

  return self
end

return obj
