-- PROJECT: blogs-convert
local fenced = "```\n%s\n```\n"
function CodeBlock(cb)
	-- use pandoc's default behavior if the block has classes or attribs
	if cb.classes[1] or next(cb.attributes) then
		return nil
	end
	return pandoc.RawBlock("bash", cb.text)
end
