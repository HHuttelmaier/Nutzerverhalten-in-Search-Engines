-- slider.lua - Quarto Extension for Content Slider
-- Author: Claude/Anthropic
-- Version: 1.0.0

local function generate_random_id()
  return tostring(math.random(100000, 999999))
end

local function read_template()
  local template_path = quarto.utils.resolvePath("slider.html")
  local file = io.open(template_path, "r")
  if not file then
    quarto.log.warning("Template file slider.html not found")
    return nil
  end
  local content = file:read("*all")
  file:close()
  return content
end

local function escape_json_string(str)
  if not str then return "" end
  -- Escape quotes and backslashes for JSON
  str = str:gsub('\\', '\\\\')
  str = str:gsub('"', '\\"')
  str = str:gsub('\n', '\\n')
  str = str:gsub('\r', '\\r')
  str = str:gsub('\t', '\\t')
  return str
end

function Shortcode(args)
  -- Parse slides
  -- Each slide consists of 4 parameters: heading, text, image/video, button_text
  -- Format: heading1, text1, media1, button1, heading2, text2, media2, button2, ...
  
  local slides = {}
  local num_params = #args
  local params_per_slide = 4
  
  -- Calculate number of slides
  local num_slides = math.floor(num_params / params_per_slide)
  
  if num_slides == 0 then
    quarto.log.warning("No slides provided to slider shortcode")
    return pandoc.Null()
  end
  
  -- Parse each slide
  for i = 1, num_slides do
    local base_idx = (i - 1) * params_per_slide
    local heading = pandoc.utils.stringify(args[base_idx + 1] or "")
    local text = pandoc.utils.stringify(args[base_idx + 2] or "")
    local media = pandoc.utils.stringify(args[base_idx + 3] or "")
    local button_text = pandoc.utils.stringify(args[base_idx + 4] or "")
    
    -- Determine media type
    local media_type = "none"
    local media_src = ""
    
    if media ~= "" then
      local lower_media = media:lower()
      if lower_media:match("%.mp4$") or lower_media:match("%.webm$") or lower_media:match("%.ogg$") then
        media_type = "video"
        media_src = media
      elseif lower_media:match("%.mp3$") or lower_media:match("%.wav$") or lower_media:match("%.ogg$") then
        media_type = "audio"
        media_src = media
      elseif lower_media ~= "" then
        media_type = "image"
        media_src = media
      end
    end
    
    table.insert(slides, {
      heading = escape_json_string(heading),
      text = escape_json_string(text),
      media_type = media_type,
      media_src = media_src,
      button_text = escape_json_string(button_text)
    })
  end
  
  -- Generate unique ID
  local random_id = generate_random_id()
  
  -- Only render for HTML format
  if quarto.doc.is_format("html") or quarto.doc.is_format("moodle-html") then
    local template = read_template()
    
    if not template then
      return pandoc.Null()
    end
    
    -- Build slides JSON
    local slides_json = "["
    for i, slide in ipairs(slides) do
      if i > 1 then
        slides_json = slides_json .. ","
      end
      slides_json = slides_json .. string.format([[
{
  "heading": "%s",
  "text": "%s",
  "media_type": "%s",
  "media_src": "%s",
  "button_text": "%s"
}]], 
        slide.heading,
        slide.text,
        slide.media_type,
        slide.media_src,
        slide.button_text
      )
    end
    slides_json = slides_json .. "]"
    
    -- Replace placeholders
    template = template:gsub("{{RANDOM_ID}}", random_id)
    template = template:gsub("{{SLIDES_DATA}}", slides_json)
    
    return pandoc.RawBlock('html', template)
    
  elseif quarto.doc.is_format("pdf") then
    -- For PDF: show first slide image or text
    local first_slide = slides[1]
    local content = {}
    
    if first_slide.heading ~= "" then
      table.insert(content, pandoc.Para({
        pandoc.Strong(pandoc.Str(first_slide.heading))
      }))
    end
    
    if first_slide.media_type == "image" and first_slide.media_src ~= "" then
      table.insert(content, pandoc.Para({pandoc.Image("", first_slide.media_src)}))
    end
    
    if first_slide.text ~= "" then
      table.insert(content, pandoc.Para({pandoc.Str(first_slide.text)}))
    end
    
    table.insert(content, pandoc.Para({
      pandoc.LineBreak(),
      pandoc.Emph(pandoc.Str("Hinweis: Interaktiver Slider mit " .. num_slides .. " Slides ist nur in der HTML-Version verfügbar."))
    }))
    
    return pandoc.Div(content)
    
  else
    -- For other formats: just show text
    return pandoc.Para({pandoc.Str("Interactive slider (" .. num_slides .. " slides)")})
  end
end

-- Register the shortcode
return {
  ['slider'] = Shortcode
}
