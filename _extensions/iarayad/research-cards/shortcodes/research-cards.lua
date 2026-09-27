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

local function meta_to_text(value)
  if value == nil then
    return nil
  end
  local text = stringify(value)
  if text:match('%S') then
    return text
  end
  return nil
end

-- Body entries are Markdown metadata; keep them as Pandoc blocks so links and spans survive.
local function meta_to_blocks(value)
  local blocks = pandoc.Blocks({})
  if value == nil then
    return blocks
  end
  local entries = pandoc.utils.type(value) == "List" and value or { value }
  for _, entry in ipairs(entries) do
    local vtype = pandoc.utils.type(entry)
    if vtype == "Inlines" then
      blocks:insert(pandoc.Para(entry))
    elseif vtype == "Blocks" then
      blocks:extend(entry)
    end
  end
  return blocks
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
    local title = meta_to_text(entry.title) or string.format("Topic %02d", idx)
    topics[#topics + 1] = {
      title = title,
      figure = meta_to_text(entry.figure),
      figure_alt = meta_to_text(entry.figure_alt) or title,
      body = meta_to_blocks(entry.body),
    }
  end
  return topics
end

-- One tab per topic, built as Quarto's own Tabset node; the figure floats inside the first paragraph.
local function render(topics)
  local tabs = pandoc.List({})
  for _, topic in ipairs(topics) do
    local body = topic.body
    if topic.figure then
      local image = pandoc.Image(topic.figure_alt, topic.figure, "", pandoc.Attr("", { "research-topic-figure" }))
      if body[1] and body[1].t == "Para" then
        body[1].content:insert(1, image)
      else
        body:insert(1, pandoc.Plain({ image }))
      end
    end
    tabs:insert(quarto.Tab({ title = topic.title, content = body }))
  end
  return (quarto.Tabset({
    level = 3,
    tabs = tabs,
    attr = pandoc.Attr("", { "panel-tabset", "research-topics" }),
  }))
end

local styles_injected = false

local topic_styles = [[
<style>
.research-topics .tab-content {
  padding-top: 1.25rem;
}

.research-topics .tab-pane p {
  text-align: justify;
  -webkit-hyphens: auto;
  hyphens: auto;
}

.research-topic-figure {
  float: right;
  width: 170px;
  height: auto;
  margin: 0.25rem 0 0.75rem 1.5rem;
}

.research-topics .tab-pane::after {
  content: "";
  display: block;
  clear: both;
}

/* Lines beside the figure are too short to justify on phones. */
@media (max-width: 575.98px) {
  .research-topics .tab-pane p {
    text-align: left;
  }

  .research-topic-figure {
    width: 110px;
    margin-left: 1rem;
  }
}
</style>
]]

return {
  ["research-cards"] = function(args, kwargs)
    local raw_path = stringify(kwargs["path"] or "")
    local path = raw_path ~= "" and raw_path or "data/research.yml"
    local topics = read_topics(path)
    if #topics == 0 then
      return pandoc.Null()
    end
    local blocks = {}
    if not styles_injected then
      table.insert(blocks, pandoc.RawBlock('html', topic_styles))
      styles_injected = true
    end
    table.insert(blocks, render(topics))
    return blocks
  end
}
