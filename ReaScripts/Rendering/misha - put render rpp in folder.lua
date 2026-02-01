-- @description Put render rpp in folder
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  Script works if Save project copy outfile.rpp is enabled in render window. It will create rpp folder and place all render rpp files in it
    

proj_path = reaper.GetProjectPath()
retval, media = reaper.GetSetProjectInfo_String(0, 'RECORD_PATH', '', 0 )
proj_path = string.gsub( proj_path,media,'')
proj_name = reaper.GetProjectName(0)
_, render_file = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", '', 0 )

PATH = proj_path..'\\'..render_file.."\\rpp"


state = reaper.GetSetProjectInfo_String(0,"RENDER_EXTRAFILEDIR",  PATH   ,1)

