# LayoutManager.spoon

A comprehensive window layout manager for Hammerspoon with GUI interface and menubar quick access.

![Layout Manager Interface](LayoutManager.png)

## Features

- 🖥️ **GUI Interface**: Clean, table-based interface for layout management
- 📐 **Menubar Integration**: Quick access to apply layouts without opening GUI
- ⌨️ **Keyboard Shortcuts**: Assign custom shortcuts to layouts
- 📸 **Window Snapshotting**: Capture current window positions and sizes
- 🖥️ **Multi-screen Support**: Works seamlessly with multiple monitors
- 💾 **Persistent Storage**: Layouts automatically saved and restored

## Installation

### Method 1: Manual Installation
1. Download `LayoutManager.spoon.zip` from the releases page
2. Unzip the file
3. Double-click `LayoutManager.spoon` to install it to Hammerspoon

### Method 2: Git Clone
```bash
cd ~/.hammerspoon/Spoons/
git clone https://github.com/christophe-calmejane/LayoutManager.spoon.git
```

### Configuration
Add to your `~/.hammerspoon/init.lua`:
```lua
local layoutManager = hs.loadSpoon("LayoutManager")
layoutManager:init()
```

Then reload your Hammerspoon configuration.

## Usage

### Opening the Interface
- **Menubar**: Click the 📐 icon in your menubar

### Creating Layouts
1. Arrange your windows as desired
2. Open Layout Manager
3. Click "Create New Layout"
4. Enter a name and optionally assign a keyboard shortcut
5. Click "Take Snapshot & Create"

### Applying Layouts
- **From GUI**: Click the "Apply" button next to any layout
- **From Menubar**: Click the 📐 icon and select a layout
- **Keyboard Shortcut**: Use the assigned shortcut (if configured)

### Managing Layouts
- **Update**: Click "Update" to save current window positions to existing layout
- **Remove**: Click "Remove" to delete a layout (with confirmation)

## API Reference

### Core Methods

#### `LayoutManager:init()`
Initializes the spoon and sets up the menubar.

#### `LayoutManager:showLayoutManagerUI()`
Opens the main GUI interface.

#### `LayoutManager:createNewLayout(name, mods, key)`
Creates a new layout programmatically.
- `name` (string): Layout name
- `mods` (table, optional): Modifier keys, e.g., `{"cmd", "alt", "ctrl"}`
- `key` (string, optional): Key for shortcut, e.g., `"w"`

#### `LayoutManager:applyLayout(layoutDef)`
Applies a layout to restore window positions.
- `layoutDef` (table): Layout definition object

## Technical Details

### Data Storage
Layouts are stored in `~/.hammerspoon/Spoons/LayoutManager.spoon/layouts.lua` as a Lua table with the following structure:

```lua
{
  {
    name = "Work Setup",
    shortcut = {
      mods = {"cmd", "alt", "ctrl"},
      key = "w"
    },
    layout = {
      {
        app = "Visual Studio Code",
        title = "window title",
        relX = 0.0,      -- Relative X position (0-1)
        relY = 0.0,      -- Relative Y position (0-1)
        relW = 0.5,      -- Relative width (0-1)
        relH = 1.0,      -- Relative height (0-1)
        screen = 123456  -- Screen ID
      },
      -- ... more windows
    }
  },
  -- ... more layouts
}
```

### Window Matching
Windows are matched by:
1. **Application name** and **window title** (exact match)
2. **Application's main window** (fallback if title doesn't match)

### Multi-screen Support
- Positions are stored as relative coordinates (0-1) within each screen
- Screen IDs are preserved to restore windows to correct monitors
- Layouts adapt to different screen resolutions

## Troubleshooting

### Layouts Not Applying Correctly
- Ensure target applications are running
- Check that window titles haven't changed
- Verify screen configurations match when layout was created

### Keyboard Shortcuts Not Working
- Make sure shortcuts don't conflict with other applications
- Check that Hammerspoon has accessibility permissions
- Verify the shortcut syntax in the layout file

## License

MIT License - see LICENSE file for details.
