-- @description Change grid in arrange view with mousewheel
-- @author misha
-- @version 1.0
-- @about Change grid in arrange view with mousewheel
  
  function main()
     local _,_,_,_,_,_,mouse_scroll  = reaper.get_action_context() 
     local dir = -(mouse_scroll/math.abs(mouse_scroll))
     ret, grid, swingmode, swingamt = reaper.GetSetProjectGrid( 0, false, 0, 0, 0 )
     local out = grid*2^-dir
    if out >= 1/32 and out <= 8 then
      reaper.GetSetProjectGrid( 0, true, out, swingmode, swingamt )
    end
  end
  
  reaper.defer(main)
