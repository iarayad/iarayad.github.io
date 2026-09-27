-- Connect the pages listed in `site-flow` (in _quarto.yml) into one sequence: each page gets a
-- cue to the next page at its end and a (pull-to-reveal) cue to the previous page. The site-wide
-- script contents/_page-flow.html turns scrolling past either edge into a view-transition
-- navigation.

local stringify = pandoc.utils.stringify

local function escape_html(text)
  local map = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;', ["'"] = '&#39;' }
  return (tostring(text or ""):gsub('[&<>"\']', map))
end

local function current_page()
  local input = quarto.doc.input_file
  local root = quarto.project.directory
  if not input or not root then
    return nil
  end
  return pandoc.path.make_relative(input, root)
end

-- Quarto rewrites relative paths in project metadata relative to each page (e.g. ../index.qmd),
-- so resolve every entry back to a project path.
local function project_path(href)
  local page_dir = pandoc.path.make_relative(pandoc.path.directory(quarto.doc.input_file), quarto.project.directory)
  -- pandoc.path.normalize keeps "..", so collapse the segments by hand.
  local parts = {}
  for _, part in ipairs(pandoc.path.split(pandoc.path.join({ page_dir, href }))) do
    if part == ".." then
      table.remove(parts)
    elseif part ~= "." then
      table.insert(parts, part)
    end
  end
  return table.concat(parts, "/")
end

-- Links start at the project root; Quarto rewrites them relative to each page and .qmd to .html.
local function cue(direction, entry)
  local href = "/" .. escape_html(project_path(stringify(entry.href)))
  local text = escape_html(stringify(entry.text))
  if direction == "next" then
    return string.format([[
<a class="flow-cue flow-next" href="%s" data-flow="next">
  <span class="flow-label">%s</span>
  <span class="flow-hint">keep scrolling</span>
  <i class="bi bi-chevron-down" aria-hidden="true"></i>
</a>]], href, text)
  end
  -- The navbar already links every page, so the previous-page cue is visual only.
  return string.format([[
<a class="flow-cue flow-prev" href="%s" data-flow="prev" aria-hidden="true" tabindex="-1">
  <i class="bi bi-chevron-up" aria-hidden="true"></i>
  <span class="flow-label">%s</span>
</a>]], href, text)
end

function Pandoc(doc)
  local flow = doc.meta["site-flow"]
  local page = current_page()
  if not flow or not page then
    return nil
  end
  for index, entry in ipairs(flow) do
    if project_path(stringify(entry.href)) == page then
      if flow[index - 1] then
        doc.blocks:insert(pandoc.RawBlock("html", cue("prev", flow[index - 1])))
      end
      if flow[index + 1] then
        doc.blocks:insert(pandoc.RawBlock("html", cue("next", flow[index + 1])))
      end
      return doc
    end
  end
  return nil
end
