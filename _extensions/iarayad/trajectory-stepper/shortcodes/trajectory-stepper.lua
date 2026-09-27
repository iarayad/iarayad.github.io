local stringify = pandoc.utils.stringify

local function log_warning(msg)
  io.stderr:write("[trajectory-stepper] " .. msg .. "\n")
end

local function is_absolute(path)
  return path:match('^%/') or path:match('^%a:[/\\]')
end

local function open_with_fallbacks(path)
  local candidates = { path }
  if not is_absolute(path) and not path:match('^contents/') then
    table.insert(candidates, "contents/" .. path)
  end
  for _, candidate in ipairs(candidates) do
    local file = io.open(candidate, "r")
    if file then
      return file, candidate
    end
  end
  log_warning("unable to open any of: " .. table.concat(candidates, ", "))
  return nil
end

local function escape_html(text)
  local map = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;', ["'"] = '&#39;' }
  return (tostring(text or ""):gsub('[&<>"\']', map))
end

-- Render Markdown metadata as inline HTML without stringifying it first, so links and emphasis survive.
local function to_inline_html(value)
  if value == nil then
    return ''
  end
  local vtype = pandoc.utils.type(value)
  local blocks
  if vtype == "Inlines" then
    blocks = { pandoc.Plain(value) }
  elseif vtype == "Blocks" then
    blocks = value
  else
    return escape_html(stringify(value))
  end
  local html = pandoc.write(pandoc.Pandoc(blocks), 'html')
  return (html:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function read_entries(path)
  local file, resolved_path = open_with_fallbacks(path)
  if not file then
    return {}
  end
  local content = file:read("*a")
  file:close()
  local doc = pandoc.read("---\n" .. content .. "\n---", "markdown")
  local meta = doc.meta.trajectory or doc.meta
  if type(meta) ~= "table" then
    log_warning("no entries found in " .. (resolved_path or path))
    return {}
  end
  local entries = {}
  for idx, entry in ipairs(meta) do
    local period = stringify(entry.period or "")
    local bullets = {}
    for _, bullet in ipairs(entry.bullets or {}) do
      table.insert(bullets, to_inline_html(bullet))
    end
    entries[#entries + 1] = {
      order = tonumber(stringify(entry.order or idx)) or idx,
      label = escape_html(stringify(entry.label or "")),
      place = escape_html(stringify(entry.place or "")),
      period = escape_html(period),
      year = period:match('(%d%d%d%d)') or "",
      summary = to_inline_html(entry.summary),
      bullets = bullets,
    }
  end
  -- Newest first, like the publication and talk lists.
  table.sort(entries, function(a, b) return a.order > b.order end)
  return entries
end

local function render(entries)
  local html = { '<ol class="entry-list">' }
  local previous_year = nil
  for _, entry in ipairs(entries) do
    local new_year = entry.year ~= previous_year
    previous_year = entry.year
    table.insert(html, string.format('  <li class="entry%s">', new_year and ' entry-new-year' or ''))
    table.insert(html, string.format('    <span class="entry-year">%s</span>', new_year and entry.year or ''))
    table.insert(html, '    <div class="entry-body">')
    local where = { entry.place, entry.period }
    local suffix = {}
    for _, part in ipairs(where) do
      if part ~= '' then
        table.insert(suffix, part)
      end
    end
    table.insert(html, string.format('      <span class="entry-title">%s</span><span class="entry-role">, %s</span>',
      entry.label, table.concat(suffix, ' · ')))
    if entry.summary ~= '' then
      table.insert(html, string.format('      <div class="entry-description">%s</div>', entry.summary))
    end
    if #entry.bullets > 0 then
      table.insert(html, '      <ul class="entry-details">')
      for _, bullet in ipairs(entry.bullets) do
        table.insert(html, string.format('        <li>%s</li>', bullet))
      end
      table.insert(html, '      </ul>')
    end
    table.insert(html, '    </div>')
    table.insert(html, '  </li>')
  end
  table.insert(html, '</ol>')
  return table.concat(html, '\n')
end

return {
  ["trajectory-stepper"] = function(args, kwargs)
    local path = stringify(kwargs["path"] or "")
    if path == "" then
      path = "data/trajectory.yml"
    end
    local entries = read_entries(path)
    if #entries == 0 then
      return pandoc.Null()
    end
    return pandoc.RawBlock('html', render(entries))
  end
}
