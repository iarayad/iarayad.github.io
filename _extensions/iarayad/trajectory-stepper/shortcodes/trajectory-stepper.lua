local stringify = pandoc.utils.stringify

local function is_absolute(path)
  return path:match('^%/') or path:match('^%a:[/\\]')
end

local function log_warning(msg)
  io.stderr:write("[trajectory-stepper] " .. msg .. "\n")
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
  str = str:gsub('[&<>"]', map)
  str = str:gsub("'", map["'"])
  return str
end

local function slugify(text, fallback)
  local slug = text:lower():gsub('[^%w]+', '-'):gsub('^-+', ''):gsub('-+$', '')
  if slug == '' then
    slug = fallback
  end
  return slug
end

local function meta_to_strings(value)
  local items = {}
  if type(value) == "table" then
    for _, entry in ipairs(value) do
      table.insert(items, escape_html(stringify(entry)))
    end
  end
  return items
end

local function extract_start_year(text)
  local raw = tostring(text or "")
  local year = raw:match('(%d%d%d%d)')
  return year or ""
end

local function to_entry(entry, index)
  local raw_id = escape_html(stringify(entry.id or ""))
  local clean_id = slugify(raw_id ~= '' and raw_id or ('step-' .. index), 'step-' .. index)
  local period_text = stringify(entry.period or "")
  return {
    id = clean_id,
    order = tonumber(stringify(entry.order or index)) or index,
    label = escape_html(stringify(entry.label or "")),
    place = escape_html(stringify(entry.place or "")),
    period = escape_html(period_text),
    start_year = extract_start_year(period_text),
    heading = escape_html(stringify(entry.heading or "")),
    summary = escape_html(stringify(entry.summary or "")),
    bullets = meta_to_strings(entry.bullets)
  }
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
  local entries = {}
  if type(meta) ~= "table" then
    log_warning("no entries found in " .. (resolved_path or path))
    return entries
  end
  for idx, entry in ipairs(meta) do
    entries[#entries + 1] = to_entry(entry, idx)
  end
  table.sort(entries, function(a, b)
    if a.order == b.order then
      return a.label < b.label
    end
    return a.order < b.order
  end)
  return entries
end

local function render(entries)
  local html = {}
  table.insert(html, '<div class="trajectory-stepper" data-stepper>')
  table.insert(html, '  <div class="stepper-track" aria-hidden="true">')
  table.insert(html, '    <div class="stepper-track-fill"></div>')
  table.insert(html, '    <div class="stepper-nodes">')
  for idx, entry in ipairs(entries) do
    local year = entry.start_year ~= '' and entry.start_year or '&nbsp;'
    table.insert(html, string.format('      <span class="stepper-node" data-step-index="%d">', idx - 1))
    table.insert(html, string.format('        <span class="stepper-node-year">%s</span>', year))
    table.insert(html, '        <span class="stepper-node-dot"></span>')
    table.insert(html, '      </span>')
  end
  table.insert(html, '    </div>')
  table.insert(html, '  </div>')
  table.insert(html, '  <div class="stepper-buttons" role="tablist" aria-label="Academic and professional journey">')
  for idx, entry in ipairs(entries) do
    local seq = string.format("%02d", idx)
    local tab_id = 'trajectory-tab-' .. entry.id
    local panel_id = 'trajectory-' .. entry.id
    local is_active = idx == 1
    local btn_classes = 'stepper-btn' .. (is_active and ' is-active' or '')
    local aria_selected = is_active and 'true' or 'false'
    local tabindex = is_active and '' or ' tabindex="-1"'
    table.insert(html, string.format('    <button id="%s" class="%s" role="tab" type="button" data-target="%s" aria-controls="%s" aria-selected="%s"%s>', tab_id, btn_classes, panel_id, panel_id, aria_selected, tabindex))
    table.insert(html, string.format('      <span class="stepper-sequence">%s</span>', seq))
    table.insert(html, '      <span class="stepper-copy">')
    table.insert(html, string.format('        <strong>%s</strong>', entry.label))
    if entry.place ~= '' then
      table.insert(html, string.format('        <small>%s</small>', entry.place))
    end
    table.insert(html, '      </span>')
    table.insert(html, '    </button>')
  end
  table.insert(html, '  </div>')
  table.insert(html, '  <div class="stepper-panels">')
  for idx, entry in ipairs(entries) do
    local panel_id = 'trajectory-' .. entry.id
    local tab_id = 'trajectory-tab-' .. entry.id
    local is_active = idx == 1
    local panel_classes = 'stepper-panel' .. (is_active and ' is-active' or '')
    local aria_hidden = is_active and 'false' or 'true'
    table.insert(html, string.format('    <section id="%s" class="%s" role="tabpanel" aria-labelledby="%s" aria-hidden="%s">', panel_id, panel_classes, tab_id, aria_hidden))
    if entry.period ~= '' or entry.heading ~= '' then
      table.insert(html, '      <div class="stepper-panel-heading">')
      if entry.period ~= '' then
        table.insert(html, string.format('        <p class="stepper-panel-period">%s</p>', entry.period))
      end
      if entry.heading ~= '' then
        table.insert(html, string.format('        <h3>%s</h3>', entry.heading))
      end
      table.insert(html, '      </div>')
    end
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
    const buttons = stepper.querySelectorAll('.stepper-btn');
    const panels = stepper.querySelectorAll('.stepper-panel');
    const trackFill = stepper.querySelector('.stepper-track-fill');
    const nodes = stepper.querySelectorAll('.stepper-node');

    const setActive = (index) => {
      buttons.forEach((btn, idx) => {
        const isActive = idx === index;
        btn.classList.toggle('is-active', isActive);
        btn.setAttribute('aria-selected', String(isActive));
        btn.setAttribute('tabindex', isActive ? '0' : '-1');
      });

      panels.forEach((panel, idx) => {
        const isActive = idx === index;
        panel.classList.toggle('is-active', isActive);
        panel.setAttribute('aria-hidden', String(!isActive));
      });

      nodes.forEach((node, idx) => {
        node.classList.toggle('is-active', idx === index);
        node.classList.toggle('is-complete', idx <= index);
      });

      if (trackFill) {
        const progress = buttons.length > 1 ? (index / (buttons.length - 1)) * 100 : 100;
        trackFill.style.setProperty('--step-progress', `${progress}%`);
      }
    };

    buttons.forEach((button, index) => {
      button.addEventListener('click', () => setActive(index));
      button.addEventListener('keydown', (event) => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        const lastIndex = buttons.length - 1;
        let nextIndex = index;
        if (event.key === 'ArrowLeft') nextIndex = Math.max(0, index - 1);
        if (event.key === 'ArrowRight') nextIndex = Math.min(lastIndex, index + 1);
        if (event.key === 'Home') nextIndex = 0;
        if (event.key === 'End') nextIndex = lastIndex;
        buttons[nextIndex].focus();
        setActive(nextIndex);
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
    local path = stringify(kwargs["path"]) or ""
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
