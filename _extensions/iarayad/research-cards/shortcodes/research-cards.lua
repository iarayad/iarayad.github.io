local stringify = pandoc.utils.stringify
local carousel_counter = 0

local function log_warning(msg)
  io.stderr:write("[research-cards] " .. msg .. "\n")
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
  local str = tostring(text or "")
  str = str:gsub('[&<>"\']', map)
  str = str:gsub("'", map["'"])
  return str
end

local function sanitize_text(value)
  if value == nil then
    return nil
  end
  local text = stringify(value)
  if type(text) ~= "string" then
    text = tostring(text or "")
  end
  if text:match('%S') then
    return escape_html(text)
  end
  return nil
end

local function meta_to_list(value)
  local items = {}
  if value == nil then
    return items
  end
  if type(value) == "table" then
    for _, entry in ipairs(value) do
      local text = stringify(entry)
      if type(text) ~= "string" then
        text = tostring(text or "")
      end
      if text:match('%S') then
        table.insert(items, text)
      end
    end
    return items
  end
  local text = stringify(value)
  if type(text) ~= "string" then
    text = tostring(text or "")
  end
  if text:match('%S') then
    table.insert(items, text)
  end
  return items
end

local function markdown_to_html(text)
  if not text or text == '' then
    return ''
  end
  local ok, doc = pcall(pandoc.read, text, 'markdown')
  if not ok then
    log_warning('unable to parse markdown snippet: ' .. text)
    return '<p>' .. escape_html(text) .. '</p>'
  end
  local html = pandoc.write(doc, 'html')
  return html:gsub('%s+$', '')
end

local function read_topics(path)
  local file = open_with_fallbacks(path)
  if not file then
    return {}
  end
  local content = file:read("*a")
  file:close()
  local ok, doc = pcall(pandoc.read, "---\n" .. content .. "\n---", "markdown")
  if not ok then
    log_warning("unable to parse YAML at " .. path)
    return {}
  end
  local meta = doc.meta.topics or doc.meta
  if type(meta) ~= "table" then
    log_warning("no topics found in " .. path)
    return {}
  end
  local topics = {}
  for idx, entry in ipairs(meta) do
    local topic = {}
    topic.title = sanitize_text(entry.title) or string.format("Topic %02d", idx)
    topic.indicator_label = sanitize_text(entry.indicator_label) or topic.title
    topic.highlight = sanitize_text(entry.highlight)
    topic.figure = sanitize_text(entry.figure)
    topic.figure_alt = sanitize_text(entry.figure_alt) or topic.title
    topic.body = {}
    for _, paragraph in ipairs(meta_to_list(entry.body)) do
      local html = markdown_to_html(paragraph)
      if html ~= '' then
        table.insert(topic.body, html)
      end
    end
    topic.buttons = {}
    if type(entry.buttons) == "table" then
      for _, btn in ipairs(entry.buttons) do
        local label = sanitize_text(btn.label)
        local href = sanitize_text(btn.href)
        local classes = sanitize_text(btn.classes)
        if label and href then
          table.insert(topic.buttons, {
            label = label,
            href = href,
            classes = classes or "btn btn-outline-primary"
          })
        end
      end
    end
    topics[#topics + 1] = topic
  end
  return topics
end

local function render(topics, carousel_id)
  local html = {}
  table.insert(html, '<div class="research-carousel-shell">')
  table.insert(html, string.format('  <div id="%s" class="carousel carousel-dark slide" data-bs-interval="false" data-bs-touch="true" aria-label="Research focus carousel">', carousel_id))
  table.insert(html, '  <div class="carousel-inner">')
  local total = #topics
  for idx, topic in ipairs(topics) do
    local item_class = idx == 1 and 'carousel-item active' or 'carousel-item'
    local prev_idx = idx == 1 and total or idx - 1
    local next_idx = idx == total and 1 or idx + 1
    local prev_title = topics[prev_idx].title
    local next_title = topics[next_idx].title
    table.insert(html, string.format('    <div class="%s">', item_class))
    table.insert(html, '      <div class="research-card card shadow-sm border-0">')
    table.insert(html, '        <div class="card-body">')
    table.insert(html, '          <div class="card-nav-hints d-flex justify-content-between align-items-center mb-3">')
    table.insert(html, string.format('            <button class="card-nav-control card-nav-prev" type="button" data-bs-target="#%s" data-bs-slide="prev" aria-label="Previous research topic">', carousel_id))
    table.insert(html, string.format('              <i class="bi bi-arrow-left-short"></i> %s', prev_title))
    table.insert(html, '            </button>')
    table.insert(html, string.format('            <button class="card-nav-control card-nav-next" type="button" data-bs-target="#%s" data-bs-slide="next" aria-label="Next research topic">', carousel_id))
    table.insert(html, string.format('              %s <i class="bi bi-arrow-right-short"></i>', next_title))
    table.insert(html, '            </button>')
    table.insert(html, '          </div>')
    table.insert(html, '          <div class="research-card-payload">')
    if topic.figure then
      table.insert(html, '            <div class="research-card-figure">')
      table.insert(html, string.format('              <img src="%s" alt="%s" loading="lazy" decoding="async" />', topic.figure, topic.figure_alt))
      table.insert(html, '            </div>')
    end
    table.insert(html, '            <div class="research-card-copy">')
    table.insert(html, string.format('              <h3 class="h4">%s</h3>', topic.title))
    for _, paragraph in ipairs(topic.body) do
      table.insert(html, '              ' .. paragraph)
    end
    if topic.highlight then
      table.insert(html, string.format('              <div class="border-top pt-3 mt-4 small text-muted">%s</div>', topic.highlight))
    end
    if #topic.buttons > 0 then
      table.insert(html, '              <div class="d-flex flex-wrap gap-2 mt-4">')
      for _, button in ipairs(topic.buttons) do
        table.insert(html, string.format('                <a class="%s" href="%s">%s</a>', button.classes, button.href, button.label))
      end
      table.insert(html, '              </div>')
    end
    table.insert(html, '            </div>')
    table.insert(html, '          </div>')
    table.insert(html, '        </div>')
    table.insert(html, '      </div>')
    table.insert(html, '    </div>')
  end
  table.insert(html, '  </div>')
  table.insert(html, '</div>')
  return table.concat(html, '\n')
end

local styles_injected = false

local carousel_styles = [[
<style>
.research-carousel-shell {
  position: relative;
  width: 100%;
  padding: 0;
  margin: 0;
}

.research-carousel-shell .carousel,
.research-carousel-shell .carousel-inner,
.research-carousel-shell .carousel-item,
.research-card.card {
  width: 100%;
}

.research-card.card {
  border-radius: 1.25rem;
}

.card-nav-control {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  font-size: 0.92rem;
  letter-spacing: 0.02em;
  border: none;
  background: transparent;
  color: #5e6a76;
  padding: 0.2rem 0.55rem;
  cursor: pointer;
  font-weight: 600;
  transition: color 180ms ease, transform 180ms ease;
}

.card-nav-control:hover {
  color: #338c73;
  transform: translateY(-1px);
}

.card-nav-control:focus-visible {
  outline: 2px solid rgba(51, 140, 115, 0.45);
  outline-offset: 3px;
}

.card-nav-control .bi {
  font-size: 1.35rem;
  line-height: 1;
}

.research-card .card-nav-hints {
  font-size: 0.92rem;
  letter-spacing: 0.01em;
  margin-bottom: 1.15rem;
}

.research-card-payload {
  display: flex;
  gap: 1.75rem;
  align-items: center;
  flex-wrap: nowrap;
}

.research-card-figure {
  flex: 0 0 240px;
  max-width: 320px;
}

.research-card-figure img {
  width: 100%;
  height: auto;
  border-radius: 1rem;
}

.research-card-copy {
  flex: 1 1 320px;
}

@media (max-width: 768px) {
  .card-nav-hints {
    flex-direction: column;
    gap: 0.4rem;
  }
  .research-card-payload {
    flex-direction: column;
    align-items: stretch;
  }
  .research-card-figure {
    flex: 0 0 auto;
    width: 100%;
    max-width: none;
  }
}
</style>
]]

return {
  ["research-cards"] = function(args, kwargs)
    local raw_path = stringify(kwargs["path"] or "")
    local path = (type(raw_path) == "string" and raw_path ~= "") and raw_path or "data/research.yml"
    local topics = read_topics(path)
    if #topics == 0 then
      return pandoc.Null()
    end
    carousel_counter = carousel_counter + 1
    local carousel_id = string.format("research-carousel-%d", carousel_counter)
    local blocks = {}
    if not styles_injected then
      table.insert(blocks, pandoc.RawBlock('html', carousel_styles))
      styles_injected = true
    end
    table.insert(blocks, pandoc.RawBlock('html', render(topics, carousel_id)))
    return blocks
  end
}
