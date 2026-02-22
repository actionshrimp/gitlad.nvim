---@mod gitlad.ui.views.diff.inline Word-level inline diff highlighting
---@brief [[
--- Character-level highlighting for changed lines. When two lines are paired
--- as "change" type, highlights the specific words/characters that differ
--- using a word-boundary tokenizer and LCS algorithm.
---@brief ]]

local M = {}

---@class InlineDiffRange
---@field col_start number 0-indexed start column
---@field col_end number 0-indexed end column

---@class InlineDiffResult
---@field old_ranges InlineDiffRange[] Ranges on the old (left) line to highlight as deleted
---@field new_ranges InlineDiffRange[] Ranges on the new (right) line to highlight as added

--- Tokenize a line into word-boundary tokens.
--- A "word" is a sequence of alphanumeric/underscore chars, a sequence of
--- non-space non-word chars, or whitespace.
---@param line string The line to tokenize
---@return string[] tokens Array of token strings
function M._tokenize(line)
  if line == "" then
    return {}
  end

  local tokens = {}
  local i = 1
  local len = #line

  while i <= len do
    local ch = line:sub(i, i)

    if ch:match("[%w_]") then
      -- Word token: sequence of alphanumeric/underscore
      local j = i + 1
      while j <= len and line:sub(j, j):match("[%w_]") do
        j = j + 1
      end
      table.insert(tokens, line:sub(i, j - 1))
      i = j
    elseif ch:match("%s") then
      -- Whitespace token: sequence of whitespace
      local j = i + 1
      while j <= len and line:sub(j, j):match("%s") do
        j = j + 1
      end
      table.insert(tokens, line:sub(i, j - 1))
      i = j
    else
      -- Punctuation/symbol token: sequence of non-space non-word chars
      local j = i + 1
      while j <= len and not line:sub(j, j):match("[%w_%s]") do
        j = j + 1
      end
      table.insert(tokens, line:sub(i, j - 1))
      i = j
    end
  end

  return tokens
end

--- Compute the Longest Common Subsequence of two token arrays.
--- Returns a set of matched (old_index, new_index) pairs.
---@param old_tokens string[] Tokens from the old line
---@param new_tokens string[] Tokens from the new line
---@return table<number, number> lcs_old_indices Map from old token index to new token index for LCS matches
function M._lcs_tokens(old_tokens, new_tokens)
  local old_len = #old_tokens
  local new_len = #new_tokens

  if old_len == 0 or new_len == 0 then
    return {}
  end

  -- Build DP table
  -- dp[i][j] = length of LCS of old_tokens[1..i] and new_tokens[1..j]
  local dp = {}
  for i = 0, old_len do
    dp[i] = {}
    for j = 0, new_len do
      dp[i][j] = 0
    end
  end

  for i = 1, old_len do
    for j = 1, new_len do
      if old_tokens[i] == new_tokens[j] then
        dp[i][j] = dp[i - 1][j - 1] + 1
      else
        dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1])
      end
    end
  end

  -- Backtrack to find the LCS pairs
  local result = {}
  local i, j = old_len, new_len
  while i > 0 and j > 0 do
    if old_tokens[i] == new_tokens[j] then
      result[i] = j
      i = i - 1
      j = j - 1
    elseif dp[i - 1][j] >= dp[i][j - 1] then
      i = i - 1
    else
      j = j - 1
    end
  end

  return result
end

--- Merge adjacent ranges into single ranges.
---@param ranges InlineDiffRange[] Ranges to merge
---@return InlineDiffRange[] merged Merged ranges
local function merge_ranges(ranges)
  if #ranges == 0 then
    return {}
  end

  local merged = { ranges[1] }
  for i = 2, #ranges do
    local prev = merged[#merged]
    local curr = ranges[i]
    if curr.col_start <= prev.col_end then
      -- Adjacent or overlapping: merge
      prev.col_end = math.max(prev.col_end, curr.col_end)
    else
      table.insert(merged, curr)
    end
  end

  return merged
end

--- Compute inline diff ranges between two lines.
--- Uses word-boundary tokenization and LCS to find the specific
--- characters that differ between the old and new line.
---@param old_line string The old (left) line
---@param new_line string The new (right) line
---@return InlineDiffResult result Ranges to highlight on each side
function M.compute_inline_diff(old_line, new_line)
  -- Handle edge cases
  if old_line == new_line then
    return { old_ranges = {}, new_ranges = {} }
  end

  if old_line == "" and new_line == "" then
    return { old_ranges = {}, new_ranges = {} }
  end

  if old_line == "" then
    return {
      old_ranges = {},
      new_ranges = { { col_start = 0, col_end = #new_line } },
    }
  end

  if new_line == "" then
    return {
      old_ranges = { { col_start = 0, col_end = #old_line } },
      new_ranges = {},
    }
  end

  local old_tokens = M._tokenize(old_line)
  local new_tokens = M._tokenize(new_line)

  local lcs = M._lcs_tokens(old_tokens, new_tokens)

  -- Build set of new_tokens indices that are in the LCS
  local new_in_lcs = {}
  for _, new_idx in pairs(lcs) do
    new_in_lcs[new_idx] = true
  end

  -- Compute old ranges: tokens NOT in LCS on the old side
  local old_ranges = {}
  local old_col = 0
  for i, token in ipairs(old_tokens) do
    local token_len = #token
    if not lcs[i] then
      table.insert(old_ranges, { col_start = old_col, col_end = old_col + token_len })
    end
    old_col = old_col + token_len
  end

  -- Compute new ranges: tokens NOT in LCS on the new side
  local new_ranges = {}
  local new_col = 0
  for i, token in ipairs(new_tokens) do
    local token_len = #token
    if not new_in_lcs[i] then
      table.insert(new_ranges, { col_start = new_col, col_end = new_col + token_len })
    end
    new_col = new_col + token_len
  end

  -- Merge adjacent ranges
  old_ranges = merge_ranges(old_ranges)
  new_ranges = merge_ranges(new_ranges)

  return { old_ranges = old_ranges, new_ranges = new_ranges }
end

return M
