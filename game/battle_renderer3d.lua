local Field=require('game.battle_field')
local Geometry=require('game.battle_geometry')
local Camera=require('game.battle_camera')
local Fog=require('game.battle_fog')
local Renderer={};Renderer.__index=Renderer
local format={{'VertexPosition','float',3},{'VertexTexCoord','float',2},{'VertexNormal','float',3},{'VertexColor','float',4}}
local shaderSource=[[
extern vec2 viewCenter;
extern vec3 viewTarget;
extern vec3 viewRight;
extern vec3 viewUp;
extern vec3 viewBack;
extern float viewScale;
extern float cameraDistance;
extern float nearDepth;
extern float farDepth;
extern float groundPass;
extern float unlit;
extern float biome;
extern float fieldRows;
extern float seedPhase;
extern Image visibilityMap;
extern vec2 fieldSize;
extern float fogEnabled;
extern float terrainDistance;
extern vec2 partySources[8];
varying vec3 worldNormal;
varying vec3 worldPosition;
varying float viewDepth;
#ifdef VERTEX
attribute vec3 VertexNormal;
vec4 position(mat4 transform_projection,vec4 vertex_position){
    vec3 relative=vertex_position.xyz-viewTarget;
    vec2 screen=viewCenter+vec2(dot(relative,viewRight),-dot(relative,viewUp))*viewScale;
    vec4 clip=transform_projection*vec4(screen,0.0,1.0);
    viewDepth=cameraDistance-dot(relative,viewBack);
    clip.z=((viewDepth-nearDepth)/(farDepth-nearDepth)*2.0-1.0)*clip.w;
    worldNormal=VertexNormal;worldPosition=vertex_position.xyz;
    return clip;
}
#endif
#ifdef PIXEL
vec4 sampleTile(Image tex,float tile,vec2 uv){
    vec2 p=vec2(mod(tile,4.0),floor(tile/4.0));
    return Texel(tex,(p+vec2(.015625)+fract(uv)*.96875)/vec2(4.0,2.0));
}
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 screen){
    vec4 pixel;
    if(groundPass>.5){
        vec2 groundUV=worldPosition.xz;
        float route=fieldRows*.5+sin(worldPosition.x*.24+seedPhase)*1.4;
        float path=1.0-smoothstep(.48,1.0,abs(worldPosition.z-route));
        float baseTile=biome==2.0?3.0:(biome==3.0?4.0:(biome==4.0?2.0:0.0));
        pixel=sampleTile(tex,baseTile,groundUV);
        pixel=mix(pixel,sampleTile(tex,2.0,groundUV*.8),smoothstep(1.0,2.8,worldPosition.y)*.7);
        pixel=mix(pixel,sampleTile(tex,1.0,groundUV),path*.85);
    }else{pixel=Texel(tex,uv);}
    if(pixel.a<.45)discard;
    float light=unlit>.5?1.0:(.55+.45*max(0.0,dot(normalize(worldNormal),normalize(vec3(-.5,.85,.35)))));
    vec3 rgb=pixel.rgb*color.rgb*light;
    if(groundPass>.5&&biome==2.0){
        float route=fieldRows*.5+sin(worldPosition.x*.24+seedPhase)*1.4;
        float path=1.0-smoothstep(.48,1.0,abs(worldPosition.z-route));
        rgb=mix(rgb,pixel.rgb*vec3(.53,.43,.28)*light,path*.75);
    }
    if(fogEnabled>.5){
        float sight=Texel(visibilityMap,clamp(worldPosition.xz/fieldSize,vec2(0.0),vec2(1.0))).r;
        float nearestSquared=1000000000.0;
        for(int i=0;i<8;i++){vec2 delta=worldPosition.xz-partySources[i];nearestSquared=min(nearestSquared,dot(delta,delta));}
        float distanceToParty=sqrt(nearestSquared);
        float fade=1.0-smoothstep(terrainDistance-2.0,terrainDistance,distanceToParty);
        rgb=mix(vec3(.045,.055,.065),rgb,sight*fade);
    }
    return vec4(rgb,pixel.a*color.a);
}
#endif
]]
function Renderer.new(options)
    options=options or {}
    return setmetatable({camera=Camera.new(),quality=options.quality or 'medium',imageLoader=options.imageLoader,
        texturePath=options.texturePath or 'assets/sprites/battle-maps/procedural/surface-kit-v1.png',chunks={},stats={}},Renderer)
end
local function release(value)if value and value.release then value:release()end end
function Renderer:releaseWorld()
    for _,c in ipairs(self.chunks)do release(c.ground);release(c.props);release(c.details);release(c.shadows)end
    self.chunks={};self.field=nil;self.obstacles=nil;self.geometryKey=nil;self.fogState=nil
end
function Renderer:release()
    self:releaseWorld();release(self.canvas);release(self.texture);release(self.shader);release(self.spriteMesh);release(self.white);release(self.fogImage)
    self.canvas,self.texture,self.shader,self.spriteMesh=nil,nil,nil,nil
end
function Renderer:initialize()
    if self.shader then return end
    self.shader=love.graphics.newShader(shaderSource)
    self.texture=self.imageLoader and self.imageLoader(self.texturePath) or love.graphics.newImage(self.texturePath,{mipmaps=true})
    self.texture:setFilter('nearest','nearest')
    if self.texture.setMipmapFilter then self.texture:setMipmapFilter('nearest',.3)end
    self.spriteMesh=love.graphics.newMesh(format,6,'triangles','stream')
    local pixel=love.image.newImageData(1,1);pixel:setPixel(0,0,1,1,1,1);self.white=love.graphics.newImage(pixel);pixel:release()
end
function Renderer:surfaceMesh(lines)
    local vertices={}
    for _,line in ipairs(lines)do
        local ax,az,bx,bz=line[1],line[2],line[3],line[4];local width=line.width or .025
        local dx,dz=bx-ax,bz-az;local length=math.max(.0001,math.sqrt(dx*dx+dz*dz));local ox,oz=-dz/length*width,dx/length*width
        local function point(x,z)return {x,Field.heightAt(self.field,x,z)+.035,z}end
        local a,b,c,d=point(ax+ox,az+oz),point(ax-ox,az-oz),point(bx+ox,bz+oz),point(bx-ox,bz-oz)
        Geometry.triangle(vertices,a,b,c,0,line.color or {1,.85,.3,1});Geometry.triangle(vertices,b,d,c,0,line.color or {1,.85,.3,1})
    end
    if #vertices==0 then return nil end
    local mesh=love.graphics.newMesh(format,vertices,'triangles','static');mesh:setTexture(self.white);return mesh
end
function Renderer:drawOverlay(mesh)
    if not mesh then return end
    self.shader:send('groundPass',0);self.shader:send('unlit',1);love.graphics.setDepthMode('lequal',false)
    love.graphics.draw(mesh);love.graphics.setDepthMode('less',true);self.stats.drawCalls=self.stats.drawCalls+1
end
function Renderer:setBattle(battle,quality)
    local field=assert(battle.field,'3D battle has no canonical field')
    quality=quality or self.quality
    if self.field==field and self.quality==quality and self.obstacles==battle.obstacles then return false end
    -- Co-op projections replace tables after commands. Reuse GPU meshes when
    -- the authoritative geometry is unchanged instead of rebuilding every turn.
    local parts={field.version,field.columns,field.rows,field.seed,field.biome,field.layout,field.elevationData,quality}
    for q=0,field.columns-1 do for r=1,field.rows do
        local o=battle.obstacles[q..':'..r];if o then parts[#parts+1]=q..':'..r..'='..o.kind end
    end end
    local key=table.concat(parts,'|')
    if self.geometryKey==key then self.field=field;self.obstacles=battle.obstacles;return false end
    self:initialize();self:releaseWorld();self.field=field;self.obstacles=battle.obstacles;self.quality=quality
    for q=0,field.columns-1,Geometry.CHUNK_SIZE do for r=1,field.rows,Geometry.CHUNK_SIZE do
        self.chunks[#self.chunks+1]={q=q,r=r,w=math.min(Geometry.CHUNK_SIZE,field.columns-q),h=math.min(Geometry.CHUNK_SIZE,field.rows-r+1)}
    end end
    self.stats={triangles=0,visibleTriangles=0,visibleChunks=0,cachedChunks=0,drawCalls=0,quality=quality}
    self.geometryKey=key
    return true
end
function Renderer:buildChunk(chunk)
    if chunk.ground then return end
    local source=Geometry.build(self.field,self.obstacles,self.quality,chunk.q,chunk.r)[1];local count=0
    for _,name in ipairs({'ground','props','details','shadows'})do
        local vertices=source[name];count=count+#vertices/3
        if #vertices>0 then chunk[name]=love.graphics.newMesh(format,vertices,'triangles','static');chunk[name]:setTexture(self.texture)end
    end
    chunk.triangles=count;self.stats.triangles=self.stats.triangles+count;self.stats.cachedChunks=self.stats.cachedChunks+1
end
function Renderer:trimCache()
    local limit=self.quality=='low'and 28 or 40
    while self.stats.cachedChunks>limit do
        local oldest
        for _,c in ipairs(self.chunks)do if c.ground and c.lastFrame~=self.frame and(not oldest or c.lastFrame<oldest.lastFrame)then oldest=c end end
        if not oldest then break end -- A split party may legitimately see more chunks.
        for _,name in ipairs({'ground','props','details','shadows'})do release(oldest[name]);oldest[name]=nil end
        self.stats.triangles=self.stats.triangles-oldest.triangles;self.stats.cachedChunks=self.stats.cachedChunks-1;oldest.triangles=nil
    end
end
function Renderer:prepareFog(battle)
    self.fogActive=self.fogEnabled~=false
    self.shader:send('fogEnabled',self.fogActive and 1 or 0)
    self.shader:send('fieldSize',{self.field.columns,self.field.rows})
    self.shader:send('terrainDistance',self.renderDistance or 14)
    if not self.fogActive then
        self.shader:send('visibilityMap',self.white);return
    end
    local state=Fog.state(battle);self.sources=state.sources
    if self.fogState~=state then
        local data=love.image.newImageData(self.field.columns,self.field.rows)
        for q=0,self.field.columns-1 do for r=1,self.field.rows do
            local k=q*self.field.rows+r;local n=state.visible[k]and 1 or state.explored[k]and .30 or 0
            data:setPixel(q,r-1,n,n,n,1)
        end end
        if self.fogImage and self.fogImage:getWidth()==self.field.columns and self.fogImage:getHeight()==self.field.rows then self.fogImage:replacePixels(data)
        else release(self.fogImage);self.fogImage=love.graphics.newImage(data);self.fogImage:setFilter('linear','linear')end
        data:release();self.fogState=state
    end
    local sources={}
    for i=1,8 do sources[i]=state.sources[i]or{-10000,-10000}end
    self.shader:send('partySources',unpack(sources));self.shader:send('visibilityMap',self.fogImage)
end
function Renderer:ensureCanvas(w,h)
    w,h=math.max(1,math.floor(w)),math.max(1,math.floor(h))
    if not self.canvas or self.canvas:getWidth()~=w or self.canvas:getHeight()~=h then
        release(self.canvas);self.canvas=love.graphics.newCanvas(w,h,{format='rgba8',dpiscale=1,msaa=0})
        self.canvas:setFilter('linear','linear')
    end
end
function Renderer:sendCamera()
    local c=self.camera;local r,u,b=c:basis();local v=c.viewport
    self.shader:send('viewCenter',{v.x+v.w/2,v.y+v.h/2});self.shader:send('viewTarget',{c.targetX,c.targetY,c.targetZ})
    self.shader:send('viewRight',r);self.shader:send('viewUp',u);self.shader:send('viewBack',b)
    self.shader:send('viewScale',c.pixelsPerUnit*c.zoom);self.shader:send('cameraDistance',c.distance)
    self.shader:send('nearDepth',c.near);self.shader:send('farDepth',c.far)
    self.shader:send('biome',self.field.biome);self.shader:send('fieldRows',self.field.rows)
    self.shader:send('seedPhase',(self.field.seed%157)*.04)
end
function Renderer:chunkVisible(chunk)
    if self.fogActive then
        local nearby=false
        for _,p in ipairs(self.sources)do
            local x=math.max(chunk.q,math.min(chunk.q+chunk.w,p[1]));local z=math.max(chunk.r-1,math.min(chunk.r-1+chunk.h,p[2]))
            if (x-p[1])^2+(z-p[2])^2<((self.renderDistance or 14)+1)^2 then nearby=true;break end
        end
        if not nearby then return false end
        local known=false
        for q=chunk.q,chunk.q+chunk.w-1 do for r=chunk.r,chunk.r+chunk.h-1 do
            if self.fogState.explored[q*self.field.rows+r]then known=true;break end
        end;if known then break end end
        if not known then return false end
    end
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    for _,x in ipairs({chunk.q-1,chunk.q+chunk.w+1})do for _,z in ipairs({chunk.r-2,chunk.r+chunk.h})do for _,y in ipairs({0,6})do
        local sx,sy=self.camera:project(x,y,z);minX=math.min(minX,sx);maxX=math.max(maxX,sx);minY=math.min(minY,sy);maxY=math.max(maxY,sy)
    end end end
    local v=self.camera.viewport;return maxX>=v.x and minX<v.x+v.w and maxY>=v.y and minY<v.y+v.h
end
-- Called inside the 3D pass. Authored sprite pixels remain unlit, with cutout
-- depth writes so terrain and solid props correctly occlude their silhouettes.
function Renderer:drawSprite(image,quad,x,y,z,w,h,tint,options)
    local r,u,b=self.camera:basis();local coords={{0,1},{0,0},{1,1},{1,1},{0,0},{1,0}}
    local verts={};local iw,ih=image:getDimensions();local qx,qy,qw,qh=0,0,iw,ih
    if quad then qx,qy,qw,qh=quad:getViewport()end
    tint=tint or {1,1,1,1}
    options=options or{};local ca,sa=math.cos(options.rotation or 0),math.sin(options.rotation or 0)
    for i,c in ipairs(coords)do
        local dx,dy=(c[1]-.5)*w,((options.centered and .5 or 1)-c[2])*h
        dx,dy=dx*ca+dy*sa,-dx*sa+dy*ca
        verts[i]={x+r[1]*dx+u[1]*dy,y+u[2]*dy,z+r[3]*dx+u[3]*dy,
            (qx+c[1]*qw)/iw,(qy+c[2]*qh)/ih,b[1],b[2],b[3],tint[1],tint[2],tint[3],tint[4]or 1}
    end
    self.spriteMesh:setVertices(verts);self.spriteMesh:setTexture(image)
    self.shader:send('groundPass',0);self.shader:send('unlit',1)
    love.graphics.draw(self.spriteMesh);self.stats.drawCalls=self.stats.drawCalls+1
end
function Renderer:render(battle,viewport,actors)
    local resolution=self.resolution or 1
    self:setBattle(battle,self.quality);self:ensureCanvas(viewport.w*resolution,viewport.h*resolution)
    local previousCanvas=love.graphics.getCanvas()
    self.camera:configure({x=0,y=0,w=viewport.w,h=viewport.h})
    love.graphics.push('all');love.graphics.origin();love.graphics.setCanvas({self.canvas,depth=true})
    love.graphics.scale(self.canvas:getWidth()/viewport.w,self.canvas:getHeight()/viewport.h)
    love.graphics.clear(.045,.055,.065,1,0,1);love.graphics.setColor(1,1,1,1);love.graphics.setBlendMode('alpha','alphamultiply')
    love.graphics.setDepthMode('less',true);love.graphics.setMeshCullMode('none');love.graphics.setShader(self.shader)
    self:sendCamera();self.shader:send('unlit',0)
    self:prepareFog(battle);self.frame=(self.frame or 0)+1
    self.stats.visibleChunks=0;self.stats.visibleTriangles=0;self.stats.drawCalls=0;self.stats.projectiles=0
    self.stats.pendingChunks=0;self.stats.builtChunks=0;self.stats.buildMilliseconds=0
    local visible={}
    for _,chunk in ipairs(self.chunks)do
        if self:chunkVisible(chunk)then
            local x,z=chunk.q+chunk.w/2,chunk.r-1+chunk.h/2
            chunk.priority=(x-self.camera.targetX)^2+(z-self.camera.targetZ)^2
            visible[#visible+1]=chunk
        end
    end
    table.sort(visible,function(a,b)return a.priority==b.priority and(a.q==b.q and a.r<b.r or a.q<b.q)or a.priority<b.priority end)
    local started=love.timer.getTime();local maximum=self.maxBuildsPerFrame or(self.quality=='low'and 2 or 3)
    local budget=self.buildBudgetSeconds or(self.quality=='low'and .002 or .004)
    for _,chunk in ipairs(visible)do
        if not chunk.ground and self.stats.builtChunks<maximum and(self.stats.builtChunks==0 or love.timer.getTime()-started<budget)then
            self:buildChunk(chunk);self.stats.builtChunks=self.stats.builtChunks+1
        end
        if chunk.ground then
            chunk.lastFrame=self.frame
            self.stats.visibleChunks=self.stats.visibleChunks+1
            self.stats.visibleTriangles=self.stats.visibleTriangles+chunk.triangles
            for _,name in ipairs({'ground','props','details'})do if chunk[name]then
                self.shader:send('groundPass',name=='ground' and 1 or 0)
                love.graphics.draw(chunk[name]);self.stats.drawCalls=self.stats.drawCalls+1
            end end
        else self.stats.pendingChunks=self.stats.pendingChunks+1 end
    end
    self.stats.buildMilliseconds=(love.timer.getTime()-started)*1000
    -- Transparent contact shadows must not write depth or precede neighboring
    -- ground chunks: even a transparent edge can otherwise punch a hole in it.
    self.shader:send('groundPass',0);self.shader:send('unlit',1);love.graphics.setDepthMode('lequal',false)
    for _,chunk in ipairs(self.chunks)do if chunk.lastFrame==self.frame and chunk.shadows then
        love.graphics.draw(chunk.shadows);self.stats.drawCalls=self.stats.drawCalls+1
    end end
    love.graphics.setDepthMode('less',true)
    self:trimCache()
    if actors then actors(self)end
    love.graphics.setShader();love.graphics.setDepthMode();love.graphics.setCanvas(previousCanvas);love.graphics.pop()
    self.camera:configure({x=viewport.x,y=viewport.y,w=viewport.w,h=viewport.h})
    love.graphics.push('all');love.graphics.setColor(1,1,1,1);love.graphics.setBlendMode('alpha','premultiplied')
    love.graphics.draw(self.canvas,viewport.x,viewport.y,0,viewport.w/self.canvas:getWidth(),viewport.h/self.canvas:getHeight());love.graphics.pop()
    return self.stats
end
function Renderer:pick(x,y)
    if not self.field or not self.camera:contains(x,y)then return nil end
    return Field.raycast(self.field,self.camera:ray(x,y))
end
return Renderer
