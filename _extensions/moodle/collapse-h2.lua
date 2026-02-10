-- collapse-h2-toc-fix.lua
-- 1. Wraps H2 + Content in <details>.
-- 2. Places the Section ID on the <details> wrapper so ScrollSpy tracks the whole section.
-- 3. Preserves H3/H4 as visible content inside the H2.

local utils = pandoc.utils

-- CONFIGURATION
local TARGET_LEVELS = { [2]=true }
local COLLAPSE_H2_OPEN = false

local function meta_bool(meta, key, default)
  local v = meta[key]
  if v == nil then return default end
  if type(v) == "boolean" then return v end
  local s = utils.stringify(v):lower()
  if s == "true" or s == "yes" or s == "1" then return true end
  if s == "false" or s == "no" or s == "0" then return false end
  return default
end

-- Helper to generate a unique ID if one is missing
local unique_counter = 0
local function ensure_id(h)
  if h.identifier and h.identifier ~= "" then
    return h.identifier
  end
  unique_counter = unique_counter + 1
  local new_id = "section-" .. tostring(unique_counter)
  h.identifier = new_id
  return new_id
end

local function process_blocks(blocks)
  local out = pandoc.List:new()
  local i = 1

  while i <= #blocks do
    local b = blocks[i]

    if b.t == "Div" then
      b.content = process_blocks(b.content)
      out:insert(b)
      i = i + 1
    elseif b.t == "BlockQuote" then
      b.content = process_blocks(b.content)
      out:insert(b)
      i = i + 1
    
    -- Main Logic: H2 Headers
    elseif b.t == "Header" and TARGET_LEVELS[b.level] then
      local current_level = b.level
      local section_id = ensure_id(b) -- Get the ID (e.g., "introduction")
      
      -- 1. Open <details> and assign it the ID
      -- This ensures the ScrollSpy tracks the entire container height.
      local open_attr = COLLAPSE_H2_OPEN and " open" or ""
      
      -- Note: We use the SAME ID on the details as the header.
      -- Browsers resolve this by linking to the first occurrence (the <details>),
      -- which is exactly what we want for Scroll tracking.
      out:insert(pandoc.RawBlock("html", 
        string.format('<details id="%s" class="native-collapse"%s>', section_id, open_attr)
      ))
      
      -- 2. Summary Wrapper
      out:insert(pandoc.RawBlock("html", '<summary class="native-summary">'))
      
      -- 3. The Header itself
      -- We keep the ID on the header too, so Pandoc's internal TOC generator 
      -- can still find it and create the link table correctly.
      if b.attr.classes == nil then b.attr.classes = {} end
      table.insert(b.attr.classes, "summary-header")
      out:insert(b)
      
      out:insert(pandoc.RawBlock("html", '</summary>'))
      
      -- 4. Content Wrapper
      out:insert(pandoc.RawBlock("html", '<div class="native-content">'))

      -- 5. Collect content (including H3, H4)
      local sub_blocks = pandoc.List:new()
      i = i + 1
      while i <= #blocks do
        local nb = blocks[i]
        if nb.t == "Header" and nb.level <= current_level then
          break
        end
        sub_blocks:insert(nb)
        i = i + 1
      end

      local processed_sub = process_blocks(sub_blocks)
      out:extend(processed_sub)
      
      -- 6. Close Tags
      out:insert(pandoc.RawBlock("html", '</div></details>'))

    else
      out:insert(b)
      i = i + 1
    end
  end

  return out
end

function Pandoc(doc)
  unique_counter = 0
  COLLAPSE_H2_OPEN = meta_bool(doc.meta, "collapse-open", false)
  doc.blocks = process_blocks(doc.blocks)
  return doc
end