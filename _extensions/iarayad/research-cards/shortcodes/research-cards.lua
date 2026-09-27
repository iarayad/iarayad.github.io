local stringify = pandoc.utils.stringify

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

local function to_html(value)
  local vtype = pandoc.utils.type(value)
  local blocks
  if vtype == "Inlines" then
    blocks = { pandoc.Para(value) }
  elseif vtype == "Blocks" then
    blocks = value
  else
    return ''
  end
  local html = pandoc.write(pandoc.Pandoc(blocks), 'html')
  return (html:gsub('%s+$', ''))
end

-- Convert Markdown metadata to HTML without stringifying it first, so links and spans survive.
local function meta_to_html_paragraphs(value)
  local paragraphs = {}
  if value == nil then
    return paragraphs
  end
  local entries = pandoc.utils.type(value) == "List" and value or { value }
  for _, entry in ipairs(entries) do
    local html = to_html(entry)
    if html:match('%S') then
      table.insert(paragraphs, html)
    end
  end
  return paragraphs
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
    topic.highlight = sanitize_text(entry.highlight)
    topic.figure = sanitize_text(entry.figure)
    topic.figure_alt = sanitize_text(entry.figure_alt) or topic.title
    topic.body = meta_to_html_paragraphs(entry.body)
    topics[#topics + 1] = topic
  end
  return topics
end

local function render(topics)
  local html = {}
  table.insert(html, '<div class="research-topics">')
  for _, topic in ipairs(topics) do
    table.insert(html, '  <section class="research-topic">')
    table.insert(html, string.format('    <h3>%s</h3>', topic.title))
    table.insert(html, '    <div class="research-topic-copy">')
    if topic.figure then
      table.insert(html, string.format('      <img class="research-topic-figure" src="%s" alt="%s" loading="lazy" decoding="async" />', topic.figure, topic.figure_alt))
    end
    for _, paragraph in ipairs(topic.body) do
      table.insert(html, '      ' .. paragraph)
    end
    if topic.highlight then
      table.insert(html, string.format('      <p class="research-topic-highlight">%s</p>', topic.highlight))
    end
    table.insert(html, '    </div>')
    table.insert(html, '  </section>')
  end
  table.insert(html, '</div>')
  return table.concat(html, '\n')
end

local styles_injected = false

local topic_styles = [[
<style>
/* Topics side by side. */
.research-topics {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 2.5rem;
  margin-top: 1.5rem;
}

.research-topic h3 {
  margin-top: 0;
  margin-bottom: 0.75rem;
  font-size: 1.2rem;
}

.research-topic-copy {
  display: flow-root;
}

.research-topic-copy p {
  font-size: 0.95rem;
  margin-bottom: 0.6rem;
}

/* Small figure wrapped by the text under each heading. */
.research-topic-figure {
  float: right;
  width: 110px;
  height: auto;
  margin: 0.2rem 0 0.5rem 0.9rem;
  border-radius: 0.5rem;
}

.research-topic-highlight {
  color: #6c757d;
  font-size: 0.9rem;
}

/* Stack columns below Bootstrap's lg breakpoint rather than leaving an orphan column. */
@media (max-width: 991.98px) {
  .research-topics {
    grid-template-columns: minmax(0, 1fr);
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
    local blocks = {}
    if not styles_injected then
      table.insert(blocks, pandoc.RawBlock('html', topic_styles))
      styles_injected = true
    end
    table.insert(blocks, pandoc.RawBlock('html', render(topics)))
    return blocks
  end
}
