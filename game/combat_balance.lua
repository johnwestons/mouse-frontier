local Balance={}

Balance.tierOrder={"easy","medium","hard"}
Balance.tierRanges={easy={1,12},medium={13,30},hard={31,50}}

local function clamp(value,low,high)
  return math.max(low,math.min(high,value))
end

function Balance.tierFor(location)
  location=clamp(math.floor(location or 1),1,50)
  return location<=12 and "easy" or (location<=30 and "medium" or "hard")
end

function Balance.enemyProfile(location,tier)
  tier=tier or Balance.tierFor(location)
  local range=Balance.tierRanges[tier] or Balance.tierRanges.easy
  location=clamp(math.floor(location or range[1]),range[1],range[2])
  local step=location-range[1]
  if tier=="easy" then
    return {tier=tier,maxHP=10+math.floor(step/4),armor=1,aim=step>=8 and 1 or 0,move=2}
  elseif tier=="medium" then
    return {tier=tier,maxHP=16+math.floor(step/4)*2,armor=step>=12 and 3 or 2,aim=step>=12 and 3 or 2,move=2}
  end
  return {tier=tier,maxHP=26+math.floor(step/4)*2,armor=step>=12 and 5 or 4,aim=step>=12 and 4 or 3,move=3}
end

function Balance.mobCount(tier,location,roll)
  tier=tier or Balance.tierFor(location)
  local range=Balance.tierRanges[tier] or Balance.tierRanges.easy
  local progress=(clamp(location or range[1],range[1],range[2])-range[1])/math.max(1,range[2]-range[1])
  roll=roll or 1
  local groupChance= tier=="easy" and (.12+.08*progress)
    or (tier=="medium" and (.30+.20*progress) or (.50+.20*progress))
  local tripleChance=tier=="hard" and (.18+.17*progress) or 0
  if roll<tripleChance then return 3 end
  if roll<groupChance then return 2 end
  return 1
end

function Balance.rewardProfile(tier,enemyCount,defenseBattle)
  tier=tier or "easy"
  enemyCount=math.max(1,math.floor(enemyCount or 1))
  local extra=enemyCount-1
  local base={
    easy={xp=6,xpExtra=2,coal={3,5},coalExtra=1,scrap={4,8},scrapExtra=1},
    medium={xp=12,xpExtra=4,coal={4,6},coalExtra=1,scrap={6,11},scrapExtra=2},
    hard={xp=20,xpExtra=6,coal={5,8},coalExtra=2,scrap={9,15},scrapExtra=3},
  }
  local values=base[tier] or base.easy
  local defense=defenseBattle and 1 or 0
  return {
    xp=values.xp+extra*values.xpExtra+defense*8,
    coalMin=values.coal[1]+extra*values.coalExtra+defense*4,
    coalMax=values.coal[2]+extra*values.coalExtra+defense*4,
    scrapMin=values.scrap[1]+extra*values.scrapExtra+defense*8,
    scrapMax=values.scrap[2]+extra*values.scrapExtra+defense*8,
  }
end

function Balance.audit()
  local tierCounts={easy=0,medium=0,hard=0}
  for location=1,50 do tierCounts[Balance.tierFor(location)]=tierCounts[Balance.tierFor(location)]+1 end
  local easyEnd=Balance.enemyProfile(12)
  local mediumStart=Balance.enemyProfile(13)
  local mediumEnd=Balance.enemyProfile(30)
  local hardStart=Balance.enemyProfile(31)
  local hardEnd=Balance.enemyProfile(50)
  local single=Balance.rewardProfile("hard",1,false)
  local group=Balance.rewardProfile("hard",3,false)
  local countsReady=Balance.mobCount("hard",31,.10)==3 and Balance.mobCount("hard",50,.40)==2
    and Balance.mobCount("hard",50,.80)==1
  local ready=tierCounts.easy==12 and tierCounts.medium==18 and tierCounts.hard==20
    and easyEnd.maxHP==12 and mediumStart.maxHP==16 and mediumEnd.maxHP==24
    and hardStart.maxHP==26 and hardEnd.maxHP==34 and hardEnd.armor==5 and hardEnd.aim==4
    and group.xp>single.xp and group.coalMin>single.coalMin and group.scrapMin>single.scrapMin and countsReady
  return {
    ready=ready,tierCounts=tierCounts,easyEnd=easyEnd,mediumStart=mediumStart,
    mediumEnd=mediumEnd,hardStart=hardStart,hardEnd=hardEnd,
    singleHardReward=single,groupHardReward=group,countsReady=countsReady,curve="combat-v1",
  }
end

return Balance
