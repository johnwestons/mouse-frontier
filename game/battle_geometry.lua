-- Reusable textured prop kit and chunk geometry. Returns plain vertex arrays;
-- the renderer owns GPU lifetime, culling, and per-device decoration density.
local Field=require('game.battle_field')
local Sites=require('game.battle_sites')
local G={CHUNK_SIZE=6}
local function uv(slot,u,v)return (slot%4+.015625+u*.96875)/4,(math.floor(slot/4)+.015625+v*.96875)/2 end
local function add(out,p,u,v,n,c)
    out[#out+1]={p[1],p[2],p[3],u,v,n[1],n[2],n[3],c[1],c[2],c[3],c[4]or 1}
end
function G.triangle(out,a,b,c,slot,color,coords)
    local ax,ay,az=b[1]-a[1],b[2]-a[2],b[3]-a[3];local bx,by,bz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
    local nx,ny,nz=ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx;local length=math.max(1e-8,math.sqrt(nx*nx+ny*ny+nz*nz))
    local n={nx/length,ny/length,nz/length};local t=coords or {{0,0},{0,1},{1,0}}
    for i,p in ipairs({a,b,c})do local u,v=uv(slot,t[i][1],t[i][2]);add(out,p,u,v,n,color)end
end
function G.box(out,x,y,z,w,h,d,slot,color,yaw)
    local ca,sa=math.cos(yaw or 0),math.sin(yaw or 0);local p={}
    for _,v in ipairs({{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}})do
        local a,b=v[1]*w/2,v[3]*d/2;p[#p+1]={x+a*ca+b*sa,y+v[2]*h/2,z-a*sa+b*ca}
    end
    for _,face in ipairs({{1,4,3,2},{5,6,7,8},{1,5,8,4},{2,3,7,6},{4,8,7,3},{1,2,6,5}})do
        local a,b,c,d=p[face[1]],p[face[2]],p[face[3]],p[face[4]]
        G.triangle(out,a,b,c,slot,color,{{0,1},{0,0},{1,0}});G.triangle(out,a,c,d,slot,color,{{0,1},{1,0},{1,1}})
    end
end
function G.cylinder(out,x,y,z,r,h,slot,color,segments,topRadius)
    segments=segments or 7;topRadius=topRadius or r
    for i=0,segments-1 do
        local a,b=i/segments*math.pi*2,(i+1)/segments*math.pi*2
        local p={x+math.cos(a)*r,y,z+math.sin(a)*r};local q={x+math.cos(b)*r,y,z+math.sin(b)*r}
        local s={x+math.cos(a)*topRadius,y+h,z+math.sin(a)*topRadius};local t={x+math.cos(b)*topRadius,y+h,z+math.sin(b)*topRadius}
        G.triangle(out,p,s,q,slot,color,{{i/segments,1},{i/segments,0},{(i+1)/segments,1}})
        G.triangle(out,q,s,t,slot,color,{{(i+1)/segments,1},{i/segments,0},{(i+1)/segments,0}})
        G.triangle(out,{x,y+h,z},t,s,slot,color)
    end
end
function G.beam(out,ax,ay,az,bx,by,bz,r,slot,color,sides)
    local dx,dy,dz=bx-ax,by-ay,bz-az;local length=math.max(.0001,math.sqrt(dx*dx+dy*dy+dz*dz))
    dx,dy,dz=dx/length,dy/length,dz/length
    local ux,uy,uz=math.abs(dy)>.95 and 0 or -dz,math.abs(dy)>.95 and dz or 0,math.abs(dy)>.95 and -dy or dx
    local n=math.max(.0001,math.sqrt(ux*ux+uy*uy+uz*uz));ux,uy,uz=ux/n,uy/n,uz/n
    local vx,vy,vz=dy*uz-dz*uy,dz*ux-dx*uz,dx*uy-dy*ux
    sides=sides or 6
    for i=0,sides-1 do
        local a,b=i/sides*math.pi*2,(i+1)/sides*math.pi*2
        local function point(x,y,z,angle)
            return{x+r*(ux*math.cos(angle)+vx*math.sin(angle)),y+r*(uy*math.cos(angle)+vy*math.sin(angle)),z+r*(uz*math.cos(angle)+vz*math.sin(angle))}
        end
        local p,q,s,t=point(ax,ay,az,a),point(ax,ay,az,b),point(bx,by,bz,a),point(bx,by,bz,b)
        G.triangle(out,p,s,q,slot,color);G.triangle(out,q,s,t,slot,color)
        G.triangle(out,{ax,ay,az},q,p,slot,color);G.triangle(out,{bx,by,bz},s,t,slot,color)
    end
end
function G.contactShadow(out,field,x,z,rx,rz,opacity)
    local center={x,Field.heightAt(field,x,z)+.022,z};local u,v=uv(0,.5,.5)
    for i=0,7 do
        local a,b=i/8*math.pi*2,(i+1)/8*math.pi*2
        local function point(angle)local px,pz=x+math.cos(angle)*rx,z+math.sin(angle)*rz;return{px,Field.heightAt(field,px,pz)+.022,pz}end
        add(out,center,u,v,{0,1,0},{0,0,0,opacity or .32})
        add(out,point(a),u,v,{0,1,0},{0,0,0,0});add(out,point(b),u,v,{0,1,0},{0,0,0,0})
    end
end
function G.boulder(out,x,y,z,r,height,color,rng)
    local middle,top={},{}
    for i=1,7 do
        local angle=i/7*math.pi*2;local size=r*(.86+rng()*.22)
        middle[i]={x+math.cos(angle)*size,y+height*(.35+rng()*.15),z+math.sin(angle)*size}
        top[i]={x+r*.1+math.cos(angle)*size*.56,y+height*(.80+rng()*.20),z-r*.1+math.sin(angle)*size*.56}
    end
    for i=1,7 do
        local j=i%7+1
        G.triangle(out,middle[i],top[i],middle[j],2,color);G.triangle(out,middle[j],top[i],top[j],2,color)
        G.triangle(out,top[i],{x+r*.1,y+height*.96,z-r*.1},top[j],2,color)
        G.triangle(out,middle[j],{x,y-.08,z},middle[i],2,color)
    end
end
function G.rock(out,x,y,z,r,color,rng,height)
    height=height or r
    local top={x+r*.12,y+height*.95,z-r*.13};local base={x,y-r*.12,z}
    local points={};for i=1,6 do local a=i/6*math.pi*2;local s=r*(.75+rng()*.35);points[i]={x+math.cos(a)*s,y+height*(.2+rng()*.18),z+math.sin(a)*s}end
    for i=1,6 do local p,q=points[i],points[i%6+1];G.triangle(out,p,top,q,2,color);G.triangle(out,q,base,p,2,color)end
end
local function palette(biome)
    if biome==2 then return {earth={.40,.47,.27},stone={.55,.58,.47},grass={.49,.58,.27}}end
    if biome==3 then return {earth={.64,.58,.45},stone={.62,.62,.55},grass={.47,.49,.29}}end
    if biome==4 then return {earth={.58,.57,.49},stone={.57,.61,.59},grass={.44,.46,.30}}end
    return {earth={.72,.55,.34},stone={.54,.52,.43},grass={.56,.52,.27}}
end
G.palette=palette
local wood={.47,.33,.20};local rust={.59,.37,.24};local steel={.43,.47,.44};local wall={.73,.68,.54}
function G.obstacle(out,field,o,rng,rich)
    local x,z=o.q+.5,o.r-.5;local y=Field.cellHeight(field,o.q,o.r);local kind=o.kind
    local colors=palette(field.biome)
    if kind=='ruin-wall-x'or kind=='ruin-wall-z'then
        local yaw=kind=='ruin-wall-z'and math.pi/2 or 0
        local height=1.55+((o.q*19+o.r*7+field.seed)%5)*.12
        local tint={.59,.55,.46}
        G.box(out,x,y+.28,z,1.02,.56,.30,7,tint,yaw)
        for _,dx in ipairs({-.40,.40})do
            G.box(out,x+dx*math.cos(yaw),y+.57+(height-.57)/2,z-dx*math.sin(yaw),.22,height-.57,.30,7,tint,yaw)
        end
        G.box(out,x,y+height-.12,z,1.02,.24,.30,7,tint,yaw)
        G.box(out,x,y+.60,z,1.06,.08,.38,2,colors.stone,yaw)
        if rich then
            for i=0,3 do
                local dx=-.38+i*.25
                G.box(out,x+dx*math.cos(yaw),y+height+.04+(i%2)*.05,z-dx*math.sin(yaw),.21,.12,.28,7,tint,yaw)
            end
            G.rock(out,x+.25,y,z+.28,.14,colors.stone,rng)
        end
    elseif kind=='boulders'then
        G.boulder(out,x-.12,y,z+.05,.42,1.35,colors.stone,rng);G.boulder(out,x+.29,y,z-.15,.26,.65,colors.stone,rng)
        if rich then G.rock(out,x-.30,y,z+.34,.15,colors.stone,rng)end
    elseif kind=='dead-tree'then
        G.cylinder(out,x,y,z,.11,1.7,5,wood,7,.055)
        G.beam(out,x,y+.8,z,x-.39,y+1.43,z+.08,.055,5,wood)
        G.beam(out,x,y+1.15,z,x+.32,y+1.60,z-.22,.045,5,wood)
        G.beam(out,x-.28,y+1.24,z+.06,x-.30,y+1.68,z+.14,.028,5,wood)
        if rich then
            for _,a in ipairs({0,2.1,4.2})do G.beam(out,x,y+.18,z,x+math.cos(a)*.26,y+.02,z+math.sin(a)*.26,.045,5,wood)end
            G.beam(out,x,y+1.45,z,x-.1,y+1.78,z-.24,.026,5,wood)
        end
        if field.biome==2 then
            G.boulder(out,x-.20,y+1.22,z+.08,.48,.75,colors.grass,rng)
            G.boulder(out,x+.20,y+1.35,z-.15,.43,.74,colors.grass,rng)
            G.boulder(out,x,y+1.70,z,.35,.55,colors.grass,rng)
        end
    elseif kind=='rusty-car'then
        G.box(out,x,y+.33,z,.85,.28,.93,6,rust)
        G.box(out,x,y+.60,z-.05,.68,.31,.47,6,rust)
        G.box(out,x,y+.61,z+.19,.56,.17,.018,6,{.22,.29,.27})
        G.box(out,x,y+.61,z-.29,.55,.17,.018,6,{.22,.29,.27})
        G.box(out,x,y+.79,z-.04,.72,.07,.51,6,rust)
        for _,dx in ipairs({-.40,.40})do for _,dz in ipairs({-.32,.32})do G.box(out,x+dx,y+.16,z+dz,.13,.27,.23,6,{.17,.17,.14})end end
        G.box(out,x,y+.33,z+.48,.59,.06,.03,6,steel)
        for _,dx in ipairs({-.35,.35})do
            G.box(out,x+dx,y+.61,z-.05,.018,.18,.31,6,{.17,.24,.25})
            G.box(out,x+dx,y+.42,z-.05,.018,.035,.18,6,steel)
        end
        for _,dx in ipairs({-.29,.29})do G.box(out,x+dx,y+.35,z+.487,.12,.09,.025,6,{.86,.71,.39})end
        if rich then
            for i=-2,2 do G.box(out,x+i*.055,y+.34,z+.49,.018,.10,.025,6,{.15,.18,.17})end
            for _,dx in ipairs({-.43,.43})do for _,dz in ipairs({-.32,.32})do
                G.beam(out,x+dx-.035,y+.16,z+dz,x+dx+.035,y+.16,z+dz,.125,6,{.12,.13,.12},8)
                G.box(out,x+dx*1.09,y+.16,z+dz,.02,.09,.09,6,steel)
            end end
        end
    elseif kind=='ruined-shack'then
        G.box(out,x,y+.05,z,.96,.10,.96,2,colors.stone)
        G.box(out,x-.41,y+.30,z,.15,.50,.9,7,wall)
        for _,dz in ipairs({-.35,.35})do G.box(out,x-.41,y+.77,z+dz,.15,.44,.20,7,wall)end
        G.box(out,x-.41,y+1.13,z,.15,.24,.9,7,wall)
        G.box(out,x,y+.58,z-.41,.9,1.06,.15,7,wall)
        -- Window and doorway are actual openings visible from either side.
        G.box(out,x+.40,y+.38,z-.29,.12,.66,.26,7,wall)
        G.box(out,x+.40,y+.38,z+.29,.12,.66,.26,7,wall)
        G.box(out,x+.40,y+1.02,z,.12,.24,.88,7,wall)
        for i=0,3 do G.box(out,x-.32+i*.20,y+1.28,z-.08,.10,.08,1.04,5,wood,.06*i)end
        G.rock(out,x+.18,y,z+.3,.13,colors.stone,rng)
        if rich then
            for i=0,3 do G.box(out,x-.36+i*.21,y+1.34,z-.40,.17,.10,.17,7,wall)end
            G.box(out,x-.32,y+.08,z+.24,.22,.055,.40,5,wood,.45)
            G.rock(out,x+.33,y,z+.32,.09,colors.stone,rng)
            G.box(out,x-.40,y+.54,z,.22,.065,.57,5,wood)
        end
    elseif kind=='barricade'then
        for _,dx in ipairs({-.34,.34})do G.box(out,x+dx,y+.40,z,.10,.80,.13,5,wood)end
        for i=0,2 do G.box(out,x,y+.17+i*.22,z,.93,.13,.12,5,wood,.035*i)end
        G.box(out,x,y+.36,z+.10,.8,.35,.04,6,rust,.08)
        if rich then for _,dx in ipairs({-.33,.33})do for _,dy in ipairs({.19,.60})do G.box(out,x+dx,y+dy,z+.13,.035,.035,.035,6,steel)end end end
    else
        G.box(out,x,y+.23,z,.86,.10,.83,5,wood)
        for _,dx in ipairs({-.39,.39})do G.box(out,x+dx,y+.49,z,.08,.46,.83,5,wood)end
        for _,dz in ipairs({-.38,.38})do G.box(out,x,y+.49,z+dz,.86,.46,.08,5,wood)end
        for _,dx in ipairs({-.45,.45})do G.box(out,x+dx,y+.19,z,.07,.13,.82,6,steel)end
        for _,dz in ipairs({-.44,.44})do G.box(out,x,y+.19,z+dz,.86,.13,.07,6,steel)end
        for _,dx in ipairs({-.44,.44})do G.box(out,x+dx,y+.74,z,.06,.06,.9,6,steel)end
        for _,dz in ipairs({-.43,.43})do G.box(out,x,y+.74,z+dz,.9,.06,.06,6,steel)end
        if rich then
            for _,dx in ipairs({-.44,.44})do for _,dz in ipairs({-.32,.32})do G.beam(out,x+dx-.04,y+.15,z+dz,x+dx+.04,y+.15,z+dz,.13,6,{.19,.21,.20},7)end end
            G.rock(out,x+.12,y+.28,z,.18,colors.stone,rng)
        end
    end
end
function G.ruinCell(chunk,field,site,q,r,rich)
    local x,z=q+.5,r-.5;local y=Field.cellHeight(field,q,r)
    local dx,dz=q-site.q,r-site.r
    local floor=site.style==1 and {.55,.51,.43}or{.48,.47,.42}
    G.box(chunk.props,x,y+.025,z,1.01,.05,1.01,site.style==2 and 5 or 4,floor)
    if dx==1 and dz==1 then
        -- A surviving hearth and chimney give the room a recognisable scale.
        G.box(chunk.props,x,y+.16,z,.85,.32,.80,7,{.48,.42,.34})
        G.box(chunk.props,x-.23,y+1.15,z-.2,.35,2.3,.38,7,{.54,.49,.40})
        G.box(chunk.props,x-.23,y+2.33,z-.2,.48,.12,.50,2,{.40,.40,.35})
    end
    if dz==1 and dx>0 and dx<site.w-1 and dx%2==1 then
        G.box(chunk.props,x,y+1.72,z+1,.12,.12,4.15,5,wood,.045*(site.style-1))
    end
    if rich then
        if dx>0 and dx<site.w-1 and dz>0 and dz<site.d-1 then
            for i=1,2 do
                local ox=((q*13+r*3+i*7)%11)/14-.35;local oz=((r*17+q+i*3)%13)/17-.35
                G.box(chunk.details,x+ox,y+.07,z+oz,.14,.09,.24,7,{.58,.52,.44},(q+r+i)*.71)
            end
            if (q+r)%3==0 then G.box(chunk.details,x,y+.10,z,.7,.07,.13,5,wood,.7*(q%4))end
        end
        -- Floor seams remain visible without expensive per-cell textures.
        G.box(chunk.details,x,y+.055,z,.012,.008,.98,2,{.26,.26,.23})
    end
end
function G.build(field,obstacles,quality,onlyQ,onlyR)
    local result={};local colors=palette(field.biome);local rich=quality=='high';local low=quality=='low'
    local sites=Sites.list(field)
    for q0=0,field.columns-1,G.CHUNK_SIZE do for r0=1,field.rows,G.CHUNK_SIZE do
        if (not onlyQ or onlyQ==q0)and(not onlyR or onlyR==r0)then
        local chunk={q=q0,r=r0,w=math.min(G.CHUNK_SIZE,field.columns-q0),h=math.min(G.CHUNK_SIZE,field.rows-r0+1),ground={},props={},details={},shadows={}}
        local rng=Field.random(field.seed+q0*733+r0*1601+3719)
        for q=q0,q0+chunk.w-1 do for r=r0,r0+chunk.h-1 do
            local x,z=q,r-1
            local a={x,Field.vertexHeight(field,x,z),z};local b={x+1,Field.vertexHeight(field,x+1,z),z}
            local c={x,Field.vertexHeight(field,x,z+1),z+1};local d={x+1,Field.vertexHeight(field,x+1,z+1),z+1}
            local shade=.89+.12*math.sin(x*.17+field.seed%31)*math.sin(z*.19+field.seed%113)
            local ground={colors.earth[1]*shade,colors.earth[2]*shade,colors.earth[3]*shade}
            G.triangle(chunk.ground,a,c,b,0,ground);G.triangle(chunk.ground,b,c,d,0,ground)
            local site=Sites.at(field,q,r,sites)
            if site then G.ruinCell(chunk,field,site,q,r,rich)end
            local obstacle=obstacles[q..':'..r];if obstacle then
                G.obstacle(chunk.props,field,obstacle,rng,rich)
                G.contactShadow(chunk.shadows,field,x+.60,z+.42,obstacle.kind=='dead-tree'and .60 or .70,.57,.38)
            end
            local corridor=Field.isCorridor(field,x+.5,z+.5)
            for _=1,(low and 1 or rich and 5 or 3)do
                local px,pz=x+rng(),z+rng();local y=Field.heightAt(field,px,pz)
                local road=math.abs(pz-Field.route(field,px))<.75
                if not road and not obstacle and not site then
                    local h=.09+rng()*.18;local w=.025+rng()*.04
                    G.triangle(chunk.details,{px-w,y,pz},{px+rng()*.05,y+h,pz},{px+w,y,pz},3,colors.grass)
                    G.triangle(chunk.details,{px,y,pz-w},{px,y+h*.8,pz},{px,y,pz+w},3,colors.grass)
                end
                if not low and not site and rng()<.35 then
                    local s=.018+rng()*.045;G.rock(chunk.details,px,y,pz,s,colors.stone,rng)
                end
            end
            if rich and not corridor and not obstacle and rng()<.10 then
                G.box(chunk.details,x+.2,Field.heightAt(field,x+.2,z+.3)+.03,z+.3,.24,.045,.12,6,rust,rng()*6)
            end
        end end
        result[#result+1]=chunk
        end
    end end
    return result
end
return G
