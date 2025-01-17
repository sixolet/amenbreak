-- amenbreak v1.3.0
--
--
-- amen+break
--
--
--
--    ▼ instructions below ▼
--
-- ef-it: K2+K3
-- in performance mode:
-- K1 switches to edit mode
-- K2 switches parameters
-- K3 stops/starts
-- E1 changes volume
-- E2 changes amen/track
-- E3 changes break/punch
-- in edit mode:
-- K1 switches to performance
-- K2 select slice
-- K3 auditions slice
-- E1 changes kick
-- E2 zooms
-- E3 jogs slice

if not string.find(package.cpath,"/home/we/dust/code/amenbreak/lib/") then
  package.cpath=package.cpath..";/home/we/dust/code/amenbreak/lib/?.so"
end
json=require("cjson")
include("lib/utils")
musicutil=require("musicutil")
sample_=include("lib/sample")
ggrid_=include("lib/ggrid")
loop_=include("lib/loop")

pos_last=0
param_switch=true
performance=true
debounce_fn={}
osc_fun={}
lfos={0,0,0,0}
screen_fade_in=15
posit={
  beg=1,
  inc={1},
dur={1}}
initital_monitor_level=0
loops={}

-- global constants (for grid)
PTTRN_STEP=1
PTTRN_AMEN=2
PTTRN_BREK=3
PTTRN_DRUM=4
PTTRN_PNCH=5
PTTRN_NAME={"STEP","BREK","AMEN","DRUM","PNCH","NAME"}
PTTRN_FUNS={
  function(v) end,
  function(v) params:set_raw("break",v) end,
  function(v) params:set_raw("amen",v) end,
  function(v) params:set_raw("track",v) end,
  function(v) params:set_raw("punch",v) end,
}
pattern_store={}
pattern_current={0,0,0,0,0,0,0}
button_fns={}
global_played={}
bass_pattern_store={}
bass_pattern_current=0
bass_sequenced=-1

UI=require 'ui'
loaded_files=0
Needs_Restart=false
Engine_Exists=(util.file_exists('/home/we/.local/share/SuperCollider/Extensions/supercollider-plugins/AnalogTape_scsynth.so') or util.file_exists("/home/we/.local/share/SuperCollider/Extensions/PortedPlugins/AnalogTape_scsynth.so"))
engine.name=Engine_Exists and 'AmenBreak1' or nil

-- other stuff
function init()
  os.execute("mkdir -p ".._path.data.."amenbreak/resampled/")
  Needs_Restart=false
  Data_Exists=util.file_exists(_path.data.."amenbreak/dats/")
  if (not Data_Exists) or (not Engine_Exists) then
    clock.run(function()
      if not Data_Exists then
        Needs_Restart=true
        os.execute("mkdir -p ".._path.data.."amenbreak/dats/")
        os.execute("mkdir -p ".._path.data.."amenbreak/cursors/")
        os.execute("mkdir -p ".._path.data.."amenbreak/pngs/")
        -- run installer
        Restart_Message=UI.Message.new{"installing amen audio...","(this takes awhile)"}
        redraw()
        clock.sleep(1)
        print("[amenbreak] INSTALLING PLEASE WAIT!!")
        os.execute(_path.code.."amenbreak/lib/install.sh")
      end
      if not Engine_Exists then
        Needs_Restart=true
        Restart_Message=UI.Message.new{"installing tapedeck..."}
        redraw()
        clock.sleep(1)
        os.execute("cd /tmp && wget https://github.com/schollz/tapedeck/releases/download/PortedPlugins/PortedPlugins.tar.gz && tar -xvzf PortedPlugins.tar.gz && rm PortedPlugins.tar.gz && sudo rsync -avrP PortedPlugins /home/we/.local/share/SuperCollider/Extensions/")
      end
      Restart_Message=UI.Message.new{"please restart norns."}
      redraw()
      clock.sleep(1)
      do return end
    end)
    do return end
  end
  -- rest of init()
  show_message("loading...")
  redraw()

  -- setup patterns
  -- empty patterns means to ignore settings
  for row=1,8 do 
    table.insert(pattern_store,{})
    for col=1,11 do 
      table.insert(pattern_store[row],{})
    end
  end
  for col=1,6 do 
    table.insert(bass_pattern_store,{})
  end
  -- pattern_store[PTTRN_STEP][1]={1,2,3,4}
  -- pattern_current[PTTRN_STEP]=1

  initital_monitor_level=params:get('monitor_level')
  params:set('monitor_level',-math.huge)
  debounce_fn["startup"]={30,function()end}
  os.execute(_path.code.."amenbreak/lib/oscnotify/run.sh &")

  -- find all the amen files
  amen_files={}
  for _,fname in ipairs(util.scandir(_path.audio.."amenbreak")) do
    if not string.find(fname,"slow") then
      if util.file_exists(_path.audio.."amenbreak/"..fname..".json") then
        table.insert(amen_files,fname)
        -- if #amen_files==10 then
        --   break
        -- end
      end
    end
  end
  table.sort(amen_files)
  print(string.format("[amenbreak] found %s files",#amen_files))

  -- choose audiowaveform binary
  audiowaveform="audiowaveform"
  local foo=util.os_capture(audiowaveform.." --help")
  if not string.find(foo,"Options") then
    audiowaveform="/home/we/dust/code/amenbreak/lib/audiowaveform"
  end


  -- load audio file loops
  loops = {}
  for row=1,5 do 
    loops[row]={}
    local folder=_path.audio.."amenbreak/row"..row
    os.execute("mkdir -p "..folder)
    for col=1,8 do 
      table.insert(loops[row],loop_:new{row=row})
    end
    for i,fname in ipairs(find_files(folder)) do 
      if i<=8 then 
        loops[row][i]:load_sample(fname)
      end
    end
  end


  -- add major parameters
  params_grid()
  params_kick()
  params_audioin()
  params_audioout()
  params_action()
  -- params:default()

  local params_menu={
    {id="db",name="volume",min=-96,max=12,exp=false,div=0.1,default=-6,unit="db"},
    {id="punch",name="punch",min=0,max=1,exp=false,div=0.01,default=0,unit="punches"},
    {id="amen",name="amen",min=0,max=1,exp=false,div=0.01,default=0,unit="amens"},
    {id="break",name="break",min=0,max=1,exp=false,div=0.01,default=0,unit="break"},
    {id="efit",name="efit",min=0,max=1,exp=false,div=1,default=0,response=1,formatter=function(param) return param:get()==1 and "yes" or "no" end},
    {id="track",name="sample",min=1,max=#amen_files,exp=false,div=1,default=1,formatter=function(param) return math.floor(param:get()) end},
    {id="probability",name="probability",hide=true,min=0,max=100,exp=false,div=1,default=100,unit="%"},
    {id="pan",name="pan",min=-1,max=1,exp=false,div=0.01,default=0},
    {id="lpf",name="lpf",min=24,max=135,exp=false,div=0.5,default=135,formatter=function(param) return musicutil.note_num_to_name(math.floor(param:get()),true)end},
    {id="res",name="res",min=0.01,max=1,exp=false,div=0.01,default=0.71},
    {id="attack",name="attack",min=0,max=100,exp=false,div=1,default=5,unit="ms"},
    {id="release",name="release",min=0,max=200,exp=false,div=1,default=15,unit="ms"},
    {id="hold",name="hold",min=0,max=128,exp=false,div=1,default=0,unit="pulses"},
    {id="decimate",name="decimate",min=0,max=0.4,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%d%%",util.round(100*param:get())) end},
    {id="drive",name="drive",min=0,max=0.75,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%d%%",util.round(100*param:get())) end},
    {id="compression",name="compression",min=0,max=0.4,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%d%%",util.round(100*param:get())) end},
    {id="pitch",name="note",min=-24,max=24,exp=false,div=0.1,default=0.0,response=1,formatter=function(param) return string.format("%s%2.1f",param:get()>-0.01 and "+" or "",param:get()) end},
    {id="gate",name="gate",min=0.1,max=1,exp=false,div=0.01,default=1.0,response=1,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="rate",name="rate",min=-2,max=2,exp=false,div=0.01,default=1.0,response=1,formatter=function(param) return string.format("%s%2.1f",param:get()>-0.01 and "+" or "",param:get()*100) end},
    {id="rotate",name="rotate",hide=true,min=-127,max=127,exp=false,div=1,default=0.0,response=1,formatter=function(param) return string.format("%s%2.0f",param:get()>-0.01 and "+" or "",param:get()) end},
    {id="stretch",name="stretch",min=0,max=5,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="compressing",name="compressing",min=0,max=1,exp=false,div=1,default=0.0,response=1,formatter=function(param) return param:get()==1 and "yes" or "no" end},
    {id="compressible",name="compressible",min=0,max=1,exp=false,div=1,default=1,response=1,formatter=function(param) return param:get()==1 and "yes" or "no" end},
    {id="send_reverb",name="reverb send",min=0,max=1,hide=true,exp=false,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="send_delay",name="delay send",min=0,max=1,exp=false,hide=true,div=0.01,default=0.0,response=1,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
  }
  for _,pram in ipairs(params_menu) do
    params:add{
      type="control",
      id=pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=pram.formatter,
    }
    if pram.hide then
      params:hide(pram.id)
    end
    if pram.id=="lpf" then 
      params:set_action(pram.id,function(x)
        engine.filter_set(musicutil.note_num_to_freq(x),clock.get_beat_sec()*math.random(1,4))
      end)
    end
  end
  params:add_separator("current sample")
  params:set_action("track",function(x)
    for i=1,#amen_files do
      ws[i]:select(x==i)
    end
  end)
  params:set_action("punch",function(x)
    params:set_raw("drive",easing_function(x,0.1,2))
    params:set_raw("compression",easing_function(x,5.4,4))
    params:set_raw("decimate",easing_function(x,8.8,12))
    params:set_raw("lpf",easing_function(x,-5.5,10)+0.25)
    params:set_raw("sine_drive",easing_function2(x,3.5,-0.1,0.095,0.5))
  end)

  -- setup ws
  ws={}

  for i=1,#amen_files do
    table.insert(ws,sample_:new{id=i})
  end

  -- bang params
  params:bang()

  efit_lfos={
    "punch",
    "amen",
    "break",
  }
  -- setup osc
  osc_fun={
    loopdone=function(args)
      print("loopdone")
      tab.print(args)
      for row=1,5 do 
        for col=1,8 do 
          if loops[row][col].loaded then 
            if loops[row][col].path==args[1] then 
              loops[row][col].playing=false
              loops[row][col].primed=false
            end
          end
        end
      end
    end,
    progressbar=function(args)
      show_message(args[1])
      show_progress(tonumber(args[2]))
    end,
    progress=function(args)
      ws[params:get("track")]:set_position(tonumber(args[1]))
    end,
    oscnotify=function(args)
      print("file edited ok!")
      rerun()
    end,
    lfos=function(args)
      local i=math.floor(tonumber(args[1]))+1
      local v=tonumber(args[2])
      lfos[i]=v
      if params:get("efit")==1 and i<4 then
        params:set_raw(efit_lfos[i],v)
      end
    end,
    aubiodone=function(args)
      local id=tonumber(args[1])
      local data_s=args[2]
      ws[params:get("track")]:got_onsets(data_s)
    end,
  }
  osc.event=function(path,args,from)
    if string.sub(path,1,1)=="/" then
      path=string.sub(path,2)
    end
    if osc_fun[path]~=nil then osc_fun[path](args) else
      -- print("osc.event: '"..path.."' ?")
    end
  end

  -- start redrawing clock
  clock.run(function()
    while true do
      debounce_params()
      clock.sleep(1/15)
      redraw()
    end
  end)

  -- listen to all the midi devices for startups
  for i,dev in pairs(midi.devices) do
    if dev.port~=nil then
      local conn=midi.connect(dev.port)
      conn.event=function(data)
        local msg=midi.to_msg(data)
        if msg.type=="clock" then
          do return end
        end
        -- OP-1 fix for transport
        if msg.type=='start' or msg.type=='continue' then
          toggle_clock(true)
        elseif msg.type=="stop" then
          toggle_clock(false)
        end
      end
    end
  end


  -- setup
  params:set("loop1_db",0)
  params:set("loop1_slew",0.05)
  params:set("loop1_oneshot",1)
  -- debug
  clock.run(function()
    -- startup
    loading_screen=true
    for i,v in ipairs(amen_files) do
      params:set(i.."sample_file",_path.audio.."amenbreak/"..v)
      loaded_files=i/#amen_files*100
      show_message(string.format("loading %2.0f%%...",loaded_files))
      show_progress(loaded_files)
      clock.sleep(0.001)
    end
    show_message_text=nil
    loading_screen=false
      -- grid
      g_=ggrid_:new()
      clock.sleep(1)
    params:set("punch",0.3)
    tab.print(loops[1][1])
    -- toggle_clock(true)
  end)
end

toggling_clock=false

function clock.transport.start()
  if clock_run==nil then
    toggle_clock(true)
  end
end

function clock.transport.stop()
  if clock_run~=nil then
    toggle_clock(false)
  end
end

-- https://www.desmos.com/calculator/oimuzwwcop
function easing_function(x,k,n)
  return (math.exp(k*x)-1)/((math.exp(k)-1)*4)*
  math.cos(2*3.14159*x*n)+
  (math.exp(k*x)-1)*0.75/(math.exp(k)-1)
end

-- https://www.desmos.com/calculator/3mmmijzncm
function easing_function2(x,k,a,t,u)
  return math.abs(math.tanh(
    a*math.exp(
    -1*(x-u)^2/(2*t^2))+
  (math.exp(k*x)-1)/(math.exp(k)-1)))
end

-- https://www.desmos.com/calculator/evz8ulsg7v
function easing_function3(x,k,n,b,a)
  return (math.exp(k*x)-1)*(b-a)/((math.exp(k)-1)*b)*
  math.cos(2*3.14159*x*n)+
  (math.exp(k*x)-1)*a/((math.exp(k)-1)*b)
end

function toggle_clock(on)
  if toggling_clock then
    do return end
  end
  toggling_clock=true
  if on==nil then
    on=clock_run==nil
  end

  -- do tape stuff
  if on then
    if params:get("tape_start_stop")==1 then 
      params:set("tape_gate",1)
      clock.run(function()
        clock.sleep(0.25)
        params:set("tape_gate",0)
      end)
    end
    if clock_run~=nil then
      clock.cancel(clock_run)
      clock_run=nil
    end
  else
    if bass_pattern_current>0 then 
      engine.reese_off()
    end
    if params:get("tape_start_stop")==1 then 
      params:set("tape_gate",1)
    end
    clock.run(function()
      if params:get("tape_start_stop")==1 then 
        clock.sleep(math.random(100,500)/1000)
      end
      if clock_run~=nil then
        clock.cancel(clock_run)
        clock_run=nil
      end
      toggling_clock=false
      if params:get("tape_start_stop")==1 then 
        clock.sleep(math.random(500,1200)/1000)
        params:set("tape_gate",0)
      end
    end)
    do return end
  end

  -- infinite loop
  if pattern_current[PTTRN_STEP]==0 or next(pattern_store[PTTRN_STEP][pattern_current[PTTRN_STEP]])~=nil then 
    pos_i=0
  else
    pos_i=#pattern_store[PTTRN_STEP][pattern_current[PTTRN_STEP]]*1000
  end
  clock_beat=-1
  local d={steps=0,ci=1}
  local switched_direction=false
  local switched_gate=false
  local gate_on=nil
  params:set("clock_reset",1)
  -- clock.internal.start(-0.1) 
  clock_run=clock.run(function()
    toggling_clock=false
    while true do
      clock.sync(1/2) -- needs to go first
      local track_beats=params:get(params:get("track").."beats")
      clock_beat=clock_beat+1

      -- iterate the loops
      for row=1,5 do 
        for col=1,8 do 
          loops[row][col]:emit(clock_beat)
        end
      end

      -- iterate the bass
      if bass_pattern_current>0 then 
        local ptn=bass_pattern_store[bass_pattern_current]
        local x=ptn[(clock_beat%#ptn)+1]
        bass_sequenced=x
        if x==-1 then 
          engine.reese_off()
        else
          bass_note_on(x+params:get("bass_basenote"))
        end
      end
      
      local first_beat=true
      if d.steps==0 then

        -- update the patterns
        for row,col in ipairs(pattern_current) do
          if col>0 and next(pattern_store[row][col])~=nil then 
            local ptn=pattern_store[row][col]
            local v=(ptn[(pos_i-1+1)%#ptn+1]-1)/31
            PTTRN_FUNS[row](v)
          end
        end

        d={ci=d.ci}
        d.beat=math.floor(clock_beat)
        d.steps=1
        d.retrig=0
        d.db=0
        d.delay=0
        d.stretch=0
        d.rate=1
        d.pitch=0
        d.gate=gate_on
        -- retriggering
        local refractory=math.random(15*1,15*10)
        if math.random()<easing_function2(params:get("break"),1.6,2,0.041,0.3)*1.5 and debounce_fn["retrig"]==nil then
          -- local retrig_beats=util.clamp(track_beats-(d.beat%track_beats),1,6)
          local retrig_beats=math.random(1,4)
          d.steps=retrig_beats*math.random(1,3)
          if math.random()<0.25 then
            d.steps=d.steps*2
          end
          d.retrig=2*math.random(1,4)*retrig_beats-1
          d.db=math.random(1,2)
          if math.random()<0.25 then
            d.pitch=-2
          end
          if math.random()<0.25 then
            d.db=d.db*-1
          end
          debounce_fn["retrig"]={math.floor(refractory/2),function()end}
        end
        if math.random()<easing_function2(params:get("break"),1.6,2,0.041,0.5) and debounce_fn["stretch"]==nil then
          d.stretch=1
          d.steps=d.steps>1 and d.steps or d.steps*math.random(8,12)
          debounce_fn["stretch"]={refractory*4,function()end}
        end
        if math.random()<easing_function2(params:get("break"),1.6,2,0.041,0.7)*0.2 and debounce_fn["delay"]==nil then
          d.delay=1
          d.gate=math.random(25,75)/100
          d.steps=d.steps>1 and d.steps or d.steps*math.random(2,8)
          debounce_fn["delay"]={refractory*2,function()end}
        end
        if math.random()<easing_function2(params:get("break"),1.6,2,0.041,0.7)*0.4 and debounce_fn["gate"]==nil then
          gate_on=0.5
          debounce_fn["gate_off"]={math.random(16,64),function() gate_on=nil end}
          debounce_fn["gate"]={refractory,function() end}
        end
        if math.random()<easing_function2(params:get("amen"),-3.1,-1.3,0.177,0.5) then
          d.rate=-1
        end

        -- calculate the next position
        if d.beat%(track_beats*4)==0 and math.random()<0.1 and params:get("amen")>0 then
          d.ci=ws[params:get("track")]:random_kick_pos()
        else
          -- switching directions
          local p=easing_function3(params:get("amen"),2.1,5.9,1.4,0.8)
          if switched_direction and math.random()>p then
            switched_direction=false
          elseif not switched_direction and math.random()<p and params:get("amen")>0 then
            switched_direction=true
          end
          pos_i=pos_i+(switched_direction and-1 or 1)
          -- jumping
          local p=easing_function3(params:get("amen"),0.8,12,1.1,0.8)
          if math.random()<p then
            -- do a jump
            pos_i=pos_i+math.random(-1*track_beats,track_beats)
          end
          if pattern_current[PTTRN_STEP]==0 then 
            d.ci=pos_i
          else
            local pttrn=pattern_store[PTTRN_STEP][pattern_current[PTTRN_STEP]]
            d.ci=pttrn[(pos_i-1)%#pttrn+1]
          end
        end
        -- do a small retrig sometimes based on amen
        local p=easing_function3(params:get("amen"),2.6,7.6,1.8,1.2)
        if d.retrig==0 and math.random()<p and params:get("amen")>0 then
          d.retrig=math.random(1,2)*2-1
        end
        -- overwrite current data with button data from grid
        for k, fn in pairs(button_fns) do
          d[k]=fn()
          print("button",k,d[k])
        end
        d.duration=d.steps*clock.get_beat_sec()/2
        global_played={}
        for k,v in pairs(d) do
          global_played[k]=v
        end
        ws[params:get("track")]:play(d)
        if params:get("efit")==1 and math.random()<lfos[5]/4 then
          params:set_raw("track",math.random())
        end
      end

      if math.random()<easing_function2(params:get("amen"),1,0.3,0.044,0.72)/64 and params:get("tape_gate")==0 and debounce_fn["tape_gate"]==nil then
        params:set("tape_gate",1)
        debounce_fn["tape_gate"]={math.random(7,15),function()
          params:set("tape_gate",0)
          debounce_fn["tape_gate"]={math.random(15*1,15*10),function()end}
        end}
      end

      d.steps=d.steps-1
      -- print(pos_i,d.ci,clock.get_beats())
    end
  end)
end

function rerun()
  norns.script.load(norns.state.script)
end

function cleanup()
  params:set('monitor_level',initital_monitor_level)
  os.execute("pkill -f oscnotify")
end

function reset_clocks()
  clock_pulse=0
  tli:reset()
end

function show_progress(val)
  show_message_progress=util.clamp(val,0,100)
end

function show_message(message,seconds)
  seconds=seconds or 2
  show_message_clock=10*seconds
  show_message_text=message
end

function draw_message()
  if show_message_clock~=nil and show_message_text~=nil and show_message_clock>0 and show_message_text~="" then
    show_message_clock=show_message_clock-1
    screen.blend_mode(0)

    local x=64
    local y=28
    local w=screen.text_extents(show_message_text)+8
    screen.rect(x-w/2,y,w+2,10)
    screen.level(0)
    screen.fill()
    screen.rect(x-w/2,y,w+2,10)
    screen.level(15)
    screen.stroke()
    screen.move(x,y+7)
    screen.level(math.floor(screen_fade_in*2/3))
    screen.text_center(show_message_text)
    if show_message_progress~=nil and show_message_progress>0 then
      -- screen.update()
      screen.blend_mode(13)
      screen.rect(x-w/2,y,w*(show_message_progress/100)+2,9)
      screen.level(math.floor(screen_fade_in*2/3))
      screen.fill()
      screen.blend_mode(0)
    else
      -- screen.update()
      screen.blend_mode(13)
      screen.rect(x-w/2,y,w+2,9)
      screen.level(math.floor(screen_fade_in*2/3))
      screen.fill()
      screen.blend_mode(0)
      screen.level(0)
      screen.rect(x-w/2,y,w+2,10)
      screen.stroke()
    end
    if show_message_clock==0 then
      show_message_text=""
      show_message_progress=0
    end
  end
end

function debounce_params()
  for k,v in pairs(debounce_fn) do
    if v~=nil and v[1]~=nil and v[1]>0 then
      v[1]=v[1]-1
      if v[1]~=nil and v[1]==0 then
        if v[2]~=nil then
          local status,err=pcall(v[2])
          if err~=nil then
            print(status,err)
          end
        end
        debounce_fn[k]=nil
      else
        debounce_fn[k]=v
      end
    end
  end
end

function enc(k,d)
  if performance then
    if k==2 and param_switch then
      params:delta("amen",d)
    elseif k==3 and param_switch then
      params:delta("break",d)
    elseif k==2 and not param_switch then
      params:delta("track",d)
    elseif k==3 and not param_switch then
      params:delta("punch",d)
    elseif k==1 then
      params:delta("db",d)
      debounce_fn["show_db"]={15,function()end}
    end
  else
    ws[params:get("track")]:enc(k,d)
  end
end

kon={false,false,false}

function key(k,z)
  kon[k]=z==1
  if k==1 and z==1 then
    performance=not performance
    if performance then
      ws[params:get("track")]:zoom(false,1000)
    end
    do return end
  end
  if performance then
    if (kon[2] and kon[3]) or (kon[1] and kon[3]) or (kon[1] and kon[2]) then
      params:set("efit",1-params:get("efit"))
    elseif kon[2] then
      param_switch=not param_switch
    elseif kon[3] then
      toggle_clock()
    end
  else
    ws[params:get("track")]:key(k,z)
  end
end

ff=1
function redraw()
  if Needs_Restart then
    screen.clear()
    screen.level(15)
    Restart_Message:redraw()
    screen.update()
    return
  end
  if loaded_files==100 then
    local efit_mode=kon[2] and kon[3]
    if efit_mode then
      screen.blend_mode(0)
    else
      screen.clear()
      screen.blend_mode(0)
    end
    if not efit_mode then
      if ws[params:get("track")]==nil then
        do return end
      end
      ws[params:get("track")]:redraw()
    end
    screen.font_face(63)
    screen.level(5)
    screen.rect(0,0,128,7)
    screen.fill()
    screen.level(0)
    screen.move(8,6)
    screen.move(64,8)
    screen.font_size(8)
    if debounce_fn["show_db"]~=nil then
      screen.level(15-debounce_fn["show_db"][1])
      screen.text_center(params:string("db"))
    else
      screen.text_center(performance and (clock_run==nil and "stopped" or "playing") or "edit")
    end
    if efit_mode then
      screen.font_size(math.random(12,36))
      screen.level(math.random(12,15))
      screen.font_face(math.random(1,63))
      screen.text_rotate(math.random(1,128),math.random(1,64),"f",math.random(0,360))
      screen.font_size(8)
    else
      if performance then
        screen.level(15)
        screen.font_size(13)
        screen.move(32,30)
        screen.text_center(param_switch and "AMEN" or "DRUM")
        screen.move(32,30+24)
        screen.text_center(param_switch and (math.floor(params:get("amen")*100).."%") or params:get("track"))

        screen.font_face(62)
        screen.move(32+60,30)
        screen.text_center(param_switch and "BREAK" or "PUNCH")
        screen.move(32+60,30+24)
        screen.text_center(param_switch and (math.floor(params:get("break")*100).."%") or (math.floor(params:get("punch")*100).."%"))
        screen.font_size(8)
      end
    end
  end

  if loading_screen then
    screen.clear()
    screen.blend_mode(0)
    screen.level(15)
    screen.font_face(63)
    screen.font_size(13)
    screen.move(32,22)
    screen.text_center("AMEN")
    screen.font_face(62)
    screen.move(32+60,22)
    screen.text_center("BREAK")
    screen.move(64,57)
    screen.font_face(63)
    screen.text_center("v1.3.0")
    screen.font_size(8)
    screen.font_face(1)
  end
  draw_message()
  screen.update()
end

function params_grid()
 local params_menu={}
 for row=1,5 do 
  local ps={
    {id="db",name="volume",min=-96,max=16,div=0.5,default=-12,unit="dB",kind="loop",row=row,fn=function(x) return util.dbamp(x) end},
    {id="pan",name="pan",min=-1,max=1,div=0.05,default=0,kind="loop",row=row},
    {id="slew",name="fade time",min=0.1,max=20,div=0.1,default=4,unit="sec",kind="loop",row=row},
    {id="oneshot",name="oneshot",min=0,max=1,div=1,default=0,row=row,formatter=function(param) return param:get()==1 and "yes" or "no" end},
  }
  for _, p in ipairs(ps) do 
    table.insert(params_menu,p)
  end
 end
 local params_menu2={
    {id="basenote",name="root note",min=0,max=128,exp=false,div=1,default=36,noaction=true,formatter=function(param) return musicutil.note_num_to_name(param:get(),true)end},
    {id="db",name="volume",min=-96,max=16,div=0.5,default=-6,unit="dB",fn=function(x) return util.dbamp(x) end},
    {id="mod1",name="mod1",min=-1,max=1,exp=false,div=0.1,default=0.0},
    {id="mod2",name="mod2",min=-1,max=1,exp=false,div=0.1,default=0.0},
    {id="mod3",name="mod3",min=-1,max=1,exp=false,div=0.1,default=0.0},
    {id="mod4",name="mod4",min=-1,max=1,exp=false,div=0.1,default=0.0},
    {id="attack",name="attack",min=0.01,max=20,exp=false,div=0.1,default=0.1,unit="sec"},
    {id="decay",name="decay",min=0.01,max=20,exp=false,div=0.1,default=0.2,unit="sec"},
    {id="sustain",name="sustain",min=0.0,max=1,exp=false,div=0.1,default=0.9,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="release",name="release",min=0.01,max=20,exp=false,div=0.1,default=2,unit="sec"},
    {id="pan",name="pan",min=-1,max=1,div=0.05,default=0,kind="loop",row=row},
    {id="portamento",name="portamento",min=0.0,max=20,exp=false,div=0.1,default=0.1,unit="sec"},
  }

 params:add_group("GRID > BASS",#params_menu2)
 for _,pram in ipairs(params_menu2) do
  params:add{
    type="control",
    id="bass_"..pram.id,
    name=pram.name,
    controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
    formatter=pram.formatter,
  }
  if not pram.noaction then 
   params:set_action("bass_"..pram.id,function(v)
     engine.reese_set(pram.id=="db" and "amp" or pram.id,pram.fn and pram.fn(v) or v)
    end)  
  end
end
params:add_group("GRID > LOOPS",#params_menu+5)
 local current_row=0
 for _,pram in ipairs(params_menu) do
    if pram.row~=current_row then 
      params:add_separator("ROW "..pram.row)
      current_row=pram.row
    end
    params:add{
      type="control",
      id="loop"..pram.row.."_"..pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=pram.formatter,
    }
    params:set_action("loop"..pram.row.."_"..pram.id,function(v)
      if pram.kind=="loop" then 
        -- set all loops simultaneously
        for col=1,8 do 
          if loops[pram.row][col].playing then 
            engine.loop_set(loops[pram.row][col].path,pram.id=="db" and "amp" or pram.id,pram.fn and pram.fn(v) or v)
          end
        end
      end
    end)
  end
end

function params_audioin()
  local params_menu={
    {id="amp",name="amp",min=0,max=4,exp=false,div=0.01,default=1.0},
    {id="compressing",name="compressing",min=0,max=1,exp=false,div=1,default=0.0,response=1,formatter=function(param) return param:get()==1 and "yes" or "no" end},
    {id="compressible",name="compressible",min=0,max=1,exp=false,div=1,default=1.0,response=1,formatter=function(param) return param:get()==1 and "yes" or "no" end},
  }
  params:add_group("AUDIO IN",#params_menu)
  for _,pram in ipairs(params_menu) do
    params:add{
      type="control",
      id="audioin"..pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=pram.formatter,
    }
    params:set_action("audioin"..pram.id,function(v)
      engine.audionin_set(pram.id,v)
    end)
  end
end

function params_kick()
  -- kick
  local params_menu={
    {id="db",name="db adj",min=-96,max=16,exp=false,div=1,default=-6,unit="db"},
    {id="preamp",name="preamp",min=0,max=4,exp=false,div=0.01,default=1,unit="amp"},
    {id="basenote",name="base note",min=10,max=90,exp=false,div=1,default=24,formatter=function(param) return musicutil.note_num_to_name(param:get(),true)end},
    {id="ratio",name="ratio",min=1,max=20,exp=false,div=1,default=6},
    {id="sweeptime",name="sweep time",min=0,max=200,exp=false,div=1,default=50,unit="ms"},
    {id="decay1",name="decay1",min=5,max=2000,exp=false,div=10,default=300,unit="ms"},
    {id="decay1L",name="decay1L",min=5,max=2000,exp=false,div=10,default=800,unit="ms"},
    {id="decay2",name="decay2",min=5,max=2000,exp=false,div=10,default=150,unit="ms"},
    {id="clicky",name="clicky",min=0,max=100,exp=false,div=1,default=0,unit="%"},
    {id="compressing",name="compressing",min=0,max=1,exp=false,div=1,default=1.0,response=1,formatter=function(param) return param:get()==1 and "yes" or "no" end},
    {id="compressible",name="compressible",min=0,max=1,exp=false,div=1,default=0.0,response=1,formatter=function(param) return param:get()==1 and "yes" or "no" end},
  }
  params:add_group("KICK",#params_menu)
  for _,pram in ipairs(params_menu) do
    params:add{
      type="control",
      id="kick_"..pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=pram.formatter,
    }
  end
end

function params_audioout()
  local params_menu={
    {id="tape_gate",name="tape stop",min=0,max=1,exp=false,div=1,default=0,response=1,formatter=function(param) return param:get()>0 and "on" or "off" end},
    {id="tape_start_stop",name="tape auto start/stop",min=0,max=1,exp=false,div=1,default=0,response=1,formatter=function(param) return param:get()>0 and "on" or "off" end},
    {id="tape_slow",name="tape slow",min=0,max=2,exp=false,div=0.01,default=0.0,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="sidechain_mult",name="sidechain amount",min=0,max=8,exp=false,div=0.1,default=2.0},
    {id="compress_thresh",name="sidechain threshold",min=0,max=1,exp=false,div=0.01,default=0.1},
    {id="compress_level",name="sidechain level",min=0,max=1,exp=false,div=0.01,default=0.1},
    {id="compress_attack",name="sidechain attack",min=0,max=1,exp=false,div=0.001,default=0.01,formatter=function(param) return (param:get()*1000).." ms" end},
    {id="compress_release",name="sidechain release",min=0,max=2,exp=false,div=0.01,default=0.2,formatter=function(param) return (param:get()*1000).." ms" end},
    {id="lpshelf",name="lp boost freq",min=12,max=127,exp=false,div=1,default=23,formatter=function(param) return musicutil.note_num_to_name(math.floor(param:get()),true)end,fn=function(x) return musicutil.note_num_to_freq(x) end},
    {id="lpgain",name="lp boost db",min=-96,max=36,exp=false,div=1,default=0,unit="dB"},
    {id="noise_gate_db",name="noise gate threshold",min=-60,max=0,exp=false,div=0.5,default=-60,unit="dB"},
    {id="noise_gate_attack",name="noise gate attack",min=0,max=1,exp=false,div=0.001,default=0.01,unit="s"},
    {id="noise_gate_release",name="noise gate release",min=0,max=1,exp=false,div=0.001,default=0.01,unit="s"},
    {id="delay_feedback",name="feedback time",min=0.001,max=12,exp=false,hide=true,div=0.1,default=clock.get_beat_sec()*16,unit="s"},
    {id="delay_time",name="delay time",min=0.01,max=4,exp=false,hide=true,div=clock.get_beat_sec()/32,default=clock.get_beat_sec()/2,unit="s"},
    {id="sine_drive",name="saturate wavefolder",min=0,max=1,exp=false,div=0.01,default=0.0,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="compress_curve_wet",name="compress curve wet",min=0,max=1,exp=false,div=0.01,default=0.0,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="compress_curve_drive",name="compress curve drive",min=0,max=10,exp=false,div=0.01,default=1,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="expand_curve_wet",name="expand curve wet",min=0,max=1,exp=false,div=0.01,default=0.0,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="expand_curve_drive",name="expand curve drive",min=0,max=10,exp=false,div=0.1,default=4,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="tape_wet",name="analog tape",min=0,max=1,exp=false,div=1,default=0,response=1,formatter=function(param) return param:get()>0 and "on" or "off" end},
    {id="tape_bias",name="tape bias",min=0,max=1,exp=false,div=0.01,default=0.8,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="saturation",name="tape saturation",min=0,max=2,exp=false,div=0.01,default=0.80,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="tape_drive",name="tape drive",min=0,max=2,exp=false,div=0.01,default=0.75,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="dist_on",name="distortion",min=0,max=1,exp=false,div=1,default=0,response=1,formatter=function(param) return param:get()>0 and "on" or "off" end},
    {id="dist_wet",name="distortion gain",min=0,max=1,exp=false,div=0.01,default=0.05,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="drivegain",name="distortion oomph",min=0,max=1,exp=false,div=0.01,default=0.5,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="dist_bias",name="distortion bias",min=0,max=2.5,exp=false,div=0.01,default=0.5,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="lowgain",name="distortion low gain",min=0,max=0.3,exp=false,div=0.01,default=0.1,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
    {id="highgain",name="distortion high gain",min=0,max=0.3,exp=false,div=0.01,default=0.1,formatter=function(param) return string.format("%2.0f%%",param:get()*100) end},
  }
  params:add_group("AUDIO OUT",#params_menu)
  for _,pram in ipairs(params_menu) do
    params:add{
      type="control",
      id=pram.id,
      name=pram.name,
      controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
      formatter=pram.formatter,
    }
    if pram.hide then
      params:hide(pram.id)
    end
    params:set_action(pram.id,function(v)
      engine.main_set(pram.id,pram.fn~=nil and pram.fn(v) or v)
    end)
  end
end


function params_action()
  params.action_write=function(filename,name)
    print("[params.action_write]",filename,name)
    local data={pattern_current=pattern_current,pattern_store=pattern_store,bass_pattern_current=bass_pattern_current,bass_pattern_store=bass_pattern_store}
    filename=filename..".json"
    local file=io.open(filename,"w+")
    io.output(file)
    io.write(json.encode(data))
    io.close(file)
  end

  params.action_read=function(filename,silent)
    print("[params.action_read]",filename,silent)
    -- load all the patterns
    filename=filename..".json"
    if not util.file_exists(filename) then
      do return end
    end
    local f=io.open(filename,"rb")
    local content=f:read("*all")
    f:close()
    if content==nil then
      do return end
    end
    local data=json.decode(content)
    if data==nil then
      do return end
    end
    pattern_current=data.pattern_current
    pattern_store=data.pattern_store
    bass_pattern_current=data.bass_pattern_current
    bass_pattern_store=data.bass_pattern_store
  end
end

function bass_note_on(note)
  engine.reese_on(note,params:get("bass_db"),
    params:get("bass_mod1"),
    params:get("bass_mod2"),
    params:get("bass_mod3"),
    params:get("bass_mod4"),
    params:get("bass_attack"),
    params:get("bass_decay"),
    params:get("bass_sustain"),
    params:get("bass_release"),
    params:get("bass_pan"),
    params:get("bass_portamento")
  )
  while note>36 do 
    note = note - 12
  end
  while note<24 do 
    note = note + 12
  end
  params:set("kick_basenote",note)
end