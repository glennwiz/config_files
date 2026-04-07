-- lua/config/floating.lua
local M = {}

-- Shared state
local state = {
  floating = {
    buf = nil,
    win = nil,
  },
}

-- Create a centered floating window (optionally reusing a buffer)
function M.create_floating_window(opts)
  opts = opts or {}
  local ui = vim.api.nvim_list_uis()[1]
  local width = opts.width or math.floor(ui.width * 0.8)
  local height = opts.height or math.floor(ui.height * 0.8)
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Create or reuse buffer
  local buf = nil
  if vim.api.nvim_buf_is_valid(opts.buf or -1) then
    buf = opts.buf
  else
    buf = vim.api.nvim_create_buf(false, true)
  end

  -- Create the floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "single",
  })

  return { buf = buf, win = win }
end

-- Run Odin command and stream output to buffer
function M.run_odin_command(buf, command)
  local cmd_table = { "odin", command, "." }
  local display_cmd = "odin " .. command .. " ."

  -- Clear the buffer first
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Running: " .. display_cmd })

  vim.fn.jobstart(cmd_table, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "=== Build completed successfully ===" })
      else
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "=== Build failed with exit code: " .. code .. " ===" })
      end
    end,
  })
end

-- Matrix animation state
local matrix_state = {
  timer = nil,
  buf = nil,
  win = nil,
  columns = {},
  chars = {},
}

-- Initialize matrix characters (UTF-8 friendly: runes + a few fillers)
local function init_matrix_chars()
  -- start minimal: mostly ᛟ, with a few cousins for variety
  local chars = {}
  local runes = {
    "ᛟ",
    "ᛟ",
    "ᛟ",
    "ᛟ",
    "ᛰ",
    "ᚡ",
    "ᚠ",
    "ᚢ",
    "ᚦ",
    "ᚨ",
    "ᚱ",
    "ᚺ",
    "ᛞ",
    "ᛉ",
    "ᛗ",
    "ᚸ",
    "ᛘ",
  }
  -- bias toward ᛟ heavily
  for i = 1, 40 do
    table.insert(chars, "ᛟ")
  end
  for _, r in ipairs(runes) do
    table.insert(chars, r)
    table.insert(chars, r)
  end
  -- optional: a couple of spaces to create soft gaps in trails
  for i = 1, 10 do
    table.insert(chars, " ")
  end
  return chars
end

-- Update matrix animation (UTF-8 safe)
local function update_matrix(buf, width, height)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  -- Initialize columns if needed
  if #matrix_state.columns == 0 then
    for i = 1, width do
      local active = math.random() < 0.3
      matrix_state.columns[i] = {
        head_row = active and math.random(-30, -5) or -999,
        speed = math.random(2, 5),
        counter = 0,
        trail_length = math.random(10, 18),
        chars = {},
        next_spawn = math.random(50, 200),
      }
      for j = 1, 30 do
        matrix_state.columns[i].chars[j] = matrix_state.chars[math.random(#matrix_state.chars)]
      end
    end
  end

  -- Prepare a char grid (tables of single UTF-8 chars)
  local grid = {}
  for r = 1, height do
    grid[r] = {}
    for c = 1, width do
      grid[r][c] = " "
    end
  end

  -- Update columns and write chars into grid
  for col = 1, width do
    local column = matrix_state.columns[col]
    column.counter = column.counter + 1

    if column.head_row < -100 then
      column.next_spawn = column.next_spawn - 1
      if column.next_spawn <= 0 then
        column.head_row = math.random(-30, -10)
        column.next_spawn = math.random(100, 300)
      end
    else
      if column.counter >= column.speed then
        column.counter = 0
        column.head_row = column.head_row + 1
        if column.head_row > height + column.trail_length then
          if math.random() < 0.4 then
            column.head_row = -999
            column.next_spawn = math.random(150, 400)
          else
            column.head_row = math.random(-30, -10)
          end
          if math.random() < 0.3 then
            for j = 1, 3 do                            ᛟ                                 ᛟ     
              column.chars[math.random(#column.chars)] = matrix_state.chars[math.random(#matrix_state.chars)]
            end
          end
        end
      end
    end

    -- draw trail into grid (active only)
    if column.head_row > -100 then
      for i = 0, column.trail_length - 1 do
        local char_row = column.head_row - i
        if char_row >= 1 and char_row <= height then
          local intensity = math.max(0, 1 - (i / column.trail_length))
          local char_index = ((char_row - 1) % #column.chars) + 1
          local ch = column.chars[char_index]
          grid[char_row][col] = ch
          -- store intensity per cell for highlighting later
          matrix_state.columns[col]["intensity_" .. char_row] = intensity
        end
      end
    end
  end

  -- Build lines with table.concat (UTF-8 safe) and compute byte offsets
  local lines, line_offsets = {}, {} -- line_offsets[row][col] = byte start of that cell
  for r = 1, height do
    local row_cells = grid[r]
    local offsets = {}
    local byte_pos = 0
    offsets[1] = 0 -- first cell starts at byte 0
    for c = 1, width do
      -- UTF-8 byte length of this cell
      local cell = row_cells[c]
      local blen = #cell
      if c < width then
        offsets[c + 1] = byte_pos + blen
      end
      byte_pos = byte_pos + blen
    end
    lines[r] = table.concat(row_cells                            ᛟ     )
    -- keep a sentinel offset for end-of-line to make end_col easy
    offsets[width + 1] = #lines[r]
    line_offsets[r] = offsets
  end

  -- Update buffer
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)

  -- Clear previous highlights
  pcall(vim.api.nvim_buf_clear_namespace, buf, -1, 0, -1)

  -- Add highlights using precise byte ranges
  for col = 1, width do
    local column = matrix_state.columns[col]
    for row = 1, height do
      local intensity = column["intensity_" .. row]
      if intensity and intensity > 0 then
        local hl_group = (intensity < 0.3) and "MatrixGreenDim"
          or (intensity < 0.6) and "MatrixGreenMed"
          or "MatrixGreen"
        -- convert "cell column" -> byte start/end using precomputed offsets
        local start_byte = line_offsets[row][col]
        local end_byte = line_offsets[row][col + 1]
        if start_byte and end_byte and end_byte > start_byte then
          pcall(vim.api.nvim_buf_add_highlight, buf, -1, hl_group, row - 1, start_byte, end_byte)
        end
      end
    end
  end

  return true
end

-- Stop matrix animation
local function stop_matrix()
  if matrix_state.timer then
    matrix_state.timer:stop()
    matrix_state.timer:close()
    matrix_state.timer = nil
  end
  -- Clear all column data
  matrix_state.columns = {}
  if matrix_state.buf and vim.api.nvim_buf_is_valid(matrix_state.buf) then
    pcall(vim.api.nvim_buf_clear_namespace, matrix_state.buf, -1, 0, -1)
  end
end

-- Command to toggle terminal in floating window
vim.api.nvim_create_user_command("Tf", function()
  if not vim.api.nvim_win_is_valid(state.floating.win or -1) then
    state.floating = M.create_floating_window({ buf = state.floating.buf })
    -- Only spawn terminal if the buffer isn't already a terminal
    if vim.bo[state.floating.buf].buftype ~= "terminal" then
      vim.cmd("term") -- Spawns the shell
    end
  else
    vim.api.nvim_win_hide(state.floating.win)
  end
end, {})

-- Command to run 'odin run .' in floating window
vim.api.nvim_create_user_command("Tr", function()
  -- Always create a fresh window/buffer for Odin commands
  local result = M.create_floating_window({})
  state.floating = result

  local buf = result.buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true

  -- Add Esc keymap to close the floating window
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_hide(state.floating.win)
  end, { buffer = buf, nowait = true })

  M.run_odin_command(buf, "run")
end, {})

-- Command to run 'odin build .' in floating window
vim.api.nvim_create_user_command("Tb", function()
  -- Always create a fresh window/buffer for Odin commands
  local result = M.create_floating_window({})
  state.floating = result

  local buf = result.buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true

  -- Add Esc keymap to close the floating window
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_hide(state.floating.win)
  end, { buffer = buf, nowait = true })

  M.run_odin_command(buf, "build")
end, {})

-- Command to show Matrix animation in floating window
vim.api.nvim_create_user_command("Ma", function()
  -- Stop any existing animation
  stop_matrix()

  -- Create floating window
  local result = M.create_floating_window({})
  state.floating = result
  matrix_state.buf = result.buf
  matrix_state.win = result.win

  local buf = result.buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true

  -- Set up Matrix green highlighting with different intensities
  vim.api.nvim_set_hl(0, "MatrixGreen", { fg = "#00FF00", bold = true })
  vim.api.nvim_set_hl(0, "MatrixGreenMed", { fg = "#00CC00" })
  vim.api.nvim_set_hl(0, "MatrixGreenDim", { fg = "#008800" })

  -- Initialize matrix characters
  matrix_state.chars = init_matrix_chars()

  -- Get window dimensions
  local width = vim.api.nvim_win_get_width(result.win)
  local height = vim.api.nvim_win_get_height(result.win)

  -- Add Esc keymap to close the floating window and stop animation
  vim.keymap.set("n", "<Esc>", function()
    stop_matrix()
    vim.api.nvim_win_hide(state.floating.win)
  end, { buffer = buf, nowait = true })

  -- Start the animation timer (slower for cleaner effect)
  matrix_state.timer = vim.loop.new_timer()
  matrix_state.timer:start(
    120,
    120,
    vim.schedule_wrap(function()
      if not update_matrix(buf, width, height) then
        stop_matrix()
      end
    end)
  )
end, {})

-- Make the module globally available if needed
_G.floating = M

return M
