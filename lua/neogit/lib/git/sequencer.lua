local git = require("neogit.lib.git")
local M = {}

-- .git/sequencer/todo does not exist when there is only one commit left.
--
-- And CHERRY_PICK_HEAD does not exist when a conflict happens while picking a series of commits with --no-commit.
-- And REVERT_HEAD does not exist when a conflict happens while reverting a series of commits with --no-commit.

---@class SequencerItem
---@field action string
---@field oid string
---@field abbreviated_commit string
---@field subject string|nil

---@param state NeogitRepo
function M.update_sequencer_status(state)
  state.sequencer = { items = {}, revert = false, cherry_pick = false }

  -- .git/sequencer/todo and/or CHERRY_PICK_HEAD can exist while rebasing
  if
    git.repo:git_path("rebase-merge"):exists()
    or git.repo:git_path("rebase-apply"):exists()
  then
    return
  end

  local todo = git.repo:git_path("sequencer/todo")
  if todo:exists() then
    -- if .git/sequencer/todo exists, use it
    local items = {}
    for line in todo:iter() do
      local action, oid = line:match("^(%w+) (%x+)")
      if action then
        table.insert(items, {
          action = action,
          oid = oid,
          abbreviated_commit = oid:sub(1, git.log.abbreviated_size()),
          subject = line:match("^%w+ %x+ (.+)$"),
        })
      end
    end

    -- use first item to detect cherry-pick/revert
    local first_item = state.sequencer.items[1]
    if first_item then
      if first_item.action == "pick" then
        state.sequencer.cherry_pick = true
        state.sequencer.items = items
      elseif first_item.action == "revert" then
        state.sequencer.revert = true
        state.sequencer.items = items
      end
    end
  else
    -- else fallback to CHERRY_PICK_HEAD and REVERT_HEAD

    local cherry_head = git.repo:git_path("CHERRY_PICK_HEAD")
    local revert_head = git.repo:git_path("REVERT_HEAD")

    if cherry_head:exists() then
      state.sequencer.cherry_pick = true
      local pick_oid = vim.trim(cherry_head:read())
      table.insert(state.sequencer.items, {
        action = "pick",
        oid = pick_oid,
        abbreviated_commit = pick_oid:sub(1, git.log.abbreviated_size()),
        subject = git.log.message(pick_oid),
      })
    elseif revert_head:exists() then
      state.sequencer.revert = true
      local revert_oid = vim.trim(revert_head:read())
      table.insert(state.sequencer.items, {
        action = "revert",
        oid = revert_oid,
        abbreviated_commit = revert_oid:sub(1, git.log.abbreviated_size()),
        subject = git.log.message(revert_oid),
      })
    end
  end

  if #state.sequencer.items > 0 then
    local HEAD_oid = git.rev_parse.oid("HEAD")
    -- If HEAD is an empty branch, then rev-parse returns HEAD
    -- This causes git log to error, so skip the onto item
    if HEAD_oid ~= "HEAD" then
      table.insert(state.sequencer.items, {
        action = "onto",
        oid = HEAD_oid,
        abbreviated_commit = HEAD_oid:sub(1, git.log.abbreviated_size()),
        subject = git.log.message(HEAD_oid),
      })
    end
  end
end

M.register = function(meta)
  meta.update_sequencer_status = M.update_sequencer_status
end

return M
