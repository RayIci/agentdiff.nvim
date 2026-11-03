---Resolving a conflicted file: accept the agent's changes, take its version,
---keep yours, or compare.
---@class AgentdiffActionsResolve
local M = {}

local baseline = require("agentdiff.core.baseline")
local buffers = require("agentdiff.editor.buffers")
local claims = require("agentdiff.core.claims")
local common = require("agentdiff.actions.common")
local merge = require("agentdiff.core.merge")
local session = require("agentdiff.core.session")
local state = require("agentdiff.core.state")
local txt = require("agentdiff.core.text")
local util = require("agentdiff.core.util")

---Resolve a conflicted file.
---@param choice? "accept"|"agent"|"mine"|"compare"|string
---@param path? string
function M.resolve(choice, path)
  local s = common.active()
  if not s then
    return
  end
  local rel = path or session.rel_of_buf(s, vim.api.nvim_get_current_buf())
  if not rel or not s.conflicts[rel] then
    return util.notify("agentdiff: no conflict here")
  end
  local function apply(c)
    local buf = session.buf_of_rel(s, rel)
    if c == "accept" then
      -- Keep the agent's changes: its content wins where it overlaps your
      -- unsaved edits; your other unsaved edits stay (unsaved) on top.
      s.conflicts[rel] = nil
      baseline.process(s, { rel }, "agent")
      local D = util.read_file(session.abs(s, rel))
      if buf and vim.api.nvim_buf_is_loaded(buf) then
        local synced = s.synced[buf]
        if synced == nil then
          synced = s.store:read("baseline", { rel })[rel]
        end
        local merged = merge.merge3(txt.disp(buf, synced or nil), txt.disp(buf, D), txt.buf_lines(buf))
        buffers.resync(buf, merged)
        s.synced[buf] = D or false
      end
      baseline.set_baseline(s, rel, D)
    elseif c == "agent" then
      s.conflicts[rel] = nil
      if buf then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent edit!")
        end)
      end
    elseif c == "mine" then
      s.conflicts[rel] = nil
      local B = s.store:read("baseline", { rel })[rel] or nil
      claims.add(s.store, { rel })
      if B == nil then
        os.remove(session.abs(s, rel))
      else
        util.write_file(session.abs(s, rel), B)
      end
      baseline.process(s, { rel }, "user")
      if buf and vim.api.nvim_buf_is_loaded(buf) then
        -- keep the unsaved edits, but on top of the file now on disk
        buffers.resync(buf, txt.buf_lines(buf))
      end
    elseif c == "compare" then
      require("agentdiff.sidebyside").compare_disk(s, rel)
      return
    end
    state.refresh(s, { rel })
  end
  if choice then
    return apply(choice)
  end
  vim.ui.select({ "accept", "agent", "mine", "compare" }, {
    prompt = "agentdiff: " .. rel .. " conflicts with your unsaved edits",
    format_item = function(c)
      return ({
        accept = "Keep the agent's changes, with your other unsaved edits on top",
        agent = "Take the agent's version (your unsaved edits can be restored with u)",
        mine = "Keep mine (undo the agent's changes to this file)",
        compare = "Compare side by side",
      })[c]
    end,
  }, function(c)
    if c then
      apply(c)
    end
  end)
end

return M
