DiG hacked it together.  
We use it at [PlayKigai](https://discord.gg/PlayKigai).
Come say hi!

---

A Neovim plugin for Unreal Engine C++ that gives you build commands, header generation, and clangd LSP integration.  
Tested on Windows 11, Unreal 5.5.

## Usage

This plugin provides commands for both your Unreal project and the engine.

### Project Commands
- `:UEBuildProject` — Build your Unreal project (pick target/config/platform)
- `:UEHeaderProject` — Generate headers only (UHT) for your project
- `:UECompileCommandsProject` — Generate `compile_commands.json` for your project
- `:UEClangdConfigProject` — Write a `.clangd` config file for your project

### Engine Commands
- `:UEBuildEngine` — Build an Unreal Engine target. Can be used to build the engine itself or any of its modules.
- `:UEHeaderEngine` — Generate headers only (UHT) for the engine or any of its modules.
- `:UECompileCommandsEngine` — Generate `compile_commands.json` for the engine
- `:UEClangdConfigEngine` — Write a `.clangd` config file for the engine

> **Important**: Make sure your working directory is set to your project (for Project commands) or engine directory for the commands to work properly.

## Setup

- Install [clangd](https://clangd.llvm.org/)  
  Windows: `winget install LLVM.LLVM`  
- Neovim 0.8+  
- Unreal Engine 5.0+  
- Install [`ripgrep`](https://github.com/BurntSushi/ripgrep) (`rg`) for Telescope helpers.
- Add to your lazy.nvim plugins:
  ```lua
  {
    'PlayKigai/Unreal-Nvim',
    ft = {'cpp', 'c', 'h', 'hpp', 'cs', 'ini', 'uproject', 'uplugin'},
    config = function()
      local keymaps = {
        ["<leader>Ub"] = { cmd = "<cmd>UEBuildProject<CR>", desc = "Unreal Build Project" },
        ["<leader>UB"] = { cmd = "<cmd>UEBuildEngine<CR>", desc = "Unreal Build Engine" },
        ["<leader>Uh"] = { cmd = "<cmd>UEHeaderProject<CR>", desc = "Unreal Header Project" },
        ["<leader>UH"] = { cmd = "<cmd>UEHeaderEngine<CR>", desc = "Unreal Header Engine" },
        ["<leader>Uc"] = { cmd = "<cmd>UECompileCommandsProject<CR>", desc = "Unreal CompCommands Project" },
        ["<leader>UC"] = { cmd = "<cmd>UECompileCommandsEngine<CR>", desc = "Unreal CompCommands Engine" },
        ["<leader>Ux"] = { cmd = "<cmd>UEClangdConfigProject<CR>", desc = "Unreal ClangdConfig Project" },
        ["<leader>UX"] = { cmd = "<cmd>UEClangdConfigEngine<CR>", desc = "Unreal ClangdConfig Engine" },
        ["<leader>Up"] = { cmd = "<cmd>UECwdProject<CR>", desc = "Unreal CWD→Project" },
        ["<leader>Ue"] = { cmd = "<cmd>UECwdEngine<CR>", desc = "Unreal CWD→Engine" },
        ["<leader>Uf"] = { cmd = "<cmd>TelescopeUnrealFind<CR>", desc = "Unreal Find", needs_telescope = true },
        ["<leader>Ug"] = { cmd = "<cmd>TelescopeUnrealGrep<CR>", desc = "Unreal Grep", needs_telescope = true },
      }

      -- Default mappings
      require('unreal-nvim').setup({
        -- engine_path = "C:/Program Files/Epic Games/UE_5.5", -- optional
        auto_register_clangd = true, -- if true, tries to auto-configure clangd for Unreal (needs nvim-lspconfig)
        keymaps = keymaps,
      })
    end,
  }
  ```
  > Note: `auto_register_clangd` tries to auto-configure clangd using nvim-lspconfig if available.  
  > You can always set up clangd manually if you prefer.
  > The plugin maps the `<leader>U*` table automatically using the `keymaps` option you pass, and it skips Telescope-only entries when Telescope is unavailable.

## How it works

- Finds your `.uproject` and UE install automatically
- Creates a `.ueinfo` file in the uproject root to remember your engine path for projects
- Detects build targets from `.Target.cs` files (or falls back to project name)
- Lets you pick build targets/configs
- Runs Unreal Build Tool in a floating window
- Generates `compile_commands.json` for clangd LSP
- Optionally makes a `.clangd` config file to suppress some warnings and help clangd parse Unreal macros
- Optionally auto-registers clangd LSP (if `auto_register_clangd = true` and nvim-lspconfig is installed)

## Engine Path Detection

The plugin tries to find your Unreal Engine in this order:
1. Uses the `engine_path` from your config (if provided)
2. Checks for a cached path from previous use
3. Reads the path from `.ueinfo` file in your project root
   - If the file exists, it will be used to remember the engine path for future use.
   - If the file doesn't exist, it will be created with the engine path.
4. Checks the `UE_ENGINE_PATH` environment variable
5. Searches for `GenerateProjectFiles` in parent directories
6. Prompts you to enter the path manually if all else fails

## Totally unbiased best things about this plugin

- **Automatic project and engine detection** 
- *Tentatively* **Cross-platform** (Windows, Linux, macOS)
- **Auto-detects build targets and platforms**
- **One command to generate LSP config and compile database**
- **Minimal config, should work out of the box for most setups**
- **Do whatever you want with it license.**
