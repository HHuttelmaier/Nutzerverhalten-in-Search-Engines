-- hotspots.lua - Quarto Extension for Interactive Hotspots
-- Author: Claude/Anthropic
-- Version: 3.0.0 - Flexible hotspot count (1-6)

local function generate_random_id()
  return tostring(math.random(100000, 999999))
end

-- Spracherkennung (wie in Ihrem filter.lua)
local function get_labels()
  local lang = "de"
  
  if quarto.doc and type(quarto.doc.lang) == "function" then
    lang = quarto.doc.lang()
  elseif PANDOC_READER_OPTIONS and PANDOC_READER_OPTIONS['lang'] then
    lang = PANDOC_READER_OPTIONS['lang']
  end
  
  local vocab = {
    note = "Note",
    interactive_note = "Note: Interactive hotspots are only available in the HTML version."
  }
  
  if lang and type(lang) == "string" and lang:find("^de") then
    vocab = {
      note = "Hinweis",
      interactive_note = "Hinweis: Interaktive Hotspots sind nur in der HTML-Version verfügbar."
    }
  end
  
  return vocab
end

-- Markdown in Pandoc Inlines konvertieren (für PDF/Typst)
local function markdown_to_pandoc(text)
  if not text or text == "" then
    return pandoc.Inlines({})
  end
  
  -- Pandoc parst Markdown automatisch
  local doc = pandoc.read(text, "markdown")
  
  -- Extrahiere alle Inline-Elemente
  local inlines = pandoc.Inlines({})
  
  for _, block in ipairs(doc.blocks) do
    if block.t == "Para" or block.t == "Plain" then
      for _, inline in ipairs(block.content) do
        inlines:insert(inline)
      end
    end
  end
  
  return inlines
end

-- Escape string for gsub replacement (second argument)
local function escape_gsub_replacement(str)
  if not str then return "" end
  -- In gsub replacement string, only % needs to be escaped
  return (str:gsub("%%", "%%%%"))
end

-- Markdown in HTML konvertieren (für HTML-Template)
local function markdown_to_html(text)
  if not text or text == "" then
    return ""
  end
  
  -- Parse Markdown zu Pandoc-Struktur
  local doc = pandoc.read(text, "markdown")
  
  -- Extrahiere Inlines
  local inlines = pandoc.Inlines({})
  for _, block in ipairs(doc.blocks) do
    if block.t == "Para" or block.t == "Plain" then
      for _, inline in ipairs(block.content) do
        inlines:insert(inline)
      end
    elseif block.t == "LineBlock" then
      -- Handle line breaks
      for i, line in ipairs(block.content) do
        if i > 1 then
          inlines:insert(pandoc.LineBreak())
        end
        for _, inline in ipairs(line) do
          inlines:insert(inline)
        end
      end
    end
  end
  
  -- Konvertiere Pandoc Inlines zu HTML String
  local html_parts = {}
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      -- Escape HTML special characters
      local str = inline.text
      str = str:gsub("&", "&amp;")
      str = str:gsub("<", "&lt;")
      str = str:gsub(">", "&gt;")
      str = str:gsub('"', "&quot;")
      table.insert(html_parts, str)
    elseif inline.t == "Space" then
      table.insert(html_parts, " ")
    elseif inline.t == "Strong" then
      local strong_text = pandoc.utils.stringify(inline.content)
      table.insert(html_parts, "<strong>" .. strong_text .. "</strong>")
    elseif inline.t == "Emph" then
      local em_text = pandoc.utils.stringify(inline.content)
      table.insert(html_parts, "<em>" .. em_text .. "</em>")
    elseif inline.t == "Code" then
      table.insert(html_parts, "<code>" .. inline.text .. "</code>")
    elseif inline.t == "LineBreak" or inline.t == "SoftBreak" then
      table.insert(html_parts, "<br>")
    elseif inline.t == "Link" then
      local link_text = pandoc.utils.stringify(inline.content)
      table.insert(html_parts, '<a href="' .. inline.target .. '">' .. link_text .. '</a>')
    else
      -- Fallback: stringify
      table.insert(html_parts, pandoc.utils.stringify({inline}))
    end
  end
  
  return table.concat(html_parts, "")
end

function Shortcode(args)
  -- Parse arguments dynamically
  -- Format: image, title1, content1, title2, content2, ..., [caption]
  
  local image = pandoc.utils.stringify(args[1] or "")
  
  -- Determine if last parameter is a caption
  -- If (total args - 1) is odd, last one is caption
  local total_args = #args
  local has_caption = false
  local caption = ""
  local content_args_count = total_args - 1  -- Exclude image
  
  if content_args_count % 2 == 1 then
    -- Odd number after image = last one is caption
    has_caption = true
    caption = pandoc.utils.stringify(args[total_args])
    content_args_count = content_args_count - 1
  end
  
  -- Parse hotspots (title/content pairs)
  local hotspots = {}
  for i = 1, content_args_count, 2 do
    local title = pandoc.utils.stringify(args[i + 1] or "")
    local content = pandoc.utils.stringify(args[i + 2] or "")
    if title ~= "" then
      table.insert(hotspots, {
        title = title,
        content = content
      })
    end
  end
  
  local num_hotspots = #hotspots
  
  -- Validate hotspot count
  if num_hotspots < 1 then
    quarto.log.warning("Hotspots: At least 1 hotspot required")
    return pandoc.Null()
  end
  
  if num_hotspots > 6 then
    quarto.log.warning("Hotspots: Maximum 6 hotspots supported, found " .. num_hotspots)
    -- Use only first 6
    local temp = {}
    for i = 1, 6 do
      table.insert(temp, hotspots[i])
    end
    hotspots = temp
    num_hotspots = 6
  end
  
  -- Generate unique ID for multiple instances
  local random_id = generate_random_id()
  
  -- === HTML: Interaktive Hotspots ===
  if quarto.doc.is_format("html") then
    -- Generate HTML dynamically instead of using template
    local html_parts = {}
    
    -- Wrapper start
    table.insert(html_parts, '<div class="interactive-hotspots-wrapper" style="margin: 2rem 0;">')
    
    -- Styles
    table.insert(html_parts, '<style>')
    table.insert(html_parts, '.interactive-hotspots-wrapper { max-width: 1200px; margin: 2rem auto; }')
    table.insert(html_parts, '.hotspot-container-' .. random_id .. ' { position: relative; width: 100%; display: inline-block; box-shadow: 0 10px 40px rgba(0, 0, 0, 0.1); border-radius: 8px; overflow: visible; background: white; }')
    table.insert(html_parts, '.hotspot-container-' .. random_id .. ' img { width: 100%; height: auto; display: block; border-radius: 8px; }')
    table.insert(html_parts, '.hotspot-' .. random_id .. ' { position: absolute; width: 48px; height: 48px; cursor: pointer; transform: translate(-50%, -50%); transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); z-index: 10; }')
    table.insert(html_parts, '.hotspot-inner-' .. random_id .. ' { width: 100%; height: 100%; border-radius: 50%; background: white; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15); display: flex; align-items: center; justify-content: center; position: relative; transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); animation: pulse-' .. random_id .. ' 2s ease-in-out infinite; }')
    table.insert(html_parts, '.hotspot-inner-' .. random_id .. '::before { content: ""; position: absolute; width: 100%; height: 100%; border-radius: 50%; border: 2px solid #ff6b35; opacity: 0; transform: scale(1.2); transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); }')
    table.insert(html_parts, '.hotspot-' .. random_id .. ':hover .hotspot-inner-' .. random_id .. ' { transform: scale(1.15); box-shadow: 0 6px 20px rgba(255, 107, 53, 0.3); }')
    table.insert(html_parts, '.hotspot-' .. random_id .. ':hover .hotspot-inner-' .. random_id .. '::before { opacity: 1; transform: scale(1.4); }')
    table.insert(html_parts, '.hotspot-' .. random_id .. '.active .hotspot-inner-' .. random_id .. ' { background: #ff6b35; }')
    table.insert(html_parts, '.hotspot-' .. random_id .. '.active .hotspot-inner-' .. random_id .. '::after { color: white; }')
    table.insert(html_parts, '.hotspot-inner-' .. random_id .. '::after { content: "+"; font-size: 24px; font-weight: 600; color: #ff6b35; transition: color 0.3s ease; }')
    table.insert(html_parts, '.hotspot-popup-' .. random_id .. ' { position: absolute; background: white; border-radius: 12px; box-shadow: 0 20px 60px rgba(0, 0, 0, 0.2); padding: 32px; min-width: 400px; max-width: 500px; z-index: 100; border-top: 4px solid #ff6b35; display: none; }')
    table.insert(html_parts, '.hotspot-popup-' .. random_id .. '.visible { display: block; }')
    table.insert(html_parts, '.hotspot-popup-' .. random_id .. '.active { animation: popupFadeIn-' .. random_id .. ' 0.3s cubic-bezier(0.4, 0, 0.2, 1) forwards; }')
    table.insert(html_parts, '@keyframes popupFadeIn-' .. random_id .. ' { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }')
    table.insert(html_parts, '@keyframes pulse-' .. random_id .. ' { 0%, 100% { box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15); } 50% { box-shadow: 0 4px 12px rgba(255, 107, 53, 0.4); } }')
    table.insert(html_parts, '.popup-header-' .. random_id .. ' { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }')
    table.insert(html_parts, '.popup-title-' .. random_id .. ' { font-size: 24px; font-weight: 700; color: #1a1a1a; }')
    table.insert(html_parts, '.popup-nav-' .. random_id .. ' { display: flex; gap: 8px; }')
    table.insert(html_parts, '.nav-btn-' .. random_id .. ' { width: 32px; height: 32px; border: 1px solid #e0e0e0; background: white; border-radius: 6px; cursor: pointer; display: flex; align-items: center; justify-content: center; transition: all 0.2s ease; font-size: 18px; color: #666; }')
    table.insert(html_parts, '.nav-btn-' .. random_id .. ':hover { background: #f8f8f8; border-color: #ff6b35; color: #ff6b35; }')
    table.insert(html_parts, '.nav-btn-' .. random_id .. ':disabled { opacity: 0.3; cursor: not-allowed; }')
    table.insert(html_parts, '.popup-content-' .. random_id .. ' { font-size: 16px; line-height: 1.7; color: #4a4a4a; }')
    table.insert(html_parts, '.close-btn-' .. random_id .. ' { position: absolute; top: 16px; right: 16px; width: 28px; height: 28px; border: none; background: transparent; cursor: pointer; font-size: 24px; color: #999; transition: color 0.2s ease; }')
    table.insert(html_parts, '.close-btn-' .. random_id .. ':hover { color: #ff6b35; }')
    table.insert(html_parts, '</style>')
    
    -- Container start
    table.insert(html_parts, '<div class="hotspot-container-' .. random_id .. '">')
    table.insert(html_parts, '<img src="' .. image .. '" alt="Interactive Image">')
    
    -- Generate hotspots dynamically positioned
    for i, hotspot in ipairs(hotspots) do
      -- Calculate vertical position: distribute evenly from 15% to 85%
      local top_percent = 15 + ((i - 1) / math.max(1, num_hotspots - 1)) * 70
      if num_hotspots == 1 then
        top_percent = 50  -- Center single hotspot
      end
      
      table.insert(html_parts, '<div class="hotspot-' .. random_id .. '" data-id="' .. (i-1) .. '" style="top: ' .. string.format("%.1f", top_percent) .. '%; left: 50%;">')
      table.insert(html_parts, '<div class="hotspot-inner-' .. random_id .. '"></div>')
      table.insert(html_parts, '</div>')
    end
    
    -- Popup
    table.insert(html_parts, '<div class="hotspot-popup-' .. random_id .. '">')
    table.insert(html_parts, '<button class="close-btn-' .. random_id .. '">×</button>')
    table.insert(html_parts, '<div class="popup-header-' .. random_id .. '">')
    table.insert(html_parts, '<h3 class="popup-title-' .. random_id .. '"></h3>')
    table.insert(html_parts, '<div class="popup-nav-' .. random_id .. '">')
    table.insert(html_parts, '<button class="nav-btn-' .. random_id .. ' prev-btn-' .. random_id .. '">‹</button>')
    table.insert(html_parts, '<button class="nav-btn-' .. random_id .. ' next-btn-' .. random_id .. '">›</button>')
    table.insert(html_parts, '</div>')
    table.insert(html_parts, '</div>')
    table.insert(html_parts, '<div class="popup-content-' .. random_id .. '"></div>')
    table.insert(html_parts, '</div>')
    
    table.insert(html_parts, '</div>') -- Close container
    
    -- JavaScript for interaction
    table.insert(html_parts, '<script>')
    table.insert(html_parts, '(function() {')
    table.insert(html_parts, 'const data = [')
    
    -- Add hotspot data
    for i, hotspot in ipairs(hotspots) do
      local content_html = markdown_to_html(hotspot.content)
      -- Escape for JavaScript string
      local title_js = hotspot.title:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
      local content_js = content_html:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
      
      table.insert(html_parts, '  {title: "' .. title_js .. '", content: "' .. content_js .. '"}')
      if i < num_hotspots then
        table.insert(html_parts, ',')
      end
    end
    
    table.insert(html_parts, '];')
    table.insert(html_parts, [[
let currentIndex = 0;
const spots = document.querySelectorAll('.hotspot-]] .. random_id .. [[');
const popup = document.querySelector('.hotspot-popup-]] .. random_id .. [[');
const title = document.querySelector('.popup-title-]] .. random_id .. [[');
const content = document.querySelector('.popup-content-]] .. random_id .. [[');
const prevBtn = document.querySelector('.prev-btn-]] .. random_id .. [[');
const nextBtn = document.querySelector('.next-btn-]] .. random_id .. [[');
const closeBtn = document.querySelector('.close-btn-]] .. random_id .. [[');

function showPopup(index) {
  currentIndex = index;
  title.textContent = data[index].title;
  content.innerHTML = data[index].content;
  popup.classList.add('visible', 'active');
  spots.forEach((s, i) => s.classList.toggle('active', i === index));
  prevBtn.disabled = index === 0;
  nextBtn.disabled = index === data.length - 1;
  
  const spot = spots[index];
  const rect = spot.getBoundingClientRect();
  const container = spot.closest('.hotspot-container-]] .. random_id .. [[');
  const containerRect = container.getBoundingClientRect();
  
  popup.style.left = '60%';
  popup.style.top = rect.top - containerRect.top + 'px';
}

function hidePopup() {
  popup.classList.remove('visible', 'active');
  spots.forEach(s => s.classList.remove('active'));
}

spots.forEach((spot, index) => {
  spot.addEventListener('click', () => showPopup(index));
});

closeBtn.addEventListener('click', hidePopup);
prevBtn.addEventListener('click', () => showPopup(currentIndex - 1));
nextBtn.addEventListener('click', () => showPopup(currentIndex + 1));

document.addEventListener('keydown', (e) => {
  if (!popup.classList.contains('visible')) return;
  if (e.key === 'Escape') hidePopup();
  if (e.key === 'ArrowLeft' && currentIndex > 0) showPopup(currentIndex - 1);
  if (e.key === 'ArrowRight' && currentIndex < data.length - 1) showPopup(currentIndex + 1);
});
]])
    table.insert(html_parts, '})();')
    table.insert(html_parts, '</script>')
    
    -- Add caption if present
    if caption ~= "" then
      local caption_escaped = caption:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
      table.insert(html_parts, '<p class="hotspot-caption" style="text-align: center; margin-top: 0.5rem; font-size: 0.9rem; color: #666; font-style: italic;">' .. caption_escaped .. '</p>')
    end
    
    table.insert(html_parts, '</div>') -- Close wrapper
    
    return pandoc.RawBlock('html', table.concat(html_parts, '\n'))
  
  -- === TYPST: Bild + formatierte Liste ===
  elseif quarto.doc.is_format("typst") then
    local labels = get_labels()
    local result = pandoc.Blocks({})
    
    -- Bild einfügen
    result:insert(pandoc.Para({pandoc.Image("", image)}))
    
    -- Hotspots als formatierte Liste
    result:insert(pandoc.RawBlock("typst", "#v(0.5em)"))
    
    -- Iterate over all hotspots
    for i, hotspot in ipairs(hotspots) do
      result:insert(pandoc.RawBlock("typst", "*" .. hotspot.title .. ":* "))
      local content_inlines = markdown_to_pandoc(hotspot.content)
      result:insert(pandoc.Para(content_inlines))
      
      -- Add spacing between hotspots (except after last one)
      if i < num_hotspots then
        result:insert(pandoc.RawBlock("typst", "#v(0.3em)"))
      end
    end
    
    -- Caption hinzufügen, falls vorhanden
    if caption ~= "" then
      result:insert(pandoc.RawBlock("typst", "#v(0.5em)"))
      result:insert(pandoc.Para({
        pandoc.Emph({pandoc.Str(caption)})
      }))
    end
    
    return result
  
  -- === PDF: Bild + formatierte Liste ===
  elseif quarto.doc.is_format("pdf") or quarto.doc.is_format("latex") then
    local labels = get_labels()
    local result = pandoc.Blocks({})
    
    -- Bild einfügen
    result:insert(pandoc.Para({pandoc.Image("", image)}))
    result:insert(pandoc.Para({})) -- Leerzeile
    
    -- Hotspots als Liste
    local items = pandoc.List({})
    
    -- Iterate over all hotspots
    for i, hotspot in ipairs(hotspots) do
      local content_inlines = markdown_to_pandoc(hotspot.content)
      local full_inlines = pandoc.Inlines({})
      full_inlines:insert(pandoc.Strong({pandoc.Str(hotspot.title .. ":")}))
      full_inlines:insert(pandoc.Space())
      full_inlines:extend(content_inlines)
      
      local item_content = pandoc.Blocks({
        pandoc.Para(full_inlines)
      })
      items:insert(item_content)
    end
    
    result:insert(pandoc.BulletList(items))
    
    -- Caption hinzufügen, falls vorhanden
    if caption ~= "" then
      result:insert(pandoc.Para({})) -- Leerzeile
      result:insert(pandoc.Para({
        pandoc.Emph({pandoc.Str(caption)})
      }))
    end
    
    return result
    
  else
    -- For other formats: just show the image
    return pandoc.Para({pandoc.Image("", image)})
  end
end

-- Register the shortcode
return {
  ['hotspots'] = Shortcode
}
