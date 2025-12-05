-- Microbe Mayhem: Immune System Defense (Love2D prototype)
-- Quick overview:
-- - Grid-based tower defense with innate/adaptive immune cells as towers
-- - Enemies traverse left->right; if they reach the goal, player loses health
-- - Nutrients act as resources; resting toggles faster nutrient gain
-- - Adaptive unlocks after ~25s; tumors require Cytotoxic T or NK to kill

local lg = love.graphics

local width, height = 1024, 720

-- Tunable parameters (feel free to adjust these to change difficulty)
-- - `game.nutrient_rate`: how quickly nutrients (money) accumulate per second
-- - `game.win_wave`: which wave number triggers a win when cleared
-- - `spawn_interval`: how often individual enemies spawn between waves
-- - `tower_types`: per-tower tuning: `cost`, `range`, `rate` (seconds between actions), `damage`,
--   and specialized fields like `durability` (for neutrophils) or `engulf_hp` (for macrophages)
-- - `enemy_types`: per-enemy tuning: `hp`, `speed`, `size`, and `score` (used as damage if enemy reaches goal)


-- Grid for tower placement
local grid = {
  cols = 10,
  rows = 8,
  cell = 48,
  origin_x = 80,
  origin_y = 80,
}

-- Game state
local game = {
  time = 0,
  nutrients = 50,
  nutrient_rate = 5, -- per second
  resting = false,
  wave = 1,
  enemies = {},
  towers = {},
  projectiles = {},
  particles = {},
  spawn_timer = 0,
  spawn_interval = 1.5,
  unlocked_adaptive = false,
  -- environmental factors that affect immune function (0-100)
  factors = { oxygen = 100, zinc = 100, vitD = 100, iron = 100 },
  event = nil, -- current environmental event {name, affected, multiplier, ends_at}
  health = 100,
  max_health = 100,
  state = 'playing', -- 'playing', 'won', 'lost'
  win_wave = 6,
  feedback = nil, -- { text, ends_at, color }
}

-- Tower definitions
local tower_types = {
  -- macrophage: slower, can engulf weak pathogens and help heal/clear
  macrophage = { cost = 30, range = 80, rate = 1.6, damage = 18, engulf_hp = 22, heal_on_digest = 3, nutrient_on_digest = 6, color = {0.9,0.6,0.4}, desc = "Innate: engulfs weak pathogens, AoE slow" },
  -- neutrophil: fast responder, high fire rate but short-lived (durability)
  -- tunables: `durability` = number of shots before the cell dies
  neutrophil = { cost = 20, range = 120, rate = 0.35, damage = 14, durability = 12, color = {0.8,0.8,0.6}, desc = "Innate: fast burst, short-lived" },
  tcell = { cost = 60, range = 180, rate = 0.8, damage = 30, color = {0.6,0.7,1}, desc = "Adaptive: strong projectile" },
  bcell = { cost = 70, range = 220, rate = 2.0, damage = 8, color = {1,0.7,0.9}, desc = "Adaptive: produces antibodies (particles)" },
  -- eosinophils: effective vs larger targets (fungus/parasite), cause area damage to big enemies
  -- Note: defined but special targeting vs 'fungus' not explicitly wired yet.
  eosinophil = { cost = 28, range = 100, rate = 1.0, damage = 20, effective_against = { 'fungus' }, color = {1,0.5,0.5}, desc = "Innate: targets larger parasites/fungi" },
  -- dendritic cells: capture antigens and increase chance of adaptive unlock (accelerate adaptive immunity)
  -- Note: defined but no special behavior added yet (future: speed adaptive unlock / buff).
  dendritic = { cost = 40, range = 140, rate = 3.0, color = {0.5,0.8,0.5}, desc = "Bridges innate->adaptive: speeds adaptive unlock" },
  -- helper T cells (CD4+): buff other adaptive cells (reduce their cooldown)
  -- Note: defined; future: apply local cooldown multiplier to adaptive towers in range.
  helper_tcell = { cost = 80, range = 220, rate = 3.5, buff = 0.85, color = {0.4,0.8,1}, desc = "Adaptive helper: buffs other adaptive cells' rate" },
  -- cytotoxic T cells (CD8+): kill infected/cancerous cells (required for tumor enemies)
  cytotoxic_tcell = { cost = 100, range = 200, rate = 0.9, damage = 50, color = {0.7,0.2,0.7}, desc = "Adaptive cytotoxic: kills tumor/infected cells" },
  -- regulatory T cells: suppress excessive immune reactions (reduce buff/overactivity)
  -- Note: defined; future: reduce helper buffs or slow nearby towers slightly.
  regulatory_tcell = { cost = 60, range = 200, rate = 4.0, suppress = 0.9, color = {0.6,0.6,0.9}, desc = "Suppresses excessive immune responses" },
  -- natural killer cells: innate killers that can also remove tumor cells without prior sensitization
  nk = { cost = 90, range = 160, rate = 0.7, damage = 40, color = {0.9,0.4,0.4}, desc = "Innate killer: removes virus-infected and tumor cells" },
}

local selected_tower = 'macrophage'

-- Enemy definitions
local enemy_types = {
  -- enemy speeds are tunable: lower speeds make the game easier
  bacteria = { hp = 40, speed = 30, color = {0.2,0.9,0.2}, size = 18, score = 5 },
  virus = { hp = 25, speed = 60, color = {0.9,0.2,0.2}, size = 12, score = 8 },
  fungus = { hp = 80, speed = 20, color = {0.6,0.3,0.7}, size = 22, score = 12 },
}

-- Utilities
local function clamp(x,a,b) return math.max(a, math.min(b,x)) end

local function world_to_cell(x,y)
  local gx = math.floor((x - grid.origin_x) / grid.cell) + 1
  local gy = math.floor((y - grid.origin_y) / grid.cell) + 1
  return gx, gy
end

local function cell_to_world(cx, cy)
  local x = grid.origin_x + (cx-1) * grid.cell + grid.cell/2
  local y = grid.origin_y + (cy-1) * grid.cell + grid.cell/2
  return x, y
end

-- Build a short info list for the currently selected tower type
local function get_selected_info()
  local ty = tower_types[selected_tower]
  if not ty then return { "Selected: " .. tostring(selected_tower) } end
  local lines = {}
  table.insert(lines, string.format("%s — %s", selected_tower, ty.desc or ""))
  table.insert(lines, string.format("Cost: %d  Range: %d  Rate: %.2fs", ty.cost or 0, ty.range or 0, ty.rate or 0))
  if ty.damage then table.insert(lines, string.format("Damage: %d", ty.damage)) end
  if ty.engulf_hp then table.insert(lines, string.format("Engulfs ≤ %d HP", ty.engulf_hp)) end
  if ty.durability then table.insert(lines, string.format("Durability: %d shots", ty.durability)) end
  if ty.buff then table.insert(lines, string.format("Buff: x%.2f cooldown for nearby adaptive", ty.buff)) end
  if ty.suppress then table.insert(lines, string.format("Suppress: x%.2f reduce overactivity", ty.suppress)) end
  if selected_tower == 'cytotoxic_tcell' or selected_tower == 'nk' then
    table.insert(lines, "Special: Can damage tumor enemies")
  end
  return lines
end

-- Spawn path: enemies enter from left, head to right goal
local goal_x = width - 120
local spawn_x = 20
local path_y = height/2
-- Define a more interesting polyline path enemies will follow
-- Orthogonal path aligned roughly with the placement grid
local function grid_center(cx, cy)
  local x = grid.origin_x + (cx-1)*grid.cell + grid.cell/2
  local y = grid.origin_y + (cy-1)*grid.cell + grid.cell/2
  return x, y
end
local path_points = {
  { x = spawn_x, y = select(2, grid_center(1, 2)) },
  (function() local x,y=grid_center(2,2); return {x=x,y=y} end)(),
  (function() local x,y=grid_center(5,2); return {x=x,y=y} end)(),
  (function() local x,y=grid_center(5,4); return {x=x,y=y} end)(),
  (function() local x,y=grid_center(7,4); return {x=x,y=y} end)(),
  (function() local x,y=grid_center(7,6); return {x=x,y=y} end)(),
  { x = goal_x, y = select(2, grid_center(grid.cols, 6)) },
}
-- Placement safety: disallow towers on/near the path within a corridor radius
-- Corridor radius scales with grid cell size so visuals/placement match
local path_corridor_radius = math.floor(grid.cell * 0.6)
local function dist2_point_segment(px, py, ax, ay, bx, by)
  local vx, vy = bx - ax, by - ay
  local wx, wy = px - ax, py - ay
  local vv = vx*vx + vy*vy
  local t = vv > 0 and math.max(0, math.min(1, (wx*vx + wy*vy) / vv)) or 0
  local cx, cy = ax + t*vx, ay + t*vy
  local dx, dy = px - cx, py - cy
  return dx*dx + dy*dy
end
local function is_point_near_path(px, py, radius)
  local r2 = (radius or path_corridor_radius)^2
  for i=1,#path_points-1 do
    local a = path_points[i]
    local b = path_points[i+1]
    if dist2_point_segment(px, py, a.x, a.y, b.x, b.y) <= r2 then return true end
  end
  return false
end

-- Game functions
-- Spawn a single enemy of a given kind.
-- If forceTumor=true, mark it as a tumor (only Cytotoxic/NK can damage).
local function spawn_enemy(kind, forceTumor)
  local def = enemy_types[kind]
  local e = {
    kind = kind,
    hp = def.hp,
    maxhp = def.hp,
    speed = def.speed,
    x = path_points[1].x,
    y = path_points[1].y + (math.random()-0.5)*30,
    size = def.size,
    color = def.color,
    reached = false,
      -- small chance an enemy is a tumor-like cell that only cytotoxic T cells / NK can kill
      tumor = (forceTumor and true) or (math.random() < 0.02),
      wp = 2, -- next waypoint index to move toward
    }
    if e.tumor then e.color = {0.6,0,0.6}; e.size = math.max(10, e.size-2) end
  table.insert(game.enemies, e)
end

local function spawn_wave()
  local n = 6 + math.floor(game.wave * 1.5)
  for i=1,n do
    local r = math.random()
    if r < 0.55 then spawn_enemy('bacteria')
    elseif r < 0.85 then spawn_enemy('virus')
    else spawn_enemy('fungus') end
  end
  game.wave = game.wave + 1
end

local function place_tower_at(mousex, mousey)
  local cx, cy = world_to_cell(mousex, mousey)
  if cx < 1 or cy < 1 or cx > grid.cols or cy > grid.rows then return end
  -- check not occupied
  for _,t in ipairs(game.towers) do
    if t.cx == cx and t.cy == cy then return end
  end
  local ty = tower_types[selected_tower]
  if game.nutrients < ty.cost then return end
  local x,y = cell_to_world(cx,cy)
  -- disallow placing towers on/near the enemy path
  if is_point_near_path(x, y, path_corridor_radius + 20) then
    game.feedback = { text = "Cannot place on bloodstream path", ends_at = game.time + 1.3, color = {1,0.4,0.4} }
    return
  end
  game.nutrients = game.nutrients - ty.cost
  local t = { type = selected_tower, cx = cx, cy = cy, x = x, y = y, def = ty, cooldown = 0 }
  if ty.durability then t.durability = ty.durability end
  table.insert(game.towers, t)
end

-- Apply damage to an enemy. Returns true if damage was applied, false if blocked.
-- owner: optional string ('cytotoxic_tcell'|'nk') used for tumor-only damage rules.
local function damage_enemy(e, dmg, owner)
  -- owner: optional string identifying which cell type dealt damage (e.g., 'cytotoxic_tcell', 'nk')
  -- tumor enemies can only be damaged by cytotoxic T cells or NK cells
  if e.tumor then
    if not owner or not (owner == 'cytotoxic_tcell' or owner == 'nk') then
      return false
    end
  end
  e.hp = e.hp - dmg
  -- spawn particles
  for i=1,6 do
    local p = { x = e.x + (math.random()-0.5)*e.size, y = e.y + (math.random()-0.5)*e.size, vx = (math.random()-0.5)*60, vy = (math.random()-0.5)*60, t = 0.6 }
    table.insert(game.particles, p)
  end
  return true
end

-- Projectiles
-- Fire a projectile toward (tx,ty). Projectiles carry optional 'owner' for tumor rules.
local function fire_projectile(sx, sy, tx, ty, speed, damage, owner)
  -- LuaJIT (used by LÖVE) provides math.atan2; computes angle from source to target.
  local ang = math.atan2(ty - sy, tx - sx)
  local p = { x = sx, y = sy, vx = math.cos(ang)*speed, vy = math.sin(ang)*speed, damage = damage, t = 5, owner = owner }
  table.insert(game.projectiles, p)
end

-- Update
function love.load()
  lg.setDefaultFilter('nearest','nearest')
  love.window.setMode(width, height)
  math.randomseed(os.time())
  -- initial wave
  spawn_wave()
end

function love.update(dt)
  game.time = game.time + dt
  -- nutrient accumulation
  local rate = game.nutrient_rate * (game.resting and 1.8 or 1)
  game.nutrients = game.nutrients + rate * dt

  -- unlock adaptive immunity after 25 seconds
  if not game.unlocked_adaptive and game.time > 25 then game.unlocked_adaptive = true end

  -- spawn handling
  game.spawn_timer = game.spawn_timer + dt
  if game.spawn_timer >= game.spawn_interval then
    game.spawn_timer = game.spawn_timer - game.spawn_interval
    -- spawn a single enemy occasionally between waves to keep action
    local r = math.random()
    if r < 0.5 then spawn_enemy('bacteria') elseif r < 0.8 then spawn_enemy('virus') else spawn_enemy('fungus') end
  end

  -- update enemies
  for i=#game.enemies,1,-1 do
    local e = game.enemies[i]
    -- Move along polyline waypoints
    local wp = path_points[e.wp]
    if wp then
      local dx = wp.x - e.x
      local dy = wp.y - e.y
      local dist = math.sqrt(dx*dx+dy*dy)
      if dist > 1 then
        e.x = e.x + (dx/dist) * e.speed * dt
        e.y = e.y + (dy/dist) * e.speed * dt
      else
        e.wp = e.wp + 1
      end
    else
      -- enemy reached the goal: damage player and remove enemy
      local dmg = enemy_types[e.kind] and enemy_types[e.kind].score or 5
      game.health = game.health - dmg
      table.remove(game.enemies, i)
    end
    if e.hp and e.hp <= 0 then table.remove(game.enemies, i) end
  end

  -- update towers
  if game.state == 'playing' then
    for _,t in ipairs(game.towers) do
      t.cooldown = t.cooldown - dt
      if t.cooldown <= 0 then
        -- find target
        local best, bd = nil, 1e9
        for _,e in ipairs(game.enemies) do
          local dx = e.x - t.x
          local dy = e.y - t.y
          local d = math.sqrt(dx*dx+dy*dy)
          if d <= t.def.range then
            if t.type == 'macrophage' then
              -- macrophage: try to engulf weak pathogens first
              if e.hp <= (t.def.engulf_hp or 0) then
                -- engulf: remove enemy, grant nutrients and small heal
                -- sanitize tunable values to avoid accidental negative heals or non-numbers
                local nutrients_gain = tonumber(t.def.nutrient_on_digest) or 4
                if nutrients_gain < 0 then nutrients_gain = 0 end
                game.nutrients = game.nutrients + nutrients_gain
                local heal_amount = tonumber(t.def.heal_on_digest) or 1
                if heal_amount < 0 then heal_amount = 0 end
                game.health = math.min(game.max_health, (tonumber(game.health) or 0) + heal_amount)
                -- spawn a digestion particle burst
                for k=1,10 do table.insert(game.particles, { x = e.x + (math.random()-0.5)*e.size, y = e.y + (math.random()-0.5)*e.size, vx = (math.random()-0.5)*40, vy = (math.random()-0.5)*40, t = 0.8 }) end
                -- remove the enemy
                for j=#game.enemies,1,-1 do if game.enemies[j] == e then table.remove(game.enemies,j); break end end
                t.cooldown = t.def.rate
                break
              else
                -- AoE: damage and slight slow to nearby
                damage_enemy(e, t.def.damage)
                for _,o in ipairs(game.enemies) do
                  local dx2 = o.x - e.x
                  local dy2 = o.y - e.y
                  local dd = math.sqrt(dx2*dx2+dy2*dy2)
                  -- Guard dd>0 to avoid division by zero / NaN when overlapping
                  if dd > 0 and dd < 40 then
                    o.x = o.x - (dx2/dd) * 4
                  end
                end
                t.cooldown = t.def.rate
                break
              end
            elseif t.type == 'neutrophil' then
              if d < bd then best, bd = e, d end
            elseif t.type == 'tcell' then
              best = e; break
            elseif t.type == 'bcell' then
              -- bcell: spawn antibodies (particle projectiles)
              for i=1,2 do
                local ang = math.random()*math.pi*2
                local px = t.x + math.cos(ang)*10
                local py = t.y + math.sin(ang)*10
                fire_projectile(px,py,t.x + math.cos(ang)*100, t.y + math.sin(ang)*100, 120, t.def.damage)
              end
              t.cooldown = t.def.rate
              break
            elseif t.type == 'cytotoxic_tcell' or t.type == 'nk' then
              if d < bd then best, bd = e, d end
            end
          end
        end
        if best and t.type == 'neutrophil' then
          fire_projectile(t.x, t.y, best.x, best.y, 320, t.def.damage)
          t.cooldown = t.def.rate
          -- neutrophils are short-lived: reduce durability per shot
          if t.durability then
            t.durability = t.durability - 1
            if t.durability <= 0 then t.remove = true end
          end
        elseif best and t.type == 'tcell' then
          fire_projectile(t.x, t.y, best.x, best.y, 380, t.def.damage)
          t.cooldown = t.def.rate
        elseif best and t.type == 'cytotoxic_tcell' then
          fire_projectile(t.x, t.y, best.x, best.y, 380, t.def.damage, 'cytotoxic_tcell')
          t.cooldown = t.def.rate
        elseif best and t.type == 'nk' then
          fire_projectile(t.x, t.y, best.x, best.y, 360, t.def.damage, 'nk')
          t.cooldown = t.def.rate
        end
      end
    end


    -- remove expired towers (e.g., neutrophils that exhausted durability)
    for i=#game.towers,1,-1 do
      if game.towers[i].remove then
        -- spawn a small particle puff to indicate cell death
        local tt = game.towers[i]
        for k=1,8 do table.insert(game.particles, { x = tt.x + (math.random()-0.5)*12, y = tt.y + (math.random()-0.5)*12, vx = (math.random()-0.5)*30, vy = (math.random()-0.5)*30, t = 0.6 }) end
        table.remove(game.towers, i)
      end
    end
  end

  -- update projectiles
  for i=#game.projectiles,1,-1 do
    local p = game.projectiles[i]
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.t = p.t - dt
    -- collision with enemies
    for j=#game.enemies,1,-1 do
      local e = game.enemies[j]
      local dx = e.x - p.x
      local dy = e.y - p.y
      if dx*dx + dy*dy < (e.size+4)^2 then
        local applied = damage_enemy(e, p.damage, p.owner)
        if applied then
          table.remove(game.projectiles, i)
        else
          -- projectile had no effect (e.g., tumor vs non-cytotoxic projectile); let it pass through
        end
        break
      end
    end
    if p.t <= 0 then table.remove(game.projectiles, i) end
  end

  -- check win / loss
  if game.health <= 0 and game.state == 'playing' then
    game.state = 'lost'
  end
  if game.state == 'playing' and game.wave > game.win_wave and #game.enemies == 0 then
    game.state = 'won'
  end
  -- update particles
  for i=#game.particles,1,-1 do
    local p = game.particles[i]
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.t = p.t - dt
    if p.t <= 0 then table.remove(game.particles, i) end
  end
end

function love.mousepressed(x,y,b)
  if game.state ~= 'playing' then return end
  if b == 1 then
    place_tower_at(x,y)
  elseif b == 2 then
    game.resting = not game.resting
  end
end

function love.keypressed(k)
  if k == 'r' then
    -- restart
    game.time = 0
    game.nutrients = 50
    game.resting = false
    game.wave = 1
    game.enemies = {}
    game.towers = {}
    game.projectiles = {}
    game.particles = {}
    game.spawn_timer = 0
    game.unlocked_adaptive = false
    game.health = game.max_health
    game.state = 'playing'
    spawn_wave()
    return
  end
  if game.state ~= 'playing' then return end
  if k == '1' then selected_tower = 'macrophage' end
  if k == '2' then selected_tower = 'neutrophil' end
  if k == '3' and game.unlocked_adaptive then selected_tower = 'tcell' end
  if k == '4' and game.unlocked_adaptive then selected_tower = 'bcell' end
  if k == '5' and game.unlocked_adaptive then selected_tower = 'cytotoxic_tcell' end
  if k == '6' then selected_tower = 'nk' end
  if k == 'space' then spawn_wave() end
  -- Debug: spawn tumor enemies (t = one, Shift+t = five)
  if k == 't' then
    local count = 1
    if love.keyboard.isDown('lshift','rshift') then count = 5 end
    for i=1,count do
      local kinds = { 'bacteria','virus','fungus' }
      local kind = kinds[math.random(#kinds)]
      spawn_enemy(kind, true)
    end
  end
end

function love.draw()
  lg.clear(0.08,0.08,0.12)

  -- draw grid
  for cx=1,grid.cols do
    for cy=1,grid.rows do
      local x = grid.origin_x + (cx-1)*grid.cell
      local y = grid.origin_y + (cy-1)*grid.cell
      lg.setColor(0.15,0.15,0.18)
      lg.rectangle('fill', x, y, grid.cell-2, grid.cell-2)
      lg.setColor(0.1,0.1,0.12)
      lg.rectangle('line', x, y, grid.cell-2, grid.cell-2)
    end
  end

  -- draw towers
  for _,t in ipairs(game.towers) do
    lg.setColor(t.def.color)
    lg.circle('fill', t.x, t.y, 18)
    lg.setColor(1,1,1,0.08)
    lg.circle('fill', t.x, t.y, t.def.range)
  end

  -- draw enemies
  for _,e in ipairs(game.enemies) do
    lg.setColor(e.color)
    lg.circle('fill', e.x, e.y, e.size)
    -- hp bar
    lg.setColor(0,0,0)
    lg.rectangle('fill', e.x - e.size, e.y - e.size - 8, e.size*2, 5)
    lg.setColor(0.2,1,0.2)
    local pct = clamp(e.hp / e.maxhp, 0, 1)
    lg.rectangle('fill', e.x - e.size, e.y - e.size - 8, e.size*2 * pct, 5)
  end

  -- draw projectiles
  for _,p in ipairs(game.projectiles) do
    lg.setColor(1,1,0.6)
    lg.circle('fill', p.x, p.y, 4)
  end

  -- particles
  for _,p in ipairs(game.particles) do
    lg.setColor(1,0.8,0.6, clamp(p.t*2,0,1))
    lg.rectangle('fill', p.x, p.y, 3,3)
  end

  -- UI
  lg.setColor(1,1,1)
  local uiY = height - 140
  lg.print(string.format("Time: %.1fs", game.time), 12, uiY)
  lg.print(string.format("Nutrients: %d", math.floor(game.nutrients)), 12, uiY + 20)
  lg.print(string.format("Wave: %d", game.wave-1), 12, uiY + 40)
  lg.print(string.format("Health: %d/%d", math.max(0, math.floor(game.health)), game.max_health), 12, uiY + 60)
  lg.print("Resting (right-click): " .. (game.resting and "ON" or "OFF"), 12, uiY + 80)
  lg.print("Selected: " .. selected_tower, 12, uiY + 100)
  lg.print("Keys: 1 macrophage, 2 neutrophil, 3 T-cell, 4 B-cell (adaptive in ~25s)", 12, uiY + 120)
  lg.print("5 Cytotoxic T (adaptive), 6 NK; T: spawn tumor (Shift=T x5)", 12, uiY + 140)
  lg.print("Click grid to place tower. Space to spawn wave.", 12, uiY + 160)
  lg.print("Tumors: only Cytotoxic T (5) or NK (6) can kill them.", 12, uiY + 180)

  -- Selected tower info panel (right side)
  local info = get_selected_info()
  local panelX = width - 360
  local panelY = height - (#info*22 + 24) - 20
  lg.setColor(0,0,0,0.35)
  lg.rectangle('fill', panelX-12, panelY-12, 332, #info*22 + 24, 8)
  lg.setColor(1,1,1)
  for i,ln in ipairs(info) do
    lg.print(ln, panelX, panelY + (i-1)*22)
  end

  -- Placement feedback toast
  if game.feedback and game.time < (game.feedback.ends_at or 0) then
    local alpha = math.max(0, math.min(1, (game.feedback.ends_at - game.time)))
    lg.setColor(0,0,0, 0.5*alpha)
    local fw = 360
    local fh = 38
    local fx = (width - fw)/2
    local fy = height - 90
    lg.rectangle('fill', fx, fy, fw, fh, 8)
    local c = game.feedback.color or {1,1,1}
    lg.setColor(c[1], c[2], c[3], alpha)
    lg.printf(game.feedback.text or "", fx, fy + 10, fw, 'center')
  else
    game.feedback = nil
  end

  if not game.unlocked_adaptive then
    lg.setColor(1,1,1,0.6)
    lg.print("Adaptive immunity will unlock shortly...", width - 320, 12)
  end

  -- Draw the path polyline and corridor
  lg.setColor(0.25,0.3,0.4,0.25)
  for i=1,#path_points-1 do
    local a = path_points[i]
    local b = path_points[i+1]
    -- draw corridor as thick line approximation
    lg.setLineWidth(path_corridor_radius*2)
    lg.line(a.x, a.y, b.x, b.y)
  end
  lg.setLineWidth(1)
  lg.setColor(0.7,0.85,1,0.6)
  for i=1,#path_points-1 do
    local a = path_points[i]
    local b = path_points[i+1]
    lg.line(a.x, a.y, b.x, b.y)
  end

  -- End screens
  if game.state == 'lost' then
    lg.setColor(0,0,0,0.6)
    lg.rectangle('fill', 0, 0, width, height)
    lg.setColor(1,0.2,0.2)
    lg.printf("GAME OVER", 0, height/2 - 40, width, 'center')
    lg.setColor(1,1,1)
    lg.printf("Press R to restart", 0, height/2 + 10, width, 'center')
  elseif game.state == 'won' then
    lg.setColor(0,0,0,0.6)
    lg.rectangle('fill', 0, 0, width, height)
    lg.setColor(0.4,1,0.4)
    lg.printf("YOU WIN!", 0, height/2 - 40, width, 'center')
    lg.setColor(1,1,1)
    lg.printf("Press R to play again", 0, height/2 + 10, width, 'center')
  end
end