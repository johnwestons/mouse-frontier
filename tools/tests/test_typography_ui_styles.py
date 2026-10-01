"""UI editor font styles retain font size and independently scale wrapped text."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class TypographyUIStyleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(r'''
            styleScale,styleFont=1,nil
            package.loaded['game.ui_layout']={currentTextStyle=function() return styleScale,styleFont end}
            graphics={}; createdFonts={}; draws={}
            function graphics.newFont(path,size)
                local font={path=path,size=size,lineHeight=1}
                function font:setFilter() end
                function font:setLineHeight(height) self.lineHeight=height end
                -- Courier Prime's line box is taller than its requested size.
                function font:getHeight() return math.ceil(self.size*1.1) end
                function font:getLineHeight() return self.lineHeight end
                function font:getWidth(text) return #text*self.size*.6 end
                function font:getWrap(text,width)
                    local lines,longest={},0
                    for paragraph in (text..'\n'):gmatch('(.-)\n') do
                        local line=''
                        for word in paragraph:gmatch('%S+') do
                            local nextLine=line=='' and word or line..' '..word
                            if line~='' and self:getWidth(nextLine)>width then
                                lines[#lines+1]=line
                                longest=math.max(longest,self:getWidth(line))
                                line=word
                            else line=nextLine end
                        end
                        lines[#lines+1]=line
                        longest=math.max(longest,self:getWidth(line))
                    end
                    return longest,lines
                end
                createdFonts[#createdFonts+1]=font
                return font
            end
            function graphics.setFont(font) currentFont=font end
            function graphics.getFont() return currentFont end
            function graphics.print(text,x,y,angle,sx,sy)
                draws[#draws+1]={font=currentFont,scale=sx}
                if onPrint then local callback=onPrint; onPrint=nil; callback() end
            end
            function graphics.printf(text,x,y,width,align,angle,sx,sy)
                draws[#draws+1]={font=currentFont,scale=sx,wrapWidth=width}
            end
            Typography=require('game.typography')
            original=Typography.install(graphics)
        ''')

    def test_default_and_regular_style_keep_original_font_size(self) -> None:
        self.lua.execute(r'''
            Typography.drawText(graphics,'Default',0,0,300,40,{singleLine=true})
            assert(draws[1].font==original and draws[1].scale==1)
            styleFont='regular'
            for i=1,5 do Typography.drawText(graphics,'Regular',0,0,300,40,{singleLine=true}) end
            assert(#createdFonts==1,'default regular UI styling must not grow the font')
            assert(currentFont==original and original.size==20)
        ''')

    def test_bold_nested_draws_preserve_requested_size_and_restore_font(self) -> None:
        self.lua.execute(r'''
            original=Typography.font(graphics,'regular',14)
            graphics.setFont(original)
            styleFont='bold'
            onPrint=function()
                Typography.drawText(graphics,'Nested',0,0,300,40,{singleLine=true})
            end
            Typography.drawText(graphics,'Outer',0,0,300,40,{singleLine=true})
            assert(#draws==2 and draws[1].font.size==14 and draws[2].font.size==14)
            assert(draws[1].font==draws[2].font and draws[1].font.path:find('Bold'))
            assert(currentFont==original,'font styling must stay inside the draw call')
            styleFont='regular'
            Typography.drawText(graphics,'Regular again',0,0,300,40,{singleLine=true})
            assert(draws[3].font==original)
        ''')

    def test_independent_text_scale_reflows_without_mutating_options(self) -> None:
        self.lua.execute(r'''
            local options={scale=.8,minScale=.8}
            local baseline,_,baseLines=Typography.drawText(graphics,'alpha beta gamma',0,0,100,200,options)
            styleScale=1.5
            local scaled,_,scaledLines,fits=Typography.drawText(graphics,'alpha beta gamma',0,0,100,200,options)
            assert(math.abs(baseline-.8)<.001 and math.abs(scaled-1.2)<.001)
            assert(baseLines==2 and scaledLines==3 and fits,'larger text must wrap within the same bounds')
            assert(math.abs(draws[2].wrapWidth-100/1.2)<.001)
            assert(options.scale==.8 and options.minScale==.8 and currentFont==original)
        ''')


if __name__ == '__main__':
    unittest.main()
