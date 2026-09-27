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
      id = (stringify(entry.id or "")):lower():gsub('[^%w]+', '-'),
      order = tonumber(stringify(entry.order or idx)) or idx,
      label = escape_html(stringify(entry.label or "")),
      place = escape_html(stringify(entry.place or "")),
      period = escape_html(period),
      year = period:match('(%d%d%d%d)') or "",
      summary = to_inline_html(entry.summary),
      bullets = bullets,
    }
    if entries[#entries].id == "" then
      entries[#entries].id = "step-" .. idx
    end
  end
  -- Oldest first: the stepper reads as a route through the places.
  table.sort(entries, function(a, b) return a.order < b.order end)
  return entries
end

-- A row of year nodes controlling one visible panel at a time.
local function render(entries)
  local html = { '<div class="trajectory-stepper" data-stepper>' }
  table.insert(html, '  <div class="stepper-track">')
  table.insert(html, '    <div class="stepper-track-fill" aria-hidden="true"></div>')
  table.insert(html, '    <div class="stepper-nodes" role="tablist" aria-label="Places I have worked and studied">')
  for idx, entry in ipairs(entries) do
    local is_active = idx == 1
    table.insert(html, string.format(
      '      <button id="trajectory-node-%s" class="stepper-node%s" type="button" role="tab" aria-controls="trajectory-%s" aria-selected="%s"%s>',
      entry.id, is_active and ' is-active' or '', entry.id, is_active and 'true' or 'false', is_active and '' or ' tabindex="-1"'))
    table.insert(html, string.format('        <span class="stepper-node-year">%s</span>', entry.year))
    table.insert(html, '        <span class="stepper-node-dot" aria-hidden="true"></span>')
    table.insert(html, '      </button>')
  end
  table.insert(html, '    </div>')
  table.insert(html, '  </div>')
  table.insert(html, '  <div class="stepper-panels">')
  for idx, entry in ipairs(entries) do
    local is_active = idx == 1
    table.insert(html, string.format(
      '    <section id="trajectory-%s" class="stepper-panel%s" role="tabpanel" aria-labelledby="trajectory-node-%s" aria-hidden="%s">',
      entry.id, is_active and ' is-active' or '', entry.id, is_active and 'false' or 'true'))
    local where = {}
    for _, part in ipairs({ entry.place, entry.period }) do
      if part ~= '' then
        table.insert(where, part)
      end
    end
    table.insert(html, string.format('      <p class="stepper-panel-heading"><span class="stepper-panel-title">%s</span><span class="stepper-panel-where">, %s</span></p>',
      entry.label, table.concat(where, ' · ')))
    if entry.summary ~= '' then
      table.insert(html, string.format('      <p>%s</p>', entry.summary))
    end
    if #entry.bullets > 0 then
      table.insert(html, '      <ul class="stepper-panel-list">')
      for _, bullet in ipairs(entry.bullets) do
        table.insert(html, string.format('        <li>%s</li>', bullet))
      end
      table.insert(html, '      </ul>')
    end
    table.insert(html, '    </section>')
  end
  table.insert(html, '  </div>')
  table.insert(html, '</div>')
  return table.concat(html, '\n')
end

local stepper_script = [[
<script type="module">
const initTrajectoryStepper = () => {
  const steppers = document.querySelectorAll('[data-stepper]');
  steppers.forEach((stepper) => {
    const panels = stepper.querySelectorAll('.stepper-panel');
    const trackFill = stepper.querySelector('.stepper-track-fill');
    const nodes = stepper.querySelectorAll('.stepper-node');
    if (!nodes.length) return;

    const setActive = (index) => {
      panels.forEach((panel, idx) => {
        const isActive = idx === index;
        panel.classList.toggle('is-active', isActive);
        panel.setAttribute('aria-hidden', String(!isActive));
      });

      nodes.forEach((node, idx) => {
        const isActive = idx === index;
        node.classList.toggle('is-active', isActive);
        node.classList.toggle('is-complete', idx <= index);
        node.setAttribute('aria-selected', String(isActive));
        node.setAttribute('tabindex', isActive ? '0' : '-1');
      });

      if (trackFill) {
        const progress = nodes.length > 1 ? (index / (nodes.length - 1)) * 100 : 100;
        trackFill.style.setProperty('--step-progress', `${progress}%`);
      }
    };

    nodes.forEach((node, index) => {
      node.addEventListener('click', () => setActive(index));
      node.addEventListener('keydown', (event) => {
        const interactiveKeys = ['ArrowLeft', 'ArrowRight', 'Home', 'End', 'Enter', ' '];
        if (!interactiveKeys.includes(event.key)) return;
        const lastIndex = nodes.length - 1;
        let nextIndex = index;
        if (event.key === 'ArrowLeft') nextIndex = Math.max(0, index - 1);
        if (event.key === 'ArrowRight') nextIndex = Math.min(lastIndex, index + 1);
        if (event.key === 'Home') nextIndex = 0;
        if (event.key === 'End') nextIndex = lastIndex;

        if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) {
          event.preventDefault();
          nodes[nextIndex].focus();
          setActive(nextIndex);
        }

        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          setActive(index);
        }
      });
    });

    setActive(0);
  });
};

if (document.readyState !== 'loading') {
  initTrajectoryStepper();
} else {
  document.addEventListener('DOMContentLoaded', initTrajectoryStepper);
}
</script>
]]

local script_injected = false

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
    local blocks = { pandoc.RawBlock('html', render(entries)) }
    if not script_injected then
      table.insert(blocks, pandoc.RawBlock('html', stepper_script))
      script_injected = true
    end
    return blocks
  end
}
