---agentdiff's hook reporter: an agent CLI runs it on each file edit.
---
---  nvim --headless -u NONE -i NONE -l agentdiff-hook.lua <harness> <state_dir> [pre|post]
---
---Reads the hook payload (JSON) from stdin, asks the harness adapter which
---files the tool call edits, and records them in the store of every reviewed
---project (one whose store exists under <state_dir>) that contains them.
---Neovim doesn't need to be running.
---
---It prints nothing and always exits 0: some CLIs (Copilot CLI) fail a tool
---call whose pre-tool hook fails, and a review tool must never do that.

pcall(function()
  local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
  local plugin = vim.fs.dirname(vim.fs.dirname(script))
  package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

  local argv = _G.arg or {}
  local name, state_dir, hint = argv[1], argv[2], argv[3]
  if type(state_dir) ~= "string" or state_dir == "" then
    return
  end
  local input = io.stdin:read("*a")
  local payload = vim.json.decode(input or "", { luanil = { object = true, array = true } })
  if type(payload) ~= "table" then
    return
  end

  local harness = require("agentdiff.harness")
  local adapter = harness.get(name or "")
  local report = adapter and adapter.parse(payload, hint)
  if not report then
    for _, n in ipairs(harness.names()) do
      report = harness.get(n).parse(payload, hint)
      if report then
        name = n
        break
      end
    end
  end
  if not report then
    return
  end

  -- Each ancestor directory that has a store is a reviewed project root;
  -- stores are named after the hash of the real path of their root.
  local uv = vim.uv
  local by_store, order = {}, {}
  for _, path in ipairs(report.paths) do
    for dir in vim.fs.parents(path) do
      local real = uv.fs_realpath(dir)
      if real then
        local store = state_dir .. "/" .. vim.fn.sha256(real):sub(1, 16)
        local f = io.open(store .. "/root", "rb")
        local root = f and f:read("*l")
        if f then
          f:close()
        end
        if root == real then
          local rel = dir == "/" and path:sub(2) or path:sub(#dir + 2)
          if not by_store[store] then
            by_store[store] = {}
            order[#order + 1] = store
          end
          table.insert(by_store[store], rel)
        end
      end
    end
  end

  local journal = require("agentdiff.core.journal")
  for _, store in ipairs(order) do
    journal.add(store, {
      harness = name,
      phase = report.phase,
      paths = by_store[store],
      session = report.session,
    })
  end
end)
os.exit(0)
